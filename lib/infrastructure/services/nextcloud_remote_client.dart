import 'package:webdav_client/webdav_client.dart' as webdav;

class NextcloudPublicShare {
  const NextcloudPublicShare({
    required this.webDavUrl,
    required this.user,
    this.password = '',
  });

  final String webDavUrl;
  final String user;
  final String password;

  factory NextcloudPublicShare.fromPublicLink(String link) {
    if (link.isEmpty) {
      throw ArgumentError('Nextcloud public link cannot be empty');
    }

    final uri = Uri.parse(link);
    if (uri.pathSegments.isEmpty) {
      throw ArgumentError('Invalid Nextcloud public link: no path segments');
    }

    final token = uri.pathSegments.last;
    final baseUrl = '${uri.scheme}://${uri.host}/public.php/webdav';

    return NextcloudPublicShare(
      webDavUrl: baseUrl,
      user: token,
    );
  }
}

class NextcloudRemoteEntry {
  const NextcloudRemoteEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.modifiedAt,
    this.sizeBytes,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final DateTime? modifiedAt;
  final int? sizeBytes;
}

abstract class NextcloudRemoteClient {
  Future<List<NextcloudRemoteEntry>> readDir(String path);

  Future<void> downloadFile(String remotePath, String localPath);
}

typedef NextcloudRemoteClientFactory = NextcloudRemoteClient Function({
  required String webDavUrl,
  required String user,
  required String password,
});

NextcloudRemoteClient createWebDavNextcloudRemoteClient({
  required String webDavUrl,
  required String user,
  required String password,
}) {
  return WebDavNextcloudRemoteClient(
    webDavUrl: webDavUrl,
    user: user,
    password: password,
  );
}

class WebDavNextcloudRemoteClient implements NextcloudRemoteClient {
  WebDavNextcloudRemoteClient({
    required String webDavUrl,
    required String user,
    required String password,
  }) : _client = webdav.newClient(
          webDavUrl,
          user: user,
          password: password,
          debug: false,
        );

  final webdav.Client _client;

  @override
  Future<List<NextcloudRemoteEntry>> readDir(String path) async {
    final entries = await _client.readDir(path);
    return entries
        .map(
          (entry) => NextcloudRemoteEntry(
            path: entry.path ?? '',
            name: entry.name ?? '',
            isDirectory: entry.isDir == true,
            modifiedAt: entry.mTime,
            sizeBytes: entry.size,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) {
    return _client.read2File(remotePath, localPath);
  }
}