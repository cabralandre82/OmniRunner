import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';

final class MarkAttendance {
  final ITrainingAttendanceRepo _repo;

  const MarkAttendance({required ITrainingAttendanceRepo repo}) : _repo = repo;

  Future<MarkAttendanceResult> call({
    required String sessionId,
    required String athleteUserId,
    String? nonce,
  }) {
    return _repo.markAttendance(
      sessionId: sessionId,
      athleteUserId: athleteUserId,
      nonce: nonce,
    );
  }
}
