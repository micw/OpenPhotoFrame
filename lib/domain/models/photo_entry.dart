import 'dart:io';

class PhotoEntry {
  final File file;
  /// File modification date - used for shuffle algorithm
  final DateTime date;
  final int sizeBytes;
  
  // EXIF metadata - loaded lazily when photo is displayed
  // null = not yet loaded, use _exifLoaded to check if loading was attempted
  bool _exifLoaded = false;
  DateTime? _captureDate;
  double? _latitude;
  double? _longitude;
  
  // Runtime properties (not persisted)
  double weight = 0;
  DateTime? lastShown;
  int displayCount = 0;

  PhotoEntry({
    required this.file,
    required this.date,
    required this.sizeBytes,
  });

  /// Returns true if EXIF data has been loaded (or attempted to load)
  bool get exifLoaded => _exifLoaded;
  
  /// Original capture date from EXIF (DateTimeOriginal)
  DateTime? get captureDate => _captureDate;
  
  /// GPS latitude
  double? get latitude => _latitude;
  
  /// GPS longitude  
  double? get longitude => _longitude;

  /// Returns true if GPS coordinates are available
  bool get hasLocation => _latitude != null && _longitude != null;
  
  /// Returns true if EXIF capture date is available
  bool get hasCaptureDate => _captureDate != null;
  
  /// Set EXIF metadata after lazy loading
  void setExifMetadata({DateTime? captureDate, double? latitude, double? longitude}) {
    _exifLoaded = true;
    _captureDate = captureDate;
    _latitude = latitude;
    _longitude = longitude;
  }

  @override
  String toString() => 'PhotoEntry(path: ${file.path}, date: $date, captureDate: $_captureDate, location: ${hasLocation ? "($_latitude, $_longitude)" : "none"})';
}
