import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_event.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_state.dart';
import 'package:omni_runner/presentation/screens/staff_training_detail_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeTrainingDetailBloc extends Cubit<TrainingDetailState>
    implements TrainingDetailBloc {
  _FakeTrainingDetailBloc(super.initial);

  @override
  void add(TrainingDetailEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _session = TrainingSessionEntity(
  id: 's1',
  groupId: 'g1',
  createdBy: 'u1',
  title: 'Treino intervalado',
  description: 'Série de 400m com recuperação.',
  startsAt: DateTime(2026, 3, 10, 6, 30),
  status: TrainingSessionStatus.scheduled,
  locationName: 'Pista de Atletismo',
  distanceTargetM: 5000,
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 1),
);

final _attendance1 = TrainingAttendanceEntity(
  id: 'a1',
  groupId: 'g1',
  sessionId: 's1',
  athleteUserId: 'u2',
  checkedAt: DateTime(2026, 3, 10, 6, 35),
  status: AttendanceStatus.completed,
  method: CheckinMethod.auto,
  athleteDisplayName: 'João Silva',
);

void main() {
  group('StaffTrainingDetailScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeTrainingDetailBloc fakeBloc;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      fakeBloc = _FakeTrainingDetailBloc(const TrainingDetailLoading());
      _sl.registerFactory<TrainingDetailBloc>(() => fakeBloc);
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('shows loading indicator for TrainingDetailLoading state',
        (tester) async {
      await tester.pumpApp(
        const StaffTrainingDetailScreen(sessionId: 's1'),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows default AppBar title while loading', (tester) async {
      await tester.pumpApp(
        const StaffTrainingDetailScreen(sessionId: 's1'),
        wrapScaffold: false,
      );

      expect(find.text('Detalhe do Treino'), findsOneWidget);
    });

    testWidgets('shows error message for TrainingDetailError state',
        (tester) async {
      fakeBloc = _FakeTrainingDetailBloc(
        const TrainingDetailError('Sessão não encontrada'),
      );
      _sl.unregister<TrainingDetailBloc>();
      _sl.registerFactory<TrainingDetailBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffTrainingDetailScreen(sessionId: 's1'),
        wrapScaffold: false,
      );

      expect(find.text('Sessão não encontrada'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('shows loaded session detail', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      fakeBloc = _FakeTrainingDetailBloc(
        TrainingDetailLoaded(
          session: _session,
          attendance: [_attendance1],
          attendanceCount: 1,
        ),
      );
      _sl.unregister<TrainingDetailBloc>();
      _sl.registerFactory<TrainingDetailBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffTrainingDetailScreen(sessionId: 's1'),
        wrapScaffold: false,
      );

      expect(find.text('Treino intervalado'), findsWidgets);
      expect(find.text('Série de 400m com recuperação.'), findsOneWidget);
      expect(find.text('Pista de Atletismo'), findsOneWidget);
      expect(find.text('Cumprimento do Treino (1)'), findsOneWidget);
      expect(find.text('João Silva'), findsOneWidget);
    });

    testWidgets('shows empty attendance message when no attendees',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      fakeBloc = _FakeTrainingDetailBloc(
        TrainingDetailLoaded(
          session: _session,
          attendance: const [],
          attendanceCount: 0,
        ),
      );
      _sl.unregister<TrainingDetailBloc>();
      _sl.registerFactory<TrainingDetailBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffTrainingDetailScreen(sessionId: 's1'),
        wrapScaffold: false,
      );

      expect(
        find.text('Nenhum resultado registrado para este treino'),
        findsOneWidget,
      );
    });
  });
}
