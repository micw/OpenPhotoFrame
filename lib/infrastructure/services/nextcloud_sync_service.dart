import 'dart:io';
import 'package:logging/logging.dart';
import '../../domain/interfaces/sync_provider.dart';
import '../../domain/interfaces/storage_provider.dart';
import 'nextcloud_remote_client.dart';
import 'nextcloud_source_config.dart';

class NextcloudFolder {
  const NextcloudFolder({
    required this.path,
    required this.depth,
  });

  final String path;
  final int depth;

  String get name {
    if (path.isEmpty) {
      return '';
    }
    final separatorIndex = path.lastIndexOf('/');
    if (separatorIndex == -1) {
      return path;
    }
    return path.substring(separatorIndex + 1);
  }
}

class NextcloudSyncService implements SyncProvider {
  final String webDavUrl;
  final String user;
  final String password;
  final String remotePath;
  final StorageProvider _storageProvider;
  final NextcloudRemoteClientFactory _clientFactory;
  final NextcloudSourceConfig _sourceConfig;
  final _log = Logger('NextcloudSyncService');

  NextcloudSyncService({
    required this.webDavUrl,
    required this.user,
    required this.password,
    required StorageProvider storageProvider,
    this.remotePath = '/',
    NextcloudRemoteClientFactory clientFactory = createWebDavNextcloudRemoteClient,
    NextcloudSourceConfig sourceConfig = const NextcloudSourceConfig(),
  })  : _storageProvider = storageProvider,
        _clientFactory = clientFactory,
        _sourceConfig = sourceConfig;

  /// Factory for Public Share Links
  /// Link format: https://cloud.example.com/s/TOKEN
  factory NextcloudSyncService.fromPublicLink(
    String link,
    StorageProvider storageProvider, {
    NextcloudRemoteClientFactory clientFactory = createWebDavNextcloudRemoteClient,
    NextcloudSourceConfig? sourceConfig,
  }) {
    final share = NextcloudPublicShare.fromPublicLink(link);

    return NextcloudSyncService(
      webDavUrl: share.webDavUrl,
      user: share.user,
      password: share.password,
      storageProvider: storageProvider,
      clientFactory: clientFactory,
      sourceConfig: (sourceConfig ?? const NextcloudSourceConfig()).copyWith(
        url: link,
      ),
    );
  }

  @override
  String get id => 'nextcloud_public';

