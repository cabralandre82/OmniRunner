import 'package:omni_runner/domain/entities/training_attendance_entity.dart';

/// Result of a mark-attendance RPC call.
sealed class MarkAttendanceResult {
  const MarkAttendanceResult();
}

final class AttendanceInserted extends MarkAttendanceResult {
  final String attendanceId;
  const AttendanceInserted(this.attendanceId);
}

final class AttendanceAlreadyPresent extends MarkAttendanceResult {
  const AttendanceAlreadyPresent();
}

final class AttendanceFailed extends MarkAttendanceResult {
  final String code;
  final String message;
  const AttendanceFailed(this.code, this.message);
}

/// Result of issuing a checkin token.
final class CheckinToken {
  final String sessionId;
  final String athleteUserId;
  final String groupId;
  final String nonce;
  final int expiresAtMs;

  const CheckinToken({
    required this.sessionId,
    required this.athleteUserId,
    required this.groupId,
    required this.nonce,
    required this.expiresAtMs,
  });

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAtMs;
}

abstract interface class ITrainingAttendanceRepo {
  /// Mark attendance via RPC (idempotent).
  Future<MarkAttendanceResult> markAttendance({
    required String sessionId,
    required String athleteUserId,
    String? nonce,
  });

  /// Issue a checkin token for the current authenticated athlete.
  Future<CheckinToken> issueCheckinToken({
    required String sessionId,
    int ttlSeconds = 120,
  });

  /// List attendance for a training session.
  Future<List<TrainingAttendanceEntity>> listBySession(String sessionId);

  /// List attendance for the current athlete across sessions.
  Future<List<TrainingAttendanceEntity>> listByAthlete({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  });

  /// Count attendance for a session.
  Future<int> countBySession(String sessionId);
}
