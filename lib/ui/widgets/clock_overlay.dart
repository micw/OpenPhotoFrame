import 'dart:async';
import 'package:flutter/material.dart';

/// A beautiful clock overlay widget with customizable size and position.
class ClockOverlay extends StatefulWidget {
  final String size; // 'small', 'medium', 'large'
  final String position; // 'bottomRight', 'bottomLeft', 'topRight', 'topLeft'

  const ClockOverlay({
    super.key,
    required this.size,
    required this.position,
  });

  @override
  State<ClockOverlay> createState() => _ClockOverlayState();
}

class _ClockOverlayState extends State<ClockOverlay> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Update every second
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  double get _fontSize {
    switch (widget.size) {
      case 'small':
        return 32;
      case 'large':
        return 72;
      case 'medium':
      default:
        return 48;
    }
  }

  Alignment get _alignment {
    switch (widget.position) {
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'topRight':
        return Alignment.topRight;
      case 'topLeft':
        return Alignment.topLeft;
      case 'bottomRight':
      default:
        return Alignment.bottomRight;
    }
  }

  EdgeInsets get _padding {
    const base = 24.0;
    switch (widget.position) {
      case 'bottomLeft':
        return const EdgeInsets.only(left: base, bottom: base);
      case 'topRight':
        return const EdgeInsets.only(right: base, top: base);
      case 'topLeft':
        return const EdgeInsets.only(left: base, top: base);
      case 'bottomRight':
      default:
        return const EdgeInsets.only(right: base, bottom: base);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeString = '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    
    return Align(
      alignment: _alignment,
      child: Padding(
        padding: _padding,
        child: Text(
          timeString,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.w300, // Light weight for elegant look
            color: Colors.white,
            shadows: const [
              // Shadow for readability on any background
              Shadow(
                offset: Offset(2, 2),
                blurRadius: 8,
                color: Colors.black54,
              ),
              Shadow(
                offset: Offset(-1, -1),
                blurRadius: 4,
                color: Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
