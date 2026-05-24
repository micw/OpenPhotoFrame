import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:open_photo_frame/domain/interfaces/storage_provider.dart';
import 'package:open_photo_frame/infrastructure/services/nextcloud_remote_client.dart';
import 'package:open_photo_frame/infrastructure/services/nextcloud_source_config.dart';
import 'package:open_photo_frame/infrastructure/services/nextcloud_sync_service.dart';

class FakeStorageProvider implements StorageProvider {
  FakeStorageProvider(this.directory);

  final Directory directory;

  @override
  Future<Directory> getPhotoDirectory() async => directory;

  @override
  bool get isReadOnly => false;

  @override
  Stream<void> get onDirectoryChanged => const Stream.empty();
}

class FakeNextcloudRemoteClient implements NextcloudRemoteClient {
  FakeNextcloudRemoteClient({
    Map<String, List<NextcloudRemoteEntry>> directories = const {},
    Map<String, List<int>> fileContents = const {},
    this.readDirError,
  })  : _directories = directories,
        _fileContents = fileContents;

  final Map<String, List<NextcloudRemoteEntry>> _directories;
  final Map<String, List<int>> _fileContents;
  final Object? readDirError;
  final List<String> readDirCalls = [];
  final List<String> downloadedPaths = [];

  @override
  Future<List<NextcloudRemoteEntry>> readDir(String path) async {
    readDirCalls.add(path);
    if (readDirError != null) {
      throw readDirError!;
    }
    return List<NextcloudRemoteEntry>.from(_directories[path] ?? const []);
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    downloadedPaths.add(remotePath);
    final file = File(localPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      _fileContents[remotePath] ?? utf8.encode('download:$remotePath'),
    );
  }
}

