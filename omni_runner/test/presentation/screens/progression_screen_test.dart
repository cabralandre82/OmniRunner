import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_bloc.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_event.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_state.dart';
import 'package:omni_runner/presentation/screens/progression_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeProgressionBloc extends Cubit<ProgressionState>
    implements ProgressionBloc {
  _FakeProgressionBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ProgressionScreen', () {
    testWidgets('shows loading indicator', (tester) async {
      final bloc = _FakeProgressionBloc(const ProgressionLoading());

      await tester.pumpApp(
        BlocProvider<ProgressionBloc>.value(
          value: bloc,
          child: const ProgressionScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc =
          _FakeProgressionBloc(const ProgressionError('Falha na conexão'));

      await tester.pumpApp(
        BlocProvider<ProgressionBloc>.value(
          value: bloc,
          child: const ProgressionScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Falha na conexão'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows empty state for initial', (tester) async {
      final bloc = _FakeProgressionBloc(const ProgressionInitial());

      await tester.pumpApp(
        BlocProvider<ProgressionBloc>.value(
          value: bloc,
          child: const ProgressionScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
      expect(find.text('Seu progresso aparece aqui'), findsOneWidget);
    });

    testWidgets('has refresh button in app bar', (tester) async {
      final bloc = _FakeProgressionBloc(const ProgressionInitial());

      await tester.pumpApp(
        BlocProvider<ProgressionBloc>.value(
          value: bloc,
          child: const ProgressionScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
