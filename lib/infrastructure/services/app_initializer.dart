import 'package:intl/date_symbol_data_local.dart' as intl;

import '../../domain/interfaces/config_provider.dart';
import 'android_runtime_settings_sync.dart';
import 'json_config_service.dart';

class AppInitializationResult {
  const AppInitializationResult({
    this.configLoadResult = const ConfigLoadResult.clean(),
  });

  final ConfigLoadResult configLoadResult;
}

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

  Future<AppInitializationResult> initialize() async {
    await _configProvider.load();
    final configLoadResult = _configProvider is JsonConfigService
        ? (_configProvider as JsonConfigService).lastLoadResult
        : const ConfigLoadResult.clean();
    await _runtimeSettingsSync.syncFromConfig(_configProvider);
    await _initializeDateFormatting();
    return AppInitializationResult(configLoadResult: configLoadResult);
  }
}