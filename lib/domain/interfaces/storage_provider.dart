import 'dart:io';

abstract class StorageProvider {
  /// Returns the directory where photos should be stored/read from.
  Future<Directory> getPhotoDirectory();
  
  /// Returns true if the photo directory is read-only (external user folder).
  /// When true, sync operations should be skipped.
  bool get isReadOnly;
  
  /// Stream that emits when the photo directory changes.
  /// Listeners should reinitialize their state when this fires.
  Stream<void> get onDirectoryChanged;
}
