import 'package:flutter/foundation.dart';

abstract class ConfigProvider extends ChangeNotifier {
  Future<void> load();
  Future<void> save();
  
  // Source settings
  String get activeSourceType;
  set activeSourceType(String value);
  Map<String, dynamic> getSourceConfig(String type);
  void setSourceConfig(String type, Map<String, dynamic> config);
  
  // Slideshow settings
  int get slideDurationSeconds; // How long each slide is shown
  set slideDurationSeconds(int value);
  
  int get transitionDurationMs; // Fade transition duration
  set transitionDurationMs(int value);
  
  // Sync settings
  int get syncIntervalMinutes; // 0 = disabled, otherwise interval in minutes
  set syncIntervalMinutes(int value);
  
  bool get deleteOrphanedFiles; // Delete local files not on server
  set deleteOrphanedFiles(bool value);
  
  DateTime? get lastSuccessfulSync; // Timestamp of last successful sync
  set lastSuccessfulSync(DateTime? value);
  
  // Android specific settings
  bool get autostartOnBoot; // Start app when device boots (Android only)
  set autostartOnBoot(bool value);
  
  // Clock display settings
  bool get showClock; // Show clock overlay
  set showClock(bool value);
  
  String get clockSize; // 'small', 'medium', 'large'
  set clockSize(String value);
  
  String get clockPosition; // 'bottomRight', 'bottomLeft', 'topRight', 'topLeft'
  set clockPosition(String value);
  
  // Display schedule settings (day/night mode)
  bool get scheduleEnabled; // Enable day/night schedule
  set scheduleEnabled(bool value);
  
  int get dayStartHour; // Hour when day mode starts (0-23), default 8
  set dayStartHour(int value);
  
  int get dayStartMinute; // Minute when day mode starts (0-59), default 0
  set dayStartMinute(int value);
  
  int get nightStartHour; // Hour when night mode starts (0-23), default 22
  set nightStartHour(int value);
  
  int get nightStartMinute; // Minute when night mode starts (0-59), default 0
  set nightStartMinute(int value);
  
  bool get useNativeScreenOff; // Use Device Admin lockNow() for true screen off (Android)
  set useNativeScreenOff(bool value);
  
  // Custom photo directory (for "local folder" mode)
  String? get customPhotoPath; // null = use internal app folder, otherwise external path
  set customPhotoPath(String? value);
}
