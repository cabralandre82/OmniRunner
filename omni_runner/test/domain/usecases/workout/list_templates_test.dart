import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/domain/usecases/workout/list_templates.dart';

WorkoutTemplateEntity _template(String id, String groupId) =>
    WorkoutTemplateEntity(
      id: id,
      groupId: groupId,
      name: 'Template $id',
      createdBy: 'coach-1',
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );

class _FakeWorkoutRepo implements IWorkoutRepo {
  final List<WorkoutTemplateEntity> templates = [];
  String? lastGroupId;

  @override
  Future<List<WorkoutTemplateEntity>> listTemplates(String groupId) async {
    lastGroupId = groupId;
    return templates.where((t) => t.groupId == groupId).toList();
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
  late ListTemplates usecase;

  setUp(() {
    repo = _FakeWorkoutRepo();
    usecase = ListTemplates(repo: repo);
  });

  test('returns empty list when no templates exist', () async {
    final result = await usecase.call(groupId: 'group-1');
    expect(result, isEmpty);
  });

  test('returns templates for the given group', () async {
    repo.templates.addAll([
      _template('t1', 'group-1'),
      _template('t2', 'group-1'),
      _template('t3', 'group-2'),
    ]);

    final result = await usecase.call(groupId: 'group-1');
    expect(result.length, 2);
    expect(result.every((t) => t.groupId == 'group-1'), isTrue);
  });

  test('passes group id to repo', () async {
    await usecase.call(groupId: 'group-42');
    expect(repo.lastGroupId, 'group-42');
  });
}
