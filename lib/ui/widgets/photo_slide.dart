import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../domain/models/photo_entry.dart';

class PhotoSlide extends StatelessWidget {
  final PhotoEntry photo;
  final Size screenSize;

  const PhotoSlide({super.key, required this.photo, required this.screenSize});

  /// Creates a ResizeImage provider optimized for the screen size.
  /// This significantly speeds up decoding on slower devices.
  static ImageProvider createOptimizedProvider(File file, Size screenSize) {
    // Use the larger dimension to ensure the image covers the screen
    // Adding some buffer for quality (1.2x)
    final targetSize = (screenSize.longestSide * 1.2).toInt();
    return ResizeImage(
      FileImage(file),
      width: targetSize,
      height: targetSize,
      policy: ResizeImagePolicy.fit,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use ResizeImage for faster decoding - loads image at screen resolution
    final imageProvider = createOptimizedProvider(photo.file, screenSize);
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Blurred Background
        Image(
          image: imageProvider,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withOpacity(0.4),
          ),
        ),
        
        // 2. Main Image
        Center(
          child: Image(
            image: imageProvider,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      ],
    );
  }
}
