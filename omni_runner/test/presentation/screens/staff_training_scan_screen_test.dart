// ignore_for_file: invalid_override, invalid_use_of_type_outside_library, extends_non_class, super_formal_parameter_without_associated_positional
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_bloc.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_event.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_state.dart';
import 'package:omni_runner/presentation/screens/staff_training_scan_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

final _sl = GetIt.instance;

class _FakeCheckinBloc extends Cubit<CheckinState> implements CheckinBloc {
  _FakeCheckinBloc(super.initial);

  @override
  void add(CheckinEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StaffTrainingScanScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeCheckinBloc fakeBloc;

    setUp(() {
      ensureSupabaseClientRegistered();
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed') || msg.contains('MobileScanner')) {
          return;
        }
        origOnError?.call(details);
      };
      fakeBloc = _FakeCheckinBloc(const CheckinConsuming());
      _sl.registerFactory<CheckinBloc>(() => fakeBloc);
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const StaffTrainingScanScreen(sessionId: 's1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const StaffTrainingScanScreen(sessionId: 's1'),
        wrapScaffold: false,
      );

      expect(find.text('Escanear QR'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows processing indicator for consuming state',
        (tester) async {
      await tester.pumpApp(
        const StaffTrainingScanScreen(sessionId: 's1'),
        wrapScaffold: false,
      );

      expect(find.text('Processando...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
