import 'package:omni_runner/domain/failures/sync_failure.dart';

/// Contract for synchronising workout sessions with the backend.
///
/// Domain interface. Implementation lives in data layer (Supabase).
/// All methods return `SyncFailure?` — null on success.
abstract interface class ISyncRepo {
  /// Mark a completed session as pending sync.
  ///
  /// Does nothing if the session is already queued or synced.
  Future<void> enqueue(String sessionId);

  /// Attempt to upload all pending sessions to the backend.
  ///
  /// Processes sessions sequentially. If one fails, continues with
  /// the next and returns the first failure encountered.
  /// Returns `null` when all pending sessions are synced.
  Future<SyncFailure?> syncPending();

  /// Mark a session as successfully synced locally.
  ///
  /// Called internally by [syncPending] after a successful upload.
  /// Exposed for testability and manual recovery scenarios.
  Future<void> markSynced(String sessionId);
}
