import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

import '../../domain/interfaces/photo_repository.dart';
import '../../domain/interfaces/metadata_provider.dart';
import '../../domain/interfaces/storage_provider.dart';
import '../../domain/models/photo_entry.dart';

class FileSystemPhotoRepository implements PhotoRepository {
  final StorageProvider _storageProvider;
  final MetadataProvider _metadataProvider;
  final _log = Logger('FileSystemPhotoRepository');

  List<PhotoEntry> _photos = [];
  final _photosController = StreamController<void>.broadcast();
  StreamSubscription? _dirWatcher;

  FileSystemPhotoRepository({
    required StorageProvider storageProvider,
    required MetadataProvider metadataProvider,
  })  : _storageProvider = storageProvider,
        _metadataProvider = metadataProvider;

  @override
  List<PhotoEntry> get photos => List.unmodifiable(_photos);

  @override
  Stream<void> get onPhotosChanged => _photosController.stream;

  @override
  Future<void> initialize() async {
    _log.info("Initializing FileSystemPhotoRepository...");
    await _scanLocalPhotos();
    _setupFileWatcher();
  }
  
  @override
  Future<void> reinitialize() async {
    _log.info("Reinitializing FileSystemPhotoRepository (directory changed)...");
    
    // 1. Stop existing file watcher
    await _dirWatcher?.cancel();
    _dirWatcher = null;
    
    // 2. Clear current photos (don't notify yet - wait for scan to complete)
    _photos = [];
    
    // 3. Scan new directory and setup new watcher
    // _scanLocalPhotos will notify listeners after scan is complete
    await _scanLocalPhotos();
    _setupFileWatcher();
  }

  void _setupFileWatcher() async {
    try {
      final localDir = await _storageProvider.getPhotoDirectory();
      _dirWatcher = localDir.watch(events: FileSystemEvent.all).listen((event) {
        bool shouldScan = false;
        
        if (event is FileSystemMoveEvent) {
          // If we move TO a valid image file (e.g. .part -> .jpg)
          if (event.destination != null && !_isPartFile(event.destination!)) {
            shouldScan = true;
          }
          // If we move FROM a valid image file (e.g. .jpg -> .trash)
          if (!_isPartFile(event.path)) {
            shouldScan = true;
          }
        } else {
          // Create, Modify, Delete
          if (!_isPartFile(event.path)) {
            shouldScan = true;
          }
        }

        if (shouldScan) {
          _log.info("File change detected: ${event.type} ${event.path}");
          _scanLocalPhotos();
        }
      });
    } catch (e) {
      _log.warning("File watching not supported or failed", e);
    }
  }

  bool _isPartFile(String path) => path.endsWith('.part');

  Future<void> _scanLocalPhotos() async {
    try {
      final localDir = await _storageProvider.getPhotoDirectory();
      _log.fine("Scanning photos in: ${localDir.path}");
      
      if (!await localDir.exists()) {
        _log.info("Photo directory does not exist yet.");
        _photos = [];
        _photosController.add(null);
        return;
      }

      final files = localDir.listSync().whereType<File>();
      final newPhotos = <PhotoEntry>[];

      for (var file in files) {
        if (_isImage(file.path) && !file.path.endsWith('.part')) {
          // Check if we already have this file in memory to preserve runtime state
          // (lastShown, weight) across rescans
          final existingIndex = _photos.indexWhere((p) => p.file.path == file.path);

          if (existingIndex != -1) {
            // File already exists - preserve the existing PhotoEntry instance
            // to maintain runtime state (lastShown, weight)
            newPhotos.add(_photos[existingIndex]);
          } else {
            // New file - load metadata and create new entry
            final date = await _metadataProvider.getDate(file);
            final stat = await file.stat();
            newPhotos.add(PhotoEntry(
              file: file,
              date: date,
              sizeBytes: stat.size,
            ));
          }
        }
      }
      
      _photos = newPhotos;
      _log.info("Scanned ${_photos.length} photos.");
      _photosController.add(null); // Notify listeners
      
    } catch (e) {
      _log.severe("Error scanning photos", e);
    }
  }

  bool _isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') || 
           lower.endsWith('.jpeg') || 
           lower.endsWith('.png') || 
           lower.endsWith('.webp');
  }

  @override
  void dispose() {
    _dirWatcher?.cancel();
    _photosController.close();
  }
}
