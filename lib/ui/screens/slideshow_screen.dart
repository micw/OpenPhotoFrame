import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../domain/interfaces/config_provider.dart';
import '../../infrastructure/services/photo_service.dart';
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

  @override
  void initState() {
    super.initState();
    // Keep screen on (Safe implementation for Linux/Dev)
    _enableWakelock();
    
    // Initialize Service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initService();
    });
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
