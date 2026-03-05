import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';

final class CreateTrainingSession {
  final ITrainingSessionRepo _repo;

  const CreateTrainingSession({required ITrainingSessionRepo repo}) : _repo = repo;

  Future<TrainingSessionEntity> call({
    required String id,
    required String groupId,
    required String createdBy,
    required String title,
    String? description,
    required DateTime startsAt,
    DateTime? endsAt,
    String? locationName,
    double? locationLat,
    double? locationLng,
    double? distanceTargetM,
    double? paceMinSecKm,
    double? paceMaxSecKm,
  }) async {
    if (title.trim().length < 2) {
      throw ArgumentError('Title must be at least 2 characters');
    }
    if (endsAt != null && endsAt.isBefore(startsAt)) {
      throw ArgumentError('endsAt must be after startsAt');
    }

    final now = DateTime.now();
    final session = TrainingSessionEntity(
      id: id,
      groupId: groupId,
      createdBy: createdBy,
      title: title.trim(),
      description: description?.trim(),
      startsAt: startsAt,
      endsAt: endsAt,
      locationName: locationName?.trim(),
      locationLat: locationLat,
      locationLng: locationLng,
      distanceTargetM: distanceTargetM,
      paceMinSecKm: paceMinSecKm,
      paceMaxSecKm: paceMaxSecKm,
      createdAt: now,
      updatedAt: now,
    );

    return _repo.create(session);
  }
}
