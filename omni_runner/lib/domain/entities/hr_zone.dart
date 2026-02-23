/// Standard 5-zone heart-rate model based on percentage of max HR.
///
/// Zone boundaries follow the widely used Karvonen / ACSM convention:
///
/// | Zone | %HRmax     | Description                  |
/// |------|------------|------------------------------|
/// |  1   | 50 – 60 %  | Recovery / warm-up           |
/// |  2   | 60 – 70 %  | Fat burn / easy aerobic      |
/// |  3   | 70 – 80 %  | Aerobic / tempo              |
/// |  4   | 80 – 90 %  | Threshold / hard              |
/// |  5   | 90 – 100 % | VO₂ max / anaerobic          |
///
/// Values below zone 1 are mapped to [belowZones],
/// values above zone 5 are clamped to zone 5.
enum HrZone {
  belowZones,
  zone1,
  zone2,
  zone3,
  zone4,
  zone5;

  /// Human-readable label in Portuguese.
  String get label => switch (this) {
        belowZones => 'Abaixo das zonas',
        zone1 => 'Zona 1 — Recuperação',
        zone2 => 'Zona 2 — Aeróbico leve',
        zone3 => 'Zona 3 — Aeróbico',
        zone4 => 'Zona 4 — Limiar',
        zone5 => 'Zona 5 — VO₂ máx',
      };

  /// Numeric zone number (0 for belowZones).
  int get number => switch (this) {
        belowZones => 0,
        zone1 => 1,
        zone2 => 2,
        zone3 => 3,
        zone4 => 4,
        zone5 => 5,
      };
}

/// Computes the [HrZone] for a given BPM and max heart rate.
///
/// Uses the standard percentage-of-max-HR formula:
///   `%HRmax = bpm / maxHr`
///
/// If [maxHr] is <= 0 or [bpm] is <= 0, returns [HrZone.belowZones].
///
/// The default [maxHr] can be estimated with `220 - age`.
final class HrZoneCalculator {
  /// User's maximum heart rate.
  final int maxHr;

  const HrZoneCalculator({required this.maxHr});

  /// Convenience factory using the age-based formula `220 - age`.
  factory HrZoneCalculator.fromAge(int age) =>
      HrZoneCalculator(maxHr: 220 - age);

  /// Returns the [HrZone] for the given [bpm].
  HrZone zoneFor(int bpm) {
    if (maxHr <= 0 || bpm <= 0) return HrZone.belowZones;

    final pct = bpm / maxHr;

    if (pct >= 0.90) return HrZone.zone5;
    if (pct >= 0.80) return HrZone.zone4;
    if (pct >= 0.70) return HrZone.zone3;
    if (pct >= 0.60) return HrZone.zone2;
    if (pct >= 0.50) return HrZone.zone1;
    return HrZone.belowZones;
  }

  /// Returns the BPM range (inclusive) for the given [zone].
  ///
  /// Returns `null` for [HrZone.belowZones] since it has no lower bound.
  ({int low, int high})? bpmRangeFor(HrZone zone) {
    if (maxHr <= 0) return null;
    return switch (zone) {
      HrZone.belowZones => null,
      HrZone.zone1 => (low: (maxHr * 0.50).ceil(), high: (maxHr * 0.60).floor()),
      HrZone.zone2 => (low: (maxHr * 0.60).ceil(), high: (maxHr * 0.70).floor()),
      HrZone.zone3 => (low: (maxHr * 0.70).ceil(), high: (maxHr * 0.80).floor()),
      HrZone.zone4 => (low: (maxHr * 0.80).ceil(), high: (maxHr * 0.90).floor()),
      HrZone.zone5 => (low: (maxHr * 0.90).ceil(), high: maxHr),
    };
  }
}
