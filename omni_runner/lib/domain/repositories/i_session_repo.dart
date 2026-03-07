import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';

/// Contract for persisting and retrieving workout sessions.
///
/// Domain interface. Implementation lives in data layer.
/// All methods are async for compatibility with any storage backend.
///
/// Dependency direction: data → domain (implements this).
abstract interface class ISessionRepo {
  /// Save a new session or update an existing one.
  ///
  /// Uses [WorkoutSessionEntity.id] as the unique key.
  /// If a session with this id exists, it is overwritten.
  Future<void> save(WorkoutSessionEntity session);

  /// Retrieve a session by its unique id.
  ///
  /// Returns `null` if no session with this id exists.
  Future<WorkoutSessionEntity?> getById(String id);

  /// Retrieve all sessions, ordered by start time descending (newest first).
  Future<List<WorkoutSessionEntity>> getAll();

  /// Retrieve sessions filtered by status.
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus status);

  /// Delete a session by its unique id.
  ///
  /// Also deletes associated location points (cascade).
  Future<void> deleteById(String id);

  /// Update only the status of a session.
  ///
  /// Returns `true` if the session was found and updated.
  Future<bool> updateStatus(String id, WorkoutStatus status);

  /// Update metrics on a session (distance, moving time).
  ///
  /// Used during tracking to persist accumulated metrics.
  Future<bool> updateMetrics({
    required String id,
    required double totalDistanceM,
    required int movingMs,
    int? endTimeMs,
  });

  /// Store the ghost session ID that this run was compared against.
  Future<bool> updateGhostSessionId(String id, String ghostSessionId);

  /// Update anti-cheat verification result for a session.
  Future<bool> updateIntegrityFlags(
    String id, {
    required bool isVerified,
    required List<String> flags,
  });

  /// Update heart rate metrics for a session.
  ///
  /// Called on session finish to persist avg/max HR from the run.
  Future<bool> updateHrMetrics(
    String id, {
    required int avgBpm,
    required int maxBpm,
  });

  /// Retrieve completed sessions that haven't been synced yet.
  Future<List<WorkoutSessionEntity>> getUnsyncedCompleted();

  /// Mark a session as synced.
  Future<void> markSynced(String id);
}
