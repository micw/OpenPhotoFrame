import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';

import 'native_screen_control_service.dart';

import 'package:logging/logging.dart';

import '../../domain/interfaces/config_provider.dart';
import '../../domain/interfaces/storage_provider.dart';
import 'android_runtime_settings_sync.dart';
import 'icloud_album_source_config.dart';
import 'photo_service.dart';

class WebServerService {
  static const int port = 8080;

  WebServerService({
    required ConfigProvider configProvider,
    required PhotoService photoService,
    required StorageProvider storageProvider,
  })  : _config = configProvider,
        _photoService = photoService,
        _storageProvider = storageProvider;

  final ConfigProvider _config;
  final PhotoService _photoService;
  final StorageProvider _storageProvider;
  final _log = Logger('WebServerService');

  HttpServer? _server;
  String? _lanIp;
  StreamSubscription<LogRecord>? _logSub;
  final DateTime _startTime = DateTime.now();

  static const int _maxLogEntries = 500;
  final List<Map<String, String>> _logBuffer = [];

  Set<String> _runningPackages = {};
  DateTime? _lastProcessScan;
  bool _processScanInFlight = false;

  String? get lanIp => _lanIp;
  String? get serverUrl => _lanIp != null ? 'http://$_lanIp:$port' : null;

  Future<void> start() async {
    // Capture all app log records into a rolling buffer
    _logSub = Logger.root.onRecord.listen((r) {
      final entry = <String, String>{
        't': r.time.toIso8601String(),
        'l': r.level.name,
        'm': r.message,
      };
      if (r.error != null) entry['e'] = r.error.toString();
      _logBuffer.add(entry);
      if (_logBuffer.length > _maxLogEntries) _logBuffer.removeAt(0);
    });

    try {
      _lanIp = await _findLanIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _log.info('Web settings server on port $port (LAN: $_lanIp)');
      _handleRequests();
    } catch (e) {
      _log.severe('Failed to start web server on port $port: $e');
    }
  }

  Future<void> stop() async {
    await _logSub?.cancel();
    _logSub = null;
    await _server?.close(force: true);
    _server = null;
  }

  void _handleRequests() {
    _server?.listen((HttpRequest request) async {
      try {
        await _route(request);
      } catch (e, st) {
        _log.warning(
            'Error handling ${request.method} ${request.uri.path}', e, st);
        _sendError(request, 500, 'Internal server error');
      }
    });
  }

  Future<void> _route(HttpRequest request) async {
    final method = request.method;
    final path = request.uri.path;

    request.response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..add('Access-Control-Allow-Headers', 'Content-Type');

    if (method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }

    // /metrics stays open so Prometheus keeps scraping without credentials. It
    // exposes only counters and gauges — no album URLs, tokens or log lines.
    // Everything else, including /api/config and /api/log, requires the password
    // when one is set.
    if (path != '/metrics' && !_isAuthorized(request)) {
      _sendUnauthorized(request);
      return;
    }

    if (method == 'GET' && path == '/') {
      _sendHtml(request, _settingsPage);
    } else if (method == 'GET' && path == '/api/config') {
      _sendJson(request, _buildConfigMap());
    } else if (method == 'POST' && path == '/api/config') {
      await _handleSaveConfig(request);
    } else if (method == 'GET' && path == '/api/status') {
      _sendJson(request, _buildStatusMap());
    } else if (method == 'POST' && path == '/api/sync') {
      _handleTriggerSync(request);
    } else if (method == 'POST' && path == '/api/photos') {
      await _handleUploadPhoto(request);
    } else if (method == 'GET' && path == '/api/log') {
      _sendJson(request, {'entries': List<Map<String, String>>.from(_logBuffer.reversed)});
    } else if (method == 'GET' && path == '/metrics') {
      await _serveMetrics(request);
    } else {
      _sendError(request, 404, 'Not found');
    }
  }

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// HTTP Basic auth against [ConfigProvider.webUiPassword]. Any username is
  /// accepted — only the password is checked. An empty configured password
  /// disables authentication entirely.
  bool _isAuthorized(HttpRequest request) {
    final expected = _config.webUiPassword;
    if (expected.isEmpty) return true;

    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.toLowerCase().startsWith('basic ')) return false;

    String decoded;
    try {
      decoded = utf8.decode(base64.decode(header.substring(6).trim()));
    } catch (_) {
      return false;
    }
    final sep = decoded.indexOf(':');
    if (sep < 0) return false;

    return _constantTimeEquals(decoded.substring(sep + 1), expected);
  }

  /// Compares without leaking length or position through timing. Not critical on
  /// a LAN device, but cheap.
  static bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    var diff = ab.length ^ bb.length;
    for (var i = 0; i < ab.length && i < bb.length; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }

  void _sendUnauthorized(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.unauthorized
      ..headers.set(HttpHeaders.wwwAuthenticateHeader,
          'Basic realm="OpenPhotoFrame", charset="UTF-8"')
      ..headers.contentType = ContentType.text
      ..write('Unauthorized');
    request.response.close();
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _buildConfigMap() => {
        // Source
        'active_source': _config.activeSourceType,
        'icloud_album': _config.getSourceConfig('icloud_album'),
        'nextcloud_link': _config.getSourceConfig('nextcloud_link'),
        // Slideshow
        'slide_duration_seconds': _config.slideDurationSeconds,
        'transition_duration_ms': _config.transitionDurationMs,
        'blur_borders': _config.blurBorders,
        // Sync
        'sync_interval_minutes': _config.syncIntervalMinutes,
        'sync_timeout_seconds': _config.syncTimeoutSeconds,
        'delete_orphaned_files': _config.deleteOrphanedFiles,
        // Clock
        'show_clock': _config.showClock,
        'clock_size': _config.clockSize,
        'clock_position': _config.clockPosition,
        // Photo info
        'show_photo_info': _config.showPhotoInfo,
        'photo_info_position': _config.photoInfoPosition,
        'photo_info_size': _config.photoInfoSize,
        'use_script_font': _config.useScriptFontForMetadata,
        'geocoding_enabled': _config.geocodingEnabled,
        // Schedule
        'schedule_enabled': _config.scheduleEnabled,
        'day_start_hour': _config.dayStartHour,
        'day_start_minute': _config.dayStartMinute,
        'night_start_hour': _config.nightStartHour,
        'night_start_minute': _config.nightStartMinute,
        'fri_sat_night_start_hour': _config.fridaySaturdayNightStartHour,
        'fri_sat_night_start_minute': _config.fridaySaturdayNightStartMinute,
        // Display
        'screen_orientation': _config.screenOrientation,
        'use_native_screen_off': _config.useNativeScreenOff,
        // Android
        'autostart_on_boot': _config.autostartOnBoot,
        'keep_alive_enabled': _config.keepAliveEnabled,
        'wifi_adb_enabled': _config.wifiAdbEnabled,
        'web_ui_password': _config.webUiPassword,
        'auto_update_enabled': _config.autoUpdateEnabled,
      };

  Future<void> _handleSaveConfig(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> u;
    try {
      u = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      _sendError(request, 400, 'Invalid JSON');
      return;
    }

    void setBool(String key, void Function(bool) setter) {
      if (u[key] is bool) setter(u[key] as bool);
    }

    void setInt(String key, void Function(int) setter) {
      if (u[key] is int) setter(u[key] as int);
    }

    void setString(String key, void Function(String) setter) {
      if (u[key] is String) setter(u[key] as String);
    }

    // Source
    setString('active_source', (v) => _config.activeSourceType = v);
    if (u['icloud_album'] is Map) {
      // Normalize through the config model so legacy `album_url` values and
      // multi-line lists both end up in the canonical on-disk format.
      _config.setSourceConfig('icloud_album', ICloudAlbumSourceConfig.fromMap(
          Map<String, dynamic>.from(u['icloud_album'] as Map)).toMap());
    }
    if (u['nextcloud_link'] is Map) {
      _config.setSourceConfig(
          'nextcloud_link', Map<String, dynamic>.from(u['nextcloud_link'] as Map));
    }
    // Slideshow
    setInt('slide_duration_seconds', (v) => _config.slideDurationSeconds = v);
    setInt('transition_duration_ms', (v) => _config.transitionDurationMs = v);
    setBool('blur_borders', (v) => _config.blurBorders = v);
    // Sync
    setInt('sync_interval_minutes', (v) => _config.syncIntervalMinutes = v);
    setInt('sync_timeout_seconds', (v) => _config.syncTimeoutSeconds = v);
    setBool('delete_orphaned_files', (v) => _config.deleteOrphanedFiles = v);
    // Clock
    setBool('show_clock', (v) => _config.showClock = v);
    setString('clock_size', (v) => _config.clockSize = v);
    setString('clock_position', (v) => _config.clockPosition = v);
    // Photo info
    setBool('show_photo_info', (v) => _config.showPhotoInfo = v);
    setString('photo_info_position', (v) => _config.photoInfoPosition = v);
    setString('photo_info_size', (v) => _config.photoInfoSize = v);
    setBool('use_script_font', (v) => _config.useScriptFontForMetadata = v);
    setBool('geocoding_enabled', (v) => _config.geocodingEnabled = v);
    // Schedule
    setBool('schedule_enabled', (v) => _config.scheduleEnabled = v);
    setInt('day_start_hour', (v) => _config.dayStartHour = v);
    setInt('day_start_minute', (v) => _config.dayStartMinute = v);
    setInt('night_start_hour', (v) => _config.nightStartHour = v);
    setInt('night_start_minute', (v) => _config.nightStartMinute = v);
    if (u.containsKey('fri_sat_night_start_hour')) {
      _config.fridaySaturdayNightStartHour =
          u['fri_sat_night_start_hour'] as int?;
    }
    if (u.containsKey('fri_sat_night_start_minute')) {
      _config.fridaySaturdayNightStartMinute =
          u['fri_sat_night_start_minute'] as int?;
    }
    // Display
    setString('screen_orientation', (v) => _config.screenOrientation = v);
    setBool('use_native_screen_off', (v) => _config.useNativeScreenOff = v);
    // Android
    setBool('autostart_on_boot', (v) => _config.autostartOnBoot = v);
    setBool('keep_alive_enabled', (v) => _config.keepAliveEnabled = v);
    setBool('wifi_adb_enabled', (v) => _config.wifiAdbEnabled = v);
    setString('web_ui_password', (v) => _config.webUiPassword = v);
    setBool('auto_update_enabled', (v) => _config.autoUpdateEnabled = v);

    await _config.save();
    // Sync Android runtime settings (SharedPreferences) so BootReceiver and
    // KeepAliveService pick up changes without requiring an app restart.
    await AndroidRuntimeSettingsSync().syncFromConfig(_config);
    _sendJson(request, {'ok': true});
  }

  Map<String, dynamic> _buildStatusMap() {
    final lastSync = _config.lastSuccessfulSync;
    return {
      'photo_count': _photoService.photoCount,
      'is_syncing': _photoService.isSyncing,
      'last_sync_iso': lastSync?.toIso8601String(),
    };
  }

  void _handleTriggerSync(HttpRequest request) {
    _photoService.triggerSync().catchError((e) {
      _log.warning('Web-triggered sync error: $e');
    });
    _sendJson(request, {'ok': true, 'message': 'Sync started'});
  }

  Future<void> _handleUploadPhoto(HttpRequest request) async {
    final filename = request.uri.queryParameters['filename'] ?? '';
    if (filename.isEmpty || filename.contains('/') || filename.contains('..')) {
      _sendError(request, 400, 'Missing or invalid filename parameter');
      return;
    }

    final dir = await _storageProvider.getPhotoDirectory();
    await dir.create(recursive: true);

    final bytes = await request.fold<List<int>>(
      [],
      (acc, chunk) => acc..addAll(chunk),
    );

    await File('${dir.path}/$filename').writeAsBytes(bytes);
    _log.info('Uploaded photo: $filename (${bytes.length} bytes)');
    _sendJson(request, {'ok': true, 'filename': filename});
  }

  // ---------------------------------------------------------------------------
  // Prometheus metrics
  // ---------------------------------------------------------------------------

  static bool _isPackageName(String name) {
    if (!name.contains('.')) return false;
    const knownTlds = {'com', 'net', 'io', 'org', 'android', 'uk', 'au', 'de', 'fr', 'co'};
    return knownTlds.contains(name.split('.').first);
  }

  Future<void> _refreshProcessStatus() async {
    final now = DateTime.now();
    if (_lastProcessScan != null && now.difference(_lastProcessScan!).inSeconds < 60) return;
    // Only ever run one scan at a time. Without this a slow scan lets every
    // subsequent scrape start another one on top of it.
    if (_processScanInFlight) return;
    // Mark the attempt up front, not on success. If the scan hangs, the throttle
    // above must still hold it off — otherwise the stuck scans pile up and the
    // forks starve the device.
    _lastProcessScan = now;
    _processScanInFlight = true;
    // /proc is mounted with hidepid=2 on Android — the app can only see its own PID
    // without root. Use su to list process names as root.
    //
    // This deliberately runs a single `ps` rather than walking /proc/[0-9]*/cmdline:
    // the old shell loop forked two processes per PID (~520 on this hardware) every
    // scan, which was enough process churn to wedge a low-end frame.
    try {
      final result = await Process.run(
        '/system/xbin/su',
        ['0', 'ps', '-A', '-o', 'NAME'],
      ).timeout(const Duration(seconds: 10));
      final found = <String>{};
      for (final line in (result.stdout as String).split('\n')) {
        final base = line.trim().split(':').first;
        if (_isPackageName(base)) found.add(base);
      }
      _runningPackages = found;
    } on TimeoutException {
      _log.warning('Process scan timed out after 10s; keeping previous results');
    } catch (e) {
      _log.fine('Process scan error: $e');
    } finally {
      _processScanInFlight = false;
    }
  }

  Future<void> _serveMetrics(HttpRequest request) async {
    final buf = StringBuffer();

    void gauge(String name, String help, num value) {
      buf.writeln('# HELP $name $help');
      buf.writeln('# TYPE $name gauge');
      buf.writeln('$name $value');
    }

    void counter(String name, String help, num value) {
      buf.writeln('# HELP $name $help');
      buf.writeln('# TYPE $name counter');
      buf.writeln('${name}_total $value');
    }

    final uptime = DateTime.now().difference(_startTime).inSeconds;
    gauge('opf_uptime_seconds', 'Seconds since the app started', uptime);

    // Dart process memory
    gauge('opf_process_rss_bytes', 'Resident set size of the app process', ProcessInfo.currentRss);

    // Flutter image cache
    final cache = PaintingBinding.instance.imageCache;
    gauge('opf_image_cache_bytes', 'Bytes currently used by Flutter image cache', cache.currentSizeBytes);
    gauge('opf_image_cache_max_bytes', 'Maximum bytes allowed in Flutter image cache', cache.maximumSizeBytes);
    gauge('opf_image_cache_count', 'Images currently in Flutter image cache', cache.currentSize);
    gauge('opf_image_cache_max_count', 'Maximum images allowed in Flutter image cache', cache.maximumSize);

    // Photos
    gauge('opf_photo_count', 'Photos available in local storage', _photoService.photoCount);
    gauge('opf_sync_in_progress', '1 if a sync is currently running', _photoService.isSyncing ? 1 : 0);
    counter('opf_sync', 'Successful syncs completed', _photoService.syncCount);
    counter('opf_sync_error', 'Syncs that ended in an error', _photoService.syncErrorCount);

    final lastSync = _config.lastSuccessfulSync;
    if (lastSync != null) {
      gauge('opf_last_sync_timestamp_seconds', 'Unix timestamp of last successful sync',
          lastSync.millisecondsSinceEpoch / 1000.0);
    }

    // Slideshow
    counter('opf_photo_display', 'Total photo display events since app start', _photoService.photoDisplayCount);
    final lastShown = _photoService.lastPhotoShownAt;
    if (lastShown != null) {
      gauge('opf_last_photo_shown_timestamp_seconds',
          'Unix timestamp of the last time a photo was displayed', lastShown.millisecondsSinceEpoch / 1000.0);
    }

    // Per-photo display counts and modification dates
    final photos = _photoService.allPhotos;
    if (photos.isNotEmpty) {
      buf.writeln('# HELP opf_photo_display_count_total Times each photo has been shown since app start');
      buf.writeln('# TYPE opf_photo_display_count_total counter');
      for (final photo in photos) {
        final name = photo.file.path.split('/').last.replaceAll('"', '');
        final freshnessTs = (photo.date.millisecondsSinceEpoch / 1000).floor();
        buf.writeln('opf_photo_display_count_total{photo="$name",freshness_date="$freshnessTs"} ${photo.displayCount}');
      }
    }

    // Android / JVM memory (no-op on non-Android)
    final androidMem = await NativeScreenControlService.getMemoryInfo();
    if (androidMem.isNotEmpty) {
      gauge('opf_android_system_avail_mem_bytes', 'Available system memory reported by Android', androidMem['system_avail_mem_bytes'] ?? 0);
      gauge('opf_android_system_total_mem_bytes', 'Total system memory reported by Android', androidMem['system_total_mem_bytes'] ?? 0);
      gauge('opf_android_low_mem_threshold_bytes', 'Android OOM threshold — system is in low-memory state below this', androidMem['system_low_mem_threshold_bytes'] ?? 0);
      gauge('opf_android_low_memory', '1 if Android reports the system is in a low-memory state', androidMem['system_low_memory'] ?? 0);
      gauge('opf_jvm_total_bytes', 'JVM total heap size', androidMem['jvm_total_bytes'] ?? 0);
      gauge('opf_jvm_free_bytes', 'JVM free heap', androidMem['jvm_free_bytes'] ?? 0);
      gauge('opf_jvm_max_bytes', 'JVM maximum heap size', androidMem['jvm_max_bytes'] ?? 0);
      gauge('opf_native_heap_allocated_bytes', 'Native heap bytes currently allocated', androidMem['native_heap_allocated_bytes'] ?? 0);
      gauge('opf_native_heap_size_bytes', 'Native heap total size', androidMem['native_heap_size_bytes'] ?? 0);
      final jiffies = androidMem['process_cpu_jiffies_total'] ?? 0;
      // Jiffies run at 100Hz on Android → divide by 100 for CPU seconds
      counter('opf_process_cpu_seconds', 'Total CPU time used by the app process', jiffies / 100.0);
    }

    // Storage
    if (androidMem.containsKey('storage_total_bytes')) {
      gauge('opf_storage_total_bytes', 'Total bytes on the storage partition used by photos', androidMem['storage_total_bytes']!);
      gauge('opf_storage_free_bytes', 'Free bytes on the storage partition', androidMem['storage_free_bytes'] ?? 0);
      gauge('opf_storage_avail_bytes', 'Available bytes on the storage partition for app use', androidMem['storage_avail_bytes'] ?? 0);
    }

    try {
      final photoDir = await _storageProvider.getPhotoDirectory();
      if (await photoDir.exists()) {
        var photoBytes = 0;
        await for (final entity in photoDir.list()) {
          if (entity is File) photoBytes += await entity.length();
        }
        gauge('opf_photo_storage_bytes', 'Bytes used by downloaded photos on disk', photoBytes);
      }
    } catch (_) {}

    // Thermal zones
    final thermal = await NativeScreenControlService.getThermalInfo();
    if (thermal.isNotEmpty) {
      buf.writeln('# HELP opf_thermal_zone_celsius Temperature of each Android thermal zone');
      buf.writeln('# TYPE opf_thermal_zone_celsius gauge');
      for (final entry in thermal.entries) {
        buf.writeln('opf_thermal_zone_celsius{zone="${entry.key}"} ${entry.value}');
      }
    }

    // Running Android processes — refreshed at most once per 60s
    await _refreshProcessStatus();
    if (_runningPackages.isNotEmpty) {
      buf.writeln('# HELP opf_process_running 1 if the named Android process is currently running');
      buf.writeln('# TYPE opf_process_running gauge');
      for (final pkg in _runningPackages) {
        buf.writeln('opf_process_running{process="$pkg"} 1');
      }
    }

    // eMMC I/O errors from kernel ring buffer, with per-sector labels.
    final ioErrors = await _fetchEmmcIoErrors();
    if (ioErrors != null) {
      buf.writeln('# HELP opf_emmc_io_errors_total eMMC I/O error events reported by the kernel since last boot');
      buf.writeln('# TYPE opf_emmc_io_errors_total counter');
      if (ioErrors.isEmpty) {
        buf.writeln('opf_emmc_io_errors_total{dev="none",sector="none"} 0');
      } else {
        // Aggregate by (dev, sector) so each bad sector gets its own label set.
        final counts = <(String, String), int>{};
        for (final e in ioErrors) {
          final key = (e.dev, e.sector);
          counts[key] = (counts[key] ?? 0) + 1;
        }
        for (final entry in counts.entries) {
          final dev = entry.key.$1;
          final sector = entry.key.$2;
          buf.writeln('opf_emmc_io_errors_total{dev="$dev",sector="$sector"} ${entry.value}');
        }
      }
    }

    request.response
      ..statusCode = 200
      ..headers.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
      ..write(buf.toString());
    await request.response.close();
  }

  // ---------------------------------------------------------------------------
  // eMMC health
  // ---------------------------------------------------------------------------

  // Tracks which error lines have already been logged so we don't spam on every scrape.
  static final Set<String> _loggedEmmcErrors = {};
  static final _emmcLog = Logger('WebServerService.emmc');

  // Returns parsed eMMC errors: list of (dev, sector, rawLine) records.
  // Also logs new errors so sector numbers survive in logcat before the
  // device potentially becomes unresponsive.
  static Future<List<({String dev, String sector, String raw})>?> _fetchEmmcIoErrors() async {
    try {
      final result = await Process.run('dmesg', []);
      final lines = (result.stdout as String).split('\n');
      final errors = <({String dev, String sector, String raw})>[];
      for (final line in lines) {
        if (!line.contains('I/O error') || !line.contains('mmcblk')) continue;
        final devMatch    = RegExp(r'dev\s+(\S+?)(?:,|$)').firstMatch(line);
        final sectorMatch = RegExp(r'sector\s+(\d+)').firstMatch(line);
        final dev    = devMatch?.group(1)    ?? 'unknown';
        final sector = sectorMatch?.group(1) ?? 'unknown';
        errors.add((dev: dev, sector: sector, raw: line.trim()));
        if (_loggedEmmcErrors.add(line)) {
          _emmcLog.warning('eMMC I/O error — dev=$dev sector=$sector: $line');
        }
      }
      return errors;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Response helpers
  // ---------------------------------------------------------------------------

  void _sendJson(HttpRequest req, Map<String, dynamic> data) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data));
    req.response.close();
  }

  void _sendHtml(HttpRequest req, String html) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(html);
    req.response.close();
  }

  void _sendError(HttpRequest req, int code, String message) {
    req.response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': message}));
    req.response.close();
  }

  // ---------------------------------------------------------------------------
  // Network
  // ---------------------------------------------------------------------------

  Future<String?> _findLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }
    } catch (e) {
      _log.warning('Could not determine LAN IP: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Embedded HTML settings page
  // ---------------------------------------------------------------------------

  static const String _settingsPage = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Open Photo Frame — Settings</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,sans-serif;background:#111;color:#eee;padding:16px;max-width:700px;margin:0 auto}
h1{font-size:1.3rem;margin-bottom:20px;color:#fff}
h2{font-size:.75rem;margin:20px 0 10px;color:#bbb;text-transform:uppercase;letter-spacing:.08em}
section{background:#1e1e1e;border-radius:8px;padding:16px;margin-bottom:12px}
label{display:block;margin-bottom:10px}
label>span{display:block;font-size:.8rem;color:#999;margin-bottom:4px}
input[type=url],input[type=text],select,textarea{width:100%;padding:8px 10px;background:#2a2a2a;
  border:1px solid #444;border-radius:6px;color:#eee;font-size:.9rem}
input[type=url]:focus,input[type=text]:focus,select:focus,textarea:focus{outline:none;border-color:#7c5cfc}
textarea{resize:vertical;font-family:inherit;line-height:1.5}
select option{background:#2a2a2a}
.row{display:flex;align-items:center;gap:10px;margin-bottom:10px}
.row>label{margin:0;flex:1}
.row>label>span{margin:0}
input[type=range]{flex:1;accent-color:#7c5cfc;min-width:0}
.val{min-width:56px;text-align:right;font-size:.9rem;color:#ccc}
.toggle{display:flex;align-items:center;justify-content:space-between;padding:6px 0;border-bottom:1px solid #2a2a2a}
.toggle:last-child{border-bottom:none}
.toggle span{font-size:.9rem}
.toggle small{display:block;font-size:.75rem;color:#888;margin-top:1px}
input[type=checkbox]{width:18px;height:18px;accent-color:#7c5cfc;cursor:pointer;flex-shrink:0}
.source-options{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px}
.src-opt{display:flex;align-items:center;gap:6px;cursor:pointer;background:#2a2a2a;
  border:1px solid #444;border-radius:6px;padding:8px 14px;font-size:.9rem;user-select:none}
.src-opt.active{border-color:#7c5cfc;background:#2a1f6b}
.src-opt input{accent-color:#7c5cfc}
.src-fields{display:none}.src-fields.show{display:block}
.two{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.btn-row{display:flex;gap:10px;flex-wrap:wrap;margin-top:4px}
button{padding:10px 20px;border:none;border-radius:6px;cursor:pointer;font-size:.9rem;font-weight:600}
.btn-p{background:#7c5cfc;color:#fff}.btn-p:hover{background:#6a4de0}
.btn-s{background:#333;color:#eee}.btn-s:hover{background:#444}
#status-bar{background:#1a1a2e;border:1px solid #333;border-radius:6px;
  padding:10px 14px;margin-bottom:12px;font-size:.85rem;color:#aaa;display:flex;gap:16px;flex-wrap:wrap}
#status-bar b{color:#eee}
#toast{position:fixed;bottom:20px;left:50%;transform:translateX(-50%);
  background:#222;border:1px solid #555;padding:10px 20px;border-radius:8px;
  font-size:.9rem;display:none;z-index:999;white-space:nowrap}
#toast.ok{border-color:#4c8;color:#4c8}#toast.err{border-color:#f55;color:#f55}
#drop-zone{border:2px dashed #444;border-radius:8px;padding:28px;text-align:center;
  color:#777;cursor:pointer;transition:border-color .2s,color .2s}
#drop-zone.over,#drop-zone:hover{border-color:#7c5cfc;color:#bbb}
#upload-list{margin-top:8px;font-size:.85rem}
.u{padding:3px 0;color:#aaa}.u.ok{color:#4c8}.u.err{color:#f55}
</style>
</head>
<body>
<h1>Open Photo Frame</h1>

<div id="status-bar">
  <span>Photos: <b id="s-count">…</b></span>
  <span>Last sync: <b id="s-last">…</b></span>
  <span id="s-syncing" style="display:none;color:#fc8">● Syncing…</span>
</div>

<!-- PHOTO SOURCE -->
<section>
  <h2>Photo Source</h2>
  <div class="source-options">
    <label class="src-opt" id="opt-none"><input type="radio" name="src" value=""> App Folder</label>
    <label class="src-opt" id="opt-icloud"><input type="radio" name="src" value="icloud_album"> iCloud Shared Album</label>
    <label class="src-opt" id="opt-nc"><input type="radio" name="src" value="nextcloud_link"> Nextcloud / WebDAV</label>
  </div>
  <div class="src-fields" id="sf-icloud">
    <label><span>iCloud Shared Album URL(s) — one link per line</span>
      <textarea id="icloud-url" rows="3" spellcheck="false" placeholder="https://www.icloud.com/photos/…&#10;https://www.icloud.com/photos/…"></textarea></label>
  </div>
  <div class="src-fields" id="sf-nc">
    <label><span>Share Link URL</span>
      <input type="url" id="nc-url" placeholder="https://cloud.example.com/s/…"></label>
  </div>
</section>

<!-- SLIDESHOW -->
<section>
  <h2>Slideshow</h2>
  <div class="row">
    <label><span>Slide duration</span></label>
    <input type="range" id="slide-dur" min="10" max="3600" step="10">
    <span class="val" id="dur-lbl">—</span>
  </div>
  <div class="row">
    <label><span>Transition duration</span></label>
    <input type="range" id="trans-dur" min="500" max="5000" step="100">
    <span class="val" id="trans-lbl">—</span>
  </div>
  <div class="toggle">
    <span>Blur borders<small>Fill screen edges with blurred image</small></span>
    <input type="checkbox" id="blur-borders">
  </div>
</section>

<!-- CLOCK -->
<section>
  <h2>Clock</h2>
  <div class="toggle">
    <span>Show clock</span>
    <input type="checkbox" id="show-clock">
  </div>
  <div id="clock-detail" style="display:none;margin-top:12px">
    <div class="two">
      <label><span>Size</span>
        <select id="clock-size">
          <option value="small">Small</option>
          <option value="medium">Medium</option>
          <option value="large">Large</option>
        </select>
      </label>
      <label><span>Position</span>
        <select id="clock-pos">
          <option value="bottomRight">Bottom Right</option>
          <option value="bottomLeft">Bottom Left</option>
          <option value="topRight">Top Right</option>
          <option value="topLeft">Top Left</option>
        </select>
      </label>
    </div>
  </div>
</section>

<!-- PHOTO INFO -->
<section>
  <h2>Photo Information</h2>
  <div class="toggle">
    <span>Show photo info<small>Date and location overlay on slideshow</small></span>
    <input type="checkbox" id="show-info">
  </div>
  <div id="info-detail" style="display:none;margin-top:12px">
    <div class="two" style="margin-bottom:10px">
      <label><span>Size</span>
        <select id="info-size">
          <option value="xsmall">X-Small</option>
          <option value="small">Small</option>
          <option value="medium">Medium</option>
          <option value="large">Large</option>
        </select>
      </label>
      <label><span>Position</span>
        <select id="info-pos">
          <option value="bottomRight">Bottom Right</option>
          <option value="bottomLeft">Bottom Left</option>
          <option value="topRight">Top Right</option>
          <option value="topLeft">Top Left</option>
        </select>
      </label>
    </div>
    <div class="toggle">
      <span>Script font<small>Handwritten style for metadata</small></span>
      <input type="checkbox" id="script-font">
    </div>
    <div class="toggle">
      <span>Resolve location names<small>Use OpenStreetMap to show place names</small></span>
      <input type="checkbox" id="geocoding">
    </div>
  </div>
</section>

<!-- DISPLAY SCHEDULE -->
<section>
  <h2>Display Schedule</h2>
  <div class="toggle">
    <span>Day / Night schedule<small>Turn off display at night</small></span>
    <input type="checkbox" id="schedule-on">
  </div>
  <div id="sched-detail" style="display:none;margin-top:12px">
    <div class="two" style="margin-bottom:10px">
      <label><span>Day starts at</span>
        <input type="text" id="day-start" placeholder="08:00" maxlength="5">
      </label>
      <label><span>Night starts at</span>
        <input type="text" id="night-start" placeholder="22:00" maxlength="5">
      </label>
    </div>
    <div class="toggle" style="margin-bottom:10px">
      <span>Different night time on Fri / Sat</span>
      <input type="checkbox" id="fri-sat-on">
    </div>
    <div id="fri-sat-detail" style="display:none">
      <label><span>Fri / Sat night starts at</span>
        <input type="text" id="fri-sat-start" placeholder="23:00" maxlength="5">
      </label>
    </div>
  </div>
</section>

<!-- SCREEN -->
<section>
  <h2>Screen</h2>
  <label><span>Screen orientation</span>
    <select id="orientation">
      <option value="auto">Automatic (Sensor)</option>
      <option value="portraitUp">Portrait</option>
      <option value="portraitDown">Portrait (upside down)</option>
      <option value="landscapeLeft">Landscape (left)</option>
      <option value="landscapeRight">Landscape (right)</option>
    </select>
  </label>
  <div class="toggle" style="margin-top:10px">
    <span>Native screen off<small>Use Device Admin to fully turn off screen at night</small></span>
    <input type="checkbox" id="native-off">
  </div>
</section>

<!-- SYNC -->
<section>
  <h2>Sync</h2>
  <div class="row">
    <label><span>Auto-sync interval</span></label>
    <input type="range" id="sync-int" min="0" max="180" step="5">
    <span class="val" id="sync-lbl">—</span>
  </div>
  <div class="row">
    <label><span>Sync timeout<small style="display:block">Seconds before a slow iCloud/Nextcloud request is aborted</small></span></label>
    <input type="range" id="sync-timeout" min="15" max="120" step="15">
    <span class="val" id="sync-timeout-lbl">—</span>
  </div>
  <div class="toggle">
    <span>Delete photos removed from source<small>Remove local files no longer on server</small></span>
    <input type="checkbox" id="del-orphans">
  </div>
</section>

<!-- ANDROID -->
<section>
  <h2>Android</h2>
  <div class="toggle">
    <span>Start on boot<small>Automatically launch when device boots</small></span>
    <input type="checkbox" id="autostart">
  </div>
  <div class="toggle">
    <span>Keep app running<small>Prevent app being stopped on low memory</small></span>
    <input type="checkbox" id="keep-alive">
  </div>
  <div class="toggle">
    <span>WiFi ADB<small>Enable ADB over WiFi on port 5555 on every boot (requires root)</small></span>
    <input type="checkbox" id="wifi-adb">
  </div>
  <div class="toggle">
    <span>Automatic updates<small>Check GitHub for new versions</small></span>
    <input type="checkbox" id="auto-update">
  </div>
  <div class="row">
    <label for="web-ui-password">Web UI password<small>Protects this page and the API. Leave blank to disable. /metrics stays open for Prometheus.</small></label>
    <input type="password" id="web-ui-password" autocomplete="new-password" placeholder="(no password)">
  </div>
</section>

<!-- ACTIONS -->
<section>
  <h2>Actions</h2>
  <div class="btn-row">
    <button class="btn-p" onclick="saveSettings()">Save Settings</button>
    <button class="btn-s" onclick="syncNow()">Sync Now</button>
  </div>
</section>

<!-- LOG -->
<section>
  <h2>App Log</h2>
  <div style="display:flex;gap:8px;margin-bottom:8px">
    <button class="btn-s" style="padding:6px 14px;font-size:.8rem" onclick="loadLog()">Refresh</button>
    <button class="btn-s" style="padding:6px 14px;font-size:.8rem" onclick="copyLog()">Copy All</button>
    <label style="display:flex;align-items:center;gap:6px;font-size:.85rem;color:#aaa;margin:0">
      <input type="checkbox" id="log-err-only" onchange="renderLog()" style="width:14px;height:14px">
      Errors only
    </label>
  </div>
  <div id="log-box" style="background:#0a0a0a;border:1px solid #333;border-radius:6px;
    padding:10px;max-height:320px;overflow-y:auto;font-family:monospace;font-size:.75rem;
    line-height:1.5;white-space:pre-wrap;word-break:break-all;color:#bbb"></div>
</section>

<!-- UPLOAD -->
<section>
  <h2>Upload Photos</h2>
  <div id="drop-zone" onclick="document.getElementById('fi').click()">
    Drop photos here, or click to select files
  </div>
  <input type="file" id="fi" multiple accept="image/*" style="display:none">
  <div id="upload-list"></div>
</section>

<div id="toast"></div>
<script>
let cfg={};

/* ---- load ---- */
async function load(){
  try{
    const[c,s]=await Promise.all([fetch('/api/config').then(r=>r.json()),fetch('/api/status').then(r=>r.json())]);
    cfg=c; applyConfig(c); applyStatus(s);
  }catch(e){toast('Failed to load: '+e,'err');}
}

function applyConfig(c){
  // Source
  const src=c.active_source||'';
  document.querySelectorAll('input[name=src]').forEach(r=>{
    r.checked=r.value===src;
    r.closest('.src-opt').classList.toggle('active',r.value===src);
  });
  showSrcFields(src);
  // iCloud album: accept legacy single album_url or album_urls list
  const icloudCfg=c.icloud_album||{};
  const icloudUrls=Array.isArray(icloudCfg.album_urls)?icloudCfg.album_urls
    :(icloudCfg.album_url?[icloudCfg.album_url]:[]);
  set('icloud-url',icloudUrls.join('\n'));
  set('nc-url',(c.nextcloud_link||{}).url||'');

  // Slideshow
  setRange('slide-dur', c.slide_duration_seconds??300); durLbl(c.slide_duration_seconds??300);
  setRange('trans-dur', c.transition_duration_ms??2000); transLbl(c.transition_duration_ms??2000);
  setCheck('blur-borders', c.blur_borders??true);

  // Clock
  const clk=c.show_clock??false;
  setCheck('show-clock',clk);
  document.getElementById('clock-detail').style.display=clk?'':'none';
  sel('clock-size', c.clock_size||'medium');
  sel('clock-pos',  c.clock_position||'bottomRight');

  // Photo info
  const inf=c.show_photo_info??false;
  setCheck('show-info',inf);
  document.getElementById('info-detail').style.display=inf?'':'none';
  sel('info-size', c.photo_info_size||'medium');
  sel('info-pos',  c.photo_info_position||'bottomRight');
  setCheck('script-font', c.use_script_font??false);
  setCheck('geocoding',   c.geocoding_enabled??false);

  // Schedule
  const sched=c.schedule_enabled??false;
  setCheck('schedule-on',sched);
  document.getElementById('sched-detail').style.display=sched?'':'none';
  set('day-start',   fmtTime(c.day_start_hour??8,   c.day_start_minute??0));
  set('night-start', fmtTime(c.night_start_hour??22, c.night_start_minute??0));
  const hasFriSat=c.fri_sat_night_start_hour!=null;
  setCheck('fri-sat-on',hasFriSat);
  document.getElementById('fri-sat-detail').style.display=hasFriSat?'':'none';
  if(hasFriSat) set('fri-sat-start',fmtTime(c.fri_sat_night_start_hour,c.fri_sat_night_start_minute??0));

  // Screen
  sel('orientation', c.screen_orientation||'auto');
  setCheck('native-off', c.use_native_screen_off??false);

  // Sync
  const si=c.sync_interval_minutes??15;
  setRange('sync-int',si); syncLbl(si);
  const st=c.sync_timeout_seconds??60;
  setRange('sync-timeout',st); syncTimeoutLbl(st);
  setCheck('del-orphans', c.delete_orphaned_files??false);

  // Android
  setCheck('autostart',    c.autostart_on_boot??false);
  setCheck('keep-alive',   c.keep_alive_enabled??false);
  document.getElementById('web-ui-password').value=c.web_ui_password??'';
  setCheck('wifi-adb',         c.wifi_adb_enabled??true);
  setCheck('auto-update',      c.auto_update_enabled??false);
}

function applyStatus(s){
  document.getElementById('s-count').textContent=s.photo_count??'?';
  document.getElementById('s-last').textContent=s.last_sync_iso?new Date(s.last_sync_iso).toLocaleString():'never';
  document.getElementById('s-syncing').style.display=s.is_syncing?'':'none';
}

/* ---- source fields ---- */
function showSrcFields(src){
  document.getElementById('sf-icloud').classList.toggle('show',src==='icloud_album');
  document.getElementById('sf-nc').classList.toggle('show',src==='nextcloud_link');
}
document.querySelectorAll('input[name=src]').forEach(r=>r.addEventListener('change',()=>{
  document.querySelectorAll('.src-opt').forEach(o=>o.classList.remove('active'));
  r.closest('.src-opt').classList.add('active');
  showSrcFields(r.value);
}));

/* ---- toggles that show sub-sections ---- */
document.getElementById('show-clock').addEventListener('change',e=>{
  document.getElementById('clock-detail').style.display=e.target.checked?'':'none';
});
document.getElementById('show-info').addEventListener('change',e=>{
  document.getElementById('info-detail').style.display=e.target.checked?'':'none';
});
document.getElementById('schedule-on').addEventListener('change',e=>{
  document.getElementById('sched-detail').style.display=e.target.checked?'':'none';
});
document.getElementById('fri-sat-on').addEventListener('change',e=>{
  document.getElementById('fri-sat-detail').style.display=e.target.checked?'':'none';
});

/* ---- range labels ---- */
function durLbl(v){const s=+v;document.getElementById('dur-lbl').textContent=s<60?s+'s':(s/60|0)+'m'+(s%60?(s%60)+'s':'');}
function transLbl(v){document.getElementById('trans-lbl').textContent=(+v/1000).toFixed(1)+'s';}
function syncLbl(v){const m=+v;document.getElementById('sync-lbl').textContent=m?m+'m':'off';}
function syncTimeoutLbl(v){document.getElementById('sync-timeout-lbl').textContent=v+'s';}
document.getElementById('slide-dur').addEventListener('input',e=>durLbl(e.target.value));
document.getElementById('trans-dur').addEventListener('input',e=>transLbl(e.target.value));
document.getElementById('sync-int').addEventListener('input',e=>syncLbl(e.target.value));
document.getElementById('sync-timeout').addEventListener('input',e=>syncTimeoutLbl(e.target.value));

/* ---- save ---- */
async function saveSettings(){
  function parseTime(id){
    const parts=(document.getElementById(id).value||'').split(':');
    if(parts.length!==2) return null;
    return{h:parseInt(parts[0])||0,m:parseInt(parts[1])||0};
  }
  const src=document.querySelector('input[name=src]:checked')?.value||'';
  const friSatOn=document.getElementById('fri-sat-on').checked;
  const friSatTime=friSatOn?parseTime('fri-sat-start'):null;
  // iCloud album links: one per line → single legacy field for one link,
  // album_urls list for several
  const icloudLines=(document.getElementById('icloud-url').value||'').split(/\r?\n/).map(s=>s.trim()).filter(s=>s.length>0);
  const icloudPayload=icloudLines.length>1?{album_urls:icloudLines}:{album_url:icloudLines[0]||''};
  const p={
    active_source:src,
    icloud_album:icloudPayload,
    nextcloud_link:{...(cfg.nextcloud_link||{}),url:document.getElementById('nc-url').value.trim()},
    slide_duration_seconds:+document.getElementById('slide-dur').value,
    transition_duration_ms:+document.getElementById('trans-dur').value,
    blur_borders:document.getElementById('blur-borders').checked,
    sync_interval_minutes:+document.getElementById('sync-int').value,
    sync_timeout_seconds:+document.getElementById('sync-timeout').value,
    delete_orphaned_files:document.getElementById('del-orphans').checked,
    show_clock:document.getElementById('show-clock').checked,
    clock_size:document.getElementById('clock-size').value,
    clock_position:document.getElementById('clock-pos').value,
    show_photo_info:document.getElementById('show-info').checked,
    photo_info_size:document.getElementById('info-size').value,
    photo_info_position:document.getElementById('info-pos').value,
    use_script_font:document.getElementById('script-font').checked,
    geocoding_enabled:document.getElementById('geocoding').checked,
    schedule_enabled:document.getElementById('schedule-on').checked,
    day_start_hour:  (parseTime('day-start')  ||{h:8,m:0}).h,
    day_start_minute:(parseTime('day-start')  ||{h:8,m:0}).m,
    night_start_hour:  (parseTime('night-start')||{h:22,m:0}).h,
    night_start_minute:(parseTime('night-start')||{h:22,m:0}).m,
    fri_sat_night_start_hour:  friSatTime?friSatTime.h:null,
    fri_sat_night_start_minute:friSatTime?friSatTime.m:null,
    screen_orientation:document.getElementById('orientation').value,
    use_native_screen_off:document.getElementById('native-off').checked,
    autostart_on_boot:document.getElementById('autostart').checked,
    keep_alive_enabled:document.getElementById('keep-alive').checked,
    wifi_adb_enabled:document.getElementById('wifi-adb').checked,
    web_ui_password:document.getElementById('web-ui-password').value,
    auto_update_enabled:document.getElementById('auto-update').checked,
  };
  try{
    await fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p)});
    toast('Settings saved','ok');
  }catch(e){toast('Save failed: '+e,'err');}
}

async function syncNow(){
  try{await fetch('/api/sync',{method:'POST'});toast('Sync started','ok');setTimeout(load,2000);}
  catch(e){toast('Failed: '+e,'err');}
}

/* ---- upload ---- */
const dz=document.getElementById('drop-zone');
const fi=document.getElementById('fi');
dz.addEventListener('dragover',e=>{e.preventDefault();dz.classList.add('over');});
dz.addEventListener('dragleave',()=>dz.classList.remove('over'));
dz.addEventListener('drop',e=>{e.preventDefault();dz.classList.remove('over');uploadFiles(e.dataTransfer.files);});
fi.addEventListener('change',()=>{uploadFiles(fi.files);fi.value='';});
async function uploadFiles(files){
  const list=document.getElementById('upload-list');
  for(const f of files){
    const el=document.createElement('div');el.className='u';el.textContent=f.name+'…';list.prepend(el);
    try{
      await fetch('/api/photos?filename='+encodeURIComponent(f.name),{method:'POST',body:f});
      el.className='u ok';el.textContent='✓ '+f.name;
    }catch(e){el.className='u err';el.textContent='✗ '+f.name+': '+e;}
  }
  setTimeout(load,500);
}

/* ---- helpers ---- */
function set(id,v){document.getElementById(id).value=v;}
function sel(id,v){const el=document.getElementById(id);if(el)el.value=v;}
function setCheck(id,v){const el=document.getElementById(id);if(el)el.checked=!!v;}
function setRange(id,v){const el=document.getElementById(id);if(el)el.value=v;}
function fmtTime(h,m){return String(h).padStart(2,'0')+':'+String(m).padStart(2,'0');}
function toast(msg,type){
  const t=document.getElementById('toast');
  t.textContent=msg;t.className=type;t.style.display='block';
  setTimeout(()=>t.style.display='none',3000);
}

/* ---- log ---- */
let allLogEntries=[];
const LOG_COLORS={SEVERE:'#f55',WARNING:'#fc8',INFO:'#6af',FINE:'#777',FINER:'#555',FINEST:'#555'};
async function loadLog(){
  try{
    const r=await fetch('/api/log');
    const d=await r.json();
    allLogEntries=d.entries||[];
    renderLog();
  }catch(e){/* ignore */}
}
function renderLog(){
  const errOnly=document.getElementById('log-err-only').checked;
  const box=document.getElementById('log-box');
  const entries=errOnly?allLogEntries.filter(e=>e.l==='SEVERE'||e.l==='WARNING'):allLogEntries;
  if(!entries.length){box.textContent='(no log entries)';box.style.color='#555';return;}
  box.innerHTML=entries.map(e=>{
    const col=LOG_COLORS[e.l]||'#aaa';
    const time=e.t.replace('T',' ').replace(/\.\d+Z$/,'');
    const err=e.e?'\n  '+e.e:'';
    return`<span style="color:${col}">[${e.l.padEnd(7)}]</span> <span style="color:#666">${time}</span> ${escHtml(e.m)}${err?'<span style="color:#f77">'+escHtml(err)+'</span>':''}`;
  }).join('\n');
  box.style.color='';
}
function escHtml(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function copyLog(){
  const entries=allLogEntries;
  const text=entries.map(e=>`[${e.l}] ${e.t} ${e.m}${e.e?' — '+e.e:''}`).join('\n');
  // navigator.clipboard requires HTTPS; use execCommand fallback for plain HTTP
  if(navigator.clipboard&&window.isSecureContext){
    navigator.clipboard.writeText(text).then(()=>toast('Log copied','ok'),()=>fallbackCopy(text));
  }else{
    fallbackCopy(text);
  }
}
function fallbackCopy(text){
  const ta=document.createElement('textarea');
  ta.value=text;
  ta.style.cssText='position:fixed;left:-9999px;top:-9999px;opacity:0';
  document.body.appendChild(ta);
  ta.focus();ta.select();
  try{document.execCommand('copy');toast('Log copied','ok');}
  catch(e){toast('Copy failed — select text manually','err');}
  document.body.removeChild(ta);
}

async function loadStatus(){
  try{const s=await fetch('/api/status').then(r=>r.json());applyStatus(s);}catch(e){}
}

load();loadLog();
setInterval(loadStatus,10000);   // refresh status bar only — don't reset the form
setInterval(loadLog,15000);
</script>
</body>
</html>''';
}
