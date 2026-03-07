import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_bloc.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_state.dart';
import 'package:omni_runner/presentation/screens/athlete_checkin_qr_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeCheckinBloc extends Cubit<CheckinState> implements CheckinBloc {
  _FakeCheckinBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('AthleteCheckinQrScreen', () {
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
      final bloc = _FakeCheckinBloc(const CheckinInitial());
      GetIt.instance.registerFactory<CheckinBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteCheckinQrScreen(
          sessionId: 's1',
          sessionTitle: 'Treino Semanal',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Check-in de Presença'), findsOneWidget);
    });

    testWidgets('shows initial state with generate button', (tester) async {
      final bloc = _FakeCheckinBloc(const CheckinInitial());
      GetIt.instance.registerFactory<CheckinBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteCheckinQrScreen(
          sessionId: 's1',
          sessionTitle: 'Treino Semanal',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Treino Semanal'), findsOneWidget);
      expect(find.text('Gerar QR'), findsOneWidget);
    });

    testWidgets('shows loading for CheckinGenerating', (tester) async {
      final bloc = _FakeCheckinBloc(const CheckinGenerating());
      GetIt.instance.registerFactory<CheckinBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteCheckinQrScreen(
          sessionId: 's1',
          sessionTitle: 'Treino Semanal',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message for CheckinError', (tester) async {
      final bloc = _FakeCheckinBloc(const CheckinError('Erro ao gerar QR'));
      GetIt.instance.registerFactory<CheckinBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteCheckinQrScreen(
          sessionId: 's1',
          sessionTitle: 'Treino Semanal',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro ao gerar QR'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Tentar Novamente'), findsOneWidget);
    });

    testWidgets('shows QR code for CheckinQrReady', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final token = CheckinToken(
        sessionId: 's1',
        athleteUserId: 'u1',
        groupId: 'g1',
        nonce: 'test-nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      );
      final bloc = _FakeCheckinBloc(
        CheckinQrReady(token: token, encodedPayload: 'dGVzdC1wYXlsb2Fk'),
      );
      GetIt.instance.registerFactory<CheckinBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteCheckinQrScreen(
          sessionId: 's1',
          sessionTitle: 'Treino Semanal',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Treino Semanal'), findsOneWidget);
      expect(find.text('Gerar Novo QR'), findsOneWidget);
    });

    testWidgets('shows expired state for expired QR token', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final token = CheckinToken(
        sessionId: 's1',
        athleteUserId: 'u1',
        groupId: 'g1',
        nonce: 'test-nonce',
        expiresAtMs: DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      );
      final bloc = _FakeCheckinBloc(
        CheckinQrReady(token: token, encodedPayload: 'dGVzdC1wYXlsb2Fk'),
      );
      GetIt.instance.registerFactory<CheckinBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteCheckinQrScreen(
          sessionId: 's1',
          sessionTitle: 'Treino Semanal',
        ),
        wrapScaffold: false,
      );

      expect(find.text('QR Expirado'), findsWidgets);
    });
  });
}
