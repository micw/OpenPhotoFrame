import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../domain/interfaces/config_provider.dart';
import '../../domain/interfaces/storage_provider.dart';

class LocalStorageProvider implements StorageProvider {
  final ConfigProvider _config;
  final _directoryChangedController = StreamController<void>.broadcast();
  
  String? _lastCustomPath;
  String? _lastActiveSourceType;
  
  LocalStorageProvider({required ConfigProvider configProvider}) 
      : _config = configProvider {
    // Listen for config changes and emit directory change events
    _config.addListener(_onConfigChanged);
    _lastCustomPath = _config.customPhotoPath;
    _lastActiveSourceType = _config.activeSourceType;
  }
  
  void _onConfigChanged() {
    final newPath = _config.customPhotoPath;
    final newSourceType = _config.activeSourceType;
    
    // Emit change if either customPhotoPath or activeSourceType changed
    if (newPath != _lastCustomPath || newSourceType != _lastActiveSourceType) {
      _lastCustomPath = newPath;
      _lastActiveSourceType = newSourceType;
      _directoryChangedController.add(null);
    }
  }
  
  @override
  bool get isReadOnly {
    // Read-only if custom path is set (local folder mode)
    // Nextcloud sync uses internal app folder (read-write)
    return _config.customPhotoPath != null && _config.customPhotoPath!.isNotEmpty;
  }
  
  @override
  Stream<void> get onDirectoryChanged => _directoryChangedController.stream;

  @override
  Future<Directory> getPhotoDirectory() async {
    // If custom path is set, use it (read-only external folder)
    final customPath = _config.customPhotoPath;
    if (customPath != null && customPath.isNotEmpty) {
      return Directory(customPath);
    }
    
    // Otherwise, use internal app folder (read-write for sync)
    return _getDefaultDirectory();
  }
  
  Future<Directory> _getDefaultDirectory() async {
    Directory? baseDir;
    String subDirName = 'photos'; // Default for Android/Sandbox

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // On Desktop, use a distinct folder name in Documents
      baseDir = await getApplicationDocumentsDirectory();
      subDirName = 'OpenPhotoFrame';
    } else if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory();
    }
    
    baseDir ??= await getApplicationDocumentsDirectory();
    
    final dir = Directory('${baseDir.path}/$subDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
  
  void dispose() {
    _config.removeListener(_onConfigChanged);
    _directoryChangedController.close();
  }
}
