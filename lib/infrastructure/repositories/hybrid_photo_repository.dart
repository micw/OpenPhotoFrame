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
            // Only get file stats (EXIF loaded lazily when displayed)
            final stat = await file.stat();
            newPhotos.add(PhotoEntry(
              file: file,
              date: stat.modified,  // File date for shuffle algorithm
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
      
      // Load selected album from config (persistence across restarts)
      final sourceConfig = _config.getSourceConfig('device_photos');
      _selectedAlbumId = sourceConfig['albumId'] as String?;
      _log.fine("Loaded album selection from config: $_selectedAlbumId");
      
      // Get the selected album or use all photos
      List<AssetEntity> assets;
      
      // Common filter options for all album queries
      final filterOption = FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      );
      
      if (_selectedAlbumId != null) {
        // Get specific album - must use same filterOption for proper SQL generation
        final albums = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          filterOption: filterOption,
        );
        _log.fine("Available albums: ${albums.map((a) => '${a.name}(${a.id})').join(', ')}");
        
        // Find the selected album, or null if not found
        AssetPathEntity? album;
        try {
          album = albums.firstWhere((a) => a.id == _selectedAlbumId);
          _log.fine("Found matching album: ${album.name}");
        } catch (e) {
          _log.warning("Selected album not found: $_selectedAlbumId, falling back to all photos");
          album = null;
        }
        
        if (album != null) {
          final count = await album.assetCountAsync;
          _log.fine("Album '${album.name}' has $count photos");
          if (count > 0) {
            assets = await album.getAssetListRange(start: 0, end: count);
          } else {
            // Album is empty
            _log.info("Selected album is empty");
            _photos = [];
            _photosController.add(null);
            return;
          }
        } else {
          // Album not found - fall through to get all photos
          _selectedAlbumId = null;
          assets = await _getAllPhotos();
        }
      } else {
        assets = await _getAllPhotos();
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
          // Get GPS coordinates from AssetEntity if available (fast - no file I/O)
          final latLng = await asset.latlngAsync();
          final hasLocation = latLng != null && (latLng.latitude != 0 || latLng.longitude != 0);
          
          // For MediaStore: modifiedDateTime for shuffle, createDateTime as captureDate
          final entry = PhotoEntry(
            file: file,
            date: asset.modifiedDateTime,  // File date for shuffle algorithm
            sizeBytes: asset.width * asset.height,  // Approximate size from dimensions
          );
          // Set EXIF data from MediaStore (already available, no need for lazy loading)
          entry.setExifMetadata(
            captureDate: asset.createDateTime,
            latitude: hasLocation ? latLng.latitude : null,
            longitude: hasLocation ? latLng.longitude : null,
          );
          newPhotos.add(entry);
        }
      }
      
      _photos = newPhotos;
      _log.info("Scanned ${_photos.length} photos from MediaStore.");
      _photosController.add(null);
      
    } catch (e) {
      _log.severe("Error scanning photos from MediaStore", e);
    }
  }
  
  /// Helper to get all photos from MediaStore
  Future<List<AssetEntity>> _getAllPhotos() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    
    if (albums.isEmpty) {
      _log.info("No photo albums found");
      return [];
    }
    
    // Use "Recent" or first album (contains all photos)
    final allPhotosAlbum = albums.first;
    final count = await allPhotosAlbum.assetCountAsync;
    return allPhotosAlbum.getAssetListRange(start: 0, end: count);
  }
  
  /// Set the album to scan (for Device Photos mode)
  void setSelectedAlbum(String? albumId) {
    _selectedAlbumId = albumId;
    // Store in config for persistence (including null for "all photos")
    _config.setSourceConfig('device_photos', {'albumId': albumId});
    // Trigger rescan with new album selection
    _scanMediaStore();
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
