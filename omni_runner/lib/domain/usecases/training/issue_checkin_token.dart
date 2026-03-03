import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';

final class IssueCheckinToken {
  final ITrainingAttendanceRepo _repo;

  const IssueCheckinToken({required ITrainingAttendanceRepo repo}) : _repo = repo;

  Future<CheckinToken> call({
    required String sessionId,
    int ttlSeconds = 120,
  }) {
    return _repo.issueCheckinToken(
      sessionId: sessionId,
      ttlSeconds: ttlSeconds,
    );
  }
}
