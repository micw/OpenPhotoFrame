import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../domain/interfaces/photo_repository.dart';
import '../../domain/interfaces/metadata_provider.dart';
import '../../domain/interfaces/storage_provider.dart';
import '../../domain/interfaces/config_provider.dart';
import '../../domain/models/photo_entry.dart';

/// A PhotoRepository that can switch between FileSystem and MediaStore sources.
/// 
/// - For 'app_folder' and 'local_folder': Uses FileSystem scanning
/// - For 'device_photos': Uses Android MediaStore API
class HybridPhotoRepository implements PhotoRepository {
  final StorageProvider _storageProvider;
  final MetadataProvider _metadataProvider;
  final ConfigProvider _config;
  final _log = Logger('HybridPhotoRepository');

  List<PhotoEntry> _photos = [];
  final _photosController = StreamController<void>.broadcast();
  
  // FileSystem mode resources
  StreamSubscription? _dirWatcher;
  
  // MediaStore mode resources
  String? _selectedAlbumId;
  bool _mediaStoreListenerRegistered = false;

  HybridPhotoRepository({
    required StorageProvider storageProvider,
    required MetadataProvider metadataProvider,
    required ConfigProvider configProvider,
  })  : _storageProvider = storageProvider,
        _metadataProvider = metadataProvider,
        _config = configProvider;

  @override
  List<PhotoEntry> get photos => List.unmodifiable(_photos);

  @override
  Stream<void> get onPhotosChanged => _photosController.stream;
  
  bool get _useMediaStore => _config.activeSourceType == 'device_photos';

  @override
  Future<void> initialize() async {
    _log.info("Initializing HybridPhotoRepository...");
    await _scan();
  }
  
  @override
  Future<void> reinitialize() async {
    _log.info("Reinitializing HybridPhotoRepository...");
    
    // 1. Clean up ALL old resources
    await _cleanup();
    
    // 2. Clear photo list
    _photos = [];
    
    // 3. Scan with new configuration
    await _scan();
  }
  
  /// Clean up all resources (watchers, listeners)
  Future<void> _cleanup() async {
    // Stop FileSystem watcher
    await _dirWatcher?.cancel();
    _dirWatcher = null;
    
    // Remove MediaStore listener
    if (_mediaStoreListenerRegistered) {
      PhotoManager.removeChangeCallback(_onMediaStoreChanged);
      _mediaStoreListenerRegistered = false;
    }
  }
  
  /// Scan photos based on current configuration
  Future<void> _scan() async {
    if (_useMediaStore) {
      await _scanMediaStore();
      _setupMediaStoreListener();
    } else {
      await _scanFileSystem();
      _setupFileWatcher();
    }
  }

  // ============================================================
  // FileSystem Mode (App Folder / Local Folder)
  // ============================================================

  void _setupFileWatcher() async {
    try {
      final localDir = await _storageProvider.getPhotoDirectory();
      _dirWatcher = localDir.watch(events: FileSystemEvent.all).listen((event) {
        bool shouldScan = false;
        
        if (event is FileSystemMoveEvent) {
          if (event.destination != null && !_isPartFile(event.destination!)) {
            shouldScan = true;
          }
          if (!_isPartFile(event.path)) {
            shouldScan = true;
          }
        } else {
          if (!_isPartFile(event.path)) {
            shouldScan = true;
          }
        }

        if (shouldScan) {
          _log.info("File change detected: ${event.type} ${event.path}");
          _scanFileSystem();
        }
      });
    } catch (e) {
      _log.warning("File watching not supported or failed", e);
    }
  }

  bool _isPartFile(String path) => path.endsWith('.part');

  Future<void> _scanFileSystem() async {
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
          // Preserve existing PhotoEntry instances to maintain runtime state
          final existingIndex = _photos.indexWhere((p) => p.file.path == file.path);

          if (existingIndex != -1) {
            newPhotos.add(_photos[existingIndex]);
          } else {
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
      _log.info("Scanned ${_photos.length} photos from filesystem.");
      _photosController.add(null);
      
    } catch (e) {
      _log.severe("Error scanning photos from filesystem", e);
    }
  }

  // ============================================================
  // MediaStore Mode (Device Photos)
  // ============================================================
  
  void _setupMediaStoreListener() {
    if (!_mediaStoreListenerRegistered) {
      PhotoManager.addChangeCallback(_onMediaStoreChanged);
      _mediaStoreListenerRegistered = true;
    }
  }
  
  void _onMediaStoreChanged(dynamic call) {
    _log.info("MediaStore change detected");
    _scanMediaStore();
  }
  
  Future<void> _scanMediaStore() async {
    try {
      // Request permission
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        _log.warning("Photo permission not granted");
        _photos = [];
        _photosController.add(null);
        return;
      }
      
      // Get the selected album or use all photos
      List<AssetEntity> assets;
      
      if (_selectedAlbumId != null) {
        // Get specific album
        final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
        final album = albums.firstWhere(
          (a) => a.id == _selectedAlbumId,
          orElse: () => albums.first,
        );
        final count = await album.assetCountAsync;
        assets = await album.getAssetListRange(start: 0, end: count);
      } else {
        // Get all photos
        final albums = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          filterOption: FilterOptionGroup(
            imageOption: const FilterOption(
              sizeConstraint: SizeConstraint(ignoreSize: true),
            ),
          ),
        );
        
        if (albums.isEmpty) {
          _log.info("No photo albums found");
          _photos = [];
          _photosController.add(null);
          return;
        }
        
        // Use "Recent" or first album (contains all photos)
        final allPhotosAlbum = albums.first;
        final count = await allPhotosAlbum.assetCountAsync;
        assets = await allPhotosAlbum.getAssetListRange(start: 0, end: count);
      }
      
      _log.fine("Found ${assets.length} assets in MediaStore");
      
      // Convert AssetEntity to PhotoEntry
      final newPhotos = <PhotoEntry>[];
      
      for (final asset in assets) {
        // Get the actual file
        final file = await asset.file;
        if (file == null) continue;
        
        // Preserve existing PhotoEntry instances
        final existingIndex = _photos.indexWhere((p) => p.file.path == file.path);
        
        if (existingIndex != -1) {
          newPhotos.add(_photos[existingIndex]);
        } else {
          // sizeBytes: use 0 as we can't easily get file size from AssetEntity
          newPhotos.add(PhotoEntry(
            file: file,
            date: asset.createDateTime,
            sizeBytes: 0,
          ));
        }
      }
      
      _photos = newPhotos;
      _log.info("Scanned ${_photos.length} photos from MediaStore.");
      _photosController.add(null);
      
    } catch (e) {
      _log.severe("Error scanning photos from MediaStore", e);
    }
  }
  
  /// Set the album to scan (for Device Photos mode)
  void setSelectedAlbum(String? albumId) {
    _selectedAlbumId = albumId;
    // Store in config for persistence
    if (albumId != null) {
      _config.setSourceConfig('device_photos', {'albumId': albumId});
    }
  }
  
  /// Get available albums (for UI picker)
  Future<List<AssetPathEntity>> getAvailableAlbums() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) return [];
    
    return PhotoManager.getAssetPathList(type: RequestType.image);
  }

  // ============================================================
  // Common
  // ============================================================

  bool _isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') || 
           lower.endsWith('.jpeg') || 
           lower.endsWith('.png') || 
           lower.endsWith('.webp');
  }

  @override
  void dispose() {
    _cleanup();
    _photosController.close();
  }
}
