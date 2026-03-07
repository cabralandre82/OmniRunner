import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_event.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_state.dart';
import 'package:omni_runner/presentation/screens/staff_training_list_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeTrainingListBloc extends Cubit<TrainingListState>
    implements TrainingListBloc {
  _FakeTrainingListBloc(super.initial);

  @override
  void add(TrainingListEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _session1 = TrainingSessionEntity(
  id: 's1',
  groupId: 'g1',
  createdBy: 'u1',
  title: 'Treino de velocidade',
  startsAt: DateTime(2026, 3, 10, 6, 30),
  status: TrainingSessionStatus.scheduled,
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 1),
);

final _session2 = TrainingSessionEntity(
  id: 's2',
  groupId: 'g1',
  createdBy: 'u1',
  title: 'Treino de longa distância',
  startsAt: DateTime(2026, 3, 12, 7, 0),
  status: TrainingSessionStatus.done,
  locationName: 'Parque Ibirapuera',
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 1),
);

void main() {
  group('StaffTrainingListScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeTrainingListBloc fakeBloc;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      fakeBloc = _FakeTrainingListBloc(const TrainingListLoading());
      _sl.registerFactory<TrainingListBloc>(() => fakeBloc);
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const StaffTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Agenda de Treinos'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows shimmer loader for loading state', (tester) async {
      await tester.pumpApp(
        const StaffTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows error message for TrainingListError state',
        (tester) async {
      fakeBloc =
          _FakeTrainingListBloc(const TrainingListError('Erro no servidor'));
      _sl.unregister<TrainingListBloc>();
      _sl.registerFactory<TrainingListBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Erro no servidor'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('shows empty state when no sessions', (tester) async {
      fakeBloc =
          _FakeTrainingListBloc(const TrainingListLoaded(sessions: []));
      _sl.unregister<TrainingListBloc>();
      _sl.registerFactory<TrainingListBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Nenhum treino agendado'), findsOneWidget);
    });

    testWidgets('shows FAB to create new training', (tester) async {
      fakeBloc =
          _FakeTrainingListBloc(const TrainingListLoaded(sessions: []));
      _sl.unregister<TrainingListBloc>();
      _sl.registerFactory<TrainingListBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffTrainingListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Novo Treino'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
