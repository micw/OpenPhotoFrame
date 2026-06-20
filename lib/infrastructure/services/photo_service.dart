import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../domain/interfaces/config_provider.dart';
import '../../domain/interfaces/playlist_strategy.dart';
import '../../domain/interfaces/sync_provider.dart';
import '../../domain/interfaces/storage_provider.dart';
import '../../domain/interfaces/photo_repository.dart';
import '../../domain/models/photo_entry.dart';

/// Factory function type that creates a SyncProvider from current config
typedef SyncProviderFactory = SyncProvider Function();

enum SyncStatusKind {
  success,
  cancelled,
  error,
}

class SyncStatus {
  const SyncStatus.success()
    : kind = SyncStatusKind.success,
      error = null;

  const SyncStatus.cancelled()
    : kind = SyncStatusKind.cancelled,
      error = null;

  const SyncStatus.error(this.error) : kind = SyncStatusKind.error;

  final SyncStatusKind kind;
  final Object? error;
}

class PhotoService extends ChangeNotifier {
  final SyncProviderFactory _syncProviderFactory;
  final PlaylistStrategy _playlistStrategy;
  final PhotoRepository _repository;
  final ConfigProvider _configProvider;
  final StorageProvider _storageProvider;
  final _log = Logger('PhotoService');

  bool _isInitialized = false;

  // Periodic ticker that decides (via wall-clock) when an automatic sync is due.
  Timer? _syncTimer;
  
  // Sync state management
  bool _isSyncing = false;
  bool _cancelRequested = false;
  Completer<void>? _currentSyncCompleter;
  SyncProgress? _syncProgress;
  SyncStatus? _syncStatus;
  
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
  SyncProgress? get syncProgress => _syncProgress;
  SyncStatus? get syncStatus => _syncStatus;

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

  void _updateSyncState({
    bool? isSyncing,
    SyncProgress? progress,
    bool clearProgress = false,
    SyncStatus? status,
    bool clearStatus = false,
  }) {
    var changed = false;

    if (isSyncing != null && _isSyncing != isSyncing) {
      _isSyncing = isSyncing;
      changed = true;
    }

    if (clearProgress) {
      if (_syncProgress != null) {
        _syncProgress = null;
        changed = true;
      }
    } else if (progress != null) {
      _syncProgress = progress;
      changed = true;
    }

    if (clearStatus) {
      if (_syncStatus != null) {
        _syncStatus = null;
        changed = true;
      }
    } else if (status != null && _syncStatus != status) {
      _syncStatus = status;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
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
    // Instead of one long-lived loop that sleeps for the whole interval, we tick
    // frequently (every minute) and decide via wall-clock whether a sync is due.
    //
    // Why: in-process timers (Timer AND Future.delayed) do not fire while the OS
    // has suspended the app (Android Doze / background). A single long delay can
    // therefore drift for hours or, in the worst case, never resume the loop.
    // Short ticks survive suspension far better, and the wall-clock check below
    // auto-corrects any drift after the device wakes up. A periodic Timer also
    // can't get "stuck" on a single await or die on an unhandled exception the
    // way the old while-loop could.
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      maybeSyncNow();
    });

    // Evaluate immediately on startup instead of waiting a full minute.
    maybeSyncNow();
  }

  /// Runs an automatic sync if one is due, based on the configured interval and
  /// the timestamp of the last successful sync.
  ///
  /// Safe to call at any time and from anywhere (periodic tick, app resume,
  /// etc.) — it is a no-op when auto-sync is disabled, when a sync is already
  /// running, or when the interval has not elapsed yet.
  Future<void> maybeSyncNow() async {
    final intervalMinutes = _configProvider.syncIntervalMinutes;

    // interval <= 0 => auto-sync disabled
    if (intervalMinutes <= 0) return;

    // Don't stack syncs (e.g. a manual sync from settings is in progress).
    if (_isSyncing) return;

    // Wall-clock check: only sync if enough time has actually passed since the
    // last successful sync. This makes the schedule robust against missed ticks
    // while the app was suspended.
    final lastSync = _configProvider.lastSuccessfulSync;
    if (lastSync != null) {
      final elapsed = DateTime.now().difference(lastSync);
      if (elapsed < Duration(minutes: intervalMinutes)) {
        return; // not due yet
      }
    }

    try {
      await _executeSync();
    } catch (e, stackTrace) {
      _log.warning("Scheduled sync failed, will retry on next tick", e, stackTrace);
    }
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
    
    _cancelRequested = false;
    _currentSyncCompleter = Completer<void>();
    _updateSyncState(
      isSyncing: true,
      clearProgress: true,
      clearStatus: true,
    );
    
    final deleteOrphaned = _configProvider.deleteOrphanedFiles;
    
    try {
      // Create a fresh SyncProvider with current config settings
      final syncProvider = _syncProviderFactory();
      _log.info("Starting sync (delete orphaned: $deleteOrphaned)");
      await syncProvider.sync(
        deleteOrphanedFiles: deleteOrphaned,
        onProgress: (progress) {
          _updateSyncState(progress: progress);
        },
      );
      
      // Save timestamp of successful sync
      _configProvider.lastSuccessfulSync = DateTime.now();
      await _configProvider.save();
      
      _log.info("Sync completed successfully");
      _updateSyncState(status: const SyncStatus.success());
      // Repository watcher will pick up changes automatically
    } catch (e, stackTrace) {
      if (_cancelRequested) {
        _log.info("Sync was cancelled");
        _updateSyncState(status: const SyncStatus.cancelled());
      } else {
        _log.warning("Sync failed", e, stackTrace);
        _updateSyncState(status: SyncStatus.error(e));
        rethrow;
      }
    } finally {
      _cancelRequested = false;
      _currentSyncCompleter?.complete();
      _currentSyncCompleter = null;
      _updateSyncState(isSyncing: false, clearProgress: true);
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
  
  @override
  void dispose() {
    _syncTimer?.cancel();
    _directoryChangeSubscription?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
