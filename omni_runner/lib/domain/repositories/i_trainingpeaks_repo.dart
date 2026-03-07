abstract interface class ITrainingPeaksRepo {
  Future<Map<String, dynamic>> pushAssignment(String assignmentId);
}
