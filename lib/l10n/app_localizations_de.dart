// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get settings => 'Einstellungen';

  @override
  String get sectionSlideshow => 'Diashow';

  @override
  String get slideDuration => 'Anzeigedauer';

  @override
  String get transitionDuration => 'Überblendzeit';

  @override
  String get blurBorders => 'Rand unscharf';

  @override
  String get blurBordersSubtitle =>
      'Bild mit Unschärfe bis zum Bildschirmrand zeichnen';

  @override
  String get unitMinutes => 'Min';

  @override
  String get unitSeconds => 'Sek';

  @override
  String get sectionClock => 'Uhr';

  @override
  String get showClock => 'Uhr anzeigen';

  @override
  String get showClockSubtitle => 'Uhrzeit auf der Diashow anzeigen';

  @override
  String get size => 'Größe';

  @override
  String get position => 'Position';

  @override
  String get useAmPm => 'AM/PM verwenden';

  @override
  String get useAmPmSubtitle => 'Uhr im 12-Stunden-Format mit AM/PM anzeigen';

  @override
  String get sectionPhotoInfo => 'Foto-Informationen';

  @override
  String get showPhotoInfo => 'Foto-Info anzeigen';

  @override
  String get showPhotoInfoSubtitle => 'Datum und Ort auf der Diashow anzeigen';

  @override
  String get useScriptFont => 'Schreibschrift verwenden';

  @override
  String get useScriptFontSubtitle =>
      'Metadaten in eleganter Handschrift anzeigen';

  @override
  String get resolveLocationNames => 'Ortsnamen auflösen';

  @override
  String get resolveLocationNamesSubtitle =>
      'OpenStreetMap nutzen um Ortsnamen statt Koordinaten anzuzeigen';

  @override
  String get nominatimHint =>
      'Verwendet Nominatim (OpenStreetMap). Kein API-Schlüssel erforderlich.';

  @override
  String get sectionPhotoSource => 'Fotoquelle';

  @override
  String get appFolder => 'App-Ordner';

  @override
  String get appFolderSubtitle => 'Fotos im App-Ordner gespeichert';

  @override
  String get appFolderWarning =>
      'Kopiere Fotos in diesen Ordner. Sie werden beim Deinstallieren der App gelöscht.';

  @override
  String get devicePhotos => 'Geräte-Fotos';

  @override
  String get devicePhotosSubtitle => 'Fotos vom Gerät anzeigen';

  @override
  String get localFolder => 'Lokaler Ordner';

  @override
  String get localFolderSubtitle => 'Fotos aus einem lokalen Ordner verwenden';

  @override
  String get nextcloud => 'Nextcloud';

  @override
  String get nextcloudSubtitle =>
      'Von Nextcloud öffentlichem Link synchronisieren';

  @override
  String get loading => 'Lädt...';

  @override
  String get loadingAlbums => 'Alben werden geladen...';

  @override
  String get tapToLoadAlbums => 'Tippen um Fotoalben zu laden';

  @override
  String get load => 'Laden';

  @override
  String get photoAlbum => 'Fotoalbum';

  @override
  String get allPhotos => 'Alle Fotos';

  @override
  String get refreshAlbums => 'Alben aktualisieren';

  @override
  String get change => 'Ändern';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get photoPermissionDenied => 'Foto-Berechtigung verweigert';

  @override
  String errorLoadingAlbums(String error) {
    return 'Fehler beim Laden der Alben: $error';
  }

  @override
  String failedToPickFolder(String error) {
    return 'Ordnerauswahl fehlgeschlagen: $error';
  }

  @override
  String get selectPhotoFolder => 'Foto-Ordner auswählen';

  @override
  String get nextcloudPublicShareUrl => 'Nextcloud öffentlicher Freigabe-Link';

  @override
  String get nextcloudUrlHint => 'https://cloud.example.com/s/abc123';

  @override
  String get webdavAuthPublicShare => 'Öffentliche Freigabe';

  @override
  String get webdavAuthLogin => 'WebDAV-Login';

  @override
  String get webdavUrlLabel => 'WebDAV-URL';

  @override
  String get webdavUrlHint =>
      'https://cloud.example.com/remote.php/dav/files/user/';

  @override
  String get webdavUsername => 'Benutzername';

  @override
  String get webdavPassword => 'Passwort';

  @override
  String get webdavAllowInvalidCertificate =>
      'Ungültiges Zertifikat akzeptieren';

  @override
  String get webdavAllowInvalidCertificateWarning =>
      'Unsicher: nur für selbstsignierte Zertifikate in vertrauenswürdigen Netzwerken.';

  @override
  String get testConnection => 'Verbindung testen';

  @override
  String get testing => 'Teste...';

  @override
  String get connectionSuccessful => 'Verbindung erfolgreich!';

  @override
  String get syncAllNextcloudFolders => 'Alle Ordner';

  @override
  String get syncAllNextcloudFoldersSubtitle =>
      'Bilder aus dem Freigabe-Root und allen Unterordnern synchronisieren';

  @override
  String get syncSelectedNextcloudFolders => 'Ausgewählte Ordner';

  @override
  String get syncSelectedNextcloudFoldersSubtitle =>
      'Wähle die Ordner, deren direkte Bilder verwendet werden sollen';

  @override
  String get loadNextcloudFolders => 'Ordner laden';

  @override
  String get loadingNextcloudFolders => 'Lade Ordner...';

  @override
  String get nextcloudFolderSelectionHint =>
      'Wähle den Freigabe-Root und alle Unterordner aus, die enthalten sein sollen.';

  @override
  String get nextcloudShareRoot => 'Freigabe-Root';

  @override
  String get nextcloudShareRootSubtitle =>
      'Bilder direkt im freigegebenen Root-Ordner';

  @override
  String nextcloudFolderPhotoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bilder',
      one: '1 Bild',
    );
    return '$_temp0';
  }

  @override
  String nextcloudFoldersLoadError(String error) {
    return 'Fehler beim Laden der Ordner: $error';
  }

  @override
  String get autoSyncInterval => 'Auto-Sync-Intervall';

  @override
  String get disabled => 'Deaktiviert';

  @override
  String get deleteOrphanedFiles => 'Verwaiste Dateien löschen';

  @override
  String get deleteOrphanedFilesSubtitle =>
      'Lokale Dateien entfernen, die nicht mehr auf dem Server sind';

  @override
  String get syncNow => 'Jetzt synchronisieren';

  @override
  String get syncing => 'Synchronisiere...';

  @override
  String get syncCompletedSuccessfully =>
      'Synchronisation erfolgreich abgeschlossen!';

  @override
  String get syncCancelled => 'Synchronisation abgebrochen.';

  @override
  String syncError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get nextcloudErrorInvalidShareLink =>
      'Der Nextcloud-Freigabelink ist nicht mehr gültig.';

  @override
  String get nextcloudErrorShareInaccessible =>
      'Die Nextcloud-Freigabe ist nicht mehr erreichbar.';

  @override
  String get nextcloudErrorConnectionTimeout =>
      'Die Verbindung zu Nextcloud ist in ein Timeout gelaufen.';

  @override
  String get nextcloudErrorConnectionFailed =>
      'Verbindung zu Nextcloud fehlgeschlagen. Bitte Internetverbindung und Freigabelink prüfen.';

  @override
  String get nextcloudErrorDownloadStalled =>
      'Der Download wurde nach 15 Minuten ohne Datenempfang abgebrochen.';

  @override
  String get nextcloudErrorInvalidUrlEmpty => 'URL ist leer.';

  @override
  String get nextcloudErrorInvalidUrlScheme =>
      'Ungültiges URL-Schema. Bitte http oder https verwenden.';

  @override
  String get nextcloudErrorInvalidUrlNoHost => 'Ungültige URL. Host fehlt.';

  @override
  String nextcloudErrorInvalidUrlFormat(String error) {
    return 'Ungültiges URL-Format: $error';
  }

  @override
  String nextcloudErrorUnknown(String error) {
    return 'Nextcloud-Synchronisation fehlgeschlagen: $error';
  }

  @override
  String get neverSynced => 'Noch nie synchronisiert';

  @override
  String get lastSyncJustNow => 'Letzte Sync: Gerade eben';

  @override
  String lastSyncMinutesAgo(int minutes) {
    return 'Letzte Sync: vor $minutes Min';
  }

  @override
  String lastSyncHoursAgo(int hours) {
    return 'Letzte Sync: vor $hours Stunden';
  }

  @override
  String lastSyncDate(String date) {
    return 'Letzte Sync: $date';
  }

  @override
  String get sectionDisplaySchedule => 'Anzeige-Zeitplan';

  @override
  String get dayNightSchedule => 'Tag/Nacht-Zeitplan';

  @override
  String get dayNightScheduleSubtitle => 'Display nachts ausschalten';

  @override
  String get dayStartsAt => 'Tag beginnt um';

  @override
  String get nightStartsAt => 'Nacht beginnt um';

  @override
  String get differentNightTimeOnFridaysAndSaturdays =>
      'Andere Nachtzeit freitags und samstags';

  @override
  String get differentNightTimeFridaysAndSaturdays =>
      'Nacht beginnt freitags und samstags um';

  @override
  String get nativeScreenOff => 'Natives Ausschalten';

  @override
  String get nativeScreenOffEnabledSubtitle =>
      'Geräte-Admin verwenden um Bildschirm komplett auszuschalten';

  @override
  String get nativeScreenOffDisabledSubtitle =>
      'Erfordert Geräte-Admin-Berechtigung';

  @override
  String get deviceAdminExplanation =>
      'Die Geräte-Admin-Berechtigung wird benötigt, um den Bildschirm vollständig auszuschalten. Ohne sie wird das Display nur gedimmt.';

  @override
  String get grantDeviceAdmin => 'Geräte-Admin gewähren';

  @override
  String get deviceAdminEnabled =>
      'Geräte-Admin aktiviert - Bildschirm wird komplett ausgeschaltet';

  @override
  String get screenLockWarning =>
      'Wichtig: Die Bildschirmsperre (PIN/Muster/Passwort) muss deaktiviert sein, damit das automatische Aufwachen funktioniert. Gehe zu Einstellungen → Sicherheit → Bildschirmsperre → Keine.';

  @override
  String get deviceAdminActive => 'Geräte-Admin aktiv';

  @override
  String get deviceAdminUninstallWarning =>
      'Um diese App zu deinstallieren, muss zuerst die Geräte-Admin-Berechtigung in den Android-Einstellungen deaktiviert werden.';

  @override
  String get openDeviceAdminSettings => 'Geräte-Admin-Einstellungen öffnen';

  @override
  String get sectionAndroid => 'Android';

  @override
  String get startOnBoot => 'Bei Start öffnen';

  @override
  String get startOnBootSubtitle => 'App automatisch beim Gerätestart öffnen';

  @override
  String get keepAppRunning => 'App am Laufen halten';

  @override
  String get keepAppRunningSubtitle =>
      'Verhindern, dass die App bei wenig Speicher beendet wird';

  @override
  String get notificationPermissionRequired =>
      'Benachrichtigungs-Berechtigung wird für \'App am Laufen halten\' benötigt';

  @override
  String get autoUpdateTitle => 'Automatische Updates';

  @override
  String get autoUpdateSubtitle =>
      'Auf GitHub nach neuen Versionen suchen und installieren';

  @override
  String get autoUpdateFdroidNote =>
      'Nur für Installationen über GitHub. Wenn du die App über F-Droid installiert hast, lass dies aus und aktualisiere über F-Droid.';

  @override
  String get autoUpdateSilentTitle => 'Ohne Rückfrage installieren';

  @override
  String get autoUpdateSilentSubtitle =>
      'Device Owner erkannt: Updates können lautlos im Hintergrund installiert werden.';

  @override
  String get autoUpdatePromptNote =>
      'Wenn ein Update verfügbar ist, wirst du vor der Installation gefragt.';

  @override
  String get autoUpdateCheckNow => 'Jetzt prüfen';

  @override
  String get autoUpdateUpToDate => 'Du bist auf dem neuesten Stand.';

  @override
  String get updateAvailableTitle => 'Update verfügbar';

  @override
  String updateAvailableMessage(String version) {
    return 'Version $version ist verfügbar. Jetzt herunterladen und installieren?';
  }

  @override
  String get updateDownloading => 'Wird heruntergeladen…';

  @override
  String get updateSkip => 'Überspringen';

  @override
  String get updateDownloadInstall => 'Herunterladen & installieren';

  @override
  String get keepAliveDialogTitle => 'App am Laufen halten';

  @override
  String get keepAliveWhatDoes => 'Was macht diese Funktion?';

  @override
  String get keepAliveWhatDoesExplanation =>
      'Diese Funktion hält die Bilderrahmen-App dauerhaft am Laufen, auch wenn das Gerät wenig Arbeitsspeicher hat.';

  @override
  String get keepAliveWhyNeed => 'Wofür brauche ich das?';

  @override
  String get keepAliveWhyNeedExplanation =>
      'Auf älteren Geräten mit wenig RAM kann Android die App beenden, um Speicher freizugeben. Dies verhindert das, indem die App als Vordergrunddienst läuft.';

  @override
  String get keepAliveWhatHappens => 'Was passiert dann?';

  @override
  String get keepAliveWhatHappensExplanation =>
      '• Eine kleine Benachrichtigung erscheint in der Statusleiste\n• Die App wird weniger wahrscheinlich von Android beendet\n• Ab Android 13 musst du die Benachrichtigungs-Berechtigung erteilen';

  @override
  String get keepAliveDisableAnytime =>
      'Du kannst dies jederzeit in den Einstellungen deaktivieren.';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get enable => 'Aktivieren';

  @override
  String get about => 'Über';

  @override
  String aboutSubtitle(String version) {
    return 'Open Photo Frame v$version';
  }

  @override
  String get noPhotosFound => 'Keine Fotos gefunden';

  @override
  String get tapCenterToOpenSettings =>
      'Tippe auf die Bildschirmmitte um Einstellungen zu öffnen';

  @override
  String get screenOrientation => 'Bildschirmausrichtung';

  @override
  String get screenOrientationAuto => 'Automatisch (Sensor)';

  @override
  String get screenOrientationPortraitUp => 'Hochformat';

  @override
  String get screenOrientationPortraitDown => 'Hochformat (auf dem Kopf)';

  @override
  String get screenOrientationLandscapeLeft => 'Querformat (links)';

  @override
  String get screenOrientationLandscapeRight => 'Querformat (rechts)';
}
