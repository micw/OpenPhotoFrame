import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class EmmcCacheWarmService {
  static const String _key = 'emmc_cache_warm_enabled';

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
