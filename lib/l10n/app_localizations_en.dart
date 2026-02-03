// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settings => 'Settings';

  @override
  String get sectionSlideshow => 'Slideshow';

  @override
  String get slideDuration => 'Slide Duration';

  @override
  String get transitionDuration => 'Transition Duration';

  @override
  String get unitMinutes => 'min';

  @override
  String get unitSeconds => 'sec';

  @override
  String get sectionClock => 'Clock';

  @override
  String get showClock => 'Show Clock';

  @override
  String get showClockSubtitle => 'Display time on slideshow';

  @override
  String get size => 'Size';

  @override
  String get position => 'Position';

  @override
  String get sectionPhotoInfo => 'Photo Information';

  @override
  String get showPhotoInfo => 'Show Photo Info';

  @override
  String get showPhotoInfoSubtitle => 'Display date and location on slideshow';

  @override
  String get useScriptFont => 'Use Script Font';

  @override
  String get useScriptFontSubtitle =>
      'Display metadata in elegant handwritten style';

  @override
  String get resolveLocationNames => 'Resolve Location Names';

  @override
  String get resolveLocationNamesSubtitle =>
      'Use OpenStreetMap to show place names instead of coordinates';

  @override
  String get nominatimHint =>
      'Uses Nominatim (OpenStreetMap). No API key required.';

  @override
  String get sectionPhotoSource => 'Photo Source';

  @override
  String get appFolder => 'App Folder';

  @override
  String get appFolderSubtitle => 'Photos stored in app folder';

  @override
  String get appFolderWarning =>
      'Copy photos to this folder. They will be deleted when uninstalling the app.';

  @override
  String get devicePhotos => 'Device Photos';

  @override
  String get devicePhotosSubtitle => 'Show photos from your device';

  @override
  String get localFolder => 'Local Folder';

  @override
  String get localFolderSubtitle => 'Use photos from a local folder';

  @override
  String get nextcloud => 'Nextcloud';

  @override
  String get nextcloudSubtitle => 'Sync from Nextcloud public share link';

  @override
  String get loading => 'Loading...';

  @override
  String get loadingAlbums => 'Loading albums...';

  @override
  String get tapToLoadAlbums => 'Tap to load device photo albums';

  @override
  String get load => 'Load';

  @override
  String get photoAlbum => 'Photo Album';

  @override
  String get allPhotos => 'All Photos';

  @override
  String get refreshAlbums => 'Refresh albums';

  @override
  String get change => 'Change';

  @override
  String get reset => 'Reset';

  @override
  String get photoPermissionDenied => 'Photo permission denied';

  @override
  String errorLoadingAlbums(String error) {
    return 'Error loading albums: $error';
  }

  @override
  String failedToPickFolder(String error) {
    return 'Failed to pick folder: $error';
  }

  @override
  String get selectPhotoFolder => 'Select Photo Folder';

  @override
  String get nextcloudPublicShareUrl => 'Nextcloud Public Share URL';

  @override
  String get nextcloudUrlHint => 'https://cloud.example.com/s/abc123';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get testing => 'Testing...';

  @override
  String get connectionSuccessful => 'Connection successful!';

  @override
  String get autoSyncInterval => 'Auto-Sync Interval';

  @override
  String get disabled => 'Disabled';

  @override
  String get deleteOrphanedFiles => 'Delete orphaned files';

  @override
  String get deleteOrphanedFilesSubtitle =>
      'Remove local files that are no longer on server';

  @override
  String get syncNow => 'Sync Now';

  @override
  String get syncing => 'Syncing...';

  @override
  String get syncCompletedSuccessfully => 'Sync completed successfully!';

  @override
  String syncError(String error) {
    return 'Error: $error';
  }

  @override
  String get neverSynced => 'Never synced';

  @override
  String get lastSyncJustNow => 'Last sync: Just now';

  @override
  String lastSyncMinutesAgo(int minutes) {
    return 'Last sync: $minutes min ago';
  }

  @override
  String lastSyncHoursAgo(int hours) {
    return 'Last sync: $hours hours ago';
  }

  @override
  String lastSyncDate(String date) {
    return 'Last sync: $date';
  }

  @override
  String get sectionDisplaySchedule => 'Display Schedule';

  @override
  String get dayNightSchedule => 'Day/Night Schedule';

  @override
  String get dayNightScheduleSubtitle => 'Turn off display at night';

  @override
  String get dayStartsAt => 'Day starts at';

  @override
  String get nightStartsAt => 'Night starts at';

  @override
  String get nativeScreenOff => 'Native Screen Off';

  @override
  String get nativeScreenOffEnabledSubtitle =>
      'Use Device Admin to completely turn off screen';

  @override
  String get nativeScreenOffDisabledSubtitle =>
      'Requires Device Admin permission';

  @override
  String get deviceAdminExplanation =>
      'Device Admin permission is required to fully turn off the screen. Without it, the display will only be dimmed.';

  @override
  String get grantDeviceAdmin => 'Grant Device Admin';

  @override
  String get deviceAdminEnabled =>
      'Device Admin enabled - screen will turn off completely';

  @override
  String get screenLockWarning =>
      'Important: Screen lock (PIN/Pattern/Password) must be disabled for automatic wake-up to work. Go to Settings → Security → Screen lock → None.';

  @override
  String get deviceAdminActive => 'Device Admin Active';

  @override
  String get deviceAdminUninstallWarning =>
      'To uninstall this app, you must first disable Device Admin permission in Android settings.';

  @override
  String get openDeviceAdminSettings => 'Open Device Admin Settings';

  @override
  String get sectionAndroid => 'Android';

  @override
  String get startOnBoot => 'Start on Boot';

  @override
  String get startOnBootSubtitle => 'Automatically start app when device boots';

  @override
  String get keepAppRunning => 'Keep App Running';

  @override
  String get keepAppRunningSubtitle =>
      'Prevent app from being stopped on low memory';

  @override
  String get notificationPermissionRequired =>
      'Notification permission is required for Keep App Running';

  @override
  String get keepAliveDialogTitle => 'Keep App Running';

  @override
  String get keepAliveWhatDoes => 'What does this do?';

  @override
  String get keepAliveWhatDoesExplanation =>
      'This feature keeps the photo frame app running continuously, even when the device is low on memory.';

  @override
  String get keepAliveWhyNeed => 'Why would I need this?';

  @override
  String get keepAliveWhyNeedExplanation =>
      'On older devices with limited RAM, Android may stop the app to free up memory. This prevents that by running the app as a foreground service.';

  @override
  String get keepAliveWhatHappens => 'What will happen?';

  @override
  String get keepAliveWhatHappensExplanation =>
      '• A small notification will appear in the status bar\n• The app will be less likely to be stopped by Android\n• On Android 13+, you\'ll need to grant notification permission';

  @override
  String get keepAliveDisableAnytime =>
      'You can disable this at any time from the settings.';

  @override
  String get cancel => 'Cancel';

  @override
  String get enable => 'Enable';

  @override
  String get about => 'About';

  @override
  String aboutSubtitle(String version) {
    return 'Open Photo Frame v$version';
  }

  @override
  String get noPhotosFound => 'No photos found';

  @override
  String get tapCenterToOpenSettings => 'Tap center of screen to open settings';

  @override
  String get screenOrientation => 'Screen Orientation';

  @override
  String get screenOrientationAuto => 'Automatic (Sensor)';

  @override
  String get screenOrientationPortraitUp => 'Portrait';

  @override
  String get screenOrientationPortraitDown => 'Portrait (upside down)';

  @override
  String get screenOrientationLandscapeLeft => 'Landscape (left)';

  @override
  String get screenOrientationLandscapeRight => 'Landscape (right)';
}
