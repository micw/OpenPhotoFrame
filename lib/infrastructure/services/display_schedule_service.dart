import 'dart:async';
import '../../domain/interfaces/display_controller.dart';

/// Configuration for a scheduled display period.
class DisplaySchedule {
  /// Start time (hour:minute) when this mode should activate.
  final TimeOfDay startTime;
  
  /// End time (hour:minute) when this mode should deactivate.
  /// If endTime < startTime, it spans midnight.
  final TimeOfDay endTime;
  
  /// The display mode to apply during this period.
  final DisplayMode mode;
  
  /// Whether this schedule is enabled.
  final bool enabled;
  
  const DisplaySchedule({
    required this.startTime,
    required this.endTime,
    required this.mode,
    this.enabled = true,
  });
  
  /// Creates a night mode schedule (e.g., 22:00 - 07:00).
  factory DisplaySchedule.nightMode({
    TimeOfDay startTime = const TimeOfDay(hour: 22, minute: 0),
    TimeOfDay endTime = const TimeOfDay(hour: 7, minute: 0),
    DisplayMode mode = DisplayMode.off,
    bool enabled = true,
  }) {
    return DisplaySchedule(
      startTime: startTime,
      endTime: endTime,
      mode: mode,
      enabled: enabled,
    );
  }
  
  /// Checks if the given time falls within this schedule.
  bool isActiveAt(DateTime dateTime) {
    if (!enabled) return false;
    
    final currentMinutes = dateTime.hour * 60 + dateTime.minute;
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    
    if (startMinutes <= endMinutes) {
      // Normal case: e.g., 09:00 - 17:00
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      // Spans midnight: e.g., 22:00 - 07:00
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }
  
  /// Calculates the next transition time (when schedule activates or deactivates).
  DateTime nextTransitionFrom(DateTime now) {
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    
    if (!enabled) {
      // Return a far future date if disabled
      return now.add(const Duration(days: 365));
    }
    
    DateTime result;
    
    if (isActiveAt(now)) {
      // Currently active, next transition is end time
      if (currentMinutes < endMinutes) {
        result = DateTime(now.year, now.month, now.day, endTime.hour, endTime.minute);
      } else {
        // End time is tomorrow
        final tomorrow = now.add(const Duration(days: 1));
        result = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, endTime.hour, endTime.minute);
      }
    } else {
      // Currently inactive, next transition is start time
      if (currentMinutes < startMinutes) {
        result = DateTime(now.year, now.month, now.day, startTime.hour, startTime.minute);
      } else {
        // Start time is tomorrow
        final tomorrow = now.add(const Duration(days: 1));
        result = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, startTime.hour, startTime.minute);
      }
    }
    
    return result;
  }
  
  DisplaySchedule copyWith({
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    DisplayMode? mode,
    bool? enabled,
  }) {
    return DisplaySchedule(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      mode: mode ?? this.mode,
      enabled: enabled ?? this.enabled,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'startHour': startTime.hour,
      'startMinute': startTime.minute,
      'endHour': endTime.hour,
      'endMinute': endTime.minute,
      'mode': mode.name,
      'enabled': enabled,
    };
  }
  
  factory DisplaySchedule.fromJson(Map<String, dynamic> json) {
    return DisplaySchedule(
      startTime: TimeOfDay(
        hour: json['startHour'] ?? 22,
        minute: json['startMinute'] ?? 0,
      ),
      endTime: TimeOfDay(
        hour: json['endHour'] ?? 7,
        minute: json['endMinute'] ?? 0,
      ),
      mode: DisplayMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => DisplayMode.off,
      ),
      enabled: json['enabled'] ?? false,
    );
  }
}

/// Simple TimeOfDay class (Flutter-independent).
class TimeOfDay {
  final int hour;
  final int minute;
  
  const TimeOfDay({required this.hour, required this.minute});
  
  @override
  String toString() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeOfDay && other.hour == hour && other.minute == minute;
  }
  
  @override
  int get hashCode => hour.hashCode ^ minute.hashCode;
}

/// Service that manages display brightness based on a schedule.
/// 
/// This service periodically checks if a scheduled period is active
/// and adjusts the display accordingly.
class DisplayScheduleService {
  final DisplayController _displayController;
  final DateTime Function() _nowProvider;
  
  Timer? _timer;
  DisplaySchedule? _schedule;
  bool _isScheduleActive = false;
  
  /// Stream controller for schedule state changes.
  final _stateController = StreamController<bool>.broadcast();
  
  DisplayScheduleService({
    required DisplayController displayController,
    DateTime Function()? nowProvider,
  })  : _displayController = displayController,
        _nowProvider = nowProvider ?? DateTime.now;
  
  /// Stream that emits true when schedule becomes active, false when inactive.
  Stream<bool> get onScheduleStateChanged => _stateController.stream;
  
  /// Whether the schedule is currently active (display is dimmed/off).
  bool get isScheduleActive => _isScheduleActive;
  
  /// The current schedule, if any.
  DisplaySchedule? get schedule => _schedule;
  
  /// The underlying display controller.
  DisplayController get displayController => _displayController;
  
  /// Sets and applies a new schedule.
  /// 
  /// Pass null to disable scheduling (returns display to normal).
  Future<void> setSchedule(DisplaySchedule? schedule) async {
    _schedule = schedule;
    
    // Cancel existing timer
    _timer?.cancel();
    
    if (schedule == null || !schedule.enabled) {
      // No schedule - ensure display is normal
      if (_isScheduleActive) {
        await _displayController.setMode(DisplayMode.normal);
        _isScheduleActive = false;
        _stateController.add(false);
      }
      return;
    }
    
    // Apply immediately and start timer
    await _checkAndApply();
    _startTimer();
  }
  
  /// Manually triggers a check and applies the schedule if needed.
  Future<void> checkNow() async {
    await _checkAndApply();
  }
  
  Future<void> _checkAndApply() async {
    final schedule = _schedule;
    if (schedule == null || !schedule.enabled) return;
    
    final now = _nowProvider();
    final shouldBeActive = schedule.isActiveAt(now);
    
    if (shouldBeActive && !_isScheduleActive) {
      // Schedule just became active
      await _displayController.setMode(schedule.mode);
      _isScheduleActive = true;
      _stateController.add(true);
    } else if (!shouldBeActive && _isScheduleActive) {
      // Schedule just became inactive
      await _displayController.setMode(DisplayMode.normal);
      _isScheduleActive = false;
      _stateController.add(false);
    }
  }
  
  void _startTimer() {
    // Check every minute for schedule changes
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkAndApply();
    });
  }
  
  /// Temporarily overrides the schedule and sets a specific mode.
  /// 
  /// Call [resumeSchedule] to return to scheduled behavior.
  Future<void> overrideMode(DisplayMode mode) async {
    _timer?.cancel();
    await _displayController.setMode(mode);
  }
  
  /// Resumes the scheduled behavior after an override.
  Future<void> resumeSchedule() async {
    if (_schedule != null && _schedule!.enabled) {
      await _checkAndApply();
      _startTimer();
    }
  }
  
  /// Disposes the service and releases resources.
  void dispose() {
    _timer?.cancel();
    _stateController.close();
    _displayController.dispose();
  }
}
