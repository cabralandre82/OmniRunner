import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_settings_entity.dart';

/// L21-06 — Polyline GPS resolution.
///
/// These tests pin the "standard vs. performance" recording-mode
/// presets so we can never silently widen the default filter (which
/// would regress battery) or narrow it (which would lose the
/// Athlete-Pro biomechanical resolution). They are the authoritative
/// spec for the numbers quoted in the finding note + runbook refs.
void main() {
  group('LocationSettingsEntity — defaults (L21-06)', () {
    test('default constructor preserves pre-L21-06 behaviour (5m / high / standard)', () {
      const settings = LocationSettingsEntity();

      expect(settings.distanceFilterMeters, 5.0);
      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.mode, RecordingMode.standard);
    });

    test('.standard() factory matches the default constructor', () {
      const defaultSettings = LocationSettingsEntity();
      const standard = LocationSettingsEntity.standard();

      expect(standard, equals(defaultSettings));
      expect(standard.distanceFilterMeters, 5.0);
      expect(standard.accuracy, LocationAccuracy.high);
      expect(standard.mode, RecordingMode.standard);
    });
  });

  group('LocationSettingsEntity — performance preset (L21-06)', () {
    test('.performance() uses 1m filter + bestForNavigation', () {
      const perf = LocationSettingsEntity.performance();

      expect(perf.distanceFilterMeters, 1.0);
      expect(perf.accuracy, LocationAccuracy.bestForNavigation);
      expect(perf.mode, RecordingMode.performance);
    });

    test('.performance() differs from .standard() on every field', () {
      const standard = LocationSettingsEntity.standard();
      const perf = LocationSettingsEntity.performance();

      expect(perf, isNot(equals(standard)));
      expect(perf.distanceFilterMeters, isNot(standard.distanceFilterMeters));
      expect(perf.accuracy, isNot(standard.accuracy));
      expect(perf.mode, isNot(standard.mode));
    });

    test('.performance() filter is strictly finer than .standard()', () {
      const standard = LocationSettingsEntity.standard();
      const perf = LocationSettingsEntity.performance();

      expect(perf.distanceFilterMeters, lessThan(standard.distanceFilterMeters));
    });
  });

  group('LocationSettingsEntity — copyWith', () {
    test('copyWith with no arguments returns an equal instance', () {
      const original = LocationSettingsEntity.performance();
      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('copyWith replaces only the provided fields', () {
      const original = LocationSettingsEntity.standard();

      final tweaked = original.copyWith(distanceFilterMeters: 2.5);
      expect(tweaked.distanceFilterMeters, 2.5);
      expect(tweaked.accuracy, original.accuracy);
      expect(tweaked.mode, original.mode);

      final modeOnly = original.copyWith(mode: RecordingMode.performance);
      expect(modeOnly.mode, RecordingMode.performance);
      expect(modeOnly.distanceFilterMeters, original.distanceFilterMeters);
      expect(modeOnly.accuracy, original.accuracy);
    });
  });

  group('LocationSettingsEntity — Equatable', () {
    test('two instances with same values are equal', () {
      const a = LocationSettingsEntity(
        distanceFilterMeters: 3.0,
        accuracy: LocationAccuracy.medium,
        mode: RecordingMode.standard,
      );
      const b = LocationSettingsEntity(
        distanceFilterMeters: 3.0,
        accuracy: LocationAccuracy.medium,
        mode: RecordingMode.standard,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('mode contributes to equality', () {
      const a = LocationSettingsEntity(
        distanceFilterMeters: 5.0,
        accuracy: LocationAccuracy.high,
        mode: RecordingMode.standard,
      );
      const b = LocationSettingsEntity(
        distanceFilterMeters: 5.0,
        accuracy: LocationAccuracy.high,
        mode: RecordingMode.performance,
      );

      expect(a, isNot(equals(b)));
    });
  });

  group('LocationAccuracy enum (L21-06)', () {
    test('exposes exactly the 4 domain-agnostic levels', () {
      expect(LocationAccuracy.values, hasLength(4));
      expect(LocationAccuracy.values, containsAll(<LocationAccuracy>[
        LocationAccuracy.low,
        LocationAccuracy.medium,
        LocationAccuracy.high,
        LocationAccuracy.bestForNavigation,
      ]));
    });
  });

  group('RecordingMode enum (L21-06)', () {
    test('exposes exactly standard + performance', () {
      expect(RecordingMode.values, hasLength(2));
      expect(RecordingMode.values, containsAll(<RecordingMode>[
        RecordingMode.standard,
        RecordingMode.performance,
      ]));
    });
  });
}
