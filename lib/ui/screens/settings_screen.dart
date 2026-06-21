import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:light_sensor/light_sensor.dart';
import '../../l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../domain/interfaces/config_provider.dart';
import '../../domain/interfaces/photo_repository.dart';
import '../../domain/interfaces/storage_provider.dart';
import '../../domain/interfaces/sync_provider.dart';
import '../../infrastructure/repositories/hybrid_photo_repository.dart';
import '../../infrastructure/services/photo_service.dart';
import '../../infrastructure/services/native_updater_service.dart';
import '../../infrastructure/services/update_service.dart';
import '../../infrastructure/services/webdav_source_config.dart';
import '../../infrastructure/services/webdav_sync_service.dart';
import '../../infrastructure/services/autostart_service.dart';
import '../../infrastructure/services/native_screen_control_service.dart';
import '../../infrastructure/services/keep_alive_service.dart';
import 'package:permission_handler/permission_handler.dart';

const PermissionRequestOption _devicePhotoPermissionRequest =
    PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: RequestType.image,
        mediaLocation: false,
      ),
    );

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  static const TimeOfDay _defaultFridaySaturdayNightStartTime = TimeOfDay(
    hour: 23,
    minute: 0,
  );

  late int _slideDurationMinutes;
  late double _transitionDurationSeconds;
  late bool _blurBorders;
  late String _syncType;
  late TextEditingController _nextcloudUrlController;
  late WebDavAuthMode _webdavAuthMode;
  late TextEditingController _webdavUserController;
  late TextEditingController _webdavPasswordController;
  late bool _webdavAllowInvalidCertificate;
  late int _syncIntervalMinutes;
  late bool _deleteOrphanedFiles;
  late bool _autostartOnBoot;
  late bool _keepAliveEnabled;
  late bool _autoUpdateEnabled;
  late bool _autoUpdateSilent;
  bool _isDeviceOwner = false;
  
  // Clock settings
  late bool _showClock;
  late String _clockSize;
  late String _clockPosition;
  
  // Photo info settings
  late bool _showPhotoInfo;
  late String _photoInfoPosition;
  late String _photoInfoSize;
  late bool _geocodingEnabled;
  late bool _useScriptFontForMetadata;
  
  // Display schedule settings
  late bool _scheduleEnabled;
  late TimeOfDay _dayStartTime;
  late TimeOfDay _nightStartTime;
  TimeOfDay? _fridaySaturdayNightStartTime;
  TimeOfDay? _lastFridaySaturdayNightStartTime;
  late bool _useNativeScreenOff;
  bool _deviceAdminEnabled = false;

  // Auto dark screen settings
  late bool _darkScreenEnabled;
  late int _darkScreenThreshold;
  late int _darkScreenOffset;
  late int _darkScreenOnDelay;
  late int _darkScreenOffDelay;
  int? _currentLux;
  StreamSubscription? _luxSubscription;

  // Screen orientation setting
  late String _screenOrientation;

  bool _isTestingConnection = false;
  String? _connectionTestResult;
  bool? _connectionTestSuccess;

  late WebDavFolderSyncMode _nextcloudFolderSyncMode;
  late Set<String> _selectedNextcloudFolders;
  List<WebDavFolder> _availableNextcloudFolders = [];
  // Number of locally synced images per folder path (relative). Used to show
  // "synced / total" in the picker.
  Map<String, int> _localFolderImageCounts = const {};
  bool _isLoadingNextcloudFolders = false;
  String? _nextcloudFolderLoadError;
  
  // Local folder path
  late String _localFolderPath;
  String _defaultFolderPath = '';
  String _appVersion = '';
  
  // Device photos album selection (Android only)
  List<AssetPathEntity> _availableAlbums = [];
  String? _selectedAlbumId;
  bool _isLoadingAlbums = false;
  
  // Track original values to detect changes
  late String _originalSyncType;
  late WebDavSourceConfig _originalWebDavSourceConfig;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Exit immersive mode to show status bar and navigation
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    
    // Allow all orientations in settings for easier configuration
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    
    final config = context.read<ConfigProvider>();
    _slideDurationMinutes = (config.slideDurationSeconds / 60).round().clamp(1, 15);
    _transitionDurationSeconds = (config.transitionDurationMs / 1000.0).clamp(0.5, 5.0);
    _blurBorders = config.blurBorders;
    // Default sync type: app_folder on Android, local_folder on Desktop
    final defaultSyncType = Platform.isAndroid ? 'app_folder' : 'local_folder';
    _syncType = config.activeSourceType.isEmpty ? defaultSyncType : config.activeSourceType;
    _localFolderPath = config.customPhotoPath ?? '';
    _syncIntervalMinutes = config.syncIntervalMinutes;
    _deleteOrphanedFiles = config.deleteOrphanedFiles;
    _autostartOnBoot = config.autostartOnBoot;
    _keepAliveEnabled = config.keepAliveEnabled;
    _autoUpdateEnabled = config.autoUpdateEnabled;
    _autoUpdateSilent = config.autoUpdateSilent;
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final isOwner = await NativeUpdaterService.isDeviceOwner();
        if (mounted) {
          setState(() => _isDeviceOwner = isOwner);
        }
      });
    }
    _showClock = config.showClock;
    _clockSize = config.clockSize;
    _clockPosition = config.clockPosition;
    
    // Photo info settings
    _showPhotoInfo = config.showPhotoInfo;
    _photoInfoPosition = config.photoInfoPosition;
    _photoInfoSize = config.photoInfoSize;
    _geocodingEnabled = config.geocodingEnabled;
    _useScriptFontForMetadata = config.useScriptFontForMetadata;
    
    // Display schedule settings
    _scheduleEnabled = config.scheduleEnabled;
    _dayStartTime = TimeOfDay(hour: config.dayStartHour, minute: config.dayStartMinute);
    _nightStartTime = TimeOfDay(hour: config.nightStartHour, minute: config.nightStartMinute);
    final fridaySaturdayNightStartHour = config.fridaySaturdayNightStartHour;
    final fridaySaturdayNightStartMinute = config.fridaySaturdayNightStartMinute;
    _fridaySaturdayNightStartTime =
        fridaySaturdayNightStartHour != null && fridaySaturdayNightStartMinute != null
        ? TimeOfDay(
            hour: fridaySaturdayNightStartHour,
            minute: fridaySaturdayNightStartMinute,
          )
        : null;
    _lastFridaySaturdayNightStartTime = _fridaySaturdayNightStartTime;
    _useNativeScreenOff = config.useNativeScreenOff;

    // Sensor based dark screen settings
    _darkScreenEnabled = config.darkScreenEnabled;
    _darkScreenThreshold = config.darkScreenThreshold;
    _darkScreenOffset = config.darkScreenOffset;
    _darkScreenOnDelay = config.darkScreenOnDelay;
    _darkScreenOffDelay = config.darkScreenOffDelay;

    LightSensor.hasSensor().then((has) {
      if (has) {
        _luxSubscription = LightSensor.luxStream().listen((lux) {
          if (mounted) setState(() => _currentLux = lux);
        });
      }
    });

    // Screen orientation
    _screenOrientation = config.screenOrientation;
    
    // Check Device Admin status
    _checkDeviceAdmin();
    
    final nextcloudConfig = WebDavSourceConfig.fromMap(
      config.getSourceConfig('nextcloud_link'),
    );
    _nextcloudUrlController = TextEditingController(
      text: nextcloudConfig.url,
    );
    _webdavAuthMode = nextcloudConfig.authMode;
    _webdavUserController = TextEditingController(text: nextcloudConfig.username);
    _webdavPasswordController = TextEditingController(
      text: nextcloudConfig.password,
    );
    _webdavAllowInvalidCertificate = nextcloudConfig.allowInvalidCertificate;
    _nextcloudFolderSyncMode = nextcloudConfig.folderSyncMode;
    _selectedNextcloudFolders = {...nextcloudConfig.normalizedSelectedFolders};
    // Restore the cached folder tree so the picker renders offline (no connection).
    // Fall back to the already-selected folders for configs saved before the
    // cache existed, so previously subscribed folders still show up offline.
    final cachedFileCounts = <String, int>{
      for (final folder in nextcloudConfig.cachedFolders)
        WebDavSourceConfig.normalizeFolderPath(folder.path): folder.fileCount,
    };
    final knownFolderPaths = <String>{
      ...cachedFileCounts.keys,
      ..._selectedNextcloudFolders,
    };
    _availableNextcloudFolders = (knownFolderPaths.toList()..sort())
        .map(
          (path) => WebDavFolder.fromPath(
            path,
            fileCount: cachedFileCounts[path] ?? 0,
          ),
        )
        .toList(growable: false);
    
    // Store original values for comparison on save
    _originalSyncType = _syncType;
    _originalWebDavSourceConfig = nextcloudConfig;
    
    // Load saved album selection for device_photos mode
    final devicePhotosConfig = config.getSourceConfig('device_photos');
    _selectedAlbumId = devicePhotosConfig['albumId'] as String?;
    
    // If device_photos is active, auto-load albums (permission already granted)
    if (_syncType == 'device_photos') {
      // Use post-frame callback to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDeviceAlbums();
      });
    }

    if (_syncType == 'nextcloud_link' &&
        nextcloudConfig.url.isNotEmpty &&
        _nextcloudFolderSyncMode == WebDavFolderSyncMode.selectedFolders) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshLocalFolderImageCounts();
        _loadAvailableNextcloudFolders();
      });
    }
    
    // Load default folder path async
    _loadDefaultFolderPath();
    _loadAppVersion();
  }
  
  Future<void> _loadDefaultFolderPath() async {
    // Get the actual default directory (not custom path)
    // We need to compute it the same way StorageProvider does
    Directory? baseDir;
    String subDirName = 'photos'; // Default for Android/Sandbox

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // On Desktop, use a distinct folder name in Documents
      baseDir = await getApplicationDocumentsDirectory();
      subDirName = 'OpenPhotoFrame';
    } else if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory();
    }
    
    baseDir ??= await getApplicationDocumentsDirectory();

    final dir = Directory('${baseDir.path}/$subDirName');
    
    if (mounted) {
      setState(() {
        _defaultFolderPath = dir.path;
      });
    }
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version.trim();

    if (mounted) {
      setState(() {
        _appVersion = version;
      });
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nextcloudUrlController.dispose();
    _webdavUserController.dispose();
    _webdavPasswordController.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check Device Admin status when app resumes (e.g., after granting permission)
    if (state == AppLifecycleState.resumed) {
      _checkDeviceAdmin();
    }
  }
  
  Future<void> _saveSettings() async {
    final config = context.read<ConfigProvider>();
    
    // Detect if sync configuration changed
    final newNextcloudUrl = _nextcloudUrlController.text.trim();
    final newWebDavSourceConfig = _buildWebDavSourceConfig(
      url: newNextcloudUrl,
    );
    final nextcloudConfigChanged =
      !_nextcloudConfigsEqual(newWebDavSourceConfig, _originalWebDavSourceConfig);
    final syncConfigChanged =
      _syncType != _originalSyncType ||
      (_syncType == 'nextcloud_link' && nextcloudConfigChanged);
    final newSyncSourceConfigured = syncConfigChanged && 
        _syncType == 'nextcloud_link' && 
        newNextcloudUrl.isNotEmpty;
    
    config.slideDurationSeconds = _slideDurationMinutes * 60;
    config.transitionDurationMs = (_transitionDurationSeconds * 1000).round();
    config.blurBorders = _blurBorders;
    // app_folder and local_folder both use empty activeSourceType (no sync)
    final isLocalMode = _syncType == 'local_folder' || _syncType == 'app_folder';
    config.activeSourceType = isLocalMode ? '' : _syncType;
    
    // Set custom photo path for local folder mode (Desktop only)
    if (_syncType == 'local_folder') {
      config.customPhotoPath = _localFolderPath.isNotEmpty ? _localFolderPath : null;
    } else {
      config.customPhotoPath = null;
    }
    config.syncIntervalMinutes = _syncIntervalMinutes;
    config.deleteOrphanedFiles = _deleteOrphanedFiles;
    config.autostartOnBoot = _autostartOnBoot;
    config.keepAliveEnabled = _keepAliveEnabled;
    config.autoUpdateEnabled = _autoUpdateEnabled;
    config.autoUpdateSilent = _autoUpdateSilent;
    config.showClock = _showClock;
    config.clockSize = _clockSize;
    config.clockPosition = _clockPosition;
    
    // Photo info settings
    config.showPhotoInfo = _showPhotoInfo;
    config.photoInfoPosition = _photoInfoPosition;
    config.photoInfoSize = _photoInfoSize;
    config.geocodingEnabled = _geocodingEnabled;
    config.useScriptFontForMetadata = _useScriptFontForMetadata;
    
    // Display schedule settings
    config.scheduleEnabled = _scheduleEnabled;
    config.dayStartHour = _dayStartTime.hour;
    config.dayStartMinute = _dayStartTime.minute;
    config.nightStartHour = _nightStartTime.hour;
    config.nightStartMinute = _nightStartTime.minute;
    config.fridaySaturdayNightStartHour = _fridaySaturdayNightStartTime?.hour;
    config.fridaySaturdayNightStartMinute = _fridaySaturdayNightStartTime?.minute;
    config.useNativeScreenOff = _useNativeScreenOff;

    // Display off in darkness settings
    config.darkScreenEnabled = _darkScreenEnabled;
    config.darkScreenThreshold = _darkScreenThreshold;
    config.darkScreenOffset = _darkScreenOffset;
    config.darkScreenOffDelay = _darkScreenOffDelay;
    config.darkScreenOnDelay = _darkScreenOnDelay;

    // Screen orientation
    config.screenOrientation = _screenOrientation;
    
    // Sync autostart setting to SharedPreferences for BootReceiver
    await AutostartService.setEnabled(_autostartOnBoot);
    
    // Sync keep alive setting to SharedPreferences for WakeReceiver
    await KeepAliveService.setEnabled(_keepAliveEnabled);
    
    if (_syncType == 'nextcloud_link') {
      config.setSourceConfig('nextcloud_link', newWebDavSourceConfig.toMap());
    }
    
    await config.save();
    
    // If a new sync source was configured, trigger an immediate sync
    // This runs in the background (fire-and-forget) so the user can continue
    if (newSyncSourceConfigured) {
      final photoService = context.read<PhotoService>();
      // Don't await - let it run in the background
      photoService.triggerSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _luxSubscription?.cancel();
            _luxSubscription = null;
          }
        },
        child: Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settings),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _saveSettings();
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // === DEVICE ADMIN WARNING ===
          if (Platform.isAndroid && _deviceAdminEnabled) ..._buildDeviceAdminWarning(),
          
          // === SLIDESHOW SETTINGS ===
          _buildSectionHeader(AppLocalizations.of(context)!.sectionSlideshow),
          const SizedBox(height: 8),
          
          // Slide Duration
          _buildSliderSetting(
            icon: Icons.timer,
            title: AppLocalizations.of(context)!.slideDuration,
            value: _slideDurationMinutes.toDouble(),
            min: 1,
            max: 15,
            divisions: 14,
            unit: AppLocalizations.of(context)!.unitMinutes,
            onChanged: (value) {
              setState(() => _slideDurationMinutes = value.round());
            },
          ),
          
          const SizedBox(height: 16),
          
          // Transition Duration (0.5 - 5 seconds, 0.5s steps)
          _buildSliderSetting(
            icon: Icons.blur_on,
            title: AppLocalizations.of(context)!.transitionDuration,
            value: _transitionDurationSeconds,
            min: 0.5,
            max: 5.0,
            divisions: 9,  // 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0
            unit: AppLocalizations.of(context)!.unitSeconds,
            formatValue: (v) => v.toStringAsFixed(1),
            onChanged: (value) {
              setState(() => _transitionDurationSeconds = value);
            },
          ),

          const SizedBox(height: 16),

          SwitchListTile(
            title: Text(AppLocalizations.of(context)!.blurBorders),
            subtitle: Text(AppLocalizations.of(context)!.blurBordersSubtitle),
            secondary: const Icon(Icons.blur_linear),
            value: _blurBorders,
            onChanged: (value) {
              setState(() => _blurBorders = value);
            },
          ),
          
          const SizedBox(height: 16),
          
          // Screen Orientation
          _buildScreenOrientationSelector(),
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // === CLOCK SETTINGS ===
          _buildSectionHeader(AppLocalizations.of(context)!.sectionClock),
          const SizedBox(height: 8),
          
          SwitchListTile(
            title: Text(AppLocalizations.of(context)!.showClock),
            subtitle: Text(AppLocalizations.of(context)!.showClockSubtitle),
            secondary: const Icon(Icons.access_time),
            value: _showClock,
            onChanged: (value) {
              setState(() => _showClock = value);
            },
          ),
          
          if (_showClock) ...[
            const SizedBox(height: 8),
            _buildClockSizeSelector(),
            const SizedBox(height: 8),
            _buildClockPositionSelector(),
          ],
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // === PHOTO INFO SETTINGS ===
          _buildSectionHeader(AppLocalizations.of(context)!.sectionPhotoInfo),
          const SizedBox(height: 8),
          
          SwitchListTile(
            title: Text(AppLocalizations.of(context)!.showPhotoInfo),
            subtitle: Text(AppLocalizations.of(context)!.showPhotoInfoSubtitle),
            secondary: const Icon(Icons.info_outline),
            value: _showPhotoInfo,
            onChanged: (value) {
              setState(() => _showPhotoInfo = value);
            },
          ),
          
          if (_showPhotoInfo) ...[
            const SizedBox(height: 8),
            _buildPhotoInfoPositionSelector(),
            const SizedBox(height: 8),
            _buildPhotoInfoSizeSelector(),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.useScriptFont),
              subtitle: Text(AppLocalizations.of(context)!.useScriptFontSubtitle),
              secondary: const Icon(Icons.font_download),
              value: _useScriptFontForMetadata,
              onChanged: (value) {
                setState(() => _useScriptFontForMetadata = value);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.resolveLocationNames),
              subtitle: Text(AppLocalizations.of(context)!.resolveLocationNamesSubtitle),
              secondary: const Icon(Icons.location_on),
              value: _geocodingEnabled,
              onChanged: (value) {
                setState(() => _geocodingEnabled = value);
              },
            ),
            if (_geocodingEnabled)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppLocalizations.of(context)!.nominatimHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // === SYNC SETTINGS ===
          _buildSectionHeader(AppLocalizations.of(context)!.sectionPhotoSource),
          const SizedBox(height: 8),
          
          // Sync Type Selection (includes inline folder selector for local_folder)
          _buildSyncTypeSelector(),
          
          // Nextcloud URL (only visible if nextcloud selected)
          if (_syncType == 'nextcloud_link') ...[
            const SizedBox(height: 16),
            _buildNextcloudSettings(),
          ],
          
          // Sync options (only visible if sync enabled - i.e. Nextcloud)
          if (_syncType == 'nextcloud_link') ...[
            const SizedBox(height: 16),
            
            // Sync Interval Slider
            _buildSyncIntervalSlider(),
            
            const SizedBox(height: 8),
            
            // Delete orphaned files checkbox
                SwitchListTile(
              title: Text(AppLocalizations.of(context)!.deleteOrphanedFiles),
              subtitle: Text(AppLocalizations.of(context)!.deleteOrphanedFilesSubtitle),
                  secondary: const Icon(Icons.delete_sweep),
              value: _deleteOrphanedFiles,
              onChanged: (value) {
                    setState(() => _deleteOrphanedFiles = value);
              },
            ),
            
            const SizedBox(height: 16),
            _buildSyncNowButton(),
            
            const SizedBox(height: 8),
            _buildLastSyncInfo(),
          ],
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // === DISPLAY SCHEDULE SETTINGS ===
          _buildSectionHeader(AppLocalizations.of(context)!.sectionDisplaySchedule),
          const SizedBox(height: 8),
          
          SwitchListTile(
            title: Text(AppLocalizations.of(context)!.dayNightSchedule),
            subtitle: Text(AppLocalizations.of(context)!.dayNightScheduleSubtitle),
            secondary: const Icon(Icons.nightlight_round),
            value: _scheduleEnabled,
            onChanged: (value) {
              setState(() => _scheduleEnabled = value);
            },
          ),
          
          if (_scheduleEnabled) ..._buildScheduleSettings(),
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // === ANDROID SETTINGS (only on Android) ===
          if (Platform.isAndroid) ...[
            const SizedBox(height: 8),

            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.darkScreenEnabled),
              subtitle: Text(AppLocalizations.of(context)!.darkScreenEnabledSubtitle),
              secondary: const Icon(Icons.nightlight_round),
              value: _darkScreenEnabled,
              onChanged: (value) {
                setState(() => _darkScreenEnabled = value);
              },
            ),

            if (_darkScreenEnabled) _buildDarkScreenSettings(),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            _buildSectionHeader(AppLocalizations.of(context)!.sectionAndroid),
            const SizedBox(height: 8),
            
            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.startOnBoot),
              subtitle: Text(AppLocalizations.of(context)!.startOnBootSubtitle),
              secondary: const Icon(Icons.power_settings_new),
              value: _autostartOnBoot,
              onChanged: (value) {
                setState(() => _autostartOnBoot = value);
              },
            ),
            
            const SizedBox(height: 8),
            
            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.keepAppRunning),
              subtitle: Text(AppLocalizations.of(context)!.keepAppRunningSubtitle),
              secondary: const Icon(Icons.memory),
              value: _keepAliveEnabled,
              onChanged: (value) async {
                if (value) {
                  // Show explanation dialog before enabling
                  final confirmed = await _showKeepAliveExplanation();
                  if (!confirmed) return;
                  
                  // Check if notification permission is needed
                  if (await KeepAliveService.shouldRequestNotificationPermission()) {
                    final permissionGranted = await _requestNotificationPermission();
                    if (!permissionGranted) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppLocalizations.of(context)!.notificationPermissionRequired),
                            duration: Duration(seconds: 4),
                          ),
                        );
                      }
                      return;
                    }
                  }
                }
                setState(() => _keepAliveEnabled = value);
              },
            ),

            const SizedBox(height: 8),
            _buildAutoUpdateSection(),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
          ],
          
          // === ABOUT ===
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(AppLocalizations.of(context)!.about),
            subtitle: Text(
              AppLocalizations.of(context)!.aboutSubtitle(
                _appVersion.isEmpty ? '...' : _appVersion,
              ),
            ),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Open Photo Frame',
                applicationVersion: _appVersion.isEmpty ? '...' : _appVersion,
                applicationLegalese: '© 2026 Michael Wyraz',
              );
            },
          ),
        ],
      ),
    ),
    );
  }
  
  Widget _buildAutoUpdateSection() {
    final l10n = AppLocalizations.of(context)!;
    final hintColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(l10n.autoUpdateTitle),
          subtitle: Text(l10n.autoUpdateSubtitle),
          secondary: const Icon(Icons.system_update),
          value: _autoUpdateEnabled,
          onChanged: (value) {
            setState(() {
              _autoUpdateEnabled = value;
              if (!value) _autoUpdateSilent = false;
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.autoUpdateFdroidNote,
            style: TextStyle(fontSize: 12, color: hintColor),
          ),
        ),
        if (_autoUpdateEnabled) ...[
          if (_isDeviceOwner)
            CheckboxListTile(
              title: Text(l10n.autoUpdateSilentTitle),
              subtitle: Text(l10n.autoUpdateSilentSubtitle),
              value: _autoUpdateSilent,
              onChanged: (value) =>
                  setState(() => _autoUpdateSilent = value ?? false),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.autoUpdatePromptNote,
                style: TextStyle(fontSize: 12, color: hintColor),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _checkForUpdateNow,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.autoUpdateCheckNow),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _checkForUpdateNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final service = context.read<UpdateService>();
    // Persist the toggles so the service sees the current configuration.
    await _saveSettings();
    final info = await service.checkForUpdate(manual: true);
    if (!mounted) return;
    if (info == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.autoUpdateUpToDate)),
      );
    }
    // If an update is found, the service shows the prompt via onUpdateAvailable.
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildDarkScreenSettings() {
    final displayValue = '${(_darkScreenThreshold)} lx';
    return Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mode_night_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(AppLocalizations.of(context)!.darkScreenThreshold)),
                if (_currentLux != null) ...[
                  Icon(Icons.wb_sunny_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${_currentLux!.round()} lx',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  displayValue,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              value: _darkScreenThreshold.toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (value) {
                setState(() => _darkScreenThreshold = value.round());
              },
            ),
            Row(
              children: [
                const Icon(Icons.brightness_medium, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(AppLocalizations.of(context)!.darkScreenOffset)),
                Text(
                  '${(_darkScreenOffset)} lx',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              value: _darkScreenOffset.toDouble(),
              min: 1,
              max: 20,
              divisions: 20,
              onChanged: (value) {
                setState(() => _darkScreenOffset = value.round());
              },
            ),
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(AppLocalizations.of(context)!.darkScreenOnDelay)),
                Text(
                  '${(_darkScreenOnDelay)} s',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              value: _darkScreenOnDelay.toDouble(),
              min: 1,
              max: 300,
              divisions: 10,
              onChanged: (value) {
                setState(() => _darkScreenOnDelay = value.round());
              },
            ),
            Row(
              children: [
                const Icon(Icons.timer_off_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(AppLocalizations.of(context)!.darkScreenOffDelay)),
                Text(
                  '${(_darkScreenOffDelay)} s',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              value: _darkScreenOffDelay.toDouble(),
              min: 1,
              max: 300,
              divisions: 10,
              onChanged: (value) {
                setState(() => _darkScreenOffDelay = value.round());
              },
            ),
          ],
        )
    );
  }

  Widget _buildSliderSetting({
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
    String Function(double)? formatValue,
  }) {
    final displayValue = formatValue != null ? formatValue(value) : '${value.round()}';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
            Text(
              '$displayValue $unit',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
  
  Widget _buildSyncTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // On Android: "App Folder", on Desktop: "Local Folder"
        if (Platform.isAndroid) ...[
          RadioListTile<String>(
            title: Text(AppLocalizations.of(context)!.appFolder),
            subtitle: Text(AppLocalizations.of(context)!.appFolderSubtitle),
            value: 'app_folder',
            groupValue: _syncType,
            onChanged: (value) {
              setState(() => _syncType = value!);
            },
          ),
          if (_syncType == 'app_folder')
            _buildAppFolderInfo(),
          RadioListTile<String>(
            title: Text(AppLocalizations.of(context)!.devicePhotos),
            subtitle: Text(AppLocalizations.of(context)!.devicePhotosSubtitle),
            value: 'device_photos',
            groupValue: _syncType,
            onChanged: (value) {
              setState(() => _syncType = value!);
              // Auto-load albums when switching to device_photos
              if (_availableAlbums.isEmpty) {
                _loadDeviceAlbums();
              }
            },
          ),
          if (_syncType == 'device_photos')
            _buildDevicePhotosSelector(),
        ] else ...[
          RadioListTile<String>(
            title: Text(AppLocalizations.of(context)!.localFolder),
            subtitle: Text(AppLocalizations.of(context)!.localFolderSubtitle),
            value: 'local_folder',
            groupValue: _syncType,
            onChanged: (value) {
              setState(() => _syncType = value!);
            },
          ),
          if (_syncType == 'local_folder')
            _buildLocalFolderSelector(),
        ],
        RadioListTile<String>(
          title: Text(AppLocalizations.of(context)!.nextcloud),
          subtitle: Text(AppLocalizations.of(context)!.nextcloudSubtitle),
          value: 'nextcloud_link',
          groupValue: _syncType,
          onChanged: (value) {
            setState(() => _syncType = value!);
          },
        ),
      ],
    );
  }
  
  /// Android only: Show app folder path with warning
  Widget _buildAppFolderInfo() {
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getDefaultFolderPath(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.appFolderWarning,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  /// Android only: Device photos album selector using MediaStore
  Widget _buildDevicePhotosSelector() {
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoadingAlbums)
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.loadingAlbums),
              ],
            )
          else if (_availableAlbums.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.tapToLoadAlbums,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadDeviceAlbums,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(AppLocalizations.of(context)!.load),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedAlbumId,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.photoAlbum,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(AppLocalizations.of(context)!.allPhotos),
                      ),
                      ..._availableAlbums.map((album) => DropdownMenuItem<String>(
                        value: album.id,
                        child: Text(album.name),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedAlbumId = value);
                      _onAlbumSelected(value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loadDeviceAlbums,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: AppLocalizations.of(context)!.refreshAlbums,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
        ],
      ),
    );
  }
  
  Future<void> _loadDeviceAlbums() async {
    setState(() => _isLoadingAlbums = true);
    
    try {
      final permission = await PhotoManager.requestPermissionExtend(
        requestOption: _devicePhotoPermissionRequest,
      );
      if (!permission.hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.photoPermissionDenied)),
          );
        }
        return;
      }
      
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      
      // Load current selection from config
      final photoRepo = context.read<PhotoRepository>();
      String? currentAlbumId;
      if (photoRepo is HybridPhotoRepository) {
        final config = context.read<ConfigProvider>();
        final sourceConfig = config.getSourceConfig('device_photos');
        currentAlbumId = sourceConfig['albumId'] as String?;
      }
      
      if (mounted) {
        setState(() {
          _availableAlbums = albums;
          _selectedAlbumId = currentAlbumId;
          _isLoadingAlbums = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAlbums = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorLoadingAlbums(e.toString()))),
        );
      }
    }
  }
  
  void _onAlbumSelected(String? albumId) {
    final photoRepo = context.read<PhotoRepository>();
    if (photoRepo is HybridPhotoRepository) {
      photoRepo.setSelectedAlbum(albumId);
    }
  }
  
  /// Desktop only: Local folder with Change button
  Widget _buildLocalFolderSelector() {
    // Show the actual path (either custom or default)
    final displayPath = _localFolderPath.isNotEmpty 
        ? _localFolderPath 
        : _getDefaultFolderPath();
    
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayPath,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _pickFolder,
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(AppLocalizations.of(context)!.change),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (_localFolderPath.isNotEmpty) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: () {
                setState(() => _localFolderPath = '');
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(AppLocalizations.of(context)!.reset),
            ),
          ],
        ],
      ),
    );
  }
  
  String _getDefaultFolderPath() {
    return _defaultFolderPath.isNotEmpty ? _defaultFolderPath : AppLocalizations.of(context)!.loading;
  }
  
  Future<void> _pickFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Photo Folder',
      );
      
      if (selectedDirectory != null) {
        setState(() {
          _localFolderPath = selectedDirectory;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.failedToPickFolder(e.toString()))),
        );
      }
    }
  }
  
  Widget _buildNextcloudSettings() {
    final localizations = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<WebDavAuthMode>(
            segments: [
              ButtonSegment(
                value: WebDavAuthMode.publicShare,
                label: Text(localizations.webdavAuthPublicShare),
              ),
              ButtonSegment(
                value: WebDavAuthMode.userPassword,
                label: Text(localizations.webdavAuthLogin),
              ),
            ],
            selected: {_webdavAuthMode},
            onSelectionChanged: (selection) {
              setState(() {
                _webdavAuthMode = selection.first;
                _connectionTestResult = null;
                _connectionTestSuccess = null;
                _availableNextcloudFolders = [];
                _nextcloudFolderLoadError = null;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nextcloudUrlController,
            decoration: InputDecoration(
              labelText: _webdavAuthMode == WebDavAuthMode.userPassword
                  ? localizations.webdavUrlLabel
                  : localizations.nextcloudPublicShareUrl,
              hintText: _webdavAuthMode == WebDavAuthMode.userPassword
                  ? localizations.webdavUrlHint
                  : localizations.nextcloudUrlHint,
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) {
              setState(() {
                _connectionTestResult = null;
                _connectionTestSuccess = null;
                _availableNextcloudFolders = [];
                _nextcloudFolderLoadError = null;
              });
            },
          ),
          if (_webdavAuthMode == WebDavAuthMode.userPassword) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _webdavUserController,
              decoration: InputDecoration(
                labelText: localizations.webdavUsername,
                prefixIcon: const Icon(Icons.person),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                setState(() {
                  _connectionTestResult = null;
                  _connectionTestSuccess = null;
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _webdavPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: localizations.webdavPassword,
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                setState(() {
                  _connectionTestResult = null;
                  _connectionTestSuccess = null;
                });
              },
            ),
          ],
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _webdavAllowInvalidCertificate,
            title: Text(localizations.webdavAllowInvalidCertificate),
            subtitle: Text(
              localizations.webdavAllowInvalidCertificateWarning,
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
            onChanged: (value) {
              setState(() {
                _webdavAllowInvalidCertificate = value ?? false;
                _connectionTestResult = null;
                _connectionTestSuccess = null;
              });
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isTestingConnection ? null : _testConnection,
            icon: _isTestingConnection
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find, size: 18),
            label: Text(_isTestingConnection ? AppLocalizations.of(context)!.testing : AppLocalizations.of(context)!.testConnection),
          ),
          if (_connectionTestResult != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  _connectionTestSuccess! ? Icons.check_circle : Icons.error,
                  size: 16,
                  color: _connectionTestSuccess! ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _connectionTestResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _connectionTestSuccess! ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          RadioListTile<WebDavFolderSyncMode>(
            title: Text(localizations.syncAllNextcloudFolders),
            subtitle: Text(localizations.syncAllNextcloudFoldersSubtitle),
            value: WebDavFolderSyncMode.all,
            groupValue: _nextcloudFolderSyncMode,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _nextcloudFolderSyncMode = value;
              });
            },
          ),
          RadioListTile<WebDavFolderSyncMode>(
            title: Text(localizations.syncSelectedNextcloudFolders),
            subtitle: Text(localizations.syncSelectedNextcloudFoldersSubtitle),
            value: WebDavFolderSyncMode.selectedFolders,
            groupValue: _nextcloudFolderSyncMode,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _nextcloudFolderSyncMode = value;
                if (_selectedNextcloudFolders.isEmpty) {
                  _selectedNextcloudFolders = {''};
                }
              });
            },
          ),
          if (_nextcloudFolderSyncMode == WebDavFolderSyncMode.selectedFolders) ...[
            const SizedBox(height: 8),
            _buildWebDavFolderSelection(),
          ],
        ],
      ),
    );
  }

  Widget _buildWebDavFolderSelection() {
    final localizations = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _isLoadingNextcloudFolders ? null : _loadAvailableNextcloudFolders,
          icon: _isLoadingNextcloudFolders
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_open, size: 18),
          label: Text(
            _isLoadingNextcloudFolders
                ? localizations.loadingNextcloudFolders
                : localizations.loadNextcloudFolders,
          ),
        ),
        if (_nextcloudFolderLoadError != null) ...[
          const SizedBox(height: 8),
          Text(
            localizations.nextcloudFoldersLoadError(_nextcloudFolderLoadError!),
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
        if (_availableNextcloudFolders.isEmpty && !_isLoadingNextcloudFolders) ...[
          const SizedBox(height: 8),
          Text(
            localizations.nextcloudFolderSelectionHint,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        if (_availableNextcloudFolders.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            localizations.nextcloudFolderSelectionHint,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: _availableNextcloudFolders.map((folder) {
                final isSelected = _selectedNextcloudFolders.contains(folder.path);
                final displayName = folder.path.isEmpty
                    ? localizations.nextcloudShareRoot
                    : folder.name;

                return CheckboxListTile(
                  value: isSelected,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.only(
                    left: 12 + (folder.depth * 20),
                    right: 12,
                  ),
                  title: Text(displayName),
                  subtitle: folder.path.isEmpty
                      ? Text(localizations.nextcloudShareRootSubtitle)
                      : null,
                  secondary: _buildFolderSyncBadge(folder),
                  onChanged: (value) {
                    setState(() {
                      if (value ?? false) {
                        _selectedNextcloudFolders.add(folder.path);
                      } else {
                        _selectedNextcloudFolders.remove(folder.path);
                      }
                    });
                  },
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }
  
  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = null;
      _connectionTestSuccess = null;
    });
    
    final error = await WebDavSyncService.testConnection(
      _buildWebDavSourceConfig(url: _nextcloudUrlController.text.trim()),
    );
    
    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _connectionTestSuccess = error == null;
        _connectionTestResult = error == null
            ? AppLocalizations.of(context)!.connectionSuccessful
            : _localizeNextcloudError(error);
      });
    }
  }

  Future<void> _loadAvailableNextcloudFolders() async {
    final publicLink = _nextcloudUrlController.text.trim();
    if (publicLink.isEmpty) {
      setState(() {
        _nextcloudFolderLoadError = AppLocalizations.of(context)!.nextcloudErrorInvalidUrlEmpty;
        _availableNextcloudFolders = [];
      });
      return;
    }

    setState(() {
      _isLoadingNextcloudFolders = true;
      _nextcloudFolderLoadError = null;
    });

    try {
      final folders = await WebDavSyncService.listAvailableFolders(
        _buildWebDavSourceConfig(url: publicLink),
      );
      final availablePaths = folders.map((folder) => folder.path).toSet();

      if (!mounted) {
        return;
      }

      setState(() {
        _availableNextcloudFolders = folders;
        _selectedNextcloudFolders = _selectedNextcloudFolders
            .where(availablePaths.contains)
            .toSet();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _nextcloudFolderLoadError = _localizeNextcloudError(e);
        // Keep the cached folder tree visible so the picker still works offline.
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingNextcloudFolders = false;
        });
      }
    }
  }

  /// Trailing badge for a folder row: "synced / total" with a check mark once
  /// every image in that folder is present locally.
  Widget _buildFolderSyncBadge(WebDavFolder folder) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = folder.fileCount;
    final rawLocal = _localFolderImageCounts[folder.path] ?? 0;
    final local = total > 0 ? rawLocal.clamp(0, total) : rawLocal;
    final fullySynced = total > 0 && local >= total;
    final label = total > 0 ? '$local / $total' : '$rawLocal';
    final color = fullySynced ? Colors.green : colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          fullySynced ? Icons.check_circle : Icons.cloud_download_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  /// Counts the locally synced images per folder so the picker can show
  /// "synced / total". Reads the local photo directory (works offline).
  Future<void> _refreshLocalFolderImageCounts() async {
    final storage = context.read<StorageProvider>();
    try {
      final dir = await storage.getPhotoDirectory();
      final counts = <String, int>{};
      if (await dir.exists()) {
        final prefixLength = dir.path.endsWith('/')
            ? dir.path.length
            : dir.path.length + 1;
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) {
            continue;
          }
          final name = entity.path.split('/').last;
          if (name.endsWith('.part') || !_isImageFileName(name)) {
            continue;
          }
          final relativePath = entity.path.length > prefixLength
              ? entity.path.substring(prefixLength)
              : '';
          final folder = WebDavSourceConfig.parentDirectoryOf(relativePath);
          counts[folder] = (counts[folder] ?? 0) + 1;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() => _localFolderImageCounts = counts);
    } catch (_) {
      // Local counts are a nice-to-have; ignore failures (e.g. missing dir).
    }
  }

  bool _isImageFileName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  WebDavSourceConfig _buildWebDavSourceConfig({required String url}) {
    var resolvedUrl = url;
    var username = _webdavUserController.text.trim();
    var password = _webdavPasswordController.text;

    if (_webdavAuthMode == WebDavAuthMode.userPassword) {
      // Accept an inline `user:pass@host` URL; explicit fields take priority.
      final split = WebDavSourceConfig.splitInlineCredentials(url);
      resolvedUrl = split.url;
      if (username.isEmpty && split.username != null) username = split.username!;
      if (password.isEmpty && split.password != null) password = split.password!;
    }

    final isUserPassword = _webdavAuthMode == WebDavAuthMode.userPassword;
    return WebDavSourceConfig(
      url: resolvedUrl,
      authMode: _webdavAuthMode,
      username: isUserPassword ? username : '',
      password: isUserPassword ? password : '',
      allowInvalidCertificate: _webdavAllowInvalidCertificate,
      folderSyncMode: _nextcloudFolderSyncMode,
      selectedFolders: _selectedNextcloudFolders.toList()..sort(),
      cachedFolders: _availableNextcloudFolders
          .map(
            (folder) => CachedWebDavFolder(
              path: folder.path,
              fileCount: folder.fileCount,
            ),
          )
          .toList(),
    );
  }

  bool _nextcloudConfigsEqual(
    WebDavSourceConfig left,
    WebDavSourceConfig right,
  ) {
    final leftFolders = left.normalizedSelectedFolders.toList()..sort();
    final rightFolders = right.normalizedSelectedFolders.toList()..sort();

    if (left.url != right.url ||
        left.authMode != right.authMode ||
        left.username != right.username ||
        left.password != right.password ||
        left.allowInvalidCertificate != right.allowInvalidCertificate ||
        left.folderSyncMode != right.folderSyncMode) {
      return false;
    }

    if (leftFolders.length != rightFolders.length) {
      return false;
    }

    for (var index = 0; index < leftFolders.length; index++) {
      if (leftFolders[index] != rightFolders[index]) {
        return false;
      }
    }

    return true;
  }
  
  Widget _buildSyncIntervalSlider() {
    // Values: 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60
    final displayValue = _syncIntervalMinutes == 0 
        ? AppLocalizations.of(context)!.disabled 
        : '$_syncIntervalMinutes ${AppLocalizations.of(context)!.unitMinutes}';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(AppLocalizations.of(context)!.autoSyncInterval)),
            Text(
              displayValue,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: _syncIntervalMinutes.toDouble(),
          min: 0,
          max: 60,
          divisions: 12, // 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60
          onChanged: (value) {
            // Snap to 5-minute steps
            final snapped = (value / 5).round() * 5;
            setState(() => _syncIntervalMinutes = snapped);
          },
        ),
      ],
    );
  }
  
  Widget _buildSyncNowButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Consumer<PhotoService>(
        builder: (context, photoService, _) {
          final syncProgress = photoService.syncProgress;
          final isSyncing = photoService.isSyncing;
          final progressValue = syncProgress?.fraction;
          final progressLabel = syncProgress?.counterLabel;
          final statusText = _localizeSyncStatus(photoService.syncStatus);
          final statusIsError = photoService.syncStatus?.kind == SyncStatusKind.error;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isSyncing) ...[
                _buildSyncProgressIndicator(
                  progressValue: progressValue,
                  label: progressLabel ?? AppLocalizations.of(context)!.syncing,
                ),
                if (syncProgress != null && syncProgress.folders.length > 1)
                  _buildSyncFolderBreakdown(syncProgress.folders),
              ] else
                ElevatedButton.icon(
                  onPressed: _triggerSync,
                  icon: const Icon(Icons.sync),
                  label: Text(AppLocalizations.of(context)!.syncNow),
                ),
              if (statusText != null) ...[
                const SizedBox(height: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusIsError ? Colors.red : Colors.green,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSyncProgressIndicator({
    required double? progressValue,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LinearProgressIndicator(
              value: progressValue,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
            Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncFolderBreakdown(List<SyncFolderProgress> folders) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final folder in folders)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      folder.folderPath.isEmpty
                          ? l10n.nextcloudShareRoot
                          : folder.folderPath,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    folder.counterLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: folder.completedFiles >= folder.totalFiles
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _localizeSyncStatus(SyncStatus? status) {
    final l10n = AppLocalizations.of(context)!;
    if (status == null) {
      return null;
    }

    return switch (status.kind) {
      SyncStatusKind.success => l10n.syncCompletedSuccessfully,
      SyncStatusKind.cancelled => l10n.syncCancelled,
      SyncStatusKind.error => l10n.syncError(
        _localizeNextcloudError(status.error),
      ),
    };
  }

  String _localizeNextcloudError(Object? error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is WebDavSyncException) {
      return switch (error.code) {
        WebDavSyncErrorCode.invalidShareLink =>
          l10n.nextcloudErrorInvalidShareLink,
        WebDavSyncErrorCode.shareInaccessible =>
          l10n.nextcloudErrorShareInaccessible,
        WebDavSyncErrorCode.connectionTimeout =>
          l10n.nextcloudErrorConnectionTimeout,
        WebDavSyncErrorCode.connectionFailed =>
          l10n.nextcloudErrorConnectionFailed,
        WebDavSyncErrorCode.downloadStalled =>
          l10n.nextcloudErrorDownloadStalled,
        WebDavSyncErrorCode.invalidUrlEmpty =>
          l10n.nextcloudErrorInvalidUrlEmpty,
        WebDavSyncErrorCode.invalidUrlScheme =>
          l10n.nextcloudErrorInvalidUrlScheme,
        WebDavSyncErrorCode.invalidUrlNoHost =>
          l10n.nextcloudErrorInvalidUrlNoHost,
        WebDavSyncErrorCode.invalidUrlFormat =>
          l10n.nextcloudErrorInvalidUrlFormat(error.details ?? ''),
        WebDavSyncErrorCode.unknown =>
          l10n.nextcloudErrorUnknown(error.details ?? error.cause?.toString() ?? ''),
      };
    }

    return l10n.nextcloudErrorUnknown(error?.toString() ?? '');
  }
  
  Widget _buildLastSyncInfo() {
    final config = context.read<ConfigProvider>();
    final lastSync = config.lastSuccessfulSync;
    final l10n = AppLocalizations.of(context)!;
    
    String text;
    if (lastSync == null) {
      text = l10n.neverSynced;
    } else {
      final now = DateTime.now();
      final diff = now.difference(lastSync);
      
      if (diff.inMinutes < 1) {
        text = l10n.lastSyncJustNow;
      } else if (diff.inMinutes < 60) {
        text = l10n.lastSyncMinutesAgo(diff.inMinutes);
      } else if (diff.inHours < 24) {
        text = l10n.lastSyncHoursAgo(diff.inHours);
      } else {
        // Format as date
        final dateStr = '${lastSync.day}.${lastSync.month}.${lastSync.year} '
               '${lastSync.hour.toString().padLeft(2, '0')}:'
               '${lastSync.minute.toString().padLeft(2, '0')}';
        text = l10n.lastSyncDate(dateStr);
      }
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.grey,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
  
  Widget _buildScreenOrientationSelector() {
    String getOrientationLabel(String value) {
      switch (value) {
        case 'auto':
          return AppLocalizations.of(context)!.screenOrientationAuto;
        case 'portraitUp':
          return AppLocalizations.of(context)!.screenOrientationPortraitUp;
        case 'portraitDown':
          return AppLocalizations.of(context)!.screenOrientationPortraitDown;
        case 'landscapeLeft':
          return AppLocalizations.of(context)!.screenOrientationLandscapeLeft;
        case 'landscapeRight':
          return AppLocalizations.of(context)!.screenOrientationLandscapeRight;
        default:
          return AppLocalizations.of(context)!.screenOrientationAuto;
      }
    }
    
    return ListTile(
      leading: const Icon(Icons.screen_rotation),
      title: Text(AppLocalizations.of(context)!.screenOrientation),
      subtitle: Text(getOrientationLabel(_screenOrientation)),
      trailing: DropdownButton<String>(
        value: _screenOrientation,
        underline: const SizedBox(),
        items: [
          DropdownMenuItem(
            value: 'auto',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.screen_rotation, size: 20),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.screenOrientationAuto),
              ],
            ),
          ),
          DropdownMenuItem(
            value: 'portraitUp',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stay_current_portrait, size: 20),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.screenOrientationPortraitUp),
              ],
            ),
          ),
          DropdownMenuItem(
            value: 'portraitDown',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: 3.14159, // 180 degrees
                  child: const Icon(Icons.stay_current_portrait, size: 20),
                ),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.screenOrientationPortraitDown),
              ],
            ),
          ),
          DropdownMenuItem(
            value: 'landscapeLeft',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stay_current_landscape, size: 20),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.screenOrientationLandscapeLeft),
              ],
            ),
          ),
          DropdownMenuItem(
            value: 'landscapeRight',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.flip(
                  flipX: true,
                  child: const Icon(Icons.stay_current_landscape, size: 20),
                ),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.screenOrientationLandscapeRight),
              ],
            ),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() => _screenOrientation = value);
          }
        },
      ),
    );
  }
  
  Widget _buildClockSizeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.format_size, size: 20),
          const SizedBox(width: 12),
          Text(AppLocalizations.of(context)!.size),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'small', label: Text('S')),
              ButtonSegment(value: 'medium', label: Text('M')),
              ButtonSegment(value: 'large', label: Text('L')),
            ],
            selected: {_clockSize},
            onSelectionChanged: (value) {
              setState(() => _clockSize = value.first);
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildClockPositionSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view, size: 20),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.position),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 160,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  // Top Left
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildPositionButton('topLeft', '⌜'),
                  ),
                  // Top Right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildPositionButton('topRight', '⌝'),
                  ),
                  // Bottom Left
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: _buildPositionButton('bottomLeft', '⌞'),
                  ),
                  // Bottom Right
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: _buildPositionButton('bottomRight', '⌟'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPositionButton(String position, String label) {
    final isSelected = _clockPosition == position;
    return GestureDetector(
      onTap: () => setState(() => _clockPosition = position),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              color: isSelected ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _triggerSync() async {
    // First save the current settings
    await _saveSettings();
    
    try {
      final photoService = context.read<PhotoService>();
      
      // Use centralized sync via PhotoService
      // This handles cancellation of running syncs and uses current config
      await photoService.triggerSync();
    } catch (_) {
      // PhotoService already exposes the sync result for the UI.
    } finally {
      // Refresh the per-folder "synced / total" counts after the sync.
      await _refreshLocalFolderImageCounts();
    }
  }
  
  // === Device Admin and Schedule Methods ===
  
  Future<void> _checkDeviceAdmin() async {
    if (!Platform.isAndroid) return;
    
    final enabled = await NativeScreenControlService.isDeviceAdminEnabled();
    if (mounted) {
      setState(() {
        _deviceAdminEnabled = enabled;
        // If Device Admin is not enabled but setting is on, turn it off
        if (!enabled && _useNativeScreenOff) {
          _useNativeScreenOff = false;
        }
      });
    }
  }
  
  Future<void> _requestDeviceAdmin() async {
    await NativeScreenControlService.requestDeviceAdmin();
    // Check again after a delay (user might grant permission)
    await Future.delayed(const Duration(seconds: 1));
    await _checkDeviceAdmin();
  }

  Future<void> _openDeviceAdminSettings() async {
    await NativeScreenControlService.openDeviceAdminSettings();
  }

  List<Widget> _buildDeviceAdminWarning() {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          border: Border.all(color: Colors.orange.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.deviceAdminActive,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.deviceAdminUninstallWarning,
              style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openDeviceAdminSettings,
              icon: const Icon(Icons.settings, size: 18),
              label: Text(AppLocalizations.of(context)!.openDeviceAdminSettings),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade700,
                side: BorderSide(color: Colors.orange.shade300),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ];
  }
  
  List<Widget> _buildScheduleSettings() {
    return [
      const SizedBox(height: 8),
      
      // Day start time
      ListTile(
        leading: const Icon(Icons.wb_sunny),
        title: Text(AppLocalizations.of(context)!.dayStartsAt),
        trailing: TextButton(
          onPressed: () => _selectTime(isDay: true),
          child: Text(
            _formatTimeOfDay(_dayStartTime),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
      
      // Night start time
      ListTile(
        leading: const Icon(Icons.nights_stay),
        title: Text(AppLocalizations.of(context)!.nightStartsAt),
        trailing: TextButton(
          onPressed: () => _selectTime(isDay: false),
          child: Text(
            _formatTimeOfDay(_nightStartTime),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),

      SwitchListTile(
        title: Text(
          AppLocalizations.of(context)!.differentNightTimeOnFridaysAndSaturdays,
        ),
        secondary: const Icon(Icons.schedule),
        value: _fridaySaturdayNightStartTime != null,
        onChanged: (_) => _toggleFridaySaturdayNightOverride(),
      ),

      if (_fridaySaturdayNightStartTime != null)
        ListTile(
          contentPadding: const EdgeInsets.only(left: 56, right: 16),
          title: Text(
            AppLocalizations.of(context)!.differentNightTimeFridaysAndSaturdays,
          ),
          trailing: TextButton(
            onPressed: _selectFridaySaturdayNightTime,
            child: Text(
              _formatTimeOfDay(_fridaySaturdayNightStartTime!),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      
      const SizedBox(height: 8),
      
      // Native screen off (Android only)
      if (Platform.isAndroid) ...[
        const Divider(),
        const SizedBox(height: 8),
        
        SwitchListTile(
          title: Text(AppLocalizations.of(context)!.nativeScreenOff),
          subtitle: Text(
            _deviceAdminEnabled
                ? AppLocalizations.of(context)!.nativeScreenOffEnabledSubtitle
                : AppLocalizations.of(context)!.nativeScreenOffDisabledSubtitle,
          ),
          secondary: const Icon(Icons.screen_lock_portrait),
          value: _useNativeScreenOff,
          onChanged: _deviceAdminEnabled
              ? (value) {
                  setState(() => _useNativeScreenOff = value);
                }
              : null, // Disabled if no Device Admin
        ),
        
        if (!_deviceAdminEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.deviceAdminExplanation,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _requestDeviceAdmin,
                  icon: const Icon(Icons.admin_panel_settings, size: 18),
                  label: Text(AppLocalizations.of(context)!.grantDeviceAdmin),
                ),
              ],
            ),
          ),
        ],
        
        if (_deviceAdminEnabled && _useNativeScreenOff) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.deviceAdminEnabled,
                      style: TextStyle(fontSize: 12, color: Colors.green[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.screenLockWarning,
                        style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    ];
  }
  
  Future<void> _selectTime({required bool isDay}) async {
    final initialTime = isDay ? _dayStartTime : _nightStartTime;
    final picked = await _pickTime(initialTime);

    if (picked != null && mounted) {
      setState(() {
        if (isDay) {
          _dayStartTime = picked;
        } else {
          _nightStartTime = picked;
        }
      });
    }
  }

  void _toggleFridaySaturdayNightOverride() {
    setState(() {
      if (_fridaySaturdayNightStartTime == null) {
        _fridaySaturdayNightStartTime =
            _lastFridaySaturdayNightStartTime ??
            _defaultFridaySaturdayNightStartTime;
      } else {
        _lastFridaySaturdayNightStartTime = _fridaySaturdayNightStartTime;
        _fridaySaturdayNightStartTime = null;
      }
    });
  }

  Future<void> _selectFridaySaturdayNightTime() async {
    final picked = await _pickTime(
      _fridaySaturdayNightStartTime ?? _defaultFridaySaturdayNightStartTime,
    );

    if (picked != null && mounted) {
      setState(() {
        _fridaySaturdayNightStartTime = picked;
        _lastFridaySaturdayNightStartTime = picked;
      });
    }
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initialTime) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    return picked;
  }
  
  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  
  Widget _buildPhotoInfoSizeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.format_size, size: 20),
          const SizedBox(width: 12),
          Text(AppLocalizations.of(context)!.size),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'small', label: Text('S')),
              ButtonSegment(value: 'medium', label: Text('M')),
              ButtonSegment(value: 'large', label: Text('L')),
            ],
            selected: {_photoInfoSize},
            onSelectionChanged: (value) {
              setState(() => _photoInfoSize = value.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoInfoPositionSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view, size: 20),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.position),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 160,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  // Top Left
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildPhotoInfoPositionButton('topLeft', '⌜'),
                  ),
                  // Top Right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildPhotoInfoPositionButton('topRight', '⌝'),
                  ),
                  // Bottom Left
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: _buildPhotoInfoPositionButton('bottomLeft', '⌞'),
                  ),
                  // Bottom Right
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: _buildPhotoInfoPositionButton('bottomRight', '⌟'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show explanation dialog for Keep App Running feature
  Future<bool> _showKeepAliveExplanation() async {
    final l10n = AppLocalizations.of(context)!;
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.keepAliveDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.keepAliveWhatDoes,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(l10n.keepAliveWhatDoesExplanation),
                SizedBox(height: 16),
                Text(
                  l10n.keepAliveWhyNeed,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(l10n.keepAliveWhyNeedExplanation),
                SizedBox(height: 16),
                Text(
                  l10n.keepAliveWhatHappens,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(l10n.keepAliveWhatHappensExplanation),
                SizedBox(height: 16),
                Text(
                  l10n.keepAliveDisableAnytime,
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.enable),
            ),
          ],
        );
      },
    ) ?? false;
  }

  /// Request notification permission (Android 13+)
  Future<bool> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }
  
  Widget _buildPhotoInfoPositionButton(String position, String label) {
    final isSelected = _photoInfoPosition == position;
    return GestureDetector(
      onTap: () => setState(() => _photoInfoPosition = position),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: isSelected ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
