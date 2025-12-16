import 'dart:io';
import 'package:screen_brightness/screen_brightness.dart';
import '../../domain/interfaces/display_controller.dart';
import 'native_screen_control_service.dart';

/// Advanced implementation of [DisplayController] that uses native screen control
/// (Device Admin lockNow) when available, with fallback to brightness control.
/// 
/// This controller automatically detects if Device Admin is enabled and uses
/// the most effective method to turn the screen off:
/// 1. If Device Admin enabled: lockNow() for true screen off
/// 2. Fallback: Brightness 0 + black overlay
class NativeDisplayController implements DisplayController {
  final ScreenBrightness _screenBrightness;
  
  DisplayMode _currentMode = DisplayMode.normal;
  double _dimmedBrightness = 0.1;
  bool _deviceAdminEnabled = false;
  DateTime? _scheduledWakeTime;
  
  NativeDisplayController({
    ScreenBrightness? screenBrightness,
  }) : _screenBrightness = screenBrightness ?? ScreenBrightness() {
    _checkDeviceAdmin();
  }
  
  Future<void> _checkDeviceAdmin() async {
    _deviceAdminEnabled = await NativeScreenControlService.isDeviceAdminEnabled();
    print('📺 Device Admin enabled: $_deviceAdminEnabled');
  }
  
  @override
  DisplayMode get currentMode => _currentMode;
  
  @override
  double get dimmedBrightness => _dimmedBrightness;
  
  @override
  set dimmedBrightness(double value) {
    _dimmedBrightness = value.clamp(0.0, 1.0);
  }
  
  @override
  bool get supportsScreenOff => _deviceAdminEnabled;
  
  /// Refresh the Device Admin status.
  Future<void> refreshDeviceAdminStatus() async {
    await _checkDeviceAdmin();
  }
  
  /// Request Device Admin permission.
  Future<void> requestDeviceAdmin() async {
    await NativeScreenControlService.requestDeviceAdmin();
  }
  
  /// Check if Device Admin is currently enabled.
  bool get isDeviceAdminEnabled => _deviceAdminEnabled;
  
  @override
  Future<DisplayControlResult> setMode(DisplayMode mode) async {
    // Refresh device admin status
    await _checkDeviceAdmin();
    
    switch (mode) {
      case DisplayMode.normal:
        return _setNormalMode();
      case DisplayMode.dimmed:
        return _setDimmedMode();
      case DisplayMode.off:
        return _setOffMode();
    }
  }
  
  Future<DisplayControlResult> _setNormalMode() async {
    print('📺 Setting mode: NORMAL');
    
    // Cancel any scheduled wake-up
    if (_scheduledWakeTime != null) {
      await NativeScreenControlService.cancelScheduledWakeUp();
      _scheduledWakeTime = null;
    }
    
    // If screen was locked, we need to wake it
    if (_currentMode == DisplayMode.off && _deviceAdminEnabled) {
      await NativeScreenControlService.wakeScreenNow();
    }
    
    // Reset brightness to system
    try {
      if (_isPlatformSupported) {
        await _screenBrightness.resetApplicationScreenBrightness();
      }
      _currentMode = DisplayMode.normal;
      return const DisplayControlResult.success(actualBrightness: null);
    } catch (e) {
      return DisplayControlResult.failure('Failed to reset brightness: $e');
    }
  }
  
  Future<DisplayControlResult> _setDimmedMode() async {
    print('📺 Setting mode: DIMMED (brightness: $_dimmedBrightness)');
    
    try {
      if (_isPlatformSupported) {
        await _screenBrightness.setApplicationScreenBrightness(_dimmedBrightness);
      }
      _currentMode = DisplayMode.dimmed;
      return DisplayControlResult.success(actualBrightness: _dimmedBrightness);
    } catch (e) {
      return DisplayControlResult.failure('Failed to set dimmed mode: $e');
    }
  }
  
  Future<DisplayControlResult> _setOffMode() async {
    print('📺 Setting mode: OFF (Device Admin: $_deviceAdminEnabled)');
    
    if (_deviceAdminEnabled) {
      // Use native screen off
      final success = await NativeScreenControlService.turnScreenOff();
      if (success) {
        _currentMode = DisplayMode.off;
        return const DisplayControlResult.success(actualBrightness: 0.0);
      } else {
        // Fall through to brightness fallback
        print('📺 lockNow() failed, falling back to brightness control');
      }
    }
    
    // Fallback: set brightness to 0
    try {
      if (_isPlatformSupported) {
        await _screenBrightness.setApplicationScreenBrightness(0.0);
      }
      _currentMode = DisplayMode.off;
      return const DisplayControlResult.success(actualBrightness: 0.0);
    } catch (e) {
      return DisplayControlResult.failure('Failed to set off mode: $e');
    }
  }
  
  /// Turn off the screen and schedule a wake-up at the specified time.
  Future<DisplayControlResult> sleepUntil(DateTime wakeTime) async {
    print('📺 Sleeping until: $wakeTime');
    
    // First, schedule the wake-up
    if (Platform.isAndroid) {
      await NativeScreenControlService.scheduleWakeUp(wakeTime);
      _scheduledWakeTime = wakeTime;
    }
    
    // Then turn off the screen
    return setMode(DisplayMode.off);
  }
  
  /// Wake up the screen immediately.
  Future<void> wakeNow() async {
    print('📺 Waking now');
    
    if (Platform.isAndroid) {
      await NativeScreenControlService.cancelScheduledWakeUp();
      _scheduledWakeTime = null;
      await NativeScreenControlService.wakeScreenNow();
    }
    
    await setMode(DisplayMode.normal);
  }
  
  @override
  Future<DisplayControlResult> setBrightness(double brightness) async {
    final clampedBrightness = brightness.clamp(0.0, 1.0);
    
    if (clampedBrightness == 0.0) {
      return setMode(DisplayMode.off);
    }
    
    try {
      if (_isPlatformSupported) {
        await _screenBrightness.setApplicationScreenBrightness(clampedBrightness);
      }
      
      if (clampedBrightness <= _dimmedBrightness) {
        _currentMode = DisplayMode.dimmed;
      } else {
        _currentMode = DisplayMode.normal;
      }
      
      return DisplayControlResult.success(actualBrightness: clampedBrightness);
    } catch (e) {
      return DisplayControlResult.failure('Failed to set brightness: $e');
    }
  }
  
  @override
  Future<double> getCurrentBrightness() async {
    if (!_isPlatformSupported) {
      return 1.0;
    }
    
    try {
      final appBrightness = await _screenBrightness.application;
      if (appBrightness >= 0) {
        return appBrightness;
      }
      return await _screenBrightness.system;
    } catch (e) {
      return 1.0;
    }
  }
  
  bool get _isPlatformSupported {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }
  
  @override
  void dispose() {
    if (_isPlatformSupported && _currentMode != DisplayMode.normal) {
      _screenBrightness.resetApplicationScreenBrightness();
    }
    if (_scheduledWakeTime != null) {
      NativeScreenControlService.cancelScheduledWakeUp();
    }
  }
}
