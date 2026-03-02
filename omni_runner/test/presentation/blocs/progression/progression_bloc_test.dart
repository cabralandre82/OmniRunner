import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/weekly_goal_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_progression_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_bloc.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_event.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_state.dart';

class MockProfileProgressRepo extends Mock implements IProfileProgressRepo {}

class MockXpTransactionRepo extends Mock implements IXpTransactionRepo {}

class MockProgressionRemoteSource extends Mock
    implements IProgressionRemoteSource {}

const _userId = 'user-1';

const _profile = ProfileProgressEntity(
  userId: _userId,
  totalXp: 1500,
  seasonXp: 300,
  dailyStreakCount: 5,
  streakBest: 10,
  weeklySessionCount: 3,
  monthlySessionCount: 12,
  lifetimeSessionCount: 100,
  lifetimeDistanceM: 500000,
  lifetimeMovingMs: 3600000,
);

final _xpHistory = [
  const XpTransactionEntity(
    id: 'xp-1',
    userId: _userId,
    xp: 100,
    source: XpSource.session,
    refId: 'session-1',
    createdAtMs: 2000000,
  ),
];

Future<List<ProgressionState>> _collectStates(
  ProgressionBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <ProgressionState>[];
  final completer = Completer<void>();
  final sub = bloc.stream.listen((s) {
    states.add(s);
    if (states.length >= count && !completer.isCompleted) {
      completer.complete();
    }
  });
  await completer.future.timeout(timeout, onTimeout: () {});
  await sub.cancel();
  return states;
}

