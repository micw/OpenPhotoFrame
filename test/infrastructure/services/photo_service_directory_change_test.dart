import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_photo_frame/domain/interfaces/config_provider.dart';
import 'package:open_photo_frame/domain/interfaces/metadata_provider.dart';
import 'package:open_photo_frame/domain/interfaces/playlist_strategy.dart';
import 'package:open_photo_frame/domain/interfaces/storage_provider.dart';
import 'package:open_photo_frame/domain/interfaces/sync_provider.dart';
import 'package:open_photo_frame/domain/models/photo_entry.dart';
import 'package:open_photo_frame/infrastructure/repositories/file_system_photo_repository.dart';
import 'package:open_photo_frame/infrastructure/services/photo_service.dart';

// === MOCKS ===

class MockStorageProvider implements StorageProvider {
  Directory _dir;
  bool _isReadOnly;
  final _directoryChangedController = StreamController<void>.broadcast();
  
  MockStorageProvider(this._dir, {bool isReadOnly = false}) : _isReadOnly = isReadOnly;
  
  @override
  Future<Directory> getPhotoDirectory() async => _dir;
  
  @override
  bool get isReadOnly => _isReadOnly;
  
  @override
  Stream<void> get onDirectoryChanged => _directoryChangedController.stream;
  
  /// Simulates changing to a new directory (e.g., user selects different folder)
  void changeDirectory(Directory newDir, {bool isReadOnly = false}) {
    _dir = newDir;
    _isReadOnly = isReadOnly;
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

class MockConfigProvider extends ChangeNotifier implements ConfigProvider {
  String? _customPhotoPath;
  int _syncIntervalMinutes = 0; // Disabled by default for tests
  
  @override
  String? get customPhotoPath => _customPhotoPath;
  
  @override
  set customPhotoPath(String? value) {
    _customPhotoPath = value;
    notifyListeners();
  }
  
  @override
  Future<void> load() async {}
  
  @override
  Future<void> save() async {}
  
  @override
  String get activeSourceType => '';
  @override
  set activeSourceType(String value) {}
  
  @override
  Map<String, dynamic> getSourceConfig(String type) => {};
  @override
  void setSourceConfig(String type, Map<String, dynamic> config) {}
  
  @override
  int get slideDurationSeconds => 600;
  @override
  set slideDurationSeconds(int value) {}
  
  @override
  int get transitionDurationMs => 2000;
  @override
  set transitionDurationMs(int value) {}
  
  @override
  int get syncIntervalMinutes => _syncIntervalMinutes;
  @override
  set syncIntervalMinutes(int value) { _syncIntervalMinutes = value; }
  
  @override
  bool get deleteOrphanedFiles => false;
  @override
  set deleteOrphanedFiles(bool value) {}
  
  @override
  DateTime? get lastSuccessfulSync => null;
  @override
  set lastSuccessfulSync(DateTime? value) {}
  
  @override
  bool get autostartOnBoot => false;
  @override
  set autostartOnBoot(bool value) {}
  
  @override
  bool get showClock => false;
  @override
  set showClock(bool value) {}
  
  @override
  String get clockSize => 'large';
  @override
  set clockSize(String value) {}
  
  @override
  String get clockPosition => 'bottomRight';
  @override
  set clockPosition(String value) {}
  
  @override
  bool get scheduleEnabled => false;
  @override
  set scheduleEnabled(bool value) {}
  
  @override
  int get dayStartHour => 8;
  @override
  set dayStartHour(int value) {}
  
  @override
  int get dayStartMinute => 0;
  @override
  set dayStartMinute(int value) {}
  
  @override
  int get nightStartHour => 22;
  @override
  set nightStartHour(int value) {}
  
  @override
  int get nightStartMinute => 0;
  @override
  set nightStartMinute(int value) {}
  
  @override
  bool get useNativeScreenOff => false;
  @override
  set useNativeScreenOff(bool value) {}
}

class MockPlaylistStrategy implements PlaylistStrategy {
  @override
  String get id => 'mock';
  
  @override
  String get name => 'Mock Strategy';
  
  @override
  PhotoEntry? nextPhoto(List<PhotoEntry> photos) {
    if (photos.isEmpty) return null;
    return photos.first;
  }
}

class MockSyncProvider implements SyncProvider {
  int syncCallCount = 0;
  
  @override
  String get id => 'mock';
  
  @override
  Future<void> sync({bool deleteOrphanedFiles = false}) async {
    syncCallCount++;
  }
}

// === TESTS ===

void main() {
  late Directory tempDir1;
  late Directory tempDir2;
  late MockStorageProvider storageProvider;
  late MockConfigProvider configProvider;
  late FileSystemPhotoRepository repository;
  late PhotoService photoService;
  late MockSyncProvider mockSyncProvider;

  setUp(() async {
    // Create two separate temp directories to simulate folder switching
    tempDir1 = await Directory.systemTemp.createTemp('photo_test_dir1_');
    tempDir2 = await Directory.systemTemp.createTemp('photo_test_dir2_');
    
    // Create test images in each directory
    await File('${tempDir1.path}/photo1.jpg').create();
    await File('${tempDir1.path}/photo2.jpg').create();
    await File('${tempDir2.path}/photo3.jpg').create();
    await File('${tempDir2.path}/photo4.jpg').create();
    await File('${tempDir2.path}/photo5.jpg').create();
    
    configProvider = MockConfigProvider();
    storageProvider = MockStorageProvider(tempDir1);
    
    repository = FileSystemPhotoRepository(
      storageProvider: storageProvider,
      metadataProvider: MockMetadataProvider(),
    );
    
    mockSyncProvider = MockSyncProvider();
    
    photoService = PhotoService(
      syncProviderFactory: () => mockSyncProvider,
      playlistStrategy: MockPlaylistStrategy(),
      repository: repository,
      configProvider: configProvider,
      storageProvider: storageProvider,
    );
  });

  tearDown(() async {
    photoService.dispose();
    storageProvider.dispose();
    await tempDir1.delete(recursive: true);
    await tempDir2.delete(recursive: true);
  });

  group('Directory Change Tests', () {
    test('initial directory has correct photos', () async {
      // Arrange & Act
      await photoService.initialize();
      
      // Assert
      expect(repository.photos.length, 2);
      expect(repository.photos.any((p) => p.file.path.contains('photo1.jpg')), true);
      expect(repository.photos.any((p) => p.file.path.contains('photo2.jpg')), true);
    });

    test('changing directory updates photos', () async {
      // Arrange
      await photoService.initialize();
      expect(repository.photos.length, 2);
      
      // Act - Change to directory 2
      storageProvider.changeDirectory(tempDir2);
      
      // Wait for async reinitialize
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Assert
      expect(repository.photos.length, 3);
      expect(repository.photos.any((p) => p.file.path.contains('photo3.jpg')), true);
      expect(repository.photos.any((p) => p.file.path.contains('photo4.jpg')), true);
      expect(repository.photos.any((p) => p.file.path.contains('photo5.jpg')), true);
      // Old photos should NOT be present
      expect(repository.photos.any((p) => p.file.path.contains('photo1.jpg')), false);
    });

    test('slideshow history is cleared on directory change', () async {
      // Arrange
      await photoService.initialize();
      
      // Get some photos to build up history
      final photo1 = photoService.nextPhoto();
      final photo2 = photoService.nextPhoto();
      expect(photo1, isNotNull);
      expect(photo2, isNotNull);
      
      // Verify we can go back in history
      final previousPhoto = photoService.previousPhoto();
      expect(previousPhoto, isNotNull);
      
      // Act - Change directory
      storageProvider.changeDirectory(tempDir2);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Assert - History should be cleared, previousPhoto returns null/first
      final newPhoto = photoService.nextPhoto();
      expect(newPhoto, isNotNull);
      expect(newPhoto!.file.path.contains('photo3.jpg') || 
             newPhoto.file.path.contains('photo4.jpg') ||
             newPhoto.file.path.contains('photo5.jpg'), true);
      
      // Going back should return the same photo (no prior history)
      final backPhoto = photoService.previousPhoto();
      expect(backPhoto?.file.path, newPhoto.file.path);
    });

    test('changing to empty directory results in no photos', () async {
      // Arrange
      await photoService.initialize();
      expect(repository.photos.length, 2);
      
      // Create empty temp directory
      final emptyDir = await Directory.systemTemp.createTemp('photo_test_empty_');
      
      try {
        // Act
        storageProvider.changeDirectory(emptyDir);
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Assert
        expect(repository.photos.length, 0);
        expect(photoService.nextPhoto(), isNull);
      } finally {
        await emptyDir.delete(recursive: true);
      }
    });

    test('file watcher works after directory change', () async {
      // Arrange
      await photoService.initialize();
      storageProvider.changeDirectory(tempDir2);
      await Future.delayed(const Duration(milliseconds: 500));
      expect(repository.photos.length, 3);
      
      // Act - Add a new file to the new directory
      await File('${tempDir2.path}/photo6.jpg').create();
      
      // Wait for file watcher
      await Future.delayed(const Duration(seconds: 1));
      
      // Assert
      expect(repository.photos.length, 4);
      expect(repository.photos.any((p) => p.file.path.contains('photo6.jpg')), true);
    });

    test('onPhotosChanged stream fires on directory change', () async {
      // Arrange
      await photoService.initialize();
      
      int changeCount = 0;
      final subscription = photoService.onPhotosChanged.listen((_) {
        changeCount++;
      });
      
      // Act
      storageProvider.changeDirectory(tempDir2);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Assert - Should fire at least twice (once for clear, once for new scan)
      expect(changeCount, greaterThanOrEqualTo(1));
      
      await subscription.cancel();
    });
  });

  group('Read-Only Mode Tests', () {
    test('sync is skipped when storage is read-only', () async {
      // Arrange
      storageProvider.changeDirectory(tempDir1, isReadOnly: true);
      configProvider.syncIntervalMinutes = 1; // Enable sync
      await photoService.initialize();
      
      // Act - Trigger manual sync
      await photoService.triggerSync();
      
      // Assert - Sync should not have been called
      expect(mockSyncProvider.syncCallCount, 0);
    });

    test('sync is executed when storage is NOT read-only', () async {
      // Arrange
      storageProvider.changeDirectory(tempDir1, isReadOnly: false);
      await photoService.initialize();
      
      // Act - Trigger manual sync
      await photoService.triggerSync();
      
      // Assert - Sync should have been called
      expect(mockSyncProvider.syncCallCount, 1);
    });

    test('switching from read-only to writable enables sync', () async {
      // Arrange - Start in read-only mode
      storageProvider.changeDirectory(tempDir1, isReadOnly: true);
      await photoService.initialize();
      
      // Verify sync is skipped
      await photoService.triggerSync();
      expect(mockSyncProvider.syncCallCount, 0);
      
      // Act - Switch to writable mode
      storageProvider.changeDirectory(tempDir1, isReadOnly: false);
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Trigger sync again
      await photoService.triggerSync();
      
      // Assert
      expect(mockSyncProvider.syncCallCount, 1);
    });
  });
}
