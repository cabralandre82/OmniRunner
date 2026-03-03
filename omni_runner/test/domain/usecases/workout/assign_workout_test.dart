import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/domain/usecases/workout/assign_workout.dart';

class _FakeWorkoutRepo implements IWorkoutRepo {
  String? lastTemplateId;
  String? lastAthleteUserId;
  DateTime? lastScheduledDate;
  String? lastNotes;

  @override
  Future<WorkoutAssignmentEntity> assignWorkout({
    required String templateId,
    required String athleteUserId,
    required DateTime scheduledDate,
    String? notes,
  }) async {
    lastTemplateId = templateId;
    lastAthleteUserId = athleteUserId;
    lastScheduledDate = scheduledDate;
    lastNotes = notes;
    return WorkoutAssignmentEntity(
      id: 'assign-1',
      groupId: 'group-1',
      athleteUserId: athleteUserId,
      templateId: templateId,
      scheduledDate: scheduledDate,
      status: WorkoutAssignmentStatus.planned,
      notes: notes,
      createdBy: 'coach-1',
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<WorkoutTemplateEntity> createTemplate(
          WorkoutTemplateEntity template) async =>
      template;
  @override
  Future<WorkoutTemplateEntity> updateTemplate(
          WorkoutTemplateEntity template) async =>
      template;
  @override
  Future<void> deleteTemplate(String templateId) async {}
  @override
  Future<List<WorkoutTemplateEntity>> listTemplates(String groupId) async => [];
  @override
  Future<WorkoutTemplateEntity?> getTemplateById(String templateId) async =>
      null;
  @override
  Future<void> saveBlocks(
          String templateId, List<WorkoutBlockEntity> blocks) async {}
  @override
  Future<List<WorkoutAssignmentEntity>> listAssignmentsByGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];
  @override
  Future<List<WorkoutAssignmentEntity>> listAssignmentsByAthlete({
    required String groupId,
    required String athleteUserId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];
  @override
  Future<void> updateAssignmentStatus(
          String assignmentId, WorkoutAssignmentStatus status) async {}
}

void main() {
  late _FakeWorkoutRepo repo;
  late AssignWorkout usecase;

  setUp(() {
    repo = _FakeWorkoutRepo();
    usecase = AssignWorkout(repo: repo);
  });

  test('assigns workout to athlete', () async {
    final date = DateTime(2026, 4, 5);
    final result = await usecase.call(
      templateId: 'tpl-1',
      athleteUserId: 'athlete-1',
      scheduledDate: date,
      notes: 'Take it easy',
    );

    expect(result.templateId, 'tpl-1');
    expect(result.athleteUserId, 'athlete-1');
    expect(result.scheduledDate, date);
    expect(result.notes, 'Take it easy');
    expect(result.status, WorkoutAssignmentStatus.planned);
  });

  test('assigns workout without notes', () async {
    final date = DateTime(2026, 4, 6);
    final result = await usecase.call(
      templateId: 'tpl-1',
      athleteUserId: 'athlete-2',
      scheduledDate: date,
    );

    expect(result.notes, isNull);
    expect(repo.lastNotes, isNull);
  });

  test('passes correct parameters to repo', () async {
    final date = DateTime(2026, 4, 7);
    await usecase.call(
      templateId: 'tpl-2',
      athleteUserId: 'athlete-3',
      scheduledDate: date,
      notes: 'Focus on form',
    );

    expect(repo.lastTemplateId, 'tpl-2');
    expect(repo.lastAthleteUserId, 'athlete-3');
    expect(repo.lastScheduledDate, date);
    expect(repo.lastNotes, 'Focus on form');
  });
}
