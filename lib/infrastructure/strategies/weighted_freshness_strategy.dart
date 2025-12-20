import 'dart:math';
import '../../domain/interfaces/playlist_strategy.dart';
import '../../domain/models/photo_entry.dart';

class WeightedFreshnessStrategy implements PlaylistStrategy {
  final Random _random = Random();
  
  // Configuration
  final double factor;
  final double baseWeight;
  
  // Internal state for count-based cooldown
  final List<PhotoEntry> _recentlyShown = [];

  WeightedFreshnessStrategy({
    this.factor = 50.0,
    this.baseWeight = 1.0,
  });

  @override
  String get id => 'weighted_freshness';

  @override
  String get name => 'Smart Freshness Shuffle';

  @override
  PhotoEntry? nextPhoto(List<PhotoEntry> availablePhotos) {
    if (availablePhotos.isEmpty) return null;
    if (availablePhotos.length == 1) {
      final photo = availablePhotos.first;
      photo.weight = _calculateWeight(photo.date);
      _trackSelection(photo);
      return photo;
    }

    // Calculate adaptive cooldown sizes
    final totalPhotos = availablePhotos.length;
    final hardCooldown = _calculateHardCooldown(totalPhotos);
    final softCooldown = _calculateSoftCooldown(totalPhotos);

    // 1. Hard Cooldown: Exclude last N photos completely
    final recentSet = _recentlyShown.take(hardCooldown).toSet();
    var candidates = availablePhotos.where((p) => !recentSet.contains(p)).toList();

    // Fallback: If all photos are in hard cooldown (shouldn't happen with adaptive sizing)
    if (candidates.isEmpty) {
      candidates = availablePhotos;
    }

    // 2. Calculate Weights with Soft Cooldown penalty
    double totalWeight = 0;
    for (var photo in candidates) {
      double weight = _calculateWeight(photo.date);
      
      // Apply soft cooldown penalty
      final posInHistory = _recentlyShown.indexOf(photo);
      if (posInHistory >= 0 && posInHistory < softCooldown) {
        // Linear penalty: more recent = stronger penalty
        final recencyFactor = 1.0 - (posInHistory / softCooldown);
        weight *= (1.0 - recencyFactor * 0.7); // Up to 70% reduction
      }
      
      photo.weight = weight;
      totalWeight += weight;
    }

    // 3. Weighted Random Selection
    if (totalWeight <= 0) {
      // Shouldn't happen, but safety fallback
      final selected = candidates[_random.nextInt(candidates.length)];
      _trackSelection(selected);
      return selected;
    }

    double randomPoint = _random.nextDouble() * totalWeight;
    for (var photo in candidates) {
      randomPoint -= photo.weight;
      if (randomPoint <= 0) {
        _trackSelection(photo);
        return photo;
      }
    }

    final selected = candidates.last;
    _trackSelection(selected);
    return selected;
  }

  /// Calculate hard cooldown: photos completely excluded from selection
  int _calculateHardCooldown(int totalPhotos) {
    if (totalPhotos <= 1) return 0;
    if (totalPhotos <= 10) return min(1, totalPhotos - 1);
    // For larger collections: exclude last ~5-10%
    return min(5, (totalPhotos * 0.1).round());
  }

  /// Calculate soft cooldown: photos get weight penalty
  int _calculateSoftCooldown(int totalPhotos) {
    if (totalPhotos <= 1) return 0;
    // Logarithmic scaling: sqrt(photos) * 2.5
    return min((sqrt(totalPhotos) * 2.5).round(), totalPhotos - 1);
  }

  /// Track a selected photo in history
  void _trackSelection(PhotoEntry photo) {
    photo.lastShown = DateTime.now();
    
    // Remove if already in history (move to front)
    _recentlyShown.remove(photo);
    
    // Add to front of history
    _recentlyShown.insert(0, photo);
    
    // Limit history size (keep last 100 to handle large collections)
    if (_recentlyShown.length > 100) {
      _recentlyShown.removeLast();
    }
  }

  double _calculateWeight(DateTime date) {
    final ageInDays = DateTime.now().difference(date).inDays;
    // Ensure age is non-negative (in case of future dates)
    final age = max(0, ageInDays);
    return (factor / (age + 1)) + baseWeight;
  }
}
