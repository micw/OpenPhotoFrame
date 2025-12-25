import '../models/photo_entry.dart';

abstract class PhotoRepository {
  /// The current list of available photos.
  List<PhotoEntry> get photos;

  /// Stream that emits an event whenever the photo list changes.
  Stream<void> get onPhotosChanged;

  /// Initializes the repository (e.g. starts scanning/watching).
  Future<void> initialize();
  
  /// Reinitializes the repository (e.g. when photo directory changes).
  /// Clears current state and rescans from the new directory.
  Future<void> reinitialize();

  /// Cleans up resources (e.g. file watchers).
  void dispose();
}
