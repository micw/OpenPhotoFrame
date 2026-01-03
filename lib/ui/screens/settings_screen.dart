import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../domain/interfaces/config_provider.dart';
import '../../domain/interfaces/storage_provider.dart';
import '../../domain/interfaces/photo_repository.dart';
import '../../infrastructure/repositories/hybrid_photo_repository.dart';
import '../../infrastructure/services/photo_service.dart';
import '../../infrastructure/services/nextcloud_sync_service.dart';
import '../../infrastructure/services/autostart_service.dart';
import '../../infrastructure/services/native_screen_control_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late int _slideDurationMinutes;
  late double _transitionDurationSeconds;
  late String _syncType;
  late TextEditingController _nextcloudUrlController;
  late int _syncIntervalMinutes;
  late bool _deleteOrphanedFiles;
  late bool _autostartOnBoot;
  
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
  late bool _useNativeScreenOff;
  bool _deviceAdminEnabled = false;
  
  bool _isSyncing = false;
  String? _syncStatus;
  
  bool _isTestingConnection = false;
  String? _connectionTestResult;
  bool? _connectionTestSuccess;
  
  // Local folder path
  late String _localFolderPath;
  String _defaultFolderPath = '';
  
  // Device photos album selection (Android only)
  List<AssetPathEntity> _availableAlbums = [];
  String? _selectedAlbumId;
  bool _isLoadingAlbums = false;
  
  // Track original values to detect changes
  late String _originalSyncType;
  late String _originalNextcloudUrl;
  late String _originalLocalFolderPath;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Exit immersive mode to show status bar and navigation
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    
    final config = context.read<ConfigProvider>();
    _slideDurationMinutes = (config.slideDurationSeconds / 60).round().clamp(1, 15);
    _transitionDurationSeconds = (config.transitionDurationMs / 1000.0).clamp(0.5, 5.0);
    // Default sync type: app_folder on Android, local_folder on Desktop
    final defaultSyncType = Platform.isAndroid ? 'app_folder' : 'local_folder';
    _syncType = config.activeSourceType.isEmpty ? defaultSyncType : config.activeSourceType;
    _localFolderPath = config.customPhotoPath ?? '';
    _syncIntervalMinutes = config.syncIntervalMinutes;
    _deleteOrphanedFiles = config.deleteOrphanedFiles;
    _autostartOnBoot = config.autostartOnBoot;
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
    _useNativeScreenOff = config.useNativeScreenOff;
    
    // Check Device Admin status
    _checkDeviceAdmin();
    
    final nextcloudConfig = config.getSourceConfig('nextcloud_link');
    _nextcloudUrlController = TextEditingController(
      text: nextcloudConfig['url'] ?? '',
    );
    
    // Store original values for comparison on save
    _originalSyncType = _syncType;
    _originalNextcloudUrl = nextcloudConfig['url'] ?? '';
    _originalLocalFolderPath = _localFolderPath;
    
    // Load default folder path async
    _loadDefaultFolderPath();
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
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nextcloudUrlController.dispose();
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
    final syncConfigChanged = _syncType != _originalSyncType ||
        (_syncType == 'nextcloud_link' && newNextcloudUrl != _originalNextcloudUrl);
    final newSyncSourceConfigured = syncConfigChanged && 
        _syncType == 'nextcloud_link' && 
        newNextcloudUrl.isNotEmpty;
    
    config.slideDurationSeconds = _slideDurationMinutes * 60;
    config.transitionDurationMs = (_transitionDurationSeconds * 1000).round();
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
    config.useNativeScreenOff = _useNativeScreenOff;
    
    // Sync autostart setting to SharedPreferences for BootReceiver
    await AutostartService.setEnabled(_autostartOnBoot);
    
    if (_syncType == 'nextcloud_link') {
      config.setSourceConfig('nextcloud_link', {
        'url': newNextcloudUrl,
      });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
          _buildSectionHeader('Slideshow'),
          const SizedBox(height: 8),
          
          // Slide Duration
          _buildSliderSetting(
            icon: Icons.timer,
            title: 'Slide Duration',
            value: _slideDurationMinutes.toDouble(),
            min: 1,
            max: 15,
            divisions: 14,
            unit: 'min',
            onChanged: (value) {
              setState(() => _slideDurationMinutes = value.round());
            },
          ),
          
          const SizedBox(height: 16),
          
          // Transition Duration (0.5 - 5 seconds, 0.5s steps)
          _buildSliderSetting(
            icon: Icons.blur_on,
            title: 'Transition Duration',
            value: _transitionDurationSeconds,
            min: 0.5,
            max: 5.0,
            divisions: 9,  // 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0
            unit: 'sec',
            formatValue: (v) => v.toStringAsFixed(1),
            onChanged: (value) {
              setState(() => _transitionDurationSeconds = value);
            },
          ),
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // === CLOCK SETTINGS ===
          _buildSectionHeader('Clock'),
          const SizedBox(height: 8),
          
          SwitchListTile(
            title: const Text('Show Clock'),
            subtitle: const Text('Display time on slideshow'),
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
          _buildSectionHeader('Photo Information'),
          const SizedBox(height: 8),
          
          SwitchListTile(
            title: const Text('Show Photo Info'),
            subtitle: const Text('Display date and location on slideshow'),
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
              title: const Text('Use Script Font'),
              subtitle: const Text('Display metadata in elegant handwritten style'),
              secondary: const Icon(Icons.font_download),
              value: _useScriptFontForMetadata,
              onChanged: (value) {
                setState(() => _useScriptFontForMetadata = value);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Resolve Location Names'),
              subtitle: const Text('Use OpenStreetMap to show place names instead of coordinates'),
              secondary: const Icon(Icons.location_on),
              value: _geocodingEnabled,
              onChanged: (value) {
                setState(() => _geocodingEnabled = value);
              },
            ),
            if (_geocodingEnabled)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Uses Nominatim (OpenStreetMap). No API key required.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // === SYNC SETTINGS ===
          _buildSectionHeader('Photo Source'),
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
            CheckboxListTile(
              title: const Text('Delete orphaned files'),
              subtitle: const Text('Remove local files that are no longer on server'),
              value: _deleteOrphanedFiles,
              onChanged: (value) {
                setState(() => _deleteOrphanedFiles = value ?? true);
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
          _buildSectionHeader('Display Schedule'),
          const SizedBox(height: 8),
          
          SwitchListTile(
            title: const Text('Day/Night Schedule'),
            subtitle: const Text('Turn off display at night'),
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
            _buildSectionHeader('Android'),
            const SizedBox(height: 8),
            
            SwitchListTile(
              title: const Text('Start on Boot'),
              subtitle: const Text('Automatically start app when device boots'),
              secondary: const Icon(Icons.power_settings_new),
              value: _autostartOnBoot,
              onChanged: (value) {
                setState(() => _autostartOnBoot = value);
              },
            ),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
          ],
          
          // === ABOUT ===
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Open Photo Frame v1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Open Photo Frame',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2024',
              );
            },
          ),
        ],
      ),
    );
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
            title: const Text('App Folder'),
            subtitle: const Text('Photos stored in app folder'),
            value: 'app_folder',
            groupValue: _syncType,
            onChanged: (value) {
              setState(() => _syncType = value!);
            },
          ),
          if (_syncType == 'app_folder')
            _buildAppFolderInfo(),
          RadioListTile<String>(
            title: const Text('Device Photos'),
            subtitle: const Text('Show photos from your device'),
            value: 'device_photos',
            groupValue: _syncType,
            onChanged: (value) {
              setState(() => _syncType = value!);
            },
          ),
          if (_syncType == 'device_photos')
            _buildDevicePhotosSelector(),
        ] else ...[
          RadioListTile<String>(
            title: const Text('Local Folder'),
            subtitle: const Text('Use photos from a local folder'),
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
          title: const Text('Nextcloud'),
          subtitle: const Text('Sync from Nextcloud public share link'),
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
                  'Copy photos to this folder. They will be deleted when uninstalling the app.',
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
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Loading albums...'),
              ],
            )
          else if (_availableAlbums.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tap to load device photo albums',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadDeviceAlbums,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Load'),
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
                    decoration: const InputDecoration(
                      labelText: 'Photo Album',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Photos'),
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
                  tooltip: 'Refresh albums',
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
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo permission denied')),
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
        currentAlbumId = sourceConfig?['albumId'] as String?;
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
          SnackBar(content: Text('Error loading albums: $e')),
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
            label: const Text('Change'),
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
              child: const Text('Reset'),
            ),
          ],
        ],
      ),
    );
  }
  
  String _getDefaultFolderPath() {
    return _defaultFolderPath.isNotEmpty ? _defaultFolderPath : 'Loading...';
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
          SnackBar(content: Text('Failed to pick folder: $e')),
        );
      }
    }
  }
  
  Widget _buildNextcloudSettings() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nextcloudUrlController,
            decoration: const InputDecoration(
              labelText: 'Nextcloud Public Share URL',
              hintText: 'https://cloud.example.com/s/abc123',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) {
              // Reset test result when URL changes
              if (_connectionTestResult != null) {
                setState(() {
                  _connectionTestResult = null;
                  _connectionTestSuccess = null;
                });
              }
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
            label: Text(_isTestingConnection ? 'Testing...' : 'Test Connection'),
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
        ],
      ),
    );
  }
  
  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = null;
      _connectionTestSuccess = null;
    });
    
    final error = await NextcloudSyncService.testConnection(
      _nextcloudUrlController.text.trim(),
    );
    
    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _connectionTestSuccess = error == null;
        _connectionTestResult = error ?? 'Connection successful!';
      });
    }
  }
  
  Widget _buildSyncIntervalSlider() {
    // Values: 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60
    final displayValue = _syncIntervalMinutes == 0 
        ? 'Disabled' 
        : '$_syncIntervalMinutes min';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule, size: 20),
            const SizedBox(width: 12),
            const Expanded(child: Text('Auto-Sync Interval')),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _isSyncing ? null : _triggerSync,
            icon: _isSyncing 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
          ),
          if (_syncStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              _syncStatus!,
              style: TextStyle(
                color: _syncStatus!.contains('Error') 
                    ? Colors.red 
                    : Colors.green,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildLastSyncInfo() {
    final config = context.read<ConfigProvider>();
    final lastSync = config.lastSuccessfulSync;
    
    String text;
    if (lastSync == null) {
      text = 'Never synced';
    } else {
      final now = DateTime.now();
      final diff = now.difference(lastSync);
      
      if (diff.inMinutes < 1) {
        text = 'Last sync: Just now';
      } else if (diff.inMinutes < 60) {
        text = 'Last sync: ${diff.inMinutes} min ago';
      } else if (diff.inHours < 24) {
        text = 'Last sync: ${diff.inHours} hours ago';
      } else {
        // Format as date
        text = 'Last sync: ${lastSync.day}.${lastSync.month}.${lastSync.year} '
               '${lastSync.hour.toString().padLeft(2, '0')}:'
               '${lastSync.minute.toString().padLeft(2, '0')}';
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
  
  Widget _buildClockSizeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.format_size, size: 20),
          const SizedBox(width: 12),
          const Text('Size'),
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
              const Text('Position'),
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
    
    setState(() {
      _isSyncing = true;
      _syncStatus = null;
    });
    
    try {
      final photoService = context.read<PhotoService>();
      
      // Use centralized sync via PhotoService
      // This handles cancellation of running syncs and uses current config
      await photoService.triggerSync();
      
      if (mounted) {
        setState(() {
          _syncStatus = 'Sync completed successfully!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
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
                    'Device Admin Active',
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
              'To uninstall this app, you must first disable Device Admin permission in Android settings.',
              style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openDeviceAdminSettings,
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Open Device Admin Settings'),
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
        title: const Text('Day starts at'),
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
        title: const Text('Night starts at'),
        trailing: TextButton(
          onPressed: () => _selectTime(isDay: false),
          child: Text(
            _formatTimeOfDay(_nightStartTime),
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
          title: const Text('Native Screen Off'),
          subtitle: Text(
            _deviceAdminEnabled
                ? 'Use Device Admin to completely turn off screen'
                : 'Requires Device Admin permission',
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
                const Text(
                  'Device Admin permission is required to fully turn off the screen. '
                  'Without it, the display will only be dimmed.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _requestDeviceAdmin,
                  icon: const Icon(Icons.admin_panel_settings, size: 18),
                  label: const Text('Grant Device Admin'),
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
                      'Device Admin enabled - screen will turn off completely',
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
                        'Important: Screen lock (PIN/Pattern/Password) must be disabled for automatic wake-up to work. '
                        'Go to Settings → Security → Screen lock → None.',
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
          const Text('Size'),
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
              const Text('Position'),
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
