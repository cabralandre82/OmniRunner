import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_event.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_state.dart';
import 'package:omni_runner/presentation/screens/staff_generate_qr_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeStaffQrBloc extends Cubit<StaffQrState> implements StaffQrBloc {
  _FakeStaffQrBloc(super.initial);

  @override
  void add(StaffQrEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StaffGenerateQrScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeStaffQrBloc fakeBloc;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      fakeBloc = _FakeStaffQrBloc(const StaffQrInitial());
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        BlocProvider<StaffQrBloc>.value(
          value: fakeBloc,
          child: const StaffGenerateQrScreen(
            type: TokenIntentType.issueToAthlete,
            groupId: 'g1',
          ),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        BlocProvider<StaffQrBloc>.value(
          value: fakeBloc,
          child: const StaffGenerateQrScreen(
            type: TokenIntentType.issueToAthlete,
            groupId: 'g1',
          ),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Emitir OmniCoins'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows form with generate button on initial state',
        (tester) async {
      await tester.pumpApp(
        BlocProvider<StaffQrBloc>.value(
          value: fakeBloc,
          child: const StaffGenerateQrScreen(
            type: TokenIntentType.burnFromAthlete,
            groupId: 'g1',
          ),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Gerar QR'), findsOneWidget);
      expect(find.text('Quantidade'), findsOneWidget);
    });

    testWidgets('shows loading indicator when generating', (tester) async {
      fakeBloc = _FakeStaffQrBloc(const StaffQrGenerating());

      await tester.pumpApp(
        BlocProvider<StaffQrBloc>.value(
          value: fakeBloc,
          child: const StaffGenerateQrScreen(
            type: TokenIntentType.issueToAthlete,
            groupId: 'g1',
          ),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
