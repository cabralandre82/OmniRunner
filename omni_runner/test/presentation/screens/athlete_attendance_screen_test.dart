// ignore_for_file: invalid_override, invalid_use_of_type_outside_library, extends_non_class, super_formal_parameter_without_associated_positional
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/presentation/screens/athlete_attendance_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeAttendanceRepo implements ITrainingAttendanceRepo {
  @override
  Future<List<TrainingAttendanceEntity>> listByAthlete({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AthleteAttendanceScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      _sl.registerFactory<ITrainingAttendanceRepo>(
        () => _FakeAttendanceRepo(),
      );
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const AthleteAttendanceScreen(groupId: 'g1', athleteUserId: 'u1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const AthleteAttendanceScreen(groupId: 'g1', athleteUserId: 'u1'),
        wrapScaffold: false,
      );

      expect(find.text('Meus Treinos Prescritos'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
