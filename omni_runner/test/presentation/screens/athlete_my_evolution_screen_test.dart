import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/presentation/screens/athlete_my_evolution_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeCrmRepo implements ICrmRepo {
  final MemberStatusEntity? statusResult;
  final List<CoachingTagEntity> tagsResult;
  final Object? error;

  _FakeCrmRepo({this.statusResult, this.tagsResult = const [], this.error});

  @override
  Future<MemberStatusEntity?> getStatus({
    required String groupId,
    required String userId,
  }) async {
    if (error != null) throw error!;
    return statusResult;
  }

  @override
  Future<List<CoachingTagEntity>> getAthleteTags({
    required String groupId,
    required String athleteUserId,
  }) async {
    if (error != null) throw error!;
    return tagsResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAttendanceRepo implements ITrainingAttendanceRepo {
  final List<TrainingAttendanceEntity> result;

  _FakeAttendanceRepo({this.result = const []});

  @override
  Future<List<TrainingAttendanceEntity>> listByAthlete({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) async {
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('AthleteMyEvolutionScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() async {
      FlutterError.onError = origOnError;
      await GetIt.instance.reset();
    });

    testWidgets('renders app bar with title', (tester) async {
      GetIt.instance
          .registerFactory<ICrmRepo>(() => _FakeCrmRepo());
      GetIt.instance
          .registerFactory<ITrainingAttendanceRepo>(() => _FakeAttendanceRepo());

      await tester.pumpApp(
        const AthleteMyEvolutionScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );
      await tester.pump();

      expect(find.text('Minha Evolução'), findsOneWidget);
    });

    testWidgets('shows loaded state with empty data', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      GetIt.instance
          .registerFactory<ICrmRepo>(() => _FakeCrmRepo());
      GetIt.instance
          .registerFactory<ITrainingAttendanceRepo>(() => _FakeAttendanceRepo());

      await tester.pumpApp(
        const AthleteMyEvolutionScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );
      await tester.pump();

      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Nenhuma tag'), findsOneWidget);
      expect(find.text('Nenhuma presença registrada'), findsOneWidget);
    });

    testWidgets('shows loaded state with data', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final status = MemberStatusEntity(
        groupId: 'g1',
        userId: 'u1',
        status: MemberStatusValue.active,
        updatedAt: DateTime(2026, 2, 15),
      );
      final tags = [
        CoachingTagEntity(
          id: 't1',
          groupId: 'g1',
          name: 'Iniciante',
          color: '#FF5722',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      final attendance = [
        TrainingAttendanceEntity(
          id: 'a1',
          groupId: 'g1',
          sessionId: 's1',
          athleteUserId: 'u1',
          checkedAt: DateTime(2026, 2, 10),
          sessionTitle: 'Treino de Terça',
          sessionStartsAt: DateTime(2026, 2, 10),
        ),
      ];

      GetIt.instance.registerFactory<ICrmRepo>(
        () => _FakeCrmRepo(statusResult: status, tagsResult: tags),
      );
      GetIt.instance.registerFactory<ITrainingAttendanceRepo>(
        () => _FakeAttendanceRepo(result: attendance),
      );

      await tester.pumpApp(
        const AthleteMyEvolutionScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );
      await tester.pump();

      expect(find.text('Ativo'), findsOneWidget);
      expect(find.text('Iniciante'), findsOneWidget);
      expect(find.text('Treino de Terça'), findsOneWidget);
    });

    testWidgets('shows error state when repo throws', (tester) async {
      GetIt.instance.registerFactory<ICrmRepo>(
        () => _FakeCrmRepo(error: Exception('Network error')),
      );
      GetIt.instance.registerFactory<ITrainingAttendanceRepo>(
        () => _FakeAttendanceRepo(),
      );

      await tester.pumpApp(
        const AthleteMyEvolutionScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });
  });
}
