import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_photo_frame/domain/models/photo_entry.dart';
import 'package:open_photo_frame/infrastructure/strategies/weighted_freshness_strategy.dart';

void main() {
  group('WeightedFreshnessStrategy', () {
    late WeightedFreshnessStrategy strategy;

    setUp(() {
      strategy = WeightedFreshnessStrategy(
        factor: 50.0,
        baseWeight: 1.0,
      );
    });

    // Helper: Create dummy photos with specific dates
    List<PhotoEntry> createPhotos(int count, {int dayOffset = 0}) {
      return List.generate(count, (i) {
        final date = DateTime.now().subtract(Duration(days: dayOffset + i));
        return PhotoEntry(
          file: File('/fake/photo_$i.jpg'),
          date: date,
          sizeBytes: 1024,
        );
      });
    }

    test('should return null when no photos available', () {
      final result = strategy.nextPhoto([]);
      expect(result, isNull);
    });

    test('should return single photo when only one available', () {
      final photos = createPhotos(1);
      final result = strategy.nextPhoto(photos);
      expect(result, equals(photos.first));
    });

    test('should prefer newer photos (statistical test)', () {
      // Create photos: 5 from today, 5 from 365 days ago
      final newPhotos = createPhotos(5, dayOffset: 0);
      final oldPhotos = createPhotos(5, dayOffset: 365);
      final allPhotos = [...newPhotos, ...oldPhotos];

      // Run selection 100 times and count how often new vs old are picked
      final selections = <PhotoEntry>[];
      for (int i = 0; i < 100; i++) {
        final photo = strategy.nextPhoto(allPhotos);
        if (photo != null) selections.add(photo);
      }

      final newCount = selections.where((p) => newPhotos.contains(p)).length;
      final oldCount = selections.where((p) => oldPhotos.contains(p)).length;

      // New photos should be selected significantly more often
      // With factor=50, new photos have ~51x weight vs old photos (~1.13x)
      // Expected ratio: ~45:1 without cooldown
      // With soft cooldown reducing repeat probability, we accept >7:1
      expect(newCount, greaterThan(oldCount * 7),
          reason: 'New photos should be selected at least 7x more often than old photos. Got $newCount new vs $oldCount old');
    });

    test('should respect count-based cooldown', () {
      final photos = createPhotos(10);
      
      // Select first photo
      final first = strategy.nextPhoto(photos);
      expect(first, isNotNull);
      
      // The very next selection should NOT be the same photo (hard cooldown)
      final second = strategy.nextPhoto(photos);
      expect(second, isNotNull);
      expect(identical(second, first), isFalse,
          reason: 'Recently selected photo should be in cooldown');
    });

    test('should apply cooldown fallback with small collections', () {
      final photos = createPhotos(2);
      
      // With only 2 photos, both should eventually be selected
      final selections = <PhotoEntry>{};
      for (int i = 0; i < 10; i++) {
        final photo = strategy.nextPhoto(photos);
        if (photo != null) selections.add(photo);
      }

      expect(selections.length, equals(2),
          reason: 'Both photos should be selected eventually even with cooldown');
    });

    test('should calculate weights correctly', () {
      final today = createPhotos(1, dayOffset: 0).first;
      final yesterday = createPhotos(1, dayOffset: 1).first;
      final oneWeekAgo = createPhotos(1, dayOffset: 7).first;
      final oneYearAgo = createPhotos(1, dayOffset: 365).first;

      final photos = [today, yesterday, oneWeekAgo, oneYearAgo];
      
      // Trigger weight calculation by selecting
      strategy.nextPhoto(photos);

      // Check weight formula: W(t) = 50/(t+1) + 1
      expect(today.weight, closeTo(51.0, 0.1)); // 50/1 + 1
      expect(yesterday.weight, closeTo(26.0, 0.1)); // 50/2 + 1
      expect(oneWeekAgo.weight, closeTo(7.25, 0.1)); // 50/8 + 1
      expect(oneYearAgo.weight, closeTo(1.14, 0.1)); // 50/366 + 1
    });

    test('should handle edge case: only one photo', () {
      final photos = createPhotos(1);

      // Should return that photo every time
      for (int i = 0; i < 5; i++) {
        final result = strategy.nextPhoto(photos);
        expect(result, equals(photos.first));
      }
    });

    test('should distribute selection across all photos eventually', () {
      final photos = createPhotos(10);
      final selectionCount = <PhotoEntry, int>{};

      // Run many selections
      for (int i = 0; i < 200; i++) {
        final photo = strategy.nextPhoto(photos);
        if (photo != null) {
          selectionCount[photo] = (selectionCount[photo] ?? 0) + 1;
        }
      }

      // All photos should have been selected at least once
      expect(selectionCount.length, equals(10),
          reason: 'All photos should be selected at least once over 200 iterations');
      
      // Each photo should have been selected at least a few times
      for (final count in selectionCount.values) {
        expect(count, greaterThan(0));
      }
    });

    test('should use configured factor parameter', () {
      final strategyHighFactor = WeightedFreshnessStrategy(factor: 100.0, baseWeight: 1.0);
      final strategyLowFactor = WeightedFreshnessStrategy(factor: 10.0, baseWeight: 1.0);

      final newPhotos = createPhotos(5, dayOffset: 0);
      final oldPhotos = createPhotos(5, dayOffset: 100);
      final allPhotos = [...newPhotos, ...oldPhotos];

      // Count selections with high factor
      int highNewCount = 0;
      for (int i = 0; i < 100; i++) {
        final photo = strategyHighFactor.nextPhoto(allPhotos);
        if (photo != null && newPhotos.contains(photo)) highNewCount++;
      }

      // Count selections with low factor
      int lowNewCount = 0;
      for (int i = 0; i < 100; i++) {
        final photo = strategyLowFactor.nextPhoto(allPhotos);
        if (photo != null && newPhotos.contains(photo)) lowNewCount++;
      }

      // Higher factor should result in more new photos being selected
      expect(highNewCount, greaterThan(lowNewCount),
          reason: 'Higher factor should prefer newer photos more strongly');
    });

    test('should handle photos with future dates gracefully', () {
      final futurePhoto = PhotoEntry(
        file: File('/fake/future.jpg'),
        date: DateTime.now().add(const Duration(days: 10)),
        sizeBytes: 1024,
      );

      final result = strategy.nextPhoto([futurePhoto]);
      expect(result, equals(futurePhoto));
      // Should not crash and should assign valid weight (max weight since age = 0)
      expect(futurePhoto.weight, greaterThan(0));
    });
  });

  group('WeightedFreshnessStrategy - Adaptive Count-based Cooldown', () {
    // Helper to simulate history by calling nextPhoto multiple times
    List<PhotoEntry> buildHistory(
      WeightedFreshnessStrategy strategy,
      List<PhotoEntry> photos,
      int count,
    ) {
      final history = <PhotoEntry>[];
      for (int i = 0; i < count; i++) {
        final photo = strategy.nextPhoto(photos);
        if (photo != null) {
          history.add(photo);
        }
      }
      return history;
    }

    test('should prevent immediate repetition with small collection (5 photos)', () {
      final strategy = WeightedFreshnessStrategy();
      final photos = List.generate(5, (i) {
        return PhotoEntry(
          file: File('/fake/photo_$i.jpg'),
          date: DateTime.now().subtract(Duration(days: i)),
          sizeBytes: 1024,
        );
      });

      // Select first photo
      final first = strategy.nextPhoto(photos);
      expect(first, isNotNull);

      // Next selection should NOT be the same photo
      final second = strategy.nextPhoto(photos);
      expect(second, isNotNull);
      expect(identical(second, first), isFalse,
          reason: 'Should not select the same photo twice in a row');
    });

    test('should ensure good rotation with 5 photos over 20 selections', () {
      final strategy = WeightedFreshnessStrategy();
      final photos = List.generate(5, (i) {
        return PhotoEntry(
          file: File('/fake/photo_$i.jpg'),
          date: DateTime.now().subtract(Duration(days: i)),
          sizeBytes: 1024,
        );
      });

      final selections = <PhotoEntry>[];
      for (int i = 0; i < 20; i++) {
        final photo = strategy.nextPhoto(photos);
        if (photo != null) selections.add(photo);
      }

      // All 5 photos should have been selected at least once
      final uniquePhotos = selections.toSet();
      expect(uniquePhotos.length, equals(5),
          reason: 'All 5 photos should be selected at least once over 20 iterations');

      // Check for immediate repetitions (same photo twice in a row)
      int immediateRepeats = 0;
      for (int i = 1; i < selections.length; i++) {
        if (identical(selections[i], selections[i - 1])) {
          immediateRepeats++;
        }
      }
      expect(immediateRepeats, equals(0),
          reason: 'No photo should be selected twice in a row');
    });

    test('should handle 1 photo gracefully (no alternative)', () {
      final strategy = WeightedFreshnessStrategy();
      final photos = [
        PhotoEntry(
          file: File('/fake/only.jpg'),
          date: DateTime.now(),
          sizeBytes: 1024,
        )
      ];

      // Should return the same photo every time (no alternative)
      for (int i = 0; i < 5; i++) {
        final photo = strategy.nextPhoto(photos);
        expect(photo, equals(photos.first));
      }
    });

    test('should prevent early repetition with 20 photos', () {
      final strategy = WeightedFreshnessStrategy();
      final photos = List.generate(20, (i) {
        return PhotoEntry(
          file: File('/fake/photo_$i.jpg'),
          date: DateTime.now().subtract(Duration(days: i)),
          sizeBytes: 1024,
        );
      });

      final selections = <PhotoEntry>[];
      for (int i = 0; i < 40; i++) {
        final photo = strategy.nextPhoto(photos);
        if (photo != null) selections.add(photo);
      }

      // Check that photos don't repeat within a small window
      // With adaptive cooldown and weighted preference for new photos,
      // we expect at least 8 different photos in first 15 selections
      final firstHalf = selections.take(15).toList();
      final uniqueInFirstHalf = firstHalf.toSet().length;
      
      expect(uniqueInFirstHalf, greaterThanOrEqualTo(8),
          reason: 'Should show at least 8 different photos in first 15 selections');
    });

    test('should scale cooldown with 100 photos', () {
      final strategy = WeightedFreshnessStrategy();
      final photos = List.generate(100, (i) {
        return PhotoEntry(
          file: File('/fake/photo_$i.jpg'),
          date: DateTime.now().subtract(Duration(days: i)),
          sizeBytes: 1024,
        );
      });

      final selections = <PhotoEntry>[];
      for (int i = 0; i < 50; i++) {
        final photo = strategy.nextPhoto(photos);
        if (photo != null) selections.add(photo);
      }

      // With 100 photos and adaptive cooldown (~25-30), should see high diversity
      final uniquePhotos = selections.toSet().length;
      
      expect(uniquePhotos, greaterThanOrEqualTo(30),
          reason: 'With 100 photos, should show at least 30 different ones in 50 selections');

      // Check for any immediate repetitions
      int immediateRepeats = 0;
      for (int i = 1; i < selections.length; i++) {
        if (identical(selections[i], selections[i - 1])) {
          immediateRepeats++;
        }
      }
      expect(immediateRepeats, equals(0),
          reason: 'With 100 photos, should never repeat immediately');
    });

    test('should apply soft cooldown penalty to recently shown photos', () {
      final strategy = WeightedFreshnessStrategy();
      final photos = List.generate(10, (i) {
        return PhotoEntry(
          file: File('/fake/photo_$i.jpg'),
          date: DateTime.now(), // All same age
          sizeBytes: 1024,
        );
      });

      // Select first photo
      final first = strategy.nextPhoto(photos);
      expect(first, isNotNull);

      // Run 100 selections and count how often the first photo appears
      int firstPhotoCount = 0;
      for (int i = 0; i < 100; i++) {
        final photo = strategy.nextPhoto(photos);
        if (identical(photo, first)) {
          firstPhotoCount++;
        }
      }

      // The first photo should appear less than average (10% would be 10 times)
      // With soft cooldown, it should be suppressed initially
      expect(firstPhotoCount, lessThan(15),
          reason: 'Recently shown photo should have reduced probability due to soft cooldown');
    });

    test('should maintain randomness even with cooldown', () {
      final strategy = WeightedFreshnessStrategy();
      final photos = List.generate(10, (i) {
        return PhotoEntry(
          file: File('/fake/photo_$i.jpg'),
          date: DateTime.now(), // All same age = same base weight
          sizeBytes: 1024,
        );
      });

      final selectionCounts = <PhotoEntry, int>{};
      for (int i = 0; i < 200; i++) {
        final photo = strategy.nextPhoto(photos);
        if (photo != null) {
          selectionCounts[photo] = (selectionCounts[photo] ?? 0) + 1;
        }
      }

      // All photos should be selected
      expect(selectionCounts.length, equals(10));

      // No photo should dominate (> 30% of selections)
      for (final count in selectionCounts.values) {
        expect(count, lessThan(60),
            reason: 'No single photo should be selected more than 30% of the time');
      }

      // No photo should be neglected (< 5% of selections)
      for (final count in selectionCounts.values) {
        expect(count, greaterThan(10),
            reason: 'All photos should be selected at least 5% of the time');
      }
    });
  });
}
