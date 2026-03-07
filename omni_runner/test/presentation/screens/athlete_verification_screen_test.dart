import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/entities/athlete_verification_entity.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_state.dart';
import 'package:omni_runner/presentation/screens/athlete_verification_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeVerificationBloc extends Cubit<VerificationState>
    implements VerificationBloc {
  _FakeVerificationBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _verifiedEntity = AthleteVerificationEntity(
  status: VerificationStatus.verified,
  trustScore: 90,
  validRunsOk: true,
  integrityOk: true,
  baselineOk: true,
  trustOk: true,
  validRunsCount: 10,
  totalDistanceM: 50000,
  avgDistanceM: 5000,
);

const _calibratingEntity = AthleteVerificationEntity(
  status: VerificationStatus.calibrating,
  trustScore: 40,
  validRunsOk: false,
  integrityOk: true,
  baselineOk: false,
  trustOk: false,
  validRunsCount: 2,
  requiredValidRuns: 7,
  totalDistanceM: 10000,
  avgDistanceM: 5000,
);

void main() {
  group('AthleteVerificationScreen', () {
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
      final bloc = _FakeVerificationBloc(const VerificationInitial());
      GetIt.instance.registerFactory<VerificationBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteVerificationScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Verificação do Atleta'), findsOneWidget);
    });

    testWidgets('shows loading indicator for VerificationLoading',
        (tester) async {
      final bloc = _FakeVerificationBloc(const VerificationLoading());
      GetIt.instance.registerFactory<VerificationBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteVerificationScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows loading indicator for VerificationInitial',
        (tester) async {
      final bloc = _FakeVerificationBloc(const VerificationInitial());
      GetIt.instance.registerFactory<VerificationBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteVerificationScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message for VerificationError', (tester) async {
      final bloc =
          _FakeVerificationBloc(const VerificationError('Erro de conexão'));
      GetIt.instance.registerFactory<VerificationBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteVerificationScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Erro de conexão'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows loaded state with verified status', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc =
          _FakeVerificationBloc(const VerificationLoaded(_verifiedEntity));
      GetIt.instance.registerFactory<VerificationBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteVerificationScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Atleta Verificado'), findsOneWidget);
    });

    testWidgets('shows loaded state with calibrating status', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc =
          _FakeVerificationBloc(const VerificationLoaded(_calibratingEntity));
      GetIt.instance.registerFactory<VerificationBloc>(() => bloc);

      await tester.pumpApp(
        const AthleteVerificationScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Em Calibração'), findsOneWidget);
    });
  });
}
