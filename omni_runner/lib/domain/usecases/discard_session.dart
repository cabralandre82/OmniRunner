import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';

/// Safely discards a workout session and all its associated data.
///
/// Deletes points first, then the session record.
/// Order matters: if session is deleted first and points deletion fails,
/// orphan points would remain with no parent session.
///
/// Conforms to [O4]: single `call()` method.
final class DiscardSession {
  static const _tag = 'DiscardSession';

  final ISessionRepo _sessionRepo;
  final IPointsRepo _pointsRepo;

  const DiscardSession({
    required ISessionRepo sessionRepo,
    required IPointsRepo pointsRepo,
  })  : _sessionRepo = sessionRepo,
        _pointsRepo = pointsRepo;

  /// Discard a session by its unique id.
  ///
  /// Returns `true` if the session existed and was deleted.
  /// Returns `false` if no session with this id was found.
  ///
  /// Deletion order: points first (children), then session (parent).
  Future<bool> call(String sessionId) async {
    try {
      final session = await _sessionRepo.getById(sessionId);
      if (session == null) return false;

      await _pointsRepo.deleteBySessionId(sessionId);
      await _sessionRepo.deleteById(sessionId);

      return true;
    } on Exception catch (e, st) {
      AppLogger.error(
        'Failed to discard session $sessionId',
        tag: _tag,
        error: e,
        stack: st,
      );
      return false;
    }
  }
}
