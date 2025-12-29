import 'dart:io';
import 'package:flutter/services.dart';

/// Native screen control service using Android Device Admin API.
/// 
/// This service provides the ability to:
/// - Turn the screen completely off using lockNow()
/// - Schedule wake-up using AlarmManager
/// - Wake the screen immediately
/// 
/// Requires Device Admin permission to be enabled by the user.
class NativeScreenControlService {
  static const _channel = MethodChannel('io.github.micw.openphotoframe/screen_control');
  
  /// Check if the platform supports native screen control.
  static bool get isSupported => Platform.isAndroid;
  
  /// Check if Device Admin is enabled for this app.
  static Future<bool> isDeviceAdminEnabled() async {
    if (!isSupported) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('isDeviceAdminEnabled');
      return result ?? false;
    } catch (e) {
      print('Error checking Device Admin status: $e');
      return false;
    }
  }
  
  /// Request the user to enable Device Admin for this app.
  /// 
  /// This will open the Android Device Admin settings screen.
  static Future<void> requestDeviceAdmin() async {
    if (!isSupported) return;
    
    try {
      await _channel.invokeMethod('requestDeviceAdmin');
    } catch (e) {
      print('Error requesting Device Admin: $e');
    }
  }

  /// Open the Device Admin settings where the user can disable this app.
  /// 
  /// This is useful for uninstalling the app, which requires disabling
  /// Device Admin first.
  static Future<void> openDeviceAdminSettings() async {
    if (!isSupported) return;
    
    try {
      await _channel.invokeMethod('openDeviceAdminSettings');
    } catch (e) {
      print('Error opening Device Admin settings: $e');
    }
  }
  
  /// Turn the screen off using lockNow().
  /// 
  /// Returns true if successful, false if Device Admin is not enabled.
  static Future<bool> turnScreenOff() async {
    if (!isSupported) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('turnScreenOff');
      return result ?? false;
    } catch (e) {
      print('Error turning screen off: $e');
      return false;
    }
  }
  
  /// Schedule a wake-up at the specified time.
  /// 
  /// The device will wake up and bring the app to the foreground.
  static Future<bool> scheduleWakeUp(DateTime wakeTime) async {
    if (!isSupported) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('scheduleWakeUp', {
        'wakeTimeMillis': wakeTime.millisecondsSinceEpoch,
      });
      return result ?? false;
    } catch (e) {
      print('Error scheduling wake-up: $e');
      return false;
    }
  }
  
  /// Cancel any scheduled wake-up.
  static Future<bool> cancelScheduledWakeUp() async {
    if (!isSupported) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('cancelScheduledWakeUp');
      return result ?? false;
    } catch (e) {
      print('Error cancelling wake-up: $e');
      return false;
    }
  }
  
  /// Wake the screen immediately.
  static Future<bool> wakeScreenNow() async {
    if (!isSupported) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('wakeScreenNow');
      return result ?? false;
    } catch (e) {
      print('Error waking screen: $e');
      return false;
    }
  }
  
  /// Check if the screen is currently on.
  static Future<bool> isScreenOn() async {
    if (!isSupported) return true;
    
    try {
      final result = await _channel.invokeMethod<bool>('isScreenOn');
      return result ?? true;
    } catch (e) {
      print('Error checking screen state: $e');
      return true;
    }
  }
}
