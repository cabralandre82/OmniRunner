import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_state.dart';
import 'package:omni_runner/presentation/screens/athlete_training_list_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

class _FakeTrainingListBloc extends Cubit<TrainingListState>
    implements TrainingListBloc {
  _FakeTrainingListBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _upcomingSession = TrainingSessionEntity(
  id: 's1',
  groupId: 'g1',
  createdBy: 'coach1',
  title: 'Treino de Intervalados',
  startsAt: DateTime.now().add(const Duration(days: 1)),
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
  locationName: 'Parque Ibirapuera',
  distanceTargetM: 8000,
);

final _pastSession = TrainingSessionEntity(
  id: 's2',
  groupId: 'g1',
  createdBy: 'coach1',
  title: 'Long Run',
  startsAt: DateTime.now().subtract(const Duration(days: 3)),
  createdAt: DateTime.now().subtract(const Duration(days: 5)),
  updatedAt: DateTime.now().subtract(const Duration(days: 3)),
  status: TrainingSessionStatus.done,
);

void main() {
  group('AthleteTrainingListScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      ensureSupabaseClientRegistered();
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
      final bloc = _FakeTrainingListBloc(const TrainingListInitial());
      GetIt.instance.registerFactory<TrainingListBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Meus Treinos'), findsOneWidget);
    });

    testWidgets('shows loading state for TrainingListInitial', (tester) async {
      final bloc = _FakeTrainingListBloc(const TrainingListInitial());
      GetIt.instance.registerFactory<TrainingListBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Nenhum treino agendado'), findsNothing);
    });

    testWidgets('shows loading state for TrainingListLoading', (tester) async {
      final bloc = _FakeTrainingListBloc(const TrainingListLoading());
      GetIt.instance.registerFactory<TrainingListBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows error message for TrainingListError', (tester) async {
      final bloc = _FakeTrainingListBloc(
        const TrainingListError('Erro ao carregar treinos'),
      );
      GetIt.instance.registerFactory<TrainingListBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Erro ao carregar treinos'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('shows empty state when sessions list is empty',
        (tester) async {
      final bloc = _FakeTrainingListBloc(
        const TrainingListLoaded(sessions: []),
      );
      GetIt.instance.registerFactory<TrainingListBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Nenhum treino agendado'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('shows loaded sessions with upcoming and past',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeTrainingListBloc(
        TrainingListLoaded(sessions: [_upcomingSession, _pastSession]),
      );
      GetIt.instance.registerFactory<TrainingListBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Treino de Intervalados'), findsOneWidget);
      expect(find.text('Long Run'), findsOneWidget);
    });

    testWidgets('has refresh button in app bar', (tester) async {
      final bloc = _FakeTrainingListBloc(const TrainingListInitial());
      GetIt.instance.registerFactory<TrainingListBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
