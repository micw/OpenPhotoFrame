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
  static const Duration _downloadIdleTimeout = Duration(minutes: 15);

  ICloudAlbumSyncService({
    required ICloudAlbumSourceConfig config,
    required StorageProvider storageProvider,
    int timeoutSeconds = 60,
  })  : _config = config,
        _storageProvider = storageProvider,
        _requestTimeout = Duration(seconds: timeoutSeconds);

  final ICloudAlbumSourceConfig _config;
  final StorageProvider _storageProvider;
  final Duration _requestTimeout;
  final _log = Logger('ICloudAlbumSyncService');

  @override
  String get id => 'icloud_album';

  @override
  Future<void> sync({
    bool deleteOrphanedFiles = false,
    SyncProgressCallback? onProgress,
  }) async {
    _log.info(
        'Starting iCloud album sync (${_config.albums.length} album(s), '
        'primary token: ${_config.token})');

    final localDir = await _storageProvider.getPhotoDirectory();
    await localDir.create(recursive: true);

    // Step 1: get photo metadata from EVERY configured album. Each album may
    // resolve to a different shard host, so the host is kept alongside its
    // photos and all albums are combined afterwards.
    final albumData = <(String, List<Map<String, dynamic>>, String)>[];
    final fetchErrors = <Object>[];
    var fetchedAlbums = 0;
    for (var i = 0; i < _config.albums.length; i++) {
      final album = _config.albums[i];
      if (!album.isValid) {
        // Not a parseable icloud.com link with a token: skip the fetch
        // entirely instead of firing a malformed request, and count it as
        // unfetched so orphan cleanup stays safe (see step 6).
        fetchErrors.add('Album ${i + 1} has an invalid or empty link: '
            '${album.url.trim()}');
        _log.warning('Skipping album ${i + 1} (${album.url.trim()}): '
            'not a valid icloud.com shared-album link');
        continue;
      }
      try {
        final result = await _fetchPhotoList(token: album.token);
        fetchedAlbums++;
        _log.info('Found ${result.$1.length} photos in iCloud album '
            '${i + 1}/${_config.albums.length} (token: ${album.token})');
        if (result.$1.isNotEmpty) {
          albumData.add((album.token, result.$1, result.$2));
        }
      } catch (e) {
        fetchErrors.add(e);
        _log.warning('Failed to fetch album ${i + 1} '
            '(${album.url.trim()}): $e');
      }
    }

    if (albumData.isEmpty) {
      if (fetchErrors.isNotEmpty) {
        throw ICloudAlbumSyncException(
            'Failed to fetch photo list for all albums',
            cause: fetchErrors.first);
      }
      return;
    }

    // Step 2: build per-album guid list and checksum→guid mapping for the
    // best derivative. webasseturls response is keyed by derivative checksum,
    // NOT photoGuid. Photos shared across several albums are de-duplicated
    // by guid.
    final perAlbumGuids = <List<String>>[];
    final checksumToGuid = <String, String>{};
    final guidToChecksum = <String, String>{};

    for (final (_, albumPhotos, _) in albumData) {
      final albumGuids = <String>[];
      for (final photo in albumPhotos) {
        final guid = photo['photoGuid'] as String?;
        if (guid == null || guid.isEmpty) continue;
        final derivatives = photo['derivatives'];
        if (derivatives is! Map) continue;

        // Iterate ALL derivative keys and pick the one with the largest max dimension.
        // iCloud uses both standard keys ('342', '2048') and exact-pixel keys ('1537', etc.)
        String? bestChecksum;
        String? bestKey;
        int bestMaxDim = 0;
        int? bestW, bestH;

        for (final derivEntry in derivatives.entries) {
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
          final checksum = bestChecksum;
          checksumToGuid.putIfAbsent(checksum, () => guid);
          guidToChecksum.putIfAbsent(guid, () => checksum);
          albumGuids.add(guid);
          _log.info('Photo ${guid.substring(0, 8)}: best derivative key=$bestKey (${bestW}x${bestH})');
        }
      }
      perAlbumGuids.add(albumGuids);
    }
    final guids = guidToChecksum.keys.toList();

    // Step 3: get download URLs per album (each album has its own token and
    // shard host), merging results across albums. Response keys are
    // derivative checksums, which are mapped back to photoGuids for file
    // naming.
    final guidToUrl = <String, String>{};
    final assetUrlErrors = <Object>[];
    for (var i = 0; i < albumData.length; i++) {
      final (token, _, host) = albumData[i];
      // Skip guids an earlier album already resolved a download URL for —
      // re-requesting them here would be a wasted duplicate API call.
      final requestedGuids =
          perAlbumGuids[i].where((g) => !guidToUrl.containsKey(g)).toList();
      if (requestedGuids.isEmpty) continue;
      try {
        final rawUrls =
            await _fetchAssetUrls(token: token, guids: requestedGuids, host: host);
        _log.info('Got ${rawUrls.length} raw asset URLs for '
            '${requestedGuids.length} photos in album ${i + 1}');
        for (final entry in rawUrls.entries) {
          final guid = checksumToGuid[entry.key];
          if (guid != null) guidToUrl.putIfAbsent(guid, () => entry.value);
        }
      } catch (e) {
        assetUrlErrors.add(e);
        _log.warning('Failed to fetch asset URLs for album ${i + 1} '
            '(token: $token): $e');
      }
    }

    if (guidToUrl.isEmpty && assetUrlErrors.isNotEmpty) {
      throw ICloudAlbumSyncException(
          'Failed to fetch download URLs for all albums',
          cause: assetUrlErrors.first);
    }
    _log.info(
        'Matched ${guidToUrl.length} of ${guids.length} photos with download URLs');

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

      final freeMb = await _storageFreeMb(localDir.path);
      if (freeMb != null && freeMb < 100) {
        _log.warning('Storage low (${freeMb.toStringAsFixed(1)} MB free) — '
            'stopping download with ${pending.length - i} photos remaining');
        break;
      }

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

    // Step 6: delete orphaned files if requested (compare by photoGuid).
    // Only safe when EVERY configured album was fetched successfully this
    // run: if any album failed (network blip, invalid link), its
    // already-downloaded photos would be missing from [guids] and wrongly
    // deleted even though the album is still a live, configured source.
    if (deleteOrphanedFiles) {
      if (fetchedAlbums == _config.albums.length) {
        await _deleteOrphans(localDir, guids.toSet());
      } else {
        _log.warning('Skipping orphaned-file cleanup: only $fetchedAlbums of '
            '${_config.albums.length} configured album(s) were fetched '
            'successfully this run, so files from failed albums would be '
            'misidentified as orphans.');
      }
    }

    _log.info('iCloud album sync complete');
  }

  // ---------------------------------------------------------------------------
  // API: webstream — returns photo metadata + the final shard host
  // ---------------------------------------------------------------------------

  Future<(List<Map<String, dynamic>>, String)> _fetchPhotoList({
    required String token,
  }) async {
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
    required String token,
    required List<String> guids,
    required String host,
  }) async {
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

  // Returns available storage in MB for the filesystem containing [path], or
  // null if the check fails. Uses `df` (always present on Android via toybox).
  static Future<double?> _storageFreeMb(String path) async {
    try {
      // -k forces 1K-block output; Android toybox df defaults to 1K-blocks but
      // emits no suffix, which caused the no-suffix branch to treat KB as bytes.
      final result = await Process.run('df', ['-k', path]);
      final lines = (result.stdout as String).trim().split('\n');
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return null;
      final raw = parts[3];
      // With -k all values are in 1K-blocks; suffixes still handled defensively.
      final multiplier = raw.endsWith('G') ? 1024.0 * 1024
          : raw.endsWith('M') ? 1024.0
          : raw.endsWith('K') ? 1.0
          : 1.0 / 1024; // 1K-blocks → MB
      final value = double.tryParse(raw.replaceAll(RegExp(r'[GMKgmk]'), ''));
      if (value == null) return null;
      return value * multiplier;
    } catch (_) {
      return null;
    }
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
