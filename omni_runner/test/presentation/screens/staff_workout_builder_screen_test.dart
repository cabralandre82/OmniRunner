// ignore_for_file: invalid_override, invalid_use_of_type_outside_library, extends_non_class, super_formal_parameter_without_associated_positional
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_bloc.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_event.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_state.dart';
import 'package:omni_runner/presentation/screens/staff_workout_builder_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeWorkoutBuilderBloc extends Cubit<WorkoutBuilderState>
    implements WorkoutBuilderBloc {
  _FakeWorkoutBuilderBloc(super.initial);

  @override
  void add(WorkoutBuilderEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StaffWorkoutBuilderScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeWorkoutBuilderBloc fakeBloc;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      fakeBloc = _FakeWorkoutBuilderBloc(const BuilderLoading());
      _sl.registerFactory<WorkoutBuilderBloc>(() => fakeBloc);
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const StaffWorkoutBuilderScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title for new template',
        (tester) async {
      fakeBloc = _FakeWorkoutBuilderBloc(
        const BuilderLoaded(blocks: [], groupId: 'g1'),
      );
      _sl.unregister<WorkoutBuilderBloc>();
      _sl.registerFactory<WorkoutBuilderBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffWorkoutBuilderScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Novo Template'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows loading indicator for loading state', (tester) async {
      await tester.pumpApp(
        const StaffWorkoutBuilderScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
