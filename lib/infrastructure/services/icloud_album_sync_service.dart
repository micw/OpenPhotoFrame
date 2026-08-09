import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../../domain/interfaces/sync_provider.dart';
import '../../domain/interfaces/storage_provider.dart';
import 'icloud_album_source_config.dart';

class ICloudAlbumSyncException implements Exception {
  ICloudAlbumSyncException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'iCloud sync failed: $message${cause != null ? ' ($cause)' : ''}';
}

class ICloudAlbumSyncService implements SyncProvider {
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _downloadIdleTimeout = Duration(minutes: 15);

  ICloudAlbumSyncService({
    required ICloudAlbumSourceConfig config,
    required StorageProvider storageProvider,
  })  : _config = config,
        _storageProvider = storageProvider;

  final ICloudAlbumSourceConfig _config;
  final StorageProvider _storageProvider;
  final _log = Logger('ICloudAlbumSyncService');

  @override
  String get id => 'icloud_album';

  @override
  Future<void> sync({
    bool deleteOrphanedFiles = false,
    SyncProgressCallback? onProgress,
  }) async {
    _log.info('Starting iCloud album sync (token: ${_config.token})');

    final localDir = await _storageProvider.getPhotoDirectory();
    await localDir.create(recursive: true);

    // Step 1: get photo metadata + final shard host
    final (photos, host) = await _fetchPhotoList();
    _log.info('Found ${photos.length} photos in iCloud album');

    if (photos.isEmpty) return;

    // Step 2: build guid list and checksum→guid mapping for best derivative.
    // webasseturls response is keyed by derivative checksum, NOT photoGuid.
    final guids = <String>[];
    final checksumToGuid = <String, String>{};
    final guidToChecksum = <String, String>{};

    for (final photo in photos) {
      final guid = photo['photoGuid'] as String?;
      if (guid == null || guid.isEmpty) continue;
      guids.add(guid);
      final derivatives = photo['derivatives'];
      if (derivatives is! Map) continue;

      // Iterate ALL derivative keys and pick the one with the largest max dimension.
      // iCloud uses both standard keys ('342', '2048') and exact-pixel keys ('1537', etc.)
      String? bestChecksum;
      String? bestKey;
      int bestMaxDim = 0;
      int? bestW, bestH;

      for (final derivEntry in (derivatives as Map).entries) {
        final deriv = derivEntry.value;
        if (deriv is! Map) continue;
        final checksum = deriv['checksum'] as String?;
        if (checksum == null || checksum.isEmpty) continue;
        final w = int.tryParse(deriv['width']?.toString() ?? '') ?? 0;
        final h = int.tryParse(deriv['height']?.toString() ?? '') ?? 0;
        final maxDim = w > h ? w : h;
        if (maxDim > bestMaxDim) {
          bestMaxDim = maxDim;
          bestChecksum = checksum;
          bestKey = derivEntry.key.toString();
          bestW = w;
          bestH = h;
        }
      }

      if (bestChecksum != null) {
        checksumToGuid[bestChecksum] = guid;
        guidToChecksum[guid] = bestChecksum;
        _log.info('Photo ${guid.substring(0, 8)}: best derivative key=$bestKey (${bestW}x${bestH})');
      }
    }

    // Step 3: get download URLs — response keys are derivative checksums
    final rawUrls = await _fetchAssetUrls(guids: guids, host: host);
    _log.info('Got ${rawUrls.length} raw asset URLs for ${guids.length} photos');

    // Map checksum keys back to photoGuids for file naming
    final guidToUrl = <String, String>{};
    for (final entry in rawUrls.entries) {
      final guid = checksumToGuid[entry.key];
      if (guid != null) guidToUrl.putIfAbsent(guid, () => entry.value);
    }
    _log.info('Matched ${guidToUrl.length} photos with download URLs');

    // Step 4: determine which files need downloading.
    // A .key sidecar file records the derivative checksum last downloaded.
    // Re-download if the file is missing OR the checksum changed (better derivative available).
    final pending = <MapEntry<String, String>>[];
    for (final entry in guidToUrl.entries) {
      final guid = entry.key;
      final localFile = File('${localDir.path}/$guid.jpg');
      final keyFile  = File('${localDir.path}/$guid.jpg.key');
      if (await localFile.exists() && await keyFile.exists()) {
        final storedChecksum = await keyFile.readAsString();
        if (storedChecksum == guidToChecksum[guid]) continue; // already have best version
        _log.info('Re-downloading upgraded derivative: $guid');
        await localFile.delete();
      }
      pending.add(entry);
    }

    _log.info('${pending.length} new photos to download');

    // Step 5: download missing photos
    final dio = Dio();
    for (var i = 0; i < pending.length; i++) {
      final guid = pending[i].key;
      final url = pending[i].value;

      onProgress?.call(SyncProgress(
        completedFiles: i,
        totalFiles: pending.length,
        currentFileLabel: guid,
      ));

      final partFile = File('${localDir.path}/$guid.jpg.part');
      final destFile = File('${localDir.path}/$guid.jpg');

      _log.info('Downloading ${i + 1}/${pending.length}: $guid');
      try {
        await dio.download(
          url,
          partFile.path,
          options: Options(receiveTimeout: _downloadIdleTimeout),
        );
        await partFile.setLastModified(DateTime.now());
        await partFile.rename(destFile.path);
        // Record which derivative checksum we downloaded for future upgrade checks
        final keyFile = File('${localDir.path}/$guid.jpg.key');
        await keyFile.writeAsString(guidToChecksum[guid] ?? '');
      } catch (e) {
        try { await partFile.delete(); } catch (_) {}
        _log.warning('Failed to download $guid: $e');
        continue;
      }

      onProgress?.call(SyncProgress(
        completedFiles: i + 1,
        totalFiles: pending.length,
        currentFileLabel: guid,
      ));
    }

    // Step 6: delete orphaned files if requested (compare by photoGuid)
    if (deleteOrphanedFiles) {
      await _deleteOrphans(localDir, guids.toSet());
    }

    _log.info('iCloud album sync complete');
  }

