import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../domain/interfaces/config_provider.dart';
import '../../domain/interfaces/display_controller.dart';
import '../../infrastructure/services/photo_service.dart';
import '../../infrastructure/services/native_display_controller.dart';
import '../../domain/models/photo_entry.dart';
import '../widgets/photo_slide.dart';
import '../widgets/clock_overlay.dart';
import 'settings_screen.dart';

class SlideshowScreen extends StatefulWidget {
  const SlideshowScreen({super.key});

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> with TickerProviderStateMixin {
  PhotoEntry? _currentPhoto;
  Timer? _timer;
  bool _isLoading = true;
  StreamSubscription? _photosSubscription;
  
  // Custom Stack for Transitions
  final List<_SlideItem> _slides = [];
  
  // Transaction ID to cancel outdated transitions
  int _transitionId = 0;
  
  // Screen size for optimized image loading
  Size? _screenSize;

  // Display schedule
  StreamSubscription? _scheduleSubscription;
  Timer? _scheduleTimer;
  bool _scheduleWasEnabled = false; // Track previous state for detecting changes
  
  // Display off state for black overlay
  bool _isDisplayOff = false;

  @override
  void initState() {
    super.initState();
    // Keep screen on (Safe implementation for Linux/Dev)
    _enableWakelock();
    
    // Initialize Service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initService();
      // Schedule init is now handled reactively in build() via _updateDisplaySchedule()
    });
  }

  /// Update display schedule based on config settings.
  /// Called from build() to react to config changes.
  void _updateDisplaySchedule(ConfigProvider config) {
    final scheduleEnabled = config.scheduleEnabled;
    
    // Detect state change
    if (scheduleEnabled != _scheduleWasEnabled) {
      print('📺 Schedule enabled changed: $_scheduleWasEnabled -> $scheduleEnabled');
      _scheduleWasEnabled = scheduleEnabled;
      
      if (scheduleEnabled) {
        // Schedule was just enabled - start timer
        print('📺 Display schedule enabled: Day ${config.dayStartHour}:${config.dayStartMinute.toString().padLeft(2, '0')}, Night ${config.nightStartHour}:${config.nightStartMinute.toString().padLeft(2, '0')}');
        
        // Cancel any existing timer
        _scheduleTimer?.cancel();
        
        // Check initial state and apply
        _applyScheduleState();
        
        // Check every minute for schedule changes
        _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
          _applyScheduleState();
        });
      } else {
        // Schedule was just disabled - stop timer and restore display
        print('📺 Display schedule disabled');
        _scheduleTimer?.cancel();
        _scheduleTimer = null;
        
        // Restore display to normal if it was off
        if (_isDisplayOff) {
          _restoreDisplay();
        }
      }
    }
  }
  
  /// Restore display to normal mode
  Future<void> _restoreDisplay() async {
    final displayController = context.read<DisplayController>();
    final nativeController = displayController is NativeDisplayController 
        ? displayController 
        : null;
    
    print('📺 Restoring display to normal');
    if (nativeController != null) {
      await nativeController.wakeNow();
    } else {
      await displayController.setMode(DisplayMode.normal);
    }
    if (mounted) setState(() => _isDisplayOff = false);
  }
  
  /// Apply current schedule state (day/night) based on time
  Future<void> _applyScheduleState() async {
    final config = context.read<ConfigProvider>();
    if (!config.scheduleEnabled) return;
    
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day, config.dayStartHour, config.dayStartMinute);
    final nightStart = DateTime(now.year, now.month, now.day, config.nightStartHour, config.nightStartMinute);
    
    // Determine if we're in day or night mode
    bool isNight;
    DateTime nextTransition;
    
    if (nightStart.isAfter(dayStart)) {
      // Normal case: day is before night (e.g., 8:00 - 22:00)
      isNight = now.isBefore(dayStart) || !now.isBefore(nightStart);
      if (isNight) {
        // We're in night mode, next transition is day start
        nextTransition = now.isBefore(dayStart) ? dayStart : dayStart.add(const Duration(days: 1));
      } else {
        // We're in day mode, next transition is night start
        nextTransition = nightStart;
      }
    } else {
      // Inverted case: night starts before day (e.g., 22:00 - 8:00 next day)
      isNight = !now.isBefore(nightStart) && now.isBefore(dayStart);
      if (isNight) {
        nextTransition = dayStart;
      } else {
        nextTransition = nightStart;
      }
    }
    
    final displayController = context.read<DisplayController>();
    final nativeController = displayController is NativeDisplayController 
        ? displayController 
        : null;
    
    if (isNight && !_isDisplayOff) {
      // Switch to night mode (screen off)
      print('📺 Switching to NIGHT mode (screen off), wake at $nextTransition');
      
      if (config.useNativeScreenOff && nativeController != null) {
        await nativeController.sleepUntil(nextTransition);
      } else {
        await displayController.setMode(DisplayMode.off);
      }
      if (mounted) setState(() => _isDisplayOff = true);
      
    } else if (!isNight && _isDisplayOff) {
      // Switch to day mode (screen on)
      print('📺 Switching to DAY mode (screen on)');
      
      if (nativeController != null) {
        await nativeController.wakeNow();
      } else {
        await displayController.setMode(DisplayMode.normal);
      }
      if (mounted) setState(() => _isDisplayOff = false);
    }
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      print("Wakelock not supported or failed on this platform (ignoring): $e");
    }
  }

  Future<void> _initService() async {
    final service = context.read<PhotoService>();
    
    // Listen for updates
    _photosSubscription = service.onPhotosChanged.listen((_) {
      if (mounted) {
        // If we were loading or showing "No photos", try to start slideshow
        if (_isLoading || _currentPhoto == null) {
           final next = service.nextPhoto();
           if (next != null) {
             _transitionTo(next);
             _startTimer();
           }
        }
      }
    });

    await service.initialize();
    
    // Initial check
    final firstPhoto = service.nextPhoto();
    if (mounted) {
      if (firstPhoto != null) {
        _transitionTo(firstPhoto);
        _startTimer();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final config = context.read<ConfigProvider>();
    final slideDuration = Duration(seconds: config.slideDurationSeconds);
    _timer = Timer.periodic(slideDuration, (timer) {
      _nextSlide();
    });
  }

  void _nextSlide() {
    final service = context.read<PhotoService>();
    final photo = service.nextPhoto();
    
    if (photo != null && photo.file.path != _currentPhoto?.file.path) {
      _transitionTo(photo);
    }
  }

  void _manualNavigation(bool forward) {
    _timer?.cancel(); // Stop auto-advance
    
    final service = context.read<PhotoService>();
    final photo = forward ? service.nextPhoto() : service.previousPhoto();
    
    if (photo != null) {
      _transitionTo(photo);
    }
    
    // Restart timer after interaction
    _startTimer();
  }

  void _openSettings() {
    _timer?.cancel(); // Stop auto-advance while in settings
    
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    ).then((_) {
      // Restore immersive mode after returning from settings
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // Restart timer when returning from settings
      _startTimer();
    });
  }

  Future<void> _transitionTo(PhotoEntry photo) async {
    // Increment transaction ID - this invalidates any pending transitions
    final myTransitionId = ++_transitionId;
    
    // Ensure we have screen size (might not be available on first call)
    if (_screenSize == null) {
      // Fallback: use a reasonable default until MediaQuery is available
      _screenSize = const Size(1920, 1080);
    }
    
    // Preload the image before starting the transition
    // Use ResizeImage for faster decoding on slower devices
    final imageProvider = PhotoSlide.createOptimizedProvider(photo.file, _screenSize!);
    try {
      await _preloadImage(imageProvider);
    } catch (e) {
      print('Failed to preload image: $e');
      // Continue anyway - the image might still load
    }

    // Check if this transition is still valid (not superseded by a newer one)
    if (!mounted || myTransitionId != _transitionId) {
      return; // A newer transition was started, abort this one
    }

    // Force all existing slides to 100% opacity immediately
    // This ensures that if a slide is mid-animation, it becomes fully visible
    // so the new slide can cleanly fade in over it.
    for (var slide in _slides) {
      if (slide.controller.isAnimating) {
        slide.controller.stop();
      }
      slide.controller.value = 1.0;
    }

    // Create controller for new slide
    final config = context.read<ConfigProvider>();
    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: config.transitionDurationMs),
    );

    final newItem = _SlideItem(
      photo: photo,
      controller: controller,
    );

    setState(() {
      _isLoading = false;
      _currentPhoto = photo;
      _slides.add(newItem);
    });

    // Start animation
    controller.forward().then((_) {
      // When finished, remove all slides below this one to save memory
      if (mounted && _slides.contains(newItem)) {
        setState(() {
          while (_slides.first != newItem) {
            _slides.first.controller.dispose();
            _slides.removeAt(0);
          }
        });
      }
    });
  }

  /// Preloads an image and waits for it to be fully decoded
  Future<void> _preloadImage(ImageProvider provider) {
    final completer = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete();
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        completer.completeError(error, stackTrace);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _photosSubscription?.cancel();
    _scheduleSubscription?.cancel();
    _scheduleTimer?.cancel();
    for (var slide in _slides) {
      slide.controller.dispose();
    }
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cache screen size for optimized image loading
    _screenSize = MediaQuery.of(context).size;
    final config = context.watch<ConfigProvider>();
    
    // React to schedule config changes
    _updateDisplaySchedule(config);
    
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_slides.isEmpty) {
      return Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openSettings,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined, size: 64, color: Colors.white54),
                SizedBox(height: 16),
                Text(
                  "No photos found",
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                SizedBox(height: 8),
                Text(
                  "Tap center of screen to open settings",
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Content Layer (Custom Stack)
          ..._slides.map((slide) {
            return FadeTransition(
              opacity: slide.controller,
              child: PhotoSlide(
                key: ValueKey(slide.photo.file.path),
                photo: slide.photo,
                screenSize: _screenSize!,
              ),
            );
          }).toList(),

          // 2. Clock Overlay
          if (config.showClock)
            ClockOverlay(
              key: ValueKey('clock_${config.clockSize}_${config.clockPosition}'),
              size: config.clockSize,
              position: config.clockPosition,
            ),

          // 3. Touch Layer (Invisible, on top)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) {
                final width = MediaQuery.of(context).size.width;
                final dx = details.globalPosition.dx;
                print("Tap detected at x=$dx (Screen width: $width)");
                
                if (dx > width * 0.75) {
                  print("Action: Tap Next");
                  _manualNavigation(true); // Right 25% -> Next
                } else if (dx < width * 0.25) {
                  print("Action: Tap Previous");
                  _manualNavigation(false); // Left 25% -> Previous
                } else {
                  print("Action: Open Settings");
                  _openSettings();
                }
              },
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity!;
                print("Drag ended with velocity: $velocity");
                
                if (velocity < 0) {
                  print("Action: Swipe Left -> Next");
                  _manualNavigation(true); // Swipe Left -> Next
                } else if (velocity > 0) {
                  print("Action: Swipe Right -> Previous");
                  _manualNavigation(false); // Swipe Right -> Previous
                }
              },
            ),
          ),
          
          // 4. Black overlay when display is "off" (for LCD displays)
          // Uses IgnorePointer so touch events pass through to the layer below
          if (_isDisplayOff)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: Colors.black),
              ),
            ),
        ],
      ),
    );
  }
}

class _SlideItem {
  final PhotoEntry photo;
  final AnimationController controller;

  _SlideItem({required this.photo, required this.controller});
}