  /// Tests the connection to the WebDAV server.
  /// Returns null on success, or an error message on failure.
  static Future<String?> testConnection(
    String publicLink, {
    NextcloudRemoteClientFactory clientFactory = createWebDavNextcloudRemoteClient,
  }) async {
    final log = Logger('NextcloudSyncService');
    
    if (publicLink.isEmpty) {
      return 'URL is empty';
    }
    
    try {
      final uri = Uri.parse(publicLink);
      
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return 'Invalid URL scheme (must be http or https)';
      }
      
      if (uri.host.isEmpty) {
        return 'Invalid URL (no host)';
      }
      final share = NextcloudPublicShare.fromPublicLink(publicLink);
      
      log.info("Testing connection to ${share.webDavUrl}");
      
      final client = clientFactory(
        webDavUrl: share.webDavUrl,
        user: share.user,
        password: share.password,
      );
      
      // Try to read root directory - this validates the connection
      await client.readDir('/');
      
      log.info("Connection test successful");
      return null; // Success
      
    } on FormatException catch (e) {
      return 'Invalid URL format: ${e.message}';
    } catch (e) {
      log.warning("Connection test failed: $e");
      // Extract meaningful error message
      final errorStr = e.toString();
      if (errorStr.contains('401')) {
        return 'Authentication failed (invalid share link?)';
      } else if (errorStr.contains('404')) {
        return 'Share not found (invalid link?)';
      } else if (errorStr.contains('SocketException')) {
        return 'Could not connect (check internet/URL)';
      }
      return 'Connection failed: $e';
    }
  }

  static Future<List<NextcloudFolder>> listAvailableFolders(
    String publicLink, {
    NextcloudRemoteClientFactory clientFactory = createWebDavNextcloudRemoteClient,
  }) async {
    final share = NextcloudPublicShare.fromPublicLink(publicLink);
    final client = clientFactory(
      webDavUrl: share.webDavUrl,
      user: share.user,
      password: share.password,
    );

    final folders = <NextcloudFolder>[const NextcloudFolder(path: '', depth: 0)];
    folders.addAll(
      await _collectRemoteFolders(
        client,
        remoteDirectoryPath: '/',
        relativeDirectoryPath: '',
      ),
    );
    folders.sort((left, right) => left.path.compareTo(right.path));
    return folders;
  }

  @override
  Future<void> sync({bool deleteOrphanedFiles = false}) async {
    _log.info("Starting Sync from $webDavUrl (deleteOrphaned: $deleteOrphanedFiles)");

    final client = _clientFactory(
      webDavUrl: webDavUrl,
      user: user,
      password: password,
    );

    try {
      final localDir = await _storageProvider.getPhotoDirectory();
      _log.info("Syncing to local directory: ${localDir.path}");

      _log.info("Listing remote files...");
      final remoteFiles = await _collectRemoteImages(
        client,
        remoteDirectoryPath: remotePath,
        relativeDirectoryPath: '',
      );
      remoteFiles.sort((left, right) => left.relativePath.compareTo(right.relativePath));

      final remoteRelativePaths = remoteFiles
          .map((remoteFile) => remoteFile.relativePath)
          .toSet();

      for (final remoteFile in remoteFiles) {
        final localFile = File('${localDir.path}/${remoteFile.relativePath}');

        bool needsDownload = false;
        if (!await localFile.exists()) {
          needsDownload = true;
        }

        if (!needsDownload) {
          continue;
        }

        _log.info('Downloading ${remoteFile.relativePath}...');

        await localFile.parent.create(recursive: true);
        final partFile = File('${localFile.path}.part');
        await partFile.parent.create(recursive: true);
        await client.downloadFile(remoteFile.remotePath, partFile.path);

        if (remoteFile.modifiedAt != null) {
          try {
            await partFile.setLastModified(remoteFile.modifiedAt!);
          } catch (e) {
            _log.warning(
              'Could not set modification time for ${remoteFile.relativePath}: $e',
            );
          }
        }

        await partFile.rename(localFile.path);
      }
      
      if (deleteOrphanedFiles) {
        await _deleteOrphanedLocalFiles(
          localDirectory: localDir,
          remoteRelativePaths: remoteRelativePaths,
        );
      }
      
      _log.info("Sync completed.");

    } catch (e) {
      _log.severe("Sync failed", e);
      rethrow;
    }
  }

  bool _isImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') || 
           lower.endsWith('.jpeg') || 
           lower.endsWith('.png') || 
           lower.endsWith('.webp');
  }

  Future<List<_RemoteImage>> _collectRemoteImages(
    NextcloudRemoteClient client, {
    required String remoteDirectoryPath,
    required String relativeDirectoryPath,
  }) async {
    final entries = await client.readDir(remoteDirectoryPath);
    final images = <_RemoteImage>[];

    for (final entry in entries) {
      final entryRelativePath = _joinRelativePath(relativeDirectoryPath, entry.name);
      if (entry.isDirectory) {
        images.addAll(
          await _collectRemoteImages(
            client,
            remoteDirectoryPath: entry.path,
            relativeDirectoryPath: entryRelativePath,
          ),
        );
        continue;
      }

      if (!_isImage(entry.name) || !_sourceConfig.includesRelativeFile(entryRelativePath)) {
        continue;
      }

      images.add(
        _RemoteImage(
          remotePath: entry.path,
          relativePath: entryRelativePath,
          modifiedAt: entry.modifiedAt,
        ),
      );
    }

    return images;
  }

  Future<void> _deleteOrphanedLocalFiles({
    required Directory localDirectory,
    required Set<String> remoteRelativePaths,
  }) async {
    _log.info('Checking for orphaned local files...');
    final localEntities = await localDirectory.list(recursive: true, followLinks: false).toList();

    for (final entity in localEntities.whereType<File>()) {
      final relativePath = _relativePathFromLocalFile(localDirectory, entity);
      if (!_isImage(relativePath) || relativePath.endsWith('.part')) {
        continue;
      }

      if (remoteRelativePaths.contains(relativePath)) {
        continue;
      }

      _log.info('Deleting orphaned file: $relativePath');
      try {
        await entity.delete();
      } catch (e) {
        _log.warning('Failed to delete orphaned file $relativePath: $e');
      }
    }

    final directories = localEntities.whereType<Directory>().toList()
      ..sort((left, right) => right.path.length.compareTo(left.path.length));
    for (final directory in directories) {
      if (directory.path == localDirectory.path || !await directory.exists()) {
        continue;
      }

      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
      }
    }
  }

  static Future<List<NextcloudFolder>> _collectRemoteFolders(
    NextcloudRemoteClient client, {
    required String remoteDirectoryPath,
    required String relativeDirectoryPath,
  }) async {
    final entries = await client.readDir(remoteDirectoryPath);
    final folders = <NextcloudFolder>[];

    for (final entry in entries) {
      if (!entry.isDirectory) {
        continue;
      }

      final folderPath = _joinRelativePath(relativeDirectoryPath, entry.name);
      folders.add(
        NextcloudFolder(
          path: folderPath,
          depth: folderPath.isEmpty ? 0 : folderPath.split('/').length,
        ),
      );
      folders.addAll(
        await _collectRemoteFolders(
          client,
          remoteDirectoryPath: entry.path,
          relativeDirectoryPath: folderPath,
        ),
      );
    }

    return folders;
  }

  static String _joinRelativePath(String directoryPath, String name) {
    final normalizedDirectory = NextcloudSourceConfig.normalizeFolderPath(directoryPath);
    if (normalizedDirectory.isEmpty) {
      return name;
    }
    return '$normalizedDirectory/$name';
  }

  static String _relativePathFromLocalFile(Directory baseDirectory, File file) {
    var relativePath = file.path.substring(baseDirectory.path.length);
    if (relativePath.startsWith(Platform.pathSeparator)) {
      relativePath = relativePath.substring(1);
    }
    return relativePath.replaceAll('\\', '/');
  }
}

class _RemoteImage {
  const _RemoteImage({
    required this.remotePath,
    required this.relativePath,
    this.modifiedAt,
  });

  final String remotePath;
  final String relativePath;
  final DateTime? modifiedAt;
}
