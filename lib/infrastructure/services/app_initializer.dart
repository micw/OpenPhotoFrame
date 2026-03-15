import 'package:intl/date_symbol_data_local.dart' as intl;

import '../../domain/interfaces/config_provider.dart';
import 'android_runtime_settings_sync.dart';

class AppInitializer {
  final ConfigProvider _configProvider;
  final AndroidRuntimeSettingsSync _runtimeSettingsSync;
  final Future<void> Function() _initializeDateFormatting;

  AppInitializer({
    required ConfigProvider configProvider,
    AndroidRuntimeSettingsSync? runtimeSettingsSync,
    Future<void> Function()? initializeDateFormatting,
  })  : _configProvider = configProvider,
        _runtimeSettingsSync =
            runtimeSettingsSync ?? AndroidRuntimeSettingsSync(),
        _initializeDateFormatting =
            initializeDateFormatting ?? intl.initializeDateFormatting;

  Future<void> initialize() async {
    await _configProvider.load();
    await _runtimeSettingsSync.syncFromConfig(_configProvider);
    await _initializeDateFormatting();
  }
}