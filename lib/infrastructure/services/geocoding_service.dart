import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for reverse geocoding (coordinates → place name)
/// Uses OpenStreetMap Nominatim API (free, no API key required)
/// Caches results persistently with automatic cleanup of old entries.
class GeocodingService {
  final _log = Logger('GeocodingService');
  
  // In-memory cache: "lat,lon" → location name
  final Map<String, String?> _cache = {};
  
  // Timestamps for cache entries (for cleanup)
  final Map<String, DateTime> _cacheTimestamps = {};
  
  /// User-Agent required by Nominatim usage policy
  static const String _userAgent = 'OpenPhotoFrame/1.0';
  
  /// Prefix for SharedPreferences keys (v2 = city-only format)
  static const String _prefsPrefix = 'geocache_v2_';
  static const String _prefsTsPrefix = 'geocache_v2_ts_';
  
  /// Maximum age for cache entries (3 months)
  static const Duration _maxCacheAge = Duration(days: 90);
  
  bool _initialized = false;
  
  /// Initialize the service and load persistent cache
  Future<void> initialize() async {
    if (_initialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefsPrefix) && !k.startsWith(_prefsTsPrefix));
    
    final now = DateTime.now();
    int loaded = 0;
    int expired = 0;
    
    for (final key in keys) {
      final cacheKey = key.substring(_prefsPrefix.length);
      final tsKey = '$_prefsTsPrefix$cacheKey';
      
      // Check timestamp
      final tsMillis = prefs.getInt(tsKey);
      if (tsMillis != null) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(tsMillis);
        if (now.difference(timestamp) > _maxCacheAge) {
          // Entry expired - remove it
          await prefs.remove(key);
          await prefs.remove(tsKey);
          expired++;
          continue;
        }
        _cacheTimestamps[cacheKey] = timestamp;
      }
      
      final value = prefs.getString(key);
      _cache[cacheKey] = value; // null if stored as empty
      loaded++;
    }
    
    _initialized = true;
    _log.info('Geocoding cache loaded: $loaded entries, $expired expired entries removed');
  }
  
  /// Reverse geocode coordinates to a place name
  /// Returns format: "City, State, Country" or null if failed
  Future<String?> getLocationName(double latitude, double longitude) async {
    // Ensure initialized
    if (!_initialized) await initialize();
    
    // Round to 3 decimal places (~100m precision) for caching
    final cacheKey = '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';
    
    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }
    
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$latitude'
        '&lon=$longitude'
        '&format=json'
        '&zoom=10'  // City level
        '&addressdetails=1'
      );
      
      final response = await http.get(url, headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'de,en',  // Prefer German, fallback English
      }).timeout(const Duration(seconds: 5));
      
      if (response.statusCode != 200) {
        _log.warning('Geocoding failed: HTTP ${response.statusCode}');
        // Don't cache HTTP errors - might be temporary
        return null;
      }
      
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final address = json['address'] as Map<String, dynamic>?;
      
      if (address == null) {
        await _cacheResult(cacheKey, null);
        return null;
      }
      
      // Build location string: city only
      final city = address['city'] ??
                   address['town'] ??
                   address['village'] ??
                   address['municipality'] ??
                   address['county'];
      final result = city?.toString();
      await _cacheResult(cacheKey, result);
      
      _log.fine('Geocoded ($latitude, $longitude) → $result');
      return result;
      
    } catch (e) {
      _log.warning('Geocoding error for ($latitude, $longitude): $e');
      // Don't cache network errors - might be temporary
      return null;
    }
  }
  
  /// Cache a result both in memory and persistently
  Future<void> _cacheResult(String cacheKey, String? result) async {
    _cache[cacheKey] = result;
    _cacheTimestamps[cacheKey] = DateTime.now();
    
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsPrefix$cacheKey';
    final tsKey = '$_prefsTsPrefix$cacheKey';
    
    if (result != null) {
      await prefs.setString(key, result);
    } else {
      await prefs.setString(key, ''); // Store empty string for null results
    }
    await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
  }
  
  /// Remove cache entries for coordinates that are no longer used
  /// Call this with a set of still-valid coordinates to clean up orphans
  Future<void> cleanupOrphans(Set<String> validCoordinates) async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = <String>[];
    
    for (final cacheKey in _cache.keys.toList()) {
      if (!validCoordinates.contains(cacheKey)) {
        keysToRemove.add(cacheKey);
      }
    }
    
    for (final cacheKey in keysToRemove) {
      _cache.remove(cacheKey);
      _cacheTimestamps.remove(cacheKey);
      await prefs.remove('$_prefsPrefix$cacheKey');
      await prefs.remove('$_prefsTsPrefix$cacheKey');
    }
    
    if (keysToRemove.isNotEmpty) {
      _log.info('Geocoding cache cleanup: removed ${keysToRemove.length} orphaned entries');
    }
  }
  
  /// Clear the entire geocoding cache
  Future<void> clearCache() async {
    _cache.clear();
    _cacheTimestamps.clear();
    
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (k) => k.startsWith(_prefsPrefix) || k.startsWith(_prefsTsPrefix)
    ).toList();
    
    for (final key in keys) {
      await prefs.remove(key);
    }
    
    _log.info('Geocoding cache cleared');
  }
}
