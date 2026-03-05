import 'package:flutter_test/flutter_test.dart';

void main() {
  const fitProviders = {'garmin', 'coros', 'suunto'};

  String? resolveWatchType(String? manualType, String? linkedProvider) {
    if (manualType != null) return manualType;
    if (linkedProvider == null) return null;
    return switch (linkedProvider) {
      'garmin' => 'garmin',
      'apple' => 'apple_watch',
      'polar' => 'polar',
      'suunto' => 'suunto',
      _ => null,
    };
  }

  bool isFitCompatible(String? watchType) =>
      fitProviders.contains(watchType);

  group('Watch type resolution', () {
    test('manual override takes precedence over device link', () {
      expect(resolveWatchType('coros', 'garmin'), 'coros');
    });

    test('falls back to device link when manual is null', () {
      expect(resolveWatchType(null, 'garmin'), 'garmin');
      expect(resolveWatchType(null, 'apple'), 'apple_watch');
      expect(resolveWatchType(null, 'polar'), 'polar');
      expect(resolveWatchType(null, 'suunto'), 'suunto');
    });

    test('returns null when both are null', () {
      expect(resolveWatchType(null, null), isNull);
    });

    test('returns null for unknown provider', () {
      expect(resolveWatchType(null, 'unknown_brand'), isNull);
    });
  });

  group('FIT compatibility', () {
    test('garmin is FIT compatible', () {
      expect(isFitCompatible('garmin'), true);
    });

    test('coros is FIT compatible', () {
      expect(isFitCompatible('coros'), true);
    });

    test('suunto is FIT compatible', () {
      expect(isFitCompatible('suunto'), true);
    });

    test('apple_watch is NOT FIT compatible', () {
      expect(isFitCompatible('apple_watch'), false);
    });

    test('polar is NOT FIT compatible', () {
      expect(isFitCompatible('polar'), false);
    });

    test('null is NOT FIT compatible', () {
      expect(isFitCompatible(null), false);
    });

    test('other is NOT FIT compatible', () {
      expect(isFitCompatible('other'), false);
    });
  });

  group('End-to-end scenarios', () {
    test('Garmin user via device link → show send to watch', () {
      final watch = resolveWatchType(null, 'garmin');
      expect(isFitCompatible(watch), true);
    });

    test('Apple Watch user via device link → hide send to watch', () {
      final watch = resolveWatchType(null, 'apple');
      expect(isFitCompatible(watch), false);
    });

    test('Coach overrides to coros → show send to watch', () {
      final watch = resolveWatchType('coros', null);
      expect(isFitCompatible(watch), true);
    });

    test('Coach overrides apple user to garmin → show send to watch', () {
      final watch = resolveWatchType('garmin', 'apple');
      expect(isFitCompatible(watch), true);
    });

    test('No device, no override → hide send to watch', () {
      final watch = resolveWatchType(null, null);
      expect(isFitCompatible(watch), false);
    });
  });
}
