import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_photo_frame/infrastructure/services/json_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('json_config_service_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  JsonConfigService createService() {
    return JsonConfigService(
      defaultConfigLoader: () async => json.encode({
        'slide_duration_seconds': 600,
        'transition_duration_ms': 2000,
        'blur_borders': true,
        'sync_interval_minutes': 15,
        'delete_orphaned_files': true,
        'active_source': '',
        'sources': {
          'nextcloud_link': {
            'url': '',
            'folder_sync_mode': 'all',
            'selected_folders': <String>[],
          },
        },
      }),
      documentsDirectoryProvider: () async => tempDir,
    );
  }

  Directory configDirectory() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return Directory('${tempDir.path}/OpenPhotoFrame');
    }
    return tempDir;
  }

  File configFile() => File('${configDirectory().path}/config.json');
  File backupFile() => File('${configFile().path}.bak');

  test('load falls back to backup when config is unreadable', () async {
    await configDirectory().create(recursive: true);
    await configFile().writeAsString('');
    await backupFile().writeAsString(json.encode({
      'sync_interval_minutes': 7,
      'active_source': 'nextcloud_link',
    }));

    final service = createService();

    await service.load();

    expect(service.lastLoadResult.state, ConfigLoadState.recoveredFromBackup);
    expect(service.syncIntervalMinutes, 7);
    expect(service.activeSourceType, 'nextcloud_link');

    final repairedConfig = json.decode(await configFile().readAsString()) as Map<String, dynamic>;
    expect(repairedConfig['sync_interval_minutes'], 7);
    expect(repairedConfig['active_source'], 'nextcloud_link');
    expect(await backupFile().readAsString(), await configFile().readAsString());
  });

  test('load falls back to defaults when config and backup are unreadable', () async {
    await configDirectory().create(recursive: true);
    await configFile().writeAsString('');
    await backupFile().writeAsString('{');

    final service = createService();

    await service.load();

    expect(service.lastLoadResult.state, ConfigLoadState.resetToDefaults);
    expect(service.syncIntervalMinutes, 15);
    expect(service.activeSourceType, '');

    final repairedConfig = json.decode(await configFile().readAsString()) as Map<String, dynamic>;
    expect(repairedConfig['sync_interval_minutes'], 15);
    expect(repairedConfig['active_source'], '');
    expect(await backupFile().readAsString(), await configFile().readAsString());
  });

  test('save updates primary and backup config atomically from memory', () async {
    final service = createService();

    await service.load();
    service.syncIntervalMinutes = 23;
    service.activeSourceType = 'nextcloud_link';

    await service.save();

    final mainConfig = await configFile().readAsString();
    final backupConfig = await backupFile().readAsString();

    expect(mainConfig, backupConfig);

    final decoded = json.decode(mainConfig) as Map<String, dynamic>;
    expect(decoded['sync_interval_minutes'], 23);
    expect(decoded['active_source'], 'nextcloud_link');
  });
}