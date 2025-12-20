import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_photo_frame/domain/interfaces/metadata_provider.dart';
import 'package:open_photo_frame/domain/interfaces/storage_provider.dart';
import 'package:open_photo_frame/infrastructure/repositories/file_system_photo_repository.dart';

// Mock implementations
class MockStorageProvider implements StorageProvider {
  final Directory _testDir;
  
  MockStorageProvider(this._testDir);
  
  @override
  Future<Directory> getPhotoDirectory() async => _testDir;
}

class MockMetadataProvider implements MetadataProvider {
  @override
  Future<DateTime> getDate(File file) async {
    // Return a fixed date for testing
    return DateTime(2024, 1, 1);
  }
}

void main() {
  group('FileSystemPhotoRepository - State Preservation', () {
    late Directory tempDir;
    late FileSystemPhotoRepository repository;

    setUp(() async {
      // Create temporary directory for test files
      tempDir = await Directory.systemTemp.createTemp('photo_repo_test_');
      
      final storageProvider = MockStorageProvider(tempDir);
      final metadataProvider = MockMetadataProvider();
      
      repository = FileSystemPhotoRepository(
        storageProvider: storageProvider,
        metadataProvider: metadataProvider,
      );
    });

    tearDown(() async {
      repository.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should preserve lastShown state across rescans', () async {
      // Create initial photo files
      final file1 = File('${tempDir.path}/photo1.jpg');
      final file2 = File('${tempDir.path}/photo2.jpg');
      await file1.writeAsString('fake image 1');
      await file2.writeAsString('fake image 2');

      // Initial scan
      await repository.initialize();
      expect(repository.photos.length, equals(2));

      // Mark photos as shown
      final photo1 = repository.photos.firstWhere((p) => p.file.path == file1.path);
      final photo2 = repository.photos.firstWhere((p) => p.file.path == file2.path);
      
      final timestamp1 = DateTime.now().subtract(const Duration(minutes: 10));
      final timestamp2 = DateTime.now().subtract(const Duration(minutes: 5));
      
      photo1.lastShown = timestamp1;
      photo2.lastShown = timestamp2;
      
      // Set some weights
      photo1.weight = 42.0;
      photo2.weight = 23.5;

      // Trigger rescan by creating a new file (this will call _scanLocalPhotos)
      final file3 = File('${tempDir.path}/photo3.jpg');
      await file3.writeAsString('fake image 3');
      
      // Wait a bit for file watcher to trigger (if it exists)
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Force a rescan manually to be sure
      await repository.initialize();

      // Verify state is preserved
      expect(repository.photos.length, equals(3));
      
      final photo1After = repository.photos.firstWhere((p) => p.file.path == file1.path);
      final photo2After = repository.photos.firstWhere((p) => p.file.path == file2.path);
      
      expect(photo1After.lastShown, equals(timestamp1),
          reason: 'lastShown timestamp should be preserved across rescan');
      expect(photo2After.lastShown, equals(timestamp2),
          reason: 'lastShown timestamp should be preserved across rescan');
      
      expect(photo1After.weight, equals(42.0),
          reason: 'weight should be preserved across rescan');
      expect(photo2After.weight, equals(23.5),
          reason: 'weight should be preserved across rescan');
    });

    test('should maintain same instance reference for unchanged files', () async {
      // Create photo file
      final file1 = File('${tempDir.path}/photo1.jpg');
      await file1.writeAsString('fake image');

      // Initial scan
      await repository.initialize();
      final photo1Before = repository.photos.first;

      // Trigger rescan
      await repository.initialize();
      final photo1After = repository.photos.first;

      // Should be the EXACT SAME instance
      expect(identical(photo1Before, photo1After), isTrue,
          reason: 'Unchanged files should maintain the same PhotoEntry instance');
    });

    test('should create new instance only for new files', () async {
      // Create initial file
      final file1 = File('${tempDir.path}/photo1.jpg');
      await file1.writeAsString('fake image');

      await repository.initialize();
      final photo1 = repository.photos.first;
      photo1.lastShown = DateTime.now();
      photo1.weight = 100.0;

      // Add new file
      final file2 = File('${tempDir.path}/photo2.jpg');
      await file2.writeAsString('fake image 2');

      await repository.initialize();
      
      expect(repository.photos.length, equals(2));
      
      final photo1After = repository.photos.firstWhere((p) => p.file.path == file1.path);
      final photo2 = repository.photos.firstWhere((p) => p.file.path == file2.path);

      // Photo1 should maintain state
      expect(photo1After.weight, equals(100.0));
      expect(photo1After.lastShown, isNotNull);

      // Photo2 should be fresh (new instance)
      expect(photo2.weight, equals(0)); // Not yet calculated
      expect(photo2.lastShown, isNull);
    });

    test('should handle file deletion correctly', () async {
      // Create files
      final file1 = File('${tempDir.path}/photo1.jpg');
      final file2 = File('${tempDir.path}/photo2.jpg');
      await file1.writeAsString('fake image 1');
      await file2.writeAsString('fake image 2');

      await repository.initialize();
      expect(repository.photos.length, equals(2));

      // Delete one file
      await file1.delete();
      await repository.initialize();

      // Should only have one photo now
      expect(repository.photos.length, equals(1));
      expect(repository.photos.first.file.path, equals(file2.path));
    });
  });
}
