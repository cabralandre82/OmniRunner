import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_bloc.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_event.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_state.dart';
import 'package:omni_runner/presentation/screens/staff_athlete_profile_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeAthleteProfileBloc extends Cubit<AthleteProfileState>
    implements AthleteProfileBloc {
  _FakeAthleteProfileBloc(super.initial);

  @override
  void add(AthleteProfileEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StaffAthleteProfileScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeAthleteProfileBloc fakeBloc;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      fakeBloc = _FakeAthleteProfileBloc(const AthleteProfileLoading());
      _sl.registerFactory<AthleteProfileBloc>(() => fakeBloc);
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const StaffAthleteProfileScreen(
          groupId: 'g1',
          athleteUserId: 'u1',
          athleteDisplayName: 'João Silva',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with athlete name', (tester) async {
      await tester.pumpApp(
        const StaffAthleteProfileScreen(
          groupId: 'g1',
          athleteUserId: 'u1',
          athleteDisplayName: 'João Silva',
        ),
        wrapScaffold: false,
      );

      expect(find.text('João Silva'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows loading indicator for loading state', (tester) async {
      await tester.pumpApp(
        const StaffAthleteProfileScreen(
          groupId: 'g1',
          athleteUserId: 'u1',
          athleteDisplayName: 'João Silva',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('shows tab bar with all tabs', (tester) async {
      await tester.pumpApp(
        const StaffAthleteProfileScreen(
          groupId: 'g1',
          athleteUserId: 'u1',
          athleteDisplayName: 'João Silva',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Visão geral'), findsOneWidget);
      expect(find.text('Notas'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Treinos'), findsOneWidget);
      expect(find.text('Alertas'), findsOneWidget);
    });
  });
}
