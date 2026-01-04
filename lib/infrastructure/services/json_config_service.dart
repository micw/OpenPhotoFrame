import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/interfaces/config_provider.dart';

class JsonConfigService extends ConfigProvider {
  final _log = Logger('JsonConfigService');
  Map<String, dynamic> _config = {};
  File? _configFile;

  @override
  Future<void> load() async {
    try {
      // 1. Load asset config as base (contains all defaults)
      final defaultJsonString = await rootBundle.loadString('assets/config.json');
      _config = json.decode(defaultJsonString);
      _log.info("Loaded default config from assets");
      
      // 2. Determine user config path
      final dir = await getApplicationDocumentsDirectory();
      // Use a subfolder on Desktop to keep things tidy
      final configDir = (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
          ? Directory('${dir.path}/OpenPhotoFrame')
          : dir;
          
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      _configFile = File('${configDir.path}/config.json');

      // 3. Load user config and merge over defaults
      if (await _configFile!.exists()) {
        _log.info("Loading user config from ${_configFile!.path}");
        final userJsonString = await _configFile!.readAsString();
        final userConfig = json.decode(userJsonString) as Map<String, dynamic>;
        
        // Deep merge: user config overwrites defaults
        _mergeConfig(_config, userConfig);
      } else {
        _log.info("No user config found at ${_configFile!.path}");
      }

      _log.info("Config loaded successfully. Active source: $activeSourceType");
    } catch (e) {
      _log.severe("Failed to load config", e);
      rethrow;
    }
  }
  
  /// Recursively merges [overlay] into [base], modifying [base] in place.
  void _mergeConfig(Map<String, dynamic> base, Map<String, dynamic> overlay) {
    for (final key in overlay.keys) {
      if (base[key] is Map<String, dynamic> && overlay[key] is Map<String, dynamic>) {
        _mergeConfig(base[key] as Map<String, dynamic>, overlay[key] as Map<String, dynamic>);
      } else {
        base[key] = overlay[key];
      }
    }
  }

  @override
  Future<void> save() async {
    if (_configFile == null) {
      _log.warning("Cannot save config: config file not initialized");
      return;
    }
    try {
      final jsonString = const JsonEncoder.withIndent('  ').convert(_config);
      await _configFile!.writeAsString(jsonString);
      _log.info("Config saved successfully");
      notifyListeners(); // Notify UI to rebuild with new config values
    } catch (e) {
      _log.severe("Failed to save config", e);
    }
  }

  @override
  String get activeSourceType => _config['active_source'] ?? '';
  
  @override
  set activeSourceType(String value) {
    _config['active_source'] = value;
  }

  @override
  Map<String, dynamic> getSourceConfig(String type) {
    final sources = _config['sources'] as Map<String, dynamic>?;
    return Map<String, dynamic>.from(sources?[type] ?? {});
  }
  
  @override
  void setSourceConfig(String type, Map<String, dynamic> config) {
    _config['sources'] ??= <String, dynamic>{};
    (_config['sources'] as Map<String, dynamic>)[type] = config;
  }
  
  // Slideshow settings with defaults
  @override
  int get slideDurationSeconds => _config['slide_duration_seconds'] ?? 600;
  
  @override
  set slideDurationSeconds(int value) {
    _config['slide_duration_seconds'] = value;
  }
  
  @override
  int get transitionDurationMs => _config['transition_duration_ms'] ?? 2000;
  
  @override
  set transitionDurationMs(int value) {
    _config['transition_duration_ms'] = value;
  }
  
  // Sync settings
  @override
  int get syncIntervalMinutes => _config['sync_interval_minutes'] ?? 15;
  
  @override
  set syncIntervalMinutes(int value) {
    _config['sync_interval_minutes'] = value;
  }
  
  @override
  bool get deleteOrphanedFiles => _config['delete_orphaned_files'] ?? true;
  
  @override
  set deleteOrphanedFiles(bool value) {
    _config['delete_orphaned_files'] = value;
  }
  
  @override
  DateTime? get lastSuccessfulSync {
    final timestamp = _config['last_successful_sync'];
    if (timestamp == null) return null;
    return DateTime.tryParse(timestamp);
  }
  
  @override
  set lastSuccessfulSync(DateTime? value) {
    _config['last_successful_sync'] = value?.toIso8601String();
  }
  
  @override
  bool get autostartOnBoot => _config['autostart_on_boot'] ?? false;
  
  @override
  set autostartOnBoot(bool value) {
    _config['autostart_on_boot'] = value;
  }
  
  @override
  bool get keepAliveEnabled => _config['keep_alive_enabled'] ?? false;
  
  @override
  set keepAliveEnabled(bool value) {
    _config['keep_alive_enabled'] = value;
  }
  
  // Clock display settings
  @override
  bool get showClock => _config['show_clock'] ?? true;
  
  @override
  set showClock(bool value) {
    _config['show_clock'] = value;
  }
  
  @override
  String get clockSize => _config['clock_size'] ?? 'large';
  
  @override
  set clockSize(String value) {
    _config['clock_size'] = value;
  }
  
  @override
  String get clockPosition => _config['clock_position'] ?? 'bottomRight';
  
  @override
  set clockPosition(String value) {
    _config['clock_position'] = value;
  }
  
  // Display schedule settings (day/night mode)
  @override
  bool get scheduleEnabled => _config['schedule_enabled'] ?? false;
  
  @override
  set scheduleEnabled(bool value) {
    _config['schedule_enabled'] = value;
  }
  
  @override
  int get dayStartHour => _config['day_start_hour'] ?? 8;
  
  @override
  set dayStartHour(int value) {
    _config['day_start_hour'] = value;
  }
  
  @override
  int get dayStartMinute => _config['day_start_minute'] ?? 0;
  
  @override
  set dayStartMinute(int value) {
    _config['day_start_minute'] = value;
  }
  
  @override
  int get nightStartHour => _config['night_start_hour'] ?? 22;
  
  @override
  set nightStartHour(int value) {
    _config['night_start_hour'] = value;
  }
  
  @override
  int get nightStartMinute => _config['night_start_minute'] ?? 0;
  
  @override
  set nightStartMinute(int value) {
    _config['night_start_minute'] = value;
  }
  
  @override
  bool get useNativeScreenOff => _config['use_native_screen_off'] ?? false;
  
  @override
  set useNativeScreenOff(bool value) {
    _config['use_native_screen_off'] = value;
  }
  
  // Custom photo directory (for "local folder" mode)
  @override
  String? get customPhotoPath => _config['custom_photo_path'];
  
  @override
  set customPhotoPath(String? value) {
    if (value == null) {
      _config.remove('custom_photo_path');
    } else {
      _config['custom_photo_path'] = value;
    }
  }
  
  // Photo info overlay settings
  @override
  bool get showPhotoInfo => _config['show_photo_info'] ?? false;
  
  @override
  set showPhotoInfo(bool value) {
    _config['show_photo_info'] = value;
  }
  
  @override
  String get photoInfoPosition => _config['photo_info_position'] ?? 'topLeft';
  
  @override
  set photoInfoPosition(String value) {
    _config['photo_info_position'] = value;
  }
  
  @override
  String get photoInfoSize => _config['photo_info_size'] ?? 'small';
  
  @override
  set photoInfoSize(String value) {
    _config['photo_info_size'] = value;
  }
  
  @override
  bool get useScriptFontForMetadata => _config['use_script_font_for_metadata'] ?? false;
  
  @override
  set useScriptFontForMetadata(bool value) {
    _config['use_script_font_for_metadata'] = value;
  }
  
  // Geocoding settings
  @override
  bool get geocodingEnabled => _config['geocoding_enabled'] ?? false;
  
  @override
  set geocodingEnabled(bool value) {
    _config['geocoding_enabled'] = value;
  }
}
