import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @sectionSlideshow.
  ///
  /// In en, this message translates to:
  /// **'Slideshow'**
  String get sectionSlideshow;

  /// No description provided for @slideDuration.
  ///
  /// In en, this message translates to:
  /// **'Slide Duration'**
  String get slideDuration;

  /// No description provided for @transitionDuration.
  ///
  /// In en, this message translates to:
  /// **'Transition Duration'**
  String get transitionDuration;

  /// No description provided for @unitMinutes.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get unitMinutes;

  /// No description provided for @unitSeconds.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get unitSeconds;

  /// No description provided for @sectionClock.
  ///
  /// In en, this message translates to:
  /// **'Clock'**
  String get sectionClock;

  /// No description provided for @showClock.
  ///
  /// In en, this message translates to:
  /// **'Show Clock'**
  String get showClock;

  /// No description provided for @showClockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Display time on slideshow'**
  String get showClockSubtitle;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get position;

  /// No description provided for @sectionPhotoInfo.
  ///
  /// In en, this message translates to:
  /// **'Photo Information'**
  String get sectionPhotoInfo;

  /// No description provided for @showPhotoInfo.
  ///
  /// In en, this message translates to:
  /// **'Show Photo Info'**
  String get showPhotoInfo;

  /// No description provided for @showPhotoInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Display date and location on slideshow'**
  String get showPhotoInfoSubtitle;

  /// No description provided for @useScriptFont.
  ///
  /// In en, this message translates to:
  /// **'Use Script Font'**
  String get useScriptFont;

  /// No description provided for @useScriptFontSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Display metadata in elegant handwritten style'**
  String get useScriptFontSubtitle;

  /// No description provided for @resolveLocationNames.
  ///
  /// In en, this message translates to:
  /// **'Resolve Location Names'**
  String get resolveLocationNames;

  /// No description provided for @resolveLocationNamesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use OpenStreetMap to show place names instead of coordinates'**
  String get resolveLocationNamesSubtitle;

  /// No description provided for @nominatimHint.
  ///
  /// In en, this message translates to:
  /// **'Uses Nominatim (OpenStreetMap). No API key required.'**
  String get nominatimHint;

  /// No description provided for @sectionPhotoSource.
  ///
  /// In en, this message translates to:
  /// **'Photo Source'**
  String get sectionPhotoSource;

  /// No description provided for @appFolder.
  ///
  /// In en, this message translates to:
  /// **'App Folder'**
  String get appFolder;

  /// No description provided for @appFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Photos stored in app folder'**
  String get appFolderSubtitle;

  /// No description provided for @appFolderWarning.
  ///
  /// In en, this message translates to:
  /// **'Copy photos to this folder. They will be deleted when uninstalling the app.'**
  String get appFolderWarning;

  /// No description provided for @devicePhotos.
  ///
  /// In en, this message translates to:
  /// **'Device Photos'**
  String get devicePhotos;

  /// No description provided for @devicePhotosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show photos from your device'**
  String get devicePhotosSubtitle;

  /// No description provided for @localFolder.
  ///
  /// In en, this message translates to:
  /// **'Local Folder'**
  String get localFolder;

  /// No description provided for @localFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use photos from a local folder'**
  String get localFolderSubtitle;

  /// No description provided for @nextcloud.
  ///
  /// In en, this message translates to:
  /// **'Nextcloud'**
  String get nextcloud;

  /// No description provided for @nextcloudSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync from Nextcloud public share link'**
  String get nextcloudSubtitle;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @loadingAlbums.
  ///
  /// In en, this message translates to:
  /// **'Loading albums...'**
  String get loadingAlbums;

  /// No description provided for @tapToLoadAlbums.
  ///
  /// In en, this message translates to:
  /// **'Tap to load device photo albums'**
  String get tapToLoadAlbums;

  /// No description provided for @load.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// No description provided for @photoAlbum.
  ///
  /// In en, this message translates to:
  /// **'Photo Album'**
  String get photoAlbum;

  /// No description provided for @allPhotos.
  ///
  /// In en, this message translates to:
  /// **'All Photos'**
  String get allPhotos;

  /// No description provided for @refreshAlbums.
  ///
  /// In en, this message translates to:
  /// **'Refresh albums'**
  String get refreshAlbums;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @photoPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Photo permission denied'**
  String get photoPermissionDenied;

  /// No description provided for @errorLoadingAlbums.
  ///
  /// In en, this message translates to:
  /// **'Error loading albums: {error}'**
  String errorLoadingAlbums(String error);

  /// No description provided for @failedToPickFolder.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick folder: {error}'**
  String failedToPickFolder(String error);

  /// No description provided for @selectPhotoFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Photo Folder'**
  String get selectPhotoFolder;

  /// No description provided for @nextcloudPublicShareUrl.
  ///
  /// In en, this message translates to:
  /// **'Nextcloud Public Share URL'**
  String get nextcloudPublicShareUrl;

  /// No description provided for @nextcloudUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://cloud.example.com/s/abc123'**
  String get nextcloudUrlHint;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @testing.
  ///
  /// In en, this message translates to:
  /// **'Testing...'**
  String get testing;

  /// No description provided for @connectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Connection successful!'**
  String get connectionSuccessful;

  /// No description provided for @autoSyncInterval.
  ///
  /// In en, this message translates to:
  /// **'Auto-Sync Interval'**
  String get autoSyncInterval;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @deleteOrphanedFiles.
  ///
  /// In en, this message translates to:
  /// **'Delete orphaned files'**
  String get deleteOrphanedFiles;

  /// No description provided for @deleteOrphanedFilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remove local files that are no longer on server'**
  String get deleteOrphanedFilesSubtitle;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get syncNow;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// No description provided for @syncCompletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Sync completed successfully!'**
  String get syncCompletedSuccessfully;

  /// No description provided for @syncError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String syncError(String error);

  /// No description provided for @neverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get neverSynced;

  /// No description provided for @lastSyncJustNow.
  ///
  /// In en, this message translates to:
  /// **'Last sync: Just now'**
  String get lastSyncJustNow;

  /// No description provided for @lastSyncMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {minutes} min ago'**
  String lastSyncMinutesAgo(int minutes);

  /// No description provided for @lastSyncHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {hours} hours ago'**
  String lastSyncHoursAgo(int hours);

  /// No description provided for @lastSyncDate.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {date}'**
  String lastSyncDate(String date);

  /// No description provided for @sectionDisplaySchedule.
  ///
  /// In en, this message translates to:
  /// **'Display Schedule'**
  String get sectionDisplaySchedule;

  /// No description provided for @dayNightSchedule.
  ///
  /// In en, this message translates to:
  /// **'Day/Night Schedule'**
  String get dayNightSchedule;

  /// No description provided for @dayNightScheduleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off display at night'**
  String get dayNightScheduleSubtitle;

  /// No description provided for @dayStartsAt.
  ///
  /// In en, this message translates to:
  /// **'Day starts at'**
  String get dayStartsAt;

  /// No description provided for @nightStartsAt.
  ///
  /// In en, this message translates to:
  /// **'Night starts at'**
  String get nightStartsAt;

  /// No description provided for @nativeScreenOff.
  ///
  /// In en, this message translates to:
  /// **'Native Screen Off'**
  String get nativeScreenOff;

  /// No description provided for @nativeScreenOffEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use Device Admin to completely turn off screen'**
  String get nativeScreenOffEnabledSubtitle;

  /// No description provided for @nativeScreenOffDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Requires Device Admin permission'**
  String get nativeScreenOffDisabledSubtitle;

  /// No description provided for @deviceAdminExplanation.
  ///
  /// In en, this message translates to:
  /// **'Device Admin permission is required to fully turn off the screen. Without it, the display will only be dimmed.'**
  String get deviceAdminExplanation;

  /// No description provided for @grantDeviceAdmin.
  ///
  /// In en, this message translates to:
  /// **'Grant Device Admin'**
  String get grantDeviceAdmin;

  /// No description provided for @deviceAdminEnabled.
  ///
  /// In en, this message translates to:
  /// **'Device Admin enabled - screen will turn off completely'**
  String get deviceAdminEnabled;

  /// No description provided for @screenLockWarning.
  ///
  /// In en, this message translates to:
  /// **'Important: Screen lock (PIN/Pattern/Password) must be disabled for automatic wake-up to work. Go to Settings → Security → Screen lock → None.'**
  String get screenLockWarning;

  /// No description provided for @deviceAdminActive.
  ///
  /// In en, this message translates to:
  /// **'Device Admin Active'**
  String get deviceAdminActive;

  /// No description provided for @deviceAdminUninstallWarning.
  ///
  /// In en, this message translates to:
  /// **'To uninstall this app, you must first disable Device Admin permission in Android settings.'**
  String get deviceAdminUninstallWarning;

  /// No description provided for @openDeviceAdminSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Device Admin Settings'**
  String get openDeviceAdminSettings;

  /// No description provided for @sectionAndroid.
  ///
  /// In en, this message translates to:
  /// **'Android'**
  String get sectionAndroid;

  /// No description provided for @startOnBoot.
  ///
  /// In en, this message translates to:
  /// **'Start on Boot'**
  String get startOnBoot;

  /// No description provided for @startOnBootSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically start app when device boots'**
  String get startOnBootSubtitle;

  /// No description provided for @keepAppRunning.
  ///
  /// In en, this message translates to:
  /// **'Keep App Running'**
  String get keepAppRunning;

  /// No description provided for @keepAppRunningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prevent app from being stopped on low memory'**
  String get keepAppRunningSubtitle;

  /// No description provided for @notificationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Notification permission is required for Keep App Running'**
  String get notificationPermissionRequired;

  /// No description provided for @keepAliveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep App Running'**
  String get keepAliveDialogTitle;

  /// No description provided for @keepAliveWhatDoes.
  ///
  /// In en, this message translates to:
  /// **'What does this do?'**
  String get keepAliveWhatDoes;

  /// No description provided for @keepAliveWhatDoesExplanation.
  ///
  /// In en, this message translates to:
  /// **'This feature keeps the photo frame app running continuously, even when the device is low on memory.'**
  String get keepAliveWhatDoesExplanation;

  /// No description provided for @keepAliveWhyNeed.
  ///
  /// In en, this message translates to:
  /// **'Why would I need this?'**
  String get keepAliveWhyNeed;

  /// No description provided for @keepAliveWhyNeedExplanation.
  ///
  /// In en, this message translates to:
  /// **'On older devices with limited RAM, Android may stop the app to free up memory. This prevents that by running the app as a foreground service.'**
  String get keepAliveWhyNeedExplanation;

  /// No description provided for @keepAliveWhatHappens.
  ///
  /// In en, this message translates to:
  /// **'What will happen?'**
  String get keepAliveWhatHappens;

  /// No description provided for @keepAliveWhatHappensExplanation.
  ///
  /// In en, this message translates to:
  /// **'• A small notification will appear in the status bar\n• The app will be less likely to be stopped by Android\n• On Android 13+, you\'ll need to grant notification permission'**
  String get keepAliveWhatHappensExplanation;

  /// No description provided for @keepAliveDisableAnytime.
  ///
  /// In en, this message translates to:
  /// **'You can disable this at any time from the settings.'**
  String get keepAliveDisableAnytime;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open Photo Frame v{version}'**
  String aboutSubtitle(String version);

  /// No description provided for @noPhotosFound.
  ///
  /// In en, this message translates to:
  /// **'No photos found'**
  String get noPhotosFound;

  /// No description provided for @tapCenterToOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Tap center of screen to open settings'**
  String get tapCenterToOpenSettings;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
