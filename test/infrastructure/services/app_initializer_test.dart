import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_photo_frame/domain/interfaces/config_provider.dart';
import 'package:open_photo_frame/infrastructure/services/android_runtime_settings_sync.dart';
import 'package:open_photo_frame/infrastructure/services/app_initializer.dart';

class FakeConfigProvider extends ChangeNotifier implements ConfigProvider {
  FakeConfigProvider({
    this.autostartOnBoot = false,
    this.keepAliveEnabled = false,
  });

  bool loadCalled = false;

  @override
  Future<void> load() async {
    loadCalled = true;
  }

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
  bool autostartOnBoot;

  @override
  bool keepAliveEnabled;

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

class RecordingAndroidRuntimeSettingsWriter
    implements AndroidRuntimeSettingsWriter {
  bool? autostartEnabled;
  bool? keepAliveEnabled;
  final List<String> callOrder = [];

  @override
  Future<void> setAutostartEnabled(bool enabled) async {
    autostartEnabled = enabled;
    callOrder.add('autostart');
  }

  @override
  Future<void> setKeepAliveEnabled(bool enabled) async {
    keepAliveEnabled = enabled;
    callOrder.add('keepAlive');
  }
}

void main() {
  test('initializer loads config before syncing Android runtime settings',
      () async {
    final configProvider =
        FakeConfigProvider(autostartOnBoot: true, keepAliveEnabled: true);
    final writer = RecordingAndroidRuntimeSettingsWriter();
    var dateFormattingInitialized = false;

    final initializer = AppInitializer(
      configProvider: configProvider,
      runtimeSettingsSync: AndroidRuntimeSettingsSync(writer: writer),
      initializeDateFormatting: () async {
        dateFormattingInitialized = true;
      },
    );

    await initializer.initialize();

    expect(configProvider.loadCalled, isTrue);
    expect(writer.autostartEnabled, isTrue);
    expect(writer.keepAliveEnabled, isTrue);
    expect(writer.callOrder, ['autostart', 'keepAlive']);
    expect(dateFormattingInitialized, isTrue);
  });
}