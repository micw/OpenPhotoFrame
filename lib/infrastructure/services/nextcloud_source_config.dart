enum NextcloudFolderSyncMode {
  all,
  selectedFolders,
}

class NextcloudSourceConfig {
  const NextcloudSourceConfig({
    this.url = '',
    this.folderSyncMode = NextcloudFolderSyncMode.all,
    this.selectedFolders = const <String>[],
  });

  final String url;
  final NextcloudFolderSyncMode folderSyncMode;
  final List<String> selectedFolders;

  factory NextcloudSourceConfig.fromMap(Map<String, dynamic> config) {
    final rawFolders = config['selected_folders'];

    return NextcloudSourceConfig(
      url: (config['url'] as String? ?? '').trim(),
      folderSyncMode: (config['folder_sync_mode'] as String?) == 'selected'
          ? NextcloudFolderSyncMode.selectedFolders
          : NextcloudFolderSyncMode.all,
      selectedFolders: switch (rawFolders) {
        List<dynamic>() => rawFolders.map((entry) => '$entry').toList(),
        _ => const <String>[],
      },
    );
  }

  bool get syncAllFolders => folderSyncMode == NextcloudFolderSyncMode.all;

  Set<String> get normalizedSelectedFolders {
    final normalizedFolders = selectedFolders
        .map(normalizeFolderPath)
        .toSet();
    final includesRoot = selectedFolders.any(
      (folder) => normalizeFolderPath(folder).isEmpty,
    );
    if (!includesRoot) {
      normalizedFolders.remove('');
    }
    return normalizedFolders;
  }

  bool includesDirectory(String directoryPath) {
    if (syncAllFolders) {
      return true;
    }

    return normalizedSelectedFolders.contains(normalizeFolderPath(directoryPath));
  }

  bool includesRelativeFile(String relativePath) {
    return includesDirectory(parentDirectoryOf(relativePath));
  }

  NextcloudSourceConfig copyWith({
    String? url,
    NextcloudFolderSyncMode? folderSyncMode,
    List<String>? selectedFolders,
  }) {
    return NextcloudSourceConfig(
      url: url ?? this.url,
      folderSyncMode: folderSyncMode ?? this.folderSyncMode,
      selectedFolders: selectedFolders ?? this.selectedFolders,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'folder_sync_mode': switch (folderSyncMode) {
        NextcloudFolderSyncMode.all => 'all',
        NextcloudFolderSyncMode.selectedFolders => 'selected',
      },
      'selected_folders': normalizedSelectedFolders.toList()..sort(),
    };
  }

  static String normalizeFolderPath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    if (normalized.isEmpty || normalized == '/') {
      return '';
    }

    while (normalized.contains('//')) {
      normalized = normalized.replaceAll('//', '/');
    }

    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String parentDirectoryOf(String relativePath) {
    final normalized = normalizeFolderPath(relativePath);
    final separatorIndex = normalized.lastIndexOf('/');
    if (separatorIndex == -1) {
      return '';
    }
    return normalized.substring(0, separatorIndex);
  }
}