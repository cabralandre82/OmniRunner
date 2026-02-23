import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// A complete workout session received from a watch (Apple Watch or WearOS).
///
/// Mirrors the JSON wire format defined in `docs/WatchArchitecture.md` §5
/// and produced by both native `toSessionJSON()` implementations:
/// - Apple Watch: `WatchWorkoutManager.toSessionJSON()`
/// - WearOS:      `WearWorkoutManager.toSessionJSON()`
///
/// Immutable value object — no side effects. Parsing happens in factory.
final class WatchSessionPayload extends Equatable {
  /// Wire format version (currently 1).
  final int version;

  /// Source platform: `"apple_watch"` or `"wear_os"`.
  final String source;

  /// Unique session identifier (UUID generated on the watch).
  final String sessionId;

  /// Start time in milliseconds since Unix epoch.
  final int startMs;

  /// End time in milliseconds since Unix epoch.
  final int endMs;

  /// Total distance in meters (Haversine-accumulated on watch).
  final double totalDistanceM;

  /// Moving time in milliseconds (excludes pauses).
  final int movingMs;

  /// Average heart rate in BPM. 0 if no HR data.
  final int avgBpm;

  /// Maximum heart rate in BPM. 0 if no HR data.
  final int maxBpm;

  /// Whether the watch marked this session as verified.
  final bool isVerified;

  /// Integrity flags raised during watch-side checks.
  final List<String> integrityFlags;

  /// GPS points captured during the session.
  final List<LocationPointEntity> points;

  /// Heart rate samples captured during the session.
  final List<HeartRateSample> hrSamples;

  const WatchSessionPayload({
    required this.version,
    required this.source,
    required this.sessionId,
    required this.startMs,
    required this.endMs,
    required this.totalDistanceM,
    required this.movingMs,
    required this.avgBpm,
    required this.maxBpm,
    required this.isVerified,
    required this.integrityFlags,
    required this.points,
    required this.hrSamples,
  });

  /// Parse a [WatchSessionPayload] from the raw JSON map received
  /// via MethodChannel from native code.
  ///
  /// Returns `null` if the map is malformed or missing required fields.
  static WatchSessionPayload? tryParse(Map<dynamic, dynamic> json) {
    try {
      final sessionId = json['sessionId'] as String?;
      if (sessionId == null || sessionId.isEmpty) return null;

      final rawPoints = json['points'] as List<dynamic>? ?? [];
      final rawHr = json['hrSamples'] as List<dynamic>? ?? [];

      return WatchSessionPayload(
        version: _intOr(json['version'], 1),
        source: (json['source'] as String?) ?? 'unknown',
        sessionId: sessionId,
        startMs: _intOr(json['startMs'], 0),
        endMs: _intOr(json['endMs'], 0),
        totalDistanceM: _doubleOr(json['totalDistanceM'], 0.0),
        movingMs: _intOr(json['movingMs'], 0),
        avgBpm: _intOr(json['avgBpm'], 0),
        maxBpm: _intOr(json['maxBpm'], 0),
        isVerified: (json['isVerified'] as bool?) ?? true,
        integrityFlags: (json['integrityFlags'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        points: rawPoints
            .map((p) => _parsePoint(p as Map<dynamic, dynamic>))
            .whereType<LocationPointEntity>()
            .toList(),
        hrSamples: rawHr
            .map((s) => _parseHrSample(s as Map<dynamic, dynamic>))
            .whereType<HeartRateSample>()
            .toList(),
      );
    } on Exception {
      return null;
    }
  }

  /// Duration of the session (wall-clock).
  Duration get duration => Duration(milliseconds: endMs - startMs);

  /// Moving duration (excluding pauses).
  Duration get movingDuration => Duration(milliseconds: movingMs);

  /// Whether this session has GPS data.
  bool get hasGps => points.isNotEmpty;

  /// Whether this session has heart rate data.
  bool get hasHr => hrSamples.isNotEmpty;

  // ── Private Parsers ──────────────────────────────────────────────

  static LocationPointEntity? _parsePoint(Map<dynamic, dynamic> m) {
    final lat = _doubleOrNull(m['lat']);
    final lng = _doubleOrNull(m['lng']);
    final ts = _intOrNull(m['timestampMs']);
    if (lat == null || lng == null || ts == null) return null;

    return LocationPointEntity(
      lat: lat,
      lng: lng,
      alt: _doubleOrNull(m['alt']),
      accuracy: _doubleOrNull(m['accuracy']),
      speed: _doubleOrNull(m['speed']),
      timestampMs: ts,
    );
  }

  static HeartRateSample? _parseHrSample(Map<dynamic, dynamic> m) {
    final bpm = _intOrNull(m['bpm']);
    final ts = _intOrNull(m['timestampMs']);
    if (bpm == null || ts == null) return null;

    return HeartRateSample(bpm: bpm, timestampMs: ts);
  }

  static int _intOr(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return fallback;
  }

  static int? _intOrNull(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return null;
  }

  static double _doubleOr(dynamic v, double fallback) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return fallback;
  }

  static double? _doubleOrNull(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return null;
  }

  @override
  List<Object?> get props => [
        version,
        source,
        sessionId,
        startMs,
        endMs,
        totalDistanceM,
        movingMs,
        avgBpm,
        maxBpm,
        isVerified,
        integrityFlags,
        points,
        hrSamples,
      ];
}

/// A live sample received from the watch during an active workout.
///
/// Lightweight snapshot — not persisted, used for real-time display only.
final class WatchLiveSample extends Equatable {
  final String sessionId;
  final int bpm;
  final double paceSecondsPerKm;
  final double distanceM;
  final int elapsedS;
  final int timestampMs;

