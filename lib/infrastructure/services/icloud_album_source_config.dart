/// A single iCloud shared-album link with its extracted share token.
///
/// Handles both URL styles:
///   https://www.icloud.com/sharedalbum/#TOKEN  (token in fragment)
///   https://www.icloud.com/photos/TOKEN        (token in last path segment)
///
/// [url] may include an inline comment separated by whitespace + `#`, e.g.:
///   https://www.icloud.com/photos/TOKEN  # Family holiday
/// The comment is stripped before URL parsing but preserved in storage and UI.
class IcloudAlbumLink {
  final String url;

  const IcloudAlbumLink(this.url);

  // Strips trailing " # comment" while preserving "#TOKEN" fragments.
  // A comment `#` is always preceded by whitespace; a URL fragment `#` is not.
  String get _cleanUrl => url.replaceFirst(RegExp(r'\s+#.*$'), '').trim();

  String get token {
    final uri = Uri.tryParse(_cleanUrl);
    if (uri == null) return '';
    if (uri.fragment.isNotEmpty) return uri.fragment;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? '' : segments.last;
  }

  bool get isValid {
    final uri = Uri.tryParse(_cleanUrl);
    if (uri == null) return false;
    return uri.host.contains('icloud.com') && token.isNotEmpty;
  }
}

/// Configuration for the iCloud shared-album source.
///
/// Supports multiple shared albums: users enter one link per line.
/// Stored on disk either as the legacy single-`album_url` map (which is still
/// read and written for a single album, for backward compatibility) or as a
/// `album_urls` list.
class ICloudAlbumSourceConfig {
  /// All configured album links (empty entries already filtered out).
  final List<IcloudAlbumLink> albums;

  const ICloudAlbumSourceConfig({List<IcloudAlbumLink>? albums})
      : albums = albums ?? const <IcloudAlbumLink>[];

  /// Parses multi-line text (one album link per line) into links.
  /// Lines starting with `#` are treated as full-line comments and skipped.
  /// Inline comments (` # note`) are preserved in the stored URL and stripped
  /// only when the URL is actually parsed.
  static List<IcloudAlbumLink> parseLinks(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('#'))
        .map(IcloudAlbumLink.new)
        .toList();
  }

  /// Convenience constructor from raw multi-line link text.
  factory ICloudAlbumSourceConfig.fromLinkText(String text) {
    return ICloudAlbumSourceConfig(albums: parseLinks(text));
  }

  /// The primary album URL (first entry, or empty). Only used to keep the
  /// legacy single-URL on-disk format stable; new code should use [albums].
  String get albumUrl => albums.isEmpty ? '' : albums.first.url.trim();

  /// All album links, one per line (for UI text fields).
  String get linksText => albums.map((a) => a.url.trim()).join('\n');

  String get token {
    final first = albums.where((a) => a.token.isNotEmpty).toList();
    return first.isEmpty ? '' : first.first.token;
  }

  /// True if [albums] is non-empty and every link is a valid icloud.com
  /// shared-album URL. This is the same strict check the config had before
  /// multi-album support; it must be true before the source is activated
  /// (e.g. by [ICloudAlbumSyncService]) — a non-empty list of garbage
  /// links is NOT valid.
  bool get isValid => albums.isNotEmpty && albums.every((a) => a.isValid);

  /// Non-empty links that are not valid icloud.com shared-album URLs.
  List<String> get invalidLinks =>
      albums.where((a) => !a.isValid).map((a) => a.url.trim()).toList();

  factory ICloudAlbumSourceConfig.fromMap(Map<String, dynamic> config) {
    final links = <String>[];

    // New format: list of URLs.
    final urls = config['album_urls'];
    if (urls is List) {
      for (final u in urls) {
        links.add(u.toString().trim());
      }
    }

    // Legacy (and current single-album) format: single URL string.
    final single = config['album_url'];
    if (single is String) {
      final trimmed = single.trim();
      if (trimmed.isNotEmpty) links.add(trimmed);
    } else if (single is List) {
      // Be defensive about a list stored under the old key.
      for (final u in single) {
        links.add(u.toString().trim());
      }
    }

    // Deduplicate, preserving order.
    final seen = <String>{};
    final cleaned = <String>[];
    for (final link in links) {
      if (link.isNotEmpty && seen.add(link)) cleaned.add(link);
    }

    return ICloudAlbumSourceConfig(
      albums: cleaned.map(IcloudAlbumLink.new).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    final urls = albums.map((a) => a.url.trim()).toList();
    if (urls.length <= 1) {
      // Keep the legacy format on disk for a single album so existing
      // consumers and older code keep working.
      return {'album_url': urls.isEmpty ? '' : urls.first};
    }
    return {'album_urls': urls};
  }
}
