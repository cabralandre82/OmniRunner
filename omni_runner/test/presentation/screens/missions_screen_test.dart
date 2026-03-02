import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_event.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_state.dart';
import 'package:omni_runner/presentation/screens/missions_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeMissionsBloc extends Cubit<MissionsState> implements MissionsBloc {
  _FakeMissionsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MissionsScreen', () {
    testWidgets('shows loading indicator', (tester) async {
      final bloc = _FakeMissionsBloc(const MissionsLoading());

      await tester.pumpApp(
        BlocProvider<MissionsBloc>.value(
          value: bloc,
          child: const MissionsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc = _FakeMissionsBloc(const MissionsError('Erro de rede'));

      await tester.pumpApp(
        BlocProvider<MissionsBloc>.value(
          value: bloc,
          child: const MissionsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro de rede'), findsOneWidget);
    });

    testWidgets('shows empty state when no missions', (tester) async {
      final bloc = _FakeMissionsBloc(const MissionsLoaded(
        active: [],
        completed: [],
      ));

      await tester.pumpApp(
        BlocProvider<MissionsBloc>.value(
          value: bloc,
          child: const MissionsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Nenhuma missão ativa'), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    });

    testWidgets('shows initial state text', (tester) async {
      final bloc = _FakeMissionsBloc(const MissionsInitial());

      await tester.pumpApp(
        BlocProvider<MissionsBloc>.value(
          value: bloc,
          child: const MissionsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Carregue suas missões.'), findsOneWidget);
    });

    testWidgets('has refresh button in app bar', (tester) async {
      final bloc = _FakeMissionsBloc(const MissionsInitial());

      await tester.pumpApp(
        BlocProvider<MissionsBloc>.value(
          value: bloc,
          child: const MissionsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