  const WatchLiveSample({
    required this.sessionId,
    required this.bpm,
    required this.paceSecondsPerKm,
    required this.distanceM,
    required this.elapsedS,
    required this.timestampMs,
  });

  /// Parse from the raw map received via MethodChannel.
  static WatchLiveSample? tryParse(Map<dynamic, dynamic> json) {
    try {
      final sessionId = json['sessionId'] as String?;
      if (sessionId == null) return null;

      return WatchLiveSample(
        sessionId: sessionId,
        bpm: _intOr(json['bpm'], 0),
        paceSecondsPerKm: _doubleOr(json['pace'], 0.0),
        distanceM: _doubleOr(json['distanceM'], 0.0),
        elapsedS: _intOr(json['elapsedS'], 0),
        timestampMs: _intOr(json['timestampMs'], 0),
      );
    } on Exception {
      return null;
    }
  }

  static int _intOr(dynamic v, int fb) =>
      v is int ? v : (v is double ? v.toInt() : fb);

  static double _doubleOr(dynamic v, double fb) =>
      v is double ? v : (v is int ? v.toDouble() : fb);

  @override
  List<Object?> get props =>
      [sessionId, bpm, paceSecondsPerKm, distanceM, elapsedS, timestampMs];
}

/// Watch workout state received via applicationContext / DataItem.
final class WatchWorkoutState extends Equatable {
  final String sessionId;

  /// One of: `"running"`, `"paused"`, `"ended"`.
  final String state;
  final int timestampMs;

  const WatchWorkoutState({
    required this.sessionId,
    required this.state,
    required this.timestampMs,
  });

  static WatchWorkoutState? tryParse(Map<dynamic, dynamic> json) {
    try {
      final sessionId = json['sessionId'] as String?;
      final state = json['state'] as String?;
      if (sessionId == null || state == null) return null;

      return WatchWorkoutState(
        sessionId: sessionId,
        state: state,
        timestampMs: json['timestampMs'] is int
            ? json['timestampMs'] as int
            : (json['timestampMs'] is double
                ? (json['timestampMs'] as double).toInt()
                : 0),
      );
    } on Exception {
      return null;
    }
  }

  bool get isRunning => state == 'running';
  bool get isPaused => state == 'paused';
  bool get isEnded => state == 'ended';

  @override
  List<Object?> get props => [sessionId, state, timestampMs];
}
