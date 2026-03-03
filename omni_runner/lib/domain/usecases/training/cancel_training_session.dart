import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';

final class CancelTrainingSession {
  final ITrainingSessionRepo _repo;

  const CancelTrainingSession({required ITrainingSessionRepo repo}) : _repo = repo;

  Future<void> call({required String sessionId}) {
    return _repo.cancel(sessionId);
  }
}
