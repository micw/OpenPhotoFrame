import 'dart:io';
import 'package:screen_brightness/screen_brightness.dart';
import '../../domain/interfaces/display_controller.dart';

/// Implementation of [DisplayController] using the screen_brightness plugin.
/// 
/// This implementation uses the app's window brightness settings which:
/// - Does NOT require WRITE_SETTINGS permission
/// - Overrides auto-brightness while a specific value is set
/// - Returns to system settings (including auto-brightness) when reset
/// 
/// On non-mobile platforms, some operations may fail gracefully.
class BrightnessDisplayController implements DisplayController {
  final ScreenBrightness _screenBrightness;
  
  DisplayMode _currentMode = DisplayMode.normal;
  double _dimmedBrightness = 0.1; // 10% default
  
  BrightnessDisplayController({
    ScreenBrightness? screenBrightness,
  }) : _screenBrightness = screenBrightness ?? ScreenBrightness();
  
  @override
  DisplayMode get currentMode => _currentMode;
  
  @override
  double get dimmedBrightness => _dimmedBrightness;
  
  @override
  set dimmedBrightness(double value) {
    _dimmedBrightness = value.clamp(0.0, 1.0);
  }
  
  @override
  bool get supportsScreenOff {
    // screen_brightness can set brightness to 0, which is effectively "off"
    // on OLED displays. On LCD, the backlight may still be on but very dim.
    // True screen off would require Device Admin permissions.
    return false;
  }
  
  @override
  Future<DisplayControlResult> setMode(DisplayMode mode) async {
    switch (mode) {
      case DisplayMode.normal:
        return _setNormalMode();
      case DisplayMode.dimmed:
        return setBrightness(_dimmedBrightness);
      case DisplayMode.off:
        return setBrightness(0.0);
    }
  }
  
  Future<DisplayControlResult> _setNormalMode() async {
    try {
      // Reset to system brightness (auto-brightness will work again)
      await _screenBrightness.resetApplicationScreenBrightness();
      _currentMode = DisplayMode.normal;
      return const DisplayControlResult.success(actualBrightness: null);
    } catch (e) {
      return DisplayControlResult.failure('Failed to reset brightness: $e');
    }
  }
  
  @override
  Future<DisplayControlResult> setBrightness(double brightness) async {
    final clampedBrightness = brightness.clamp(0.0, 1.0);
    
    // Skip on unsupported platforms
    if (!_isPlatformSupported) {
      _currentMode = clampedBrightness == 0.0 
          ? DisplayMode.off 
          : (clampedBrightness <= _dimmedBrightness ? DisplayMode.dimmed : DisplayMode.normal);
      return DisplayControlResult.success(actualBrightness: clampedBrightness);
    }
    
    try {
      await _screenBrightness.setApplicationScreenBrightness(clampedBrightness);
      
      // Update current mode based on brightness value
      if (clampedBrightness == 0.0) {
        _currentMode = DisplayMode.off;
      } else if (clampedBrightness <= _dimmedBrightness) {
        _currentMode = DisplayMode.dimmed;
      } else {
        // If we're setting a specific brightness that's not dimmed/off,
        // we're still in a "controlled" state, not truly normal
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
      return 1.0; // Assume full brightness on unsupported platforms
    }
    
    try {
      // Try to get application brightness first
      final appBrightness = await _screenBrightness.application;
      if (appBrightness >= 0) {
        return appBrightness;
      }
      
      // Fall back to system brightness
      return await _screenBrightness.system;
    } catch (e) {
      return 1.0; // Default to full brightness on error
    }
  }
  
  bool get _isPlatformSupported {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }
  
  @override
  void dispose() {
    // Reset to system brightness when disposing
    if (_isPlatformSupported && _currentMode != DisplayMode.normal) {
      _screenBrightness.resetApplicationScreenBrightness();
    }
  }
}
