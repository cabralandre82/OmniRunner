import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_bloc.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_event.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_state.dart';
import 'package:omni_runner/presentation/screens/coach_insights_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeCoachInsightsBloc extends Cubit<CoachInsightsState>
    implements CoachInsightsBloc {
  _FakeCoachInsightsBloc(super.initial);

  @override
  void add(CoachInsightsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CoachInsightsScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeCoachInsightsBloc fakeBloc;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      fakeBloc = _FakeCoachInsightsBloc(const CoachInsightsLoading());
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        BlocProvider<CoachInsightsBloc>.value(
          value: fakeBloc,
          child: const CoachInsightsScreen(groupName: 'Test Group'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        BlocProvider<CoachInsightsBloc>.value(
          value: fakeBloc,
          child: const CoachInsightsScreen(groupName: 'Test Group'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Insights · Test Group'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows loading indicator for loading state', (tester) async {
      await tester.pumpApp(
        BlocProvider<CoachInsightsBloc>.value(
          value: fakeBloc,
          child: const CoachInsightsScreen(groupName: 'Test Group'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message for error state', (tester) async {
      fakeBloc =
          _FakeCoachInsightsBloc(const CoachInsightsError('Erro no servidor'));

      await tester.pumpApp(
        BlocProvider<CoachInsightsBloc>.value(
          value: fakeBloc,
          child: const CoachInsightsScreen(groupName: 'Test Group'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro no servidor'), findsOneWidget);
    });
  });
}
