/// Possible display modes for the screen.
enum DisplayMode {
  /// Normal operation - system controls brightness (auto-brightness if enabled)
  normal,
  
  /// Dimmed - fixed low brightness value
  dimmed,
  
  /// Off - screen as dark as possible (brightness 0)
  off,
}

/// Result of a display control operation.
class DisplayControlResult {
  final bool success;
  final String? errorMessage;
  
  /// The actual brightness value that was set (0.0 to 1.0)
  /// Null if we returned control to the system.
  final double? actualBrightness;
  
  const DisplayControlResult.success({this.actualBrightness})
      : success = true,
        errorMessage = null;
  
  const DisplayControlResult.failure(this.errorMessage)
      : success = false,
        actualBrightness = null;
}

/// Controller for managing display brightness and on/off state.
/// 
/// This abstraction allows different implementations for different platforms
/// and provides a clean separation between the scheduling logic and the
/// actual display control mechanism.
abstract class DisplayController {
  /// Sets the display to a specific mode.
  /// 
  /// - [DisplayMode.normal]: Returns control to system (auto-brightness works)
  /// - [DisplayMode.dimmed]: Sets a fixed dim brightness
  /// - [DisplayMode.off]: Sets brightness to minimum (0)
  Future<DisplayControlResult> setMode(DisplayMode mode);
  
  /// Sets a specific brightness value (0.0 = off, 1.0 = max).
  /// 
  /// This overrides auto-brightness while active.
  /// Use [setMode(DisplayMode.normal)] to return control to system.
  Future<DisplayControlResult> setBrightness(double brightness);
  
  /// Gets the current brightness value (0.0 to 1.0).
  Future<double> getCurrentBrightness();
  
  /// The brightness value to use for dimmed mode.
  /// Can be configured by the user (e.g., 0.1 for 10% brightness).
  double get dimmedBrightness;
  set dimmedBrightness(double value);
  
  /// Returns true if the platform supports turning the screen completely off.
  /// If false, the best we can do is set brightness to 0.
  bool get supportsScreenOff;
  
  /// The current display mode.
  DisplayMode get currentMode;
  
  /// Releases all resources.
  void dispose();
}
