import 'package:isar/isar.dart';

part 'workout_session_record.g.dart';

/// Isar collection for persisting workout sessions.
///
/// Location points are stored separately in [LocationPointRecord]
/// and linked via [sessionUuid] ↔ sessionId.
///
/// Maps to/from [WorkoutSessionEntity] in the domain layer.
///
/// Status int mapping (matches [WorkoutStatus] enum ordinal):
///   0 = initial, 1 = running, 2 = paused,
///   3 = completed, 4 = discarded
@collection
class WorkoutSessionRecord {
  /// Auto-incremented Isar primary key.
  Id isarId = Isar.autoIncrement;

  /// Application-level unique identifier (UUID v4).
  /// Used as foreign key reference from LocationPointRecord.sessionId.
  @Index(unique: true)
  late String sessionUuid;

  /// Owner user ID. Null if not yet synced / no auth.
  String? userId;

  /// Workout status as integer (see class doc for mapping).
  @Index()
  late int status;

  /// Start time in milliseconds since Unix epoch (UTC).
  @Index()
  late int startTimeMs;

  /// End time in milliseconds since Unix epoch (UTC).
  /// Null if session is still active.
  int? endTimeMs;

  /// Total accumulated distance in meters (filtered).
  late double totalDistanceM;

  /// Time spent moving in milliseconds (excludes pauses).
  late int movingMs;

  /// Whether this session has passed anti-cheat verification.
  @Index()
  late bool isVerified;

  /// Whether this session has been synced to the server.
  @Index()
  late bool isSynced;

  /// ID of the ghost session this run was compared against. Null if no ghost.
  String? ghostSessionId;

  /// Human-readable integrity flags raised during verification.
  /// Empty list = no issues. Stored as native Isar List<String>.
  List<String> integrityFlags = const [];

  /// Average heart rate in BPM. Null if no HR data was collected.
  int? avgBpm;

  /// Maximum heart rate in BPM. Null if no HR data was collected.
  int? maxBpm;

  /// Average running cadence in steps per minute. Null if unavailable.
  double? avgCadenceSpm;

  /// Origin: 'app', 'strava', 'watch', 'manual'.
  String source = 'app';

  /// Device that recorded the session (e.g. "Garmin Forerunner 265").
  String? deviceName;
}