void main() {
  group('NextcloudSourceConfig', () {
    test('normalizes root and nested folders', () {
      final config = NextcloudSourceConfig.fromMap({
        'url': 'https://cloud.example.com/s/abc',
        'folder_sync_mode': 'selected',
        'selected_folders': ['/', 'albums//summer/'],
      });

      expect(config.syncAllFolders, isFalse);
      expect(config.normalizedSelectedFolders, {'', 'albums/summer'});
      expect(config.includesDirectory(''), isTrue);
      expect(config.includesDirectory('albums/summer'), isTrue);
      expect(config.includesDirectory('albums'), isFalse);
      expect(config.includesRelativeFile('albums/summer/photo.jpg'), isTrue);
      expect(config.includesRelativeFile('albums/photo.jpg'), isFalse);
    });
  });

  group('NextcloudSyncService', () {
    late Directory tempDir;
    late FakeStorageProvider storageProvider;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nextcloud_sync_test_');
      storageProvider = FakeStorageProvider(tempDir);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('fromPublicLink extracts webdav url and token', () {
      final service = NextcloudSyncService.fromPublicLink(
        'https://cloud.example.com/s/abc123',
        storageProvider,
        clientFactory: ({
          required String webDavUrl,
          required String user,
          required String password,
        }) {
          return FakeNextcloudRemoteClient();
        },
      );

      expect(service.webDavUrl, 'https://cloud.example.com/public.php/webdav');
      expect(service.user, 'abc123');
      expect(service.password, '');
    });

    test('testConnection lists the root directory', () async {
      final client = FakeNextcloudRemoteClient(
        directories: {
          '/': const [
            NextcloudRemoteEntry(
              path: '/folder/',
              name: 'folder',
              isDirectory: true,
            ),
          ],
        },
      );

      final error = await NextcloudSyncService.testConnection(
        'https://cloud.example.com/s/abc123',
        clientFactory: ({
          required String webDavUrl,
          required String user,
          required String password,
        }) {
          expect(webDavUrl, 'https://cloud.example.com/public.php/webdav');
          expect(user, 'abc123');
          expect(password, '');
          return client;
        },
      );

      expect(error, isNull);
      expect(client.readDirCalls, ['/']);
    });

    test('listAvailableFolders returns root and nested folders', () async {
      final client = FakeNextcloudRemoteClient(
        directories: {
          '/': const [
            NextcloudRemoteEntry(
              path: '/albums/',
              name: 'albums',
              isDirectory: true,
            ),
            NextcloudRemoteEntry(
              path: '/cover.jpg',
              name: 'cover.jpg',
              isDirectory: false,
            ),
          ],
          '/albums/': const [
            NextcloudRemoteEntry(
              path: '/albums/summer/',
              name: 'summer',
              isDirectory: true,
            ),
          ],
          '/albums/summer/': const [],
        },
      );

      final folders = await NextcloudSyncService.listAvailableFolders(
        'https://cloud.example.com/s/abc123',
        clientFactory: ({
          required String webDavUrl,
          required String user,
          required String password,
        }) => client,
      );

      expect(folders.map((folder) => folder.path), ['', 'albums', 'albums/summer']);
      expect(folders.map((folder) => folder.depth), [0, 1, 2]);
    });

    test('sync downloads root and nested images with relative paths', () async {
      final modifiedAt = DateTime(2026, 5, 18, 12, 0);
      final client = FakeNextcloudRemoteClient(
        directories: {
          '/': [
            NextcloudRemoteEntry(
              path: '/root.jpg',
              name: 'root.jpg',
              isDirectory: false,
              modifiedAt: modifiedAt,
            ),
            const NextcloudRemoteEntry(
              path: '/albums/',
              name: 'albums',
              isDirectory: true,
            ),
          ],
          '/albums/': const [
            NextcloudRemoteEntry(
              path: '/albums/nested.png',
              name: 'nested.png',
              isDirectory: false,
            ),
            NextcloudRemoteEntry(
              path: '/albums/notes.txt',
              name: 'notes.txt',
              isDirectory: false,
            ),
          ],
        },
      );

      final service = NextcloudSyncService.fromPublicLink(
        'https://cloud.example.com/s/abc123',
        storageProvider,
        clientFactory: ({
          required String webDavUrl,
          required String user,
          required String password,
        }) => client,
      );

      await service.sync();

      final rootFile = File('${tempDir.path}/root.jpg');
      final nestedFile = File('${tempDir.path}/albums/nested.png');
      expect(await rootFile.exists(), isTrue);
      expect(await nestedFile.exists(), isTrue);
      expect(File('${tempDir.path}/albums/notes.txt').existsSync(), isFalse);
        expect(
          client.downloadedPaths,
          unorderedEquals(['/root.jpg', '/albums/nested.png']),
        );
      expect(await rootFile.lastModified(), modifiedAt);
    });

      test('sync logs download progress counts for pending files only', () async {
        final existingFile = File('${tempDir.path}/already-here.jpg');
        await existingFile.writeAsString('existing');

        final client = FakeNextcloudRemoteClient(
          directories: {
            '/': const [
              NextcloudRemoteEntry(
                path: '/already-here.jpg',
                name: 'already-here.jpg',
                isDirectory: false,
              ),
              NextcloudRemoteEntry(
                path: '/first.jpg',
                name: 'first.jpg',
                isDirectory: false,
              ),
              NextcloudRemoteEntry(
                path: '/second.jpg',
                name: 'second.jpg',
                isDirectory: false,
              ),
            ],
          },
        );

        final service = NextcloudSyncService.fromPublicLink(
          'https://cloud.example.com/s/abc123',
          storageProvider,
          clientFactory: ({
            required String webDavUrl,
            required String user,
            required String password,
          }) => client,
        );

        final recordedMessages = <String>[];
        Logger.root.level = Level.ALL;
        final subscription = Logger.root.onRecord.listen((record) {
          if (record.loggerName == 'NextcloudSyncService') {
            recordedMessages.add(record.message);
          }
        });

        try {
          await service.sync();
        } finally {
          await subscription.cancel();
        }

        expect(client.downloadedPaths, ['/first.jpg', '/second.jpg']);
        expect(
          recordedMessages,
          containsAllInOrder([
            'Downloading 1/2...',
            'Downloading 2/2...',
          ]),
        );
      });

    test('sync only downloads images from selected folders', () async {
      final client = FakeNextcloudRemoteClient(
        directories: {
          '/': const [
            NextcloudRemoteEntry(
              path: '/root.jpg',
              name: 'root.jpg',
              isDirectory: false,
            ),
            NextcloudRemoteEntry(
              path: '/albums/',
              name: 'albums',
              isDirectory: true,
            ),
          ],
          '/albums/': const [
            NextcloudRemoteEntry(
              path: '/albums/pick-me.jpg',
              name: 'pick-me.jpg',
              isDirectory: false,
            ),
            NextcloudRemoteEntry(
              path: '/albums/sub/',
              name: 'sub',
              isDirectory: true,
            ),
          ],
          '/albums/sub/': const [
            NextcloudRemoteEntry(
              path: '/albums/sub/skip-me.jpg',
              name: 'skip-me.jpg',
              isDirectory: false,
            ),
          ],
        },
      );

      final service = NextcloudSyncService.fromPublicLink(
        'https://cloud.example.com/s/abc123',
        storageProvider,
        clientFactory: ({
          required String webDavUrl,
          required String user,
          required String password,
        }) => client,
        sourceConfig: const NextcloudSourceConfig(
          url: 'https://cloud.example.com/s/abc123',
          folderSyncMode: NextcloudFolderSyncMode.selectedFolders,
          selectedFolders: ['albums'],
        ),
      );

      await service.sync();

      expect(File('${tempDir.path}/root.jpg').existsSync(), isFalse);
      expect(File('${tempDir.path}/albums/pick-me.jpg').existsSync(), isTrue);
      expect(File('${tempDir.path}/albums/sub/skip-me.jpg').existsSync(), isFalse);
      expect(client.downloadedPaths, ['/albums/pick-me.jpg']);
    });

    test('sync deletes orphaned files using relative paths', () async {
      final orphanFile = File('${tempDir.path}/albums/orphan.jpg');
      await orphanFile.parent.create(recursive: true);
      await orphanFile.writeAsString('orphan');
      final keepFile = File('${tempDir.path}/albums/keep.jpg');
      await keepFile.writeAsString('old');
      final orphanRootFile = File('${tempDir.path}/root.jpg');
      await orphanRootFile.writeAsString('orphan-root');

      final client = FakeNextcloudRemoteClient(
        directories: {
          '/': const [
            NextcloudRemoteEntry(
              path: '/albums/',
              name: 'albums',
              isDirectory: true,
            ),
          ],
          '/albums/': const [
            NextcloudRemoteEntry(
              path: '/albums/keep.jpg',
              name: 'keep.jpg',
              isDirectory: false,
            ),
          ],
        },
      );

      final service = NextcloudSyncService.fromPublicLink(
        'https://cloud.example.com/s/abc123',
        storageProvider,
        clientFactory: ({
          required String webDavUrl,
          required String user,
          required String password,
        }) => client,
      );

      await service.sync(deleteOrphanedFiles: true);

      expect(keepFile.existsSync(), isTrue);
      expect(orphanFile.existsSync(), isFalse);
      expect(orphanRootFile.existsSync(), isFalse);
    });
  });
}