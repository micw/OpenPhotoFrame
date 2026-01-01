import 'dart:async';
import 'package:logging/logging.dart';

import '../../domain/interfaces/config_provider.dart';
import '../../domain/interfaces/playlist_strategy.dart';
import '../../domain/interfaces/sync_provider.dart';
import '../../domain/interfaces/storage_provider.dart';
import '../../domain/interfaces/photo_repository.dart';
import '../../domain/models/photo_entry.dart';

/// Factory function type that creates a SyncProvider from current config
typedef SyncProviderFactory = SyncProvider Function();

class PhotoService {
  final SyncProviderFactory _syncProviderFactory;
  final PlaylistStrategy _playlistStrategy;
  final PhotoRepository _repository;
  final ConfigProvider _configProvider;
  final StorageProvider _storageProvider;
  final _log = Logger('PhotoService');

  bool _isInitialized = false;
  bool _syncLoopRunning = false;
  
  // Sync state management
  bool _isSyncing = false;
  bool _cancelRequested = false;
  Completer<void>? _currentSyncCompleter;
  
  // History management
  final List<PhotoEntry> _history = [];
  int _historyIndex = -1;
  
  // Directory change subscription
  StreamSubscription? _directoryChangeSubscription;

  PhotoService({
    required SyncProviderFactory syncProviderFactory,
    required PlaylistStrategy playlistStrategy,
    required PhotoRepository repository,
    required ConfigProvider configProvider,
    required StorageProvider storageProvider,
  })  : _syncProviderFactory = syncProviderFactory,
        _playlistStrategy = playlistStrategy,
        _repository = repository,
        _configProvider = configProvider,
        _storageProvider = storageProvider;

  Stream<void> get onPhotosChanged => _repository.onPhotosChanged;
  
  /// Returns true if a sync is currently in progress
  bool get isSyncing => _isSyncing;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _log.info("Initializing PhotoService...");
    
    // 1. Initialize Repository (Load local photos)
    await _repository.initialize();
    
    // 2. Listen for directory changes
    _directoryChangeSubscription = _storageProvider.onDirectoryChanged.listen((_) {
      _onDirectoryChanged();
    });
    
    // 3. Start Sync in Background
    _startBackgroundSync();
    
    _isInitialized = true;
  }
  
  /// Called when the photo directory changes (e.g., user selected different folder)
  Future<void> _onDirectoryChanged() async {
    _log.info("Photo directory changed, reinitializing...");
    
    // 1. Reset slideshow state (history is no longer valid)
    _resetState();
    
    // 2. Reinitialize repository with new directory
    await _repository.reinitialize();
    
    _log.info("Directory change complete");
  }
  
  /// Resets slideshow state (history, current position)
  void _resetState() {
    _history.clear();
    _historyIndex = -1;
    _log.info("Slideshow state reset");
  }

  void _startBackgroundSync() {
    if (_syncLoopRunning) return;
    _syncLoopRunning = true;
    
    Future.doWhile(() async {
      // Read current config values (they might change via settings)
      final intervalMinutes = _configProvider.syncIntervalMinutes;
      
      // If interval is 0, sync is disabled
      if (intervalMinutes <= 0) {
        _log.info("Auto-sync is disabled. Checking again in 1 minute...");
        await Future.delayed(const Duration(minutes: 1));
        return true;
      }
      
      // Skip if a sync is already running (e.g., manual sync from settings)
      if (_isSyncing) {
        _log.info("Sync already in progress, skipping scheduled sync");
        await Future.delayed(Duration(minutes: intervalMinutes));
        return true;
      }
      
      await _executeSync();
      
      // Wait for configured interval before next sync
      await Future.delayed(Duration(minutes: intervalMinutes));
      return true;
    });
  }
  
  /// Triggers a manual sync. If a sync is already running, it will be cancelled first.
  /// Returns a Future that completes when the new sync is done.
  Future<void> triggerSync() async {
    _log.info("Manual sync triggered");
    
    // If a sync is already running, request cancellation and wait for it
    if (_isSyncing) {
      _log.info("Cancelling current sync...");
      _cancelRequested = true;
      
      // Wait for the current sync to finish
      if (_currentSyncCompleter != null) {
        await _currentSyncCompleter!.future;
      }
    }
    
    // Now execute the new sync
    await _executeSync();
  }
  
  /// Internal method that actually executes the sync
  Future<void> _executeSync() async {
    // Skip sync if storage is read-only (external user folder)
    if (_storageProvider.isReadOnly) {
      _log.info("Storage is read-only (local folder mode), skipping sync");
      return;
    }
    
    if (_isSyncing) return; // Double-check
    
    _isSyncing = true;
    _cancelRequested = false;
    _currentSyncCompleter = Completer<void>();
    
    final deleteOrphaned = _configProvider.deleteOrphanedFiles;
    
    try {
      // Create a fresh SyncProvider with current config settings
      final syncProvider = _syncProviderFactory();
      _log.info("Starting sync (delete orphaned: $deleteOrphaned)");
      await syncProvider.sync(deleteOrphanedFiles: deleteOrphaned);
      
      // Save timestamp of successful sync
      _configProvider.lastSuccessfulSync = DateTime.now();
      await _configProvider.save();
      
      _log.info("Sync completed successfully");
      // Repository watcher will pick up changes automatically
    } catch (e) {
      if (_cancelRequested) {
        _log.info("Sync was cancelled");
      } else {
        _log.warning("Sync failed", e);
        rethrow;
      }
    } finally {
      _isSyncing = false;
      _cancelRequested = false;
      _currentSyncCompleter?.complete();
      _currentSyncCompleter = null;
    }
  }

  PhotoEntry? nextPhoto() {
    // 1. If we are in the past, move forward in history
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      return _history[_historyIndex];
    }

    // 2. Otherwise, generate new photo
    final photos = _repository.photos;
    final photo = _playlistStrategy.nextPhoto(photos);
    
    if (photo != null) {
      photo.lastShown = DateTime.now();
      _history.add(photo);
      _historyIndex++;
      
      // Limit history size to prevent memory leaks (keep last 50)
      if (_history.length > 50) {
        _history.removeAt(0);
        _historyIndex--;
      }
    }
    return photo;
  }

  PhotoEntry? previousPhoto() {
    if (_historyIndex > 0) {
      _historyIndex--;
      return _history[_historyIndex];
    }
    // If we are at the start, stay there
    return _history.isNotEmpty ? _history[_historyIndex] : null;
  }
  
  /// Check if a photo is still in the current photo list
  bool containsPhoto(PhotoEntry photo) {
    return _repository.photos.any((p) => p.file.path == photo.file.path);
  }
  
  void dispose() {
    _directoryChangeSubscription?.cancel();
    _repository.dispose();
  }
}