void main() {
  late MockProfileProgressRepo profileRepo;
  late MockXpTransactionRepo xpRepo;
  late MockProgressionRemoteSource remote;

  setUpAll(() {
    registerFallbackValue(const ProfileProgressEntity(
      userId: '',
      totalXp: 0,
      seasonXp: 0,
      dailyStreakCount: 0,
      streakBest: 0,
      weeklySessionCount: 0,
      monthlySessionCount: 0,
      lifetimeSessionCount: 0,
      lifetimeDistanceM: 0,
      lifetimeMovingMs: 0,
    ));
    registerFallbackValue(const XpTransactionEntity(
      id: '',
      userId: '',
      xp: 0,
      source: XpSource.session,
      createdAtMs: 0,
    ));
  });

  setUp(() {
    profileRepo = MockProfileProgressRepo();
    xpRepo = MockXpTransactionRepo();
    remote = MockProgressionRemoteSource();

    // Default: remote returns empty (offline fallback)
    when(() => remote.recalculateAndEvaluate(any()))
        .thenAnswer((_) async {});
    when(() => remote.fetchProfileProgress(any()))
        .thenAnswer((_) async => null);
    when(() => remote.fetchXpTransactions(any()))
        .thenAnswer((_) async => []);
    when(() => remote.fetchWeeklyGoal(any()))
        .thenAnswer((_) async => null);
    when(() => remote.fetchBadges(any())).thenAnswer((_) async =>
        (catalog: const <Map<String, dynamic>>[], earnedIds: const <String>{}));
  });

  ProgressionBloc buildBloc() => ProgressionBloc(
        profileRepo: profileRepo,
        xpRepo: xpRepo,
        remote: remote,
      );

  group('ProgressionBloc', () {
    test('initial state is ProgressionInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const ProgressionInitial());
      bloc.close();
    });

    group('LoadProgression', () {
      test('emits [Loading, Loaded] with profile and XP history', () async {
        when(() => profileRepo.getByUserId(_userId))
            .thenAnswer((_) async => _profile);
        when(() => xpRepo.getByUserId(_userId))
            .thenAnswer((_) async => _xpHistory);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadProgression(_userId));
        final states = await future;

        expect(states[0], isA<ProgressionLoading>());
        expect(states[1], isA<ProgressionLoaded>());
        final loaded = states[1] as ProgressionLoaded;
        expect(loaded.profile.totalXp, 1500);
        expect(loaded.recentXp.length, 1);
        expect(loaded.weeklyGoal, isNull);
        expect(loaded.badgeCatalog, isEmpty);
        await bloc.close();
      });

      test('emits [Loading, Error] on exception', () async {
        when(() => profileRepo.getByUserId(_userId))
            .thenThrow(Exception('db'));
        when(() => xpRepo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadProgression(_userId));
        final states = await future;

        expect(states[0], isA<ProgressionLoading>());
        expect(states[1], isA<ProgressionError>());
        await bloc.close();
      });
    });

    group('RefreshProgression', () {
      test('does nothing when userId not set', () async {
        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1,
            timeout: const Duration(milliseconds: 200));
        bloc.add(const RefreshProgression());
        final states = await future;

        expect(states, isEmpty);
        await bloc.close();
      });

      test('re-fetches after LoadProgression', () async {
        when(() => profileRepo.getByUserId(_userId))
            .thenAnswer((_) async => _profile);
        when(() => xpRepo.getByUserId(_userId))
            .thenAnswer((_) async => _xpHistory);

        final bloc = buildBloc();
        var future = _collectStates(bloc, count: 2);
        bloc.add(const LoadProgression(_userId));
        await future;

        // Update XP
        const updatedProfile = ProfileProgressEntity(
          userId: _userId,
          totalXp: 2000,
          seasonXp: 500,
          dailyStreakCount: 6,
          streakBest: 10,
          weeklySessionCount: 4,
          monthlySessionCount: 13,
          lifetimeSessionCount: 101,
          lifetimeDistanceM: 510000,
          lifetimeMovingMs: 3700000,
        );
        when(() => profileRepo.getByUserId(_userId))
            .thenAnswer((_) async => updatedProfile);

        future = _collectStates(bloc, count: 1);
        bloc.add(const RefreshProgression());
        final states = await future;

        expect(states[0], isA<ProgressionLoaded>());
        expect((states[0] as ProgressionLoaded).profile.totalXp, 2000);
        await bloc.close();
      });
    });

    group('Remote sync', () {
      test('syncs profile and XP from remote, includes weekly goal', () async {
        final weeklyGoal = WeeklyGoalEntity(
          id: 'wg-1',
          userId: _userId,
          weekStart: DateTime(2026, 2, 23),
          targetValue: 15000,
          currentValue: 8000,
        );

        when(() => remote.fetchProfileProgress(_userId))
            .thenAnswer((_) async => _profile);
        when(() => remote.fetchXpTransactions(_userId))
            .thenAnswer((_) async => _xpHistory);
        when(() => remote.fetchWeeklyGoal(_userId))
            .thenAnswer((_) async => weeklyGoal);
        when(() => remote.fetchBadges(_userId)).thenAnswer((_) async => (
              catalog: const [
                {'id': 'b1', 'name': 'First 5K'}
              ],
              earnedIds: const {'b1'},
            ));
        when(() => profileRepo.save(any())).thenAnswer((_) async {});
        when(() => xpRepo.append(any())).thenAnswer((_) async {});
        when(() => profileRepo.getByUserId(_userId))
            .thenAnswer((_) async => _profile);
        when(() => xpRepo.getByUserId(_userId))
            .thenAnswer((_) async => _xpHistory);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadProgression(_userId));
        final states = await future;
        await bloc.close();

        verify(() => remote.recalculateAndEvaluate(_userId)).called(1);
        verify(() => profileRepo.save(any())).called(1);
        verify(() => xpRepo.append(any())).called(1);

        final loaded = states[1] as ProgressionLoaded;
        expect(loaded.weeklyGoal, isNotNull);
        expect(loaded.weeklyGoal!.targetValue, 15000);
        expect(loaded.badgeCatalog, hasLength(1));
        expect(loaded.earnedBadgeIds, contains('b1'));
      });

      test('works offline when remote returns null/empty', () async {
        when(() => profileRepo.getByUserId(_userId))
            .thenAnswer((_) async => _profile);
        when(() => xpRepo.getByUserId(_userId))
            .thenAnswer((_) async => _xpHistory);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadProgression(_userId));
        final states = await future;
        await bloc.close();

        verifyNever(() => profileRepo.save(any()));
        verifyNever(() => xpRepo.append(any()));

        final loaded = states[1] as ProgressionLoaded;
        expect(loaded.profile.totalXp, 1500);
        expect(loaded.weeklyGoal, isNull);
        expect(loaded.badgeCatalog, isEmpty);
      });
    });
  });
}
