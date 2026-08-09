class ICloudAlbumSourceConfig {
  final String albumUrl;

  const ICloudAlbumSourceConfig({this.albumUrl = ''});

  /// Extracts the share token.
  /// Handles both URL styles:
  ///   https://www.icloud.com/sharedalbum/#TOKEN  (token in fragment)
  ///   https://www.icloud.com/photos/TOKEN        (token in last path segment)
  String get token {
    final trimmed = albumUrl.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return '';
    if (uri.fragment.isNotEmpty) return uri.fragment;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? '' : segments.last;
  }

  bool get isValid {
    if (albumUrl.trim().isEmpty) return false;
    final uri = Uri.tryParse(albumUrl.trim());
    if (uri == null) return false;
    return uri.host.contains('icloud.com') && token.isNotEmpty;
  }

  factory ICloudAlbumSourceConfig.fromMap(Map<String, dynamic> config) {
    return ICloudAlbumSourceConfig(
      albumUrl: (config['album_url'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() => {'album_url': albumUrl.trim()};
}