  // ---------------------------------------------------------------------------
  // API: webstream — returns photo metadata + the final shard host
  // ---------------------------------------------------------------------------

  Future<(List<Map<String, dynamic>>, String)> _fetchPhotoList() async {
    final token = _config.token;
    final dio = Dio();
    var host = 'sharedstreams.icloud.com';

    for (var attempt = 0; attempt < 2; attempt++) {
      final url = 'https://$host/$token/sharedstreams/webstream';
      Response<Map<String, dynamic>> response;

      try {
        response = await dio.post<Map<String, dynamic>>(
          url,
          data: '{"streamCtag":null}',
          options: Options(
            contentType: 'application/json',
            receiveTimeout: _requestTimeout,
            followRedirects: false,
            validateStatus: (s) => s != null,
          ),
        );
      } on DioException catch (e) {
        throw ICloudAlbumSyncException('Request failed', cause: e);
      }

      if (response.statusCode == 330) {
        final newHost = _extractRedirectHost(response);
        if (newHost == null) {
          throw ICloudAlbumSyncException('Got 330 redirect but no host in response');
        }
        _log.info('iCloud redirect: $host → $newHost');
        host = newHost;
        continue;
      }

      if (response.statusCode != 200) {
        throw ICloudAlbumSyncException('Unexpected HTTP ${response.statusCode}');
      }

      final data = response.data;
      if (data == null) return (<Map<String, dynamic>>[], host);
      final photos = data['photos'];
      if (photos is! List) return (<Map<String, dynamic>>[], host);

      final all = photos.whereType<Map<String, dynamic>>().toList();

      // Log the first non-image item type we encounter so we can see the field
      for (final p in all) {
        final t = p['mediaAssetType'] ?? p['type'] ?? p['assetType'];
        if (t != null && t.toString().toLowerCase() != 'image') {
          _log.info('Skipping non-image asset: type=$t guid=${p['photoGuid']}');
        }
      }

      // Filter to images only — videos and live photo components are excluded
      final images = all.where((p) {
        final t = (p['mediaAssetType'] ?? p['type'] ?? p['assetType'])
            ?.toString()
            .toLowerCase();
        return t == null || t == 'image';
      }).toList();

      if (images.length < all.length) {
        _log.info('Filtered ${all.length - images.length} non-image assets');
      }

      return (images, host);
    }

    throw ICloudAlbumSyncException('Too many redirects');
  }

