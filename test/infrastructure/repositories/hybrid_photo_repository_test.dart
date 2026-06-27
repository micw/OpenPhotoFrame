import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_photo_frame/domain/interfaces/config_provider.dart';
import 'package:open_photo_frame/domain/interfaces/metadata_provider.dart';
import 'package:open_photo_frame/domain/interfaces/storage_provider.dart';
import 'package:open_photo_frame/infrastructure/repositories/hybrid_photo_repository.dart';

class FakeConfigProvider extends ChangeNotifier implements ConfigProvider {
  @override
  Future<void> load() async {}

  @override
  Future<void> save() async {}

  @override
  bool useAmPm = false;

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
  bool get blurBorders => true;

  @override
  set blurBorders(bool value) {}

  @override
  int get syncIntervalMinutes => 0;

  @override
  set syncIntervalMinutes(int value) {}

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
  bool get keepAliveEnabled => false;

  @override
  set keepAliveEnabled(bool value) {}

  @override
  bool get autoUpdateEnabled => false;
  @override
  set autoUpdateEnabled(bool value) {}
  @override
  bool get autoUpdateSilent => false;
  @override
  set autoUpdateSilent(bool value) {}
  @override
  String? get autoUpdateSkippedVersion => null;
  @override
  set autoUpdateSkippedVersion(String? value) {}
  @override
  DateTime? get autoUpdateLastCheck => null;
  @override
  set autoUpdateLastCheck(DateTime? value) {}

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
  int? get fridaySaturdayNightStartHour => null;

  @override
  set fridaySaturdayNightStartHour(int? value) {}

  @override
  int? get fridaySaturdayNightStartMinute => null;

  @override
  set fridaySaturdayNightStartMinute(int? value) {}

  @override
  bool get useNativeScreenOff => false;

  @override
  set useNativeScreenOff(bool value) {}

  @override
  String? get customPhotoPath => null;

  @override
  set customPhotoPath(String? value) {}

  @override
  bool get showPhotoInfo => false;

  @override
  set showPhotoInfo(bool value) {}

  @override
  String get photoInfoPosition => 'bottomRight';

  @override
  set photoInfoPosition(String value) {}

  @override
  String get photoInfoSize => 'large';

  @override
  set photoInfoSize(String value) {}

  @override
  bool get useScriptFontForMetadata => false;

  @override
  set useScriptFontForMetadata(bool value) {}

  @override
  bool get geocodingEnabled => false;

  @override
  set geocodingEnabled(bool value) {}

  @override
  String get screenOrientation => 'auto';

  @override
  set screenOrientation(String value) {}
}

class FakeStorageProvider implements StorageProvider {
  FakeStorageProvider(this._directory);

  Directory _directory;
  final _directoryChangedController = StreamController<void>.broadcast();

  @override
  Future<Directory> getPhotoDirectory() async => _directory;

  @override
  bool get isReadOnly => false;

  @override
  Stream<void> get onDirectoryChanged => _directoryChangedController.stream;

  void changeDirectory(Directory newDirectory) {
    _directory = newDirectory;
    _directoryChangedController.add(null);
  }

  void dispose() {
    _directoryChangedController.close();
  }
}

class FakeMetadataProvider implements MetadataProvider {
  @override
  Future<ExifMetadata> getExifMetadata(File file) async => const ExifMetadata();
}

void main() {
  group('HybridPhotoRepository filesystem mode', () {
    late Directory tempDir;
    late FakeStorageProvider storageProvider;
    late HybridPhotoRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hybrid_photo_repo_test_');
      storageProvider = FakeStorageProvider(tempDir);
      repository = HybridPhotoRepository(
        storageProvider: storageProvider,
        metadataProvider: FakeMetadataProvider(),
        configProvider: FakeConfigProvider(),
      );
    });

    tearDown(() async {
      repository.dispose();
      storageProvider.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initialize scans nested filesystem photos recursively', () async {
      final nestedFile = File('${tempDir.path}/nested/album/test.jpg');
      await nestedFile.parent.create(recursive: true);
      await nestedFile.writeAsString('nested image');

      await repository.initialize();

      expect(repository.photos.length, 1);
      expect(repository.photos.first.file.path, nestedFile.path);
    });

    test('recursive watcher picks up nested filesystem changes', () async {
      await repository.initialize();
      expect(repository.photos, isEmpty);

      final nestedFile = File('${tempDir.path}/nested/new.png');
      await nestedFile.parent.create(recursive: true);
      await nestedFile.writeAsString('new image');

      await Future.delayed(const Duration(seconds: 1));

      expect(repository.photos.length, 1);
      expect(repository.photos.first.file.path, nestedFile.path);
    });
  });
}