
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/leaderboard_entity.dart';
import 'package:omni_runner/domain/repositories/i_leaderboard_repo.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_bloc.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_event.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_state.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements ILeaderboardRepo {
  LeaderboardEntity? result;
  Exception? error;
  int callCount = 0;

  @override
  Future<LeaderboardEntity?> fetchLeaderboard({
    required LeaderboardScope scope,
    required LeaderboardPeriod period,
    required LeaderboardMetric metric,
    String? groupId,
    String? championshipId,
  }) async {
    callCount++;
    if (error != null) throw error!;
    return result;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LeaderboardEntity _makeLb({
  String id = 'lb-1',
  LeaderboardScope scope = LeaderboardScope.global,
  LeaderboardPeriod period = LeaderboardPeriod.weekly,
  LeaderboardMetric metric = LeaderboardMetric.composite,
  List<LeaderboardEntryEntity> entries = const [],
}) =>
    LeaderboardEntity(
      id: id,
      scope: scope,
      period: period,
      metric: metric,
      periodKey: '2026-W09',
      entries: entries,
      computedAtMs: 1000000,
    );

const _entry = LeaderboardEntryEntity(
  userId: 'u1',
  displayName: 'Alice',
  level: 5,
  value: 42000,
  rank: 1,
  periodKey: '2026-W09',
);

/// Collects states emitted by [bloc] (skipping the seed) until the stream
/// pauses for [settle] or [max] states are collected.
Future<List<LeaderboardsState>> _collectStates(
  LeaderboardsBloc bloc, {
  int max = 10,
  Duration settle = const Duration(milliseconds: 300),
}) async {
  final states = <LeaderboardsState>[];
  final sub = bloc.stream.listen(states.add);
  // Wait for the stream to settle
  var prev = -1;
  while (states.length < max) {
    await Future<void>.delayed(settle);
    if (states.length == prev) break;
    prev = states.length;
  }
  await sub.cancel();
  return states;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeRepo repo;

  setUp(() {
    repo = _FakeRepo();
  });

  group('LeaderboardsBloc', () {
    test('initial state is LeaderboardsInitial', () {
      final bloc = LeaderboardsBloc(repo: repo);
      expect(bloc.state, isA<LeaderboardsInitial>());
      bloc.close();
    });

    test('emits [Loading, Loaded] when repo returns a leaderboard', () async {
      repo.result = _makeLb(entries: [_entry]);
      final bloc = LeaderboardsBloc(repo: repo);

      bloc.add(LoadLeaderboard(
        scope: LeaderboardScope.global,
        period: LeaderboardPeriod.weekly,
      ));

      final states = await _collectStates(bloc);
      await bloc.close();

      expect(states, hasLength(2));
      expect(states[0], isA<LeaderboardsLoading>());
      expect(states[1], isA<LeaderboardsLoaded>());

      final loaded = states[1] as LeaderboardsLoaded;
      expect(loaded.leaderboard.id, 'lb-1');
      expect(loaded.leaderboard.entries, hasLength(1));
    });

    test('emits [Loading, Loaded(empty)] when repo returns null', () async {
      repo.result = null;
      final bloc = LeaderboardsBloc(repo: repo);

      bloc.add(LoadLeaderboard(
        scope: LeaderboardScope.global,
        period: LeaderboardPeriod.weekly,
      ));

      final states = await _collectStates(bloc);
      await bloc.close();

      expect(states, hasLength(2));
      expect(states[1], isA<LeaderboardsLoaded>());

      final loaded = states[1] as LeaderboardsLoaded;
      expect(loaded.leaderboard.entries, isEmpty);
      expect(loaded.leaderboard.id, contains('empty'));
    });

    test('emits [Loading, Error] when repo throws', () async {
      repo.error = Exception('network');
      final bloc = LeaderboardsBloc(repo: repo);

      bloc.add(LoadLeaderboard(
        scope: LeaderboardScope.global,
        period: LeaderboardPeriod.weekly,
      ));

      final states = await _collectStates(bloc);
      await bloc.close();

      expect(states, hasLength(2));
      expect(states[0], isA<LeaderboardsLoading>());
      expect(states[1], isA<LeaderboardsError>());
      expect((states[1] as LeaderboardsError).message, contains('ranking'));
    });

    test('RefreshLeaderboard does nothing if no previous load', () async {
      final bloc = LeaderboardsBloc(repo: repo);

      bloc.add(const RefreshLeaderboard());

      final states = await _collectStates(bloc);
      await bloc.close();

      expect(states, isEmpty);
      expect(repo.callCount, 0);
    });

    test('RefreshLeaderboard re-fetches after a Load', () async {
      repo.result = _makeLb();
      final bloc = LeaderboardsBloc(repo: repo);

      final allStates = <LeaderboardsState>[];
      final sub = bloc.stream.listen(allStates.add);

      bloc.add(LoadLeaderboard(
        scope: LeaderboardScope.assessoria,
        period: LeaderboardPeriod.monthly,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      bloc.add(const RefreshLeaderboard());

      await Future<void>.delayed(const Duration(milliseconds: 300));

      await sub.cancel();
      await bloc.close();

      expect(allStates.length, greaterThanOrEqualTo(4));
      expect(repo.callCount, 2);
    });
  });
}
