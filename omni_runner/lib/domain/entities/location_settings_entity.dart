import 'package:equatable/equatable.dart';

/// Configuration for GPS location tracking.
///
/// Immutable value object. No logic. No behavior.
/// Used as parameter for [ILocationStream.watch].
///
/// ### L21-06 — Recording modes (Athlete Pro)
///
/// Default (`standard`) mode samples every 5 meters — fine for casual
/// runners and to preserve battery. Elite / biomechanical analysis
/// users need a much finer polyline: at sprint speed (~12 m/s), a 5 m
/// filter gives one point every ~0.4 s which is too coarse for
/// stride/ground-contact analytics and for replay smoothness.
///
/// [RecordingMode.performance] raises the sampling to 1 m filter +
/// `LocationAccuracy.bestForNavigation` (multi-constellation GNSS on
/// capable devices). Trade-off: ~+30 % battery and ~3-5× storage.
/// Performance mode is opt-in — the UI exposes a toggle in run
/// settings; the default constructor preserves the previous behaviour.
///
/// CI guard: N/A — covered by the domain unit tests
///   `test/domain/entities/location_settings_entity_test.dart`.
/// Finding: docs/audit/findings/L21-06-polyline-gps-resolucao-baixa-5m-distancefilter.md
final class LocationSettingsEntity extends Equatable {
  /// Minimum distance in meters between location updates.
  final double distanceFilterMeters;

  /// Desired accuracy level for GPS readings.
  final LocationAccuracy accuracy;

  /// Recording mode — `standard` for casual runners (5 m filter,
  /// battery-friendly), `performance` for elite athletes who need a
  /// dense polyline for biomechanical / replay analysis (1 m filter,
  /// bestForNavigation accuracy, ~+30 % battery).
  ///
  /// Adding the mode here keeps the entity immutable — each mode is
  /// a distinct const value — while still giving consumers a single
  /// boolean-like switch (`mode == RecordingMode.performance`) if
  /// they need mode-aware UI (e.g., battery-warning banner).
  final RecordingMode mode;

  /// Default constructor — explicit fields. Callers should prefer
  /// the [LocationSettingsEntity.standard] / [.performance] factories
  /// which encode the L21-06 presets.
  const LocationSettingsEntity({
    this.distanceFilterMeters = 5.0,
    this.accuracy = LocationAccuracy.high,
    this.mode = RecordingMode.standard,
  });

  /// Battery-friendly default for casual runners (5 m filter,
  /// high accuracy, standard mode). Equivalent to
  /// `const LocationSettingsEntity()` and kept as a named
  /// constructor for parity with [.performance].
  const LocationSettingsEntity.standard()
      : distanceFilterMeters = 5.0,
        accuracy = LocationAccuracy.high,
        mode = RecordingMode.standard;

  /// Elite / Athlete-Pro preset — 1 m filter +
  /// [LocationAccuracy.bestForNavigation]. Intended for time-trial
  /// runs and biomechanical analysis. Documented trade-off: battery
  /// drain is ~+30 % vs. [.standard] and GPS point volume ~3-5×;
  /// the UI must surface that before the user opts in.
  const LocationSettingsEntity.performance()
      : distanceFilterMeters = 1.0,
        accuracy = LocationAccuracy.bestForNavigation,
        mode = RecordingMode.performance;

  /// Convenience copy-with used by the settings screen to tweak a
  /// single knob without rebuilding the whole object (e.g., letting
  /// QA override the distance filter on the performance preset).
  LocationSettingsEntity copyWith({
    double? distanceFilterMeters,
    LocationAccuracy? accuracy,
    RecordingMode? mode,
  }) {
    return LocationSettingsEntity(
      distanceFilterMeters: distanceFilterMeters ?? this.distanceFilterMeters,
      accuracy: accuracy ?? this.accuracy,
      mode: mode ?? this.mode,
    );
  }

  @override
  List<Object?> get props => [distanceFilterMeters, accuracy, mode];
}

/// Desired accuracy level for GPS location readings.
///
/// Platform-agnostic. Maps to platform-specific values in infrastructure.
enum LocationAccuracy {
  /// Battery-optimized. ~100m accuracy. Not suitable for run tracking.
  low,

  /// Balanced. ~10-50m accuracy.
  medium,

  /// Best available fused provider. ~3-10m accuracy. Default for run
  /// tracking on [RecordingMode.standard].
  high,

  /// Finest accuracy the platform can provide — iOS enables multi-
  /// constellation GNSS, Android uses the highest-priority fused
  /// provider. Used by [RecordingMode.performance]; more battery
  /// intensive than [high].
  bestForNavigation,
}

/// Recording mode selected by the athlete for a workout session.
///
/// Each mode encodes a (distanceFilter, accuracy) pair that lives on
/// [LocationSettingsEntity]. Keeping the enum separate lets UI code
/// switch on the mode without touching the numerics (and keeps the
/// display labels / battery-warning copy in the presentation layer).
enum RecordingMode {
  /// Default. Battery-friendly sampling — 5 m displacement filter,
  /// [LocationAccuracy.high]. Suitable for ~99 % of workouts.
  standard,

  /// Elite preset. 1 m displacement filter +
  /// [LocationAccuracy.bestForNavigation]. ~+30 % battery, ~3-5×
  /// GPS point volume. Opt-in only; UI must warn about battery /
  /// storage before enabling.
  performance,
}
