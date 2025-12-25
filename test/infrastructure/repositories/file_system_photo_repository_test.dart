import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_photo_frame/domain/interfaces/metadata_provider.dart';
import 'package:open_photo_frame/domain/interfaces/storage_provider.dart';
import 'package:open_photo_frame/infrastructure/repositories/file_system_photo_repository.dart';

// Mocks
class MockStorageProvider implements StorageProvider {
  Directory _dir;
  final _directoryChangedController = StreamController<void>.broadcast();
  
  MockStorageProvider(this._dir);
  
  @override
  Future<Directory> getPhotoDirectory() async => _dir;
  
  @override
  bool get isReadOnly => false;
  
  @override
  Stream<void> get onDirectoryChanged => _directoryChangedController.stream;
  
  /// Changes the directory and notifies listeners
  void changeDirectory(Directory newDir) {
    _dir = newDir;
    _directoryChangedController.add(null);
  }
  
  void dispose() {
    _directoryChangedController.close();
  }
}

class MockMetadataProvider implements MetadataProvider {
  @override
  Future<DateTime> getDate(File file) async => DateTime.now();
}

void main() {
  late Directory tempDir;
  late FileSystemPhotoRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_test_');
    repository = FileSystemPhotoRepository(
      storageProvider: MockStorageProvider(tempDir),
      metadataProvider: MockMetadataProvider(),
    );
  });

  tearDown(() async {
    repository.dispose();
    await tempDir.delete(recursive: true);
  });

  test('initialize scans existing photos', () async {
    // Arrange
    final file = File('${tempDir.path}/test.jpg');
    await file.create();

    // Act
    await repository.initialize();

    // Assert
    expect(repository.photos.length, 1);
    expect(repository.photos.first.file.path, file.path);
  });

  test('detects new files via watcher', () async {
    // Arrange
    await repository.initialize();
    expect(repository.photos.length, 0);

    // Act
    final file = File('${tempDir.path}/new.jpg');
    await file.create();

    // Wait for watcher (it's async)
    await Future.delayed(const Duration(seconds: 1));

    // Assert
    expect(repository.photos.length, 1);
    expect(repository.photos.first.file.path, file.path);
  });

  test('ignores .part files', () async {
    // Arrange
    await repository.initialize();

    // Act
    final file = File('${tempDir.path}/download.part');
    await file.create();

    // Wait for watcher
    await Future.delayed(const Duration(seconds: 1));

    // Assert
    expect(repository.photos.length, 0);
  });

  test('detects rename from .part to .jpg', () async {
    // Arrange
    await repository.initialize();
    final partFile = File('${tempDir.path}/image.part');
    await partFile.create();
    await Future.delayed(const Duration(milliseconds: 500));
    expect(repository.photos.length, 0);

    // Act
    final jpgFile = await partFile.rename('${tempDir.path}/image.jpg');

    // Wait for watcher
    await Future.delayed(const Duration(seconds: 1));

    // Assert
    expect(repository.photos.length, 1);
    expect(repository.photos.first.file.path, jpgFile.path);
  });
}
