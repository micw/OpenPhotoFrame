import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage the Keep Alive foreground service on Android.
/// 
/// This service prevents the app from being killed by the system's low memory
/// killer by running a foreground service with a persistent notification.
class KeepAliveService {
  static const _channel = MethodChannel('io.github.micw.openphotoframe/keep_alive');
  static const String _keepAliveKey = 'keep_alive_enabled';

  /// Save keep alive setting to SharedPreferences.
  /// This is read by the Android WakeReceiver during wake-up.
  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepAliveKey, enabled);
  }

  /// Get current keep alive setting from SharedPreferences.
  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keepAliveKey) ?? false;
  }

  /// Start the Keep Alive foreground service.
  /// 
  /// On Android 13+, this will request notification permission if not granted.
  /// Returns true if service started successfully, false otherwise.
  static Future<bool> startService() async {
    if (!Platform.isAndroid) return false;
    
    try {
      // Check if we need notification permission (Android 13+)
      final needsPermission = await shouldRequestNotificationPermission();
      if (needsPermission) {
        // Note: The actual permission request dialog should be handled by the UI
        // This just checks the status
        return false;
      }
      
      final result = await _channel.invokeMethod<bool>('startService');
      return result ?? false;
    } catch (e) {
      print('Error starting Keep Alive service: $e');
      return false;
    }
  }

  /// Stop the Keep Alive foreground service.
  static Future<void> stopService() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('stopService');
    } catch (e) {
      print('Error stopping Keep Alive service: $e');
    }
  }

  /// Check if notification permission is granted.
  /// 
  /// Always returns true on Android < 13.
  static Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final result = await _channel.invokeMethod<bool>('hasNotificationPermission');
      return result ?? false;
    } catch (e) {
      print('Error checking notification permission: $e');
      return false;
    }
  }

  /// Check if we should request notification permission.
  /// 
  /// Returns true only on Android 13+ if permission is not granted.
  static Future<bool> shouldRequestNotificationPermission() async {
    if (!Platform.isAndroid) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('shouldRequestNotificationPermission');
      return result ?? false;
    } catch (e) {
      print('Error checking if should request permission: $e');
      return false;
    }
  }

  /// Check if the Keep Alive service is currently running.
  static Future<bool> isServiceRunning() async {
    if (!Platform.isAndroid) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      return result ?? false;
    } catch (e) {
      print('Error checking service status: $e');
      return false;
    }
  }
}
