import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/domain/usecases/workout/create_template.dart';

class _FakeWorkoutRepo implements IWorkoutRepo {
  WorkoutTemplateEntity? saved;

  @override
  Future<WorkoutTemplateEntity> createTemplate(
      WorkoutTemplateEntity template) async {
    saved = template;
    return template;
  }

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
  Future<WorkoutAssignmentEntity> assignWorkout({
    required String templateId,
    required String athleteUserId,
    required DateTime scheduledDate,
    String? notes,
  }) async =>
      throw UnimplementedError();
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
  late CreateTemplate usecase;

  setUp(() {
    repo = _FakeWorkoutRepo();
    usecase = CreateTemplate(repo: repo);
  });

  test('creates template with valid data', () async {
    final result = await usecase.call(
      id: 'tpl-1',
      groupId: 'group-1',
      createdBy: 'coach-1',
      name: 'Long Run',
      description: 'Weekend long run template',
    );

    expect(result.id, 'tpl-1');
    expect(result.groupId, 'group-1');
    expect(result.name, 'Long Run');
    expect(result.description, 'Weekend long run template');
    expect(repo.saved, isNotNull);
  });

  test('trims whitespace from name', () async {
    final result = await usecase.call(
      id: 'tpl-2',
      groupId: 'group-1',
      createdBy: 'coach-1',
      name: '  Tempo Run  ',
    );

    expect(result.name, 'Tempo Run');
  });

  test('creates template without description', () async {
    final result = await usecase.call(
      id: 'tpl-3',
      groupId: 'group-1',
      createdBy: 'coach-1',
      name: 'Recovery',
    );

    expect(result.description, isNull);
  });

  test('throws when name is too short', () {
    expect(
      () => usecase.call(
        id: 'tpl-4',
        groupId: 'group-1',
        createdBy: 'coach-1',
        name: 'X',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when name is only whitespace', () {
    expect(
      () => usecase.call(
        id: 'tpl-5',
        groupId: 'group-1',
        createdBy: 'coach-1',
        name: '   ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