  // ---------------------------------------------------------------------------
  // API: webasseturls — returns {photoGuid: downloadUrl} for the best derivative
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _fetchAssetUrls({
    required List<String> guids,
    required String host,
  }) async {
    final token = _config.token;
    final dio = Dio();
    final url = 'https://$host/$token/sharedstreams/webasseturls';

    Response<Map<String, dynamic>> response;
    try {
      response = await dio.post<Map<String, dynamic>>(
        url,
        data: jsonEncode({'photoGuids': guids}),
        options: Options(
          contentType: 'application/json',
          receiveTimeout: _requestTimeout,
          validateStatus: (s) => s != null,
        ),
      );
    } on DioException catch (e) {
      throw ICloudAlbumSyncException('webasseturls request failed', cause: e);
    }

    if (response.statusCode != 200) {
      throw ICloudAlbumSyncException(
          'webasseturls returned HTTP ${response.statusCode}');
    }

    final data = response.data;
    if (data == null) return {};

    // Log structure once so we can see what fields Apple returns
    final items = data['items'];
    if (items is Map && items.isNotEmpty) {
      final firstItem = items.values.firstOrNull;
      if (firstItem is Map) {
        _log.info('webasseturls item keys: ${firstItem.keys.toList()}');
        final firstValue = firstItem.values.firstOrNull;
        if (firstValue is Map) {
          _log.info('webasseturls nested keys: ${firstValue.keys.toList()}');
        }
      }
    }

    return _extractAssetUrls(data);
  }

  Map<String, String> _extractAssetUrls(Map<String, dynamic> data) {
    final result = <String, String>{};
    final items = data['items'];
    if (items is! Map) return result;

    for (final entry in items.entries) {
      final guid = entry.key as String;
      final item = entry.value;
      if (item is! Map) continue;

      String? url;

      // Format A: items[guid] = {"2048": {"url": "...", ...}}  (per-derivative map)
      for (final key in ['2048', '1024', '512', '342', '256']) {
        final deriv = item[key];
        if (deriv is Map) {
          url = _buildUrl(deriv);
          if (url != null) break;
        }
      }

      // Format B: items[guid] = {"url_location": "host", "url_path": "/path?sig=...", ...}
      //           Apple CDN splits host and signed path into separate fields
      url ??= _buildUrl(item);

      if (url != null) result[guid] = url;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Builds a full HTTPS URL from an API item map.
  /// Handles three formats:
  ///   1. {"url": "https://..."}           — already full URL
  ///   2. {"url_location": "host", "url_path": "/path?sig=..."} — Apple CDN split
  ///   3. {"downloadURL": "..."}           — alternate key name
  String? _buildUrl(Map item) {
    // Full URL in a single field
    for (final key in ['url', 'downloadURL', 'download_url']) {
      final v = item[key] as String?;
      if (v != null && v.isNotEmpty) {
        return v.startsWith('http') ? v : 'https://$v';
      }
    }
    // Apple split: url_location (host) + url_path (signed path)
    final loc = item['url_location'] as String?;
    final path = item['url_path'] as String?;
    if (loc != null && loc.isNotEmpty && path != null && path.isNotEmpty) {
      final host = loc.startsWith('http') ? loc : 'https://$loc';
      return '$host$path';
    }
    return null;
  }

  String? _extractRedirectHost(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body != null) {
      final h = body['X-Apple-MMe-Host'] as String?;
      if (h != null && h.isNotEmpty) return h;
    }
    return response.headers.map['x-apple-mme-host']?.firstOrNull;
  }

  Future<void> _deleteOrphans(Directory dir, Set<String> remoteGuids) async {
    final expectedJpg = remoteGuids.map((g) => '$g.jpg').toSet();
    final expectedKey = remoteGuids.map((g) => '$g.jpg.key').toSet();
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (name.endsWith('.part')) continue;
      if (name.endsWith('.jpg.key')) {
        if (expectedKey.contains(name)) continue;
      } else if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
        if (expectedJpg.contains(name)) continue;
      } else {
        continue;
      }
      _log.info('Deleting orphaned file: $name');
      try { await entity.delete(); } catch (e) {
        _log.warning('Failed to delete orphan $name: $e');
      }
    }
  }
}
