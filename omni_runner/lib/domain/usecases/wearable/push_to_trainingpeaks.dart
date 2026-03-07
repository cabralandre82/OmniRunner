import 'package:omni_runner/domain/repositories/i_trainingpeaks_repo.dart';

class PushToTrainingPeaks {
  final ITrainingPeaksRepo _repo;

  const PushToTrainingPeaks(this._repo);

  Future<Map<String, dynamic>> call(String assignmentId) async {
    return _repo.pushAssignment(assignmentId);
  }
}
