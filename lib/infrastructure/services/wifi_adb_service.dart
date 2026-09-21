import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class WifiAdbService {
  static const String _wifiAdbKey = 'wifi_adb_enabled';

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wifiAdbKey, enabled);
  }
}
