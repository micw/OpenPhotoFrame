import '../../domain/interfaces/config_provider.dart';
import 'autostart_service.dart';
import 'keep_alive_service.dart';
import 'wifi_adb_service.dart';

abstract class AndroidRuntimeSettingsWriter {
  Future<void> setAutostartEnabled(bool enabled);

  Future<void> setKeepAliveEnabled(bool enabled);

  Future<void> setWifiAdbEnabled(bool enabled);
}

class SharedPreferencesAndroidRuntimeSettingsWriter
    implements AndroidRuntimeSettingsWriter {
  @override
  Future<void> setAutostartEnabled(bool enabled) {
    return AutostartService.setEnabled(enabled);
  }

  @override
  Future<void> setKeepAliveEnabled(bool enabled) {
    return KeepAliveService.setEnabled(enabled);
  }

  @override
  Future<void> setWifiAdbEnabled(bool enabled) {
    return WifiAdbService.setEnabled(enabled);
  }
}

class AndroidRuntimeSettingsSync {
  final AndroidRuntimeSettingsWriter _writer;

  AndroidRuntimeSettingsSync({AndroidRuntimeSettingsWriter? writer})
      : _writer = writer ?? SharedPreferencesAndroidRuntimeSettingsWriter();

  Future<void> syncFromConfig(ConfigProvider configProvider) async {
    await _writer.setAutostartEnabled(configProvider.autostartOnBoot);
    await _writer.setKeepAliveEnabled(configProvider.keepAliveEnabled);
    await _writer.setWifiAdbEnabled(configProvider.wifiAdbEnabled);
  }
}