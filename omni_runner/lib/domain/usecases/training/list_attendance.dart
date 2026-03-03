import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';

final class ListAttendance {
  final ITrainingAttendanceRepo _repo;

  const ListAttendance({required ITrainingAttendanceRepo repo}) : _repo = repo;

  /// List all attendance records for a specific training session.
  Future<List<TrainingAttendanceEntity>> bySession(String sessionId) {
    return _repo.listBySession(sessionId);
  }

  /// List attendance for a specific athlete across all sessions in a group.
  Future<List<TrainingAttendanceEntity>> byAthlete({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) {
    return _repo.listByAthlete(
      groupId: groupId,
      athleteUserId: athleteUserId,
      limit: limit,
      offset: offset,
    );
  }
}
