import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/domain/repositories/i_badges_remote_source.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_bloc.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_event.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_state.dart';

class MockBadgeAwardRepo extends Mock implements IBadgeAwardRepo {}

class MockBadgesRemoteSource extends Mock implements IBadgesRemoteSource {}

const _userId = 'user-1';

final _awards = [
  const BadgeAwardEntity(
    id: 'ba-1',
    userId: _userId,
    badgeId: 'badge-distance-bronze',
    unlockedAtMs: 2000000,
    xpAwarded: 50,
    coinsAwarded: 10,
  ),
  const BadgeAwardEntity(
    id: 'ba-2',
    userId: _userId,
    badgeId: 'badge-frequency-silver',
    triggerSessionId: 'session-5',
    unlockedAtMs: 3000000,
    xpAwarded: 100,
    coinsAwarded: 25,
  ),
];

Future<List<BadgesState>> _collectStates(
  BadgesBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <BadgesState>[];
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
  late MockBadgeAwardRepo awardRepo;
  late MockBadgesRemoteSource remote;

  setUpAll(() {
    registerFallbackValue(const BadgeAwardEntity(
      id: '',
      userId: '',
      badgeId: '',
      unlockedAtMs: 0,
    ));
  });

  setUp(() {
    awardRepo = MockBadgeAwardRepo();
    remote = MockBadgesRemoteSource();

    // Default: remote returns empty (offline fallback)
    when(() => remote.evaluateRetroactive(any())).thenAnswer((_) async {});
    when(() => remote.fetchCatalog()).thenAnswer((_) async => []);
    when(() => remote.fetchAwards(any())).thenAnswer((_) async => []);
  });

  BadgesBloc buildBloc() => BadgesBloc(
        awardRepo: awardRepo,
        remote: remote,
      );

  group('BadgesBloc', () {
    test('initial state is BadgesInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const BadgesInitial());
      bloc.close();
    });

    group('LoadBadges', () {
      test('emits [Loading, Loaded] with awards from repo', () async {
        when(() => awardRepo.getByUserId(_userId))
            .thenAnswer((_) async => _awards);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadBadges(_userId));
        final states = await future;

        expect(states[0], isA<BadgesLoading>());
        expect(states[1], isA<BadgesLoaded>());
        final loaded = states[1] as BadgesLoaded;
        expect(loaded.awards.length, 2);
        expect(loaded.catalog, isEmpty);
        expect(loaded.isUnlocked('badge-distance-bronze'), isTrue);
        expect(loaded.isUnlocked('badge-nonexistent'), isFalse);
        await bloc.close();
      });

      test('emits [Loading, Loaded] with empty awards', () async {
        when(() => awardRepo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadBadges(_userId));
        final states = await future;

        final loaded = states[1] as BadgesLoaded;
        expect(loaded.awards, isEmpty);
        expect(loaded.unlockedIds, isEmpty);
        await bloc.close();
      });

      test('emits [Loading, Error] on exception', () async {
        when(() => awardRepo.getByUserId(_userId))
            .thenThrow(Exception('db'));

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadBadges(_userId));
        final states = await future;

        expect(states[0], isA<BadgesLoading>());
        expect(states[1], isA<BadgesError>());
        await bloc.close();
      });
    });

    group('RefreshBadges', () {
      test('does nothing when userId not set', () async {
        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1,
            timeout: const Duration(milliseconds: 200));
        bloc.add(const RefreshBadges());
        final states = await future;

        expect(states, isEmpty);
        await bloc.close();
      });

      test('re-fetches after load', () async {
        when(() => awardRepo.getByUserId(_userId))
            .thenAnswer((_) async => _awards);

        final bloc = buildBloc();
        var future = _collectStates(bloc, count: 2);
        bloc.add(const LoadBadges(_userId));
        await future;

        // New award unlocked
        final updated = [
          ..._awards,
          const BadgeAwardEntity(
            id: 'ba-3',
            userId: _userId,
            badgeId: 'badge-speed-gold',
            unlockedAtMs: 4000000,
            xpAwarded: 200,
          ),
        ];
        when(() => awardRepo.getByUserId(_userId))
            .thenAnswer((_) async => updated);

        future = _collectStates(bloc, count: 1);
        bloc.add(const RefreshBadges());
        final states = await future;

        final loaded = states[0] as BadgesLoaded;
        expect(loaded.awards.length, 3);
        await bloc.close();
      });
    });

    group('Remote sync', () {
      test('syncs catalog and awards from remote', () async {
        const badge = BadgeEntity(
          id: 'badge-1',
          category: BadgeCategory.distance,
          tier: BadgeTier.bronze,
          name: 'First 5K',
          description: 'Run 5km',
          xpReward: 50,
          criteria: SingleSessionDistance(5000),
        );

        when(() => remote.fetchCatalog())
            .thenAnswer((_) async => [badge]);
        when(() => remote.fetchAwards(_userId))
            .thenAnswer((_) async => _awards);
        when(() => awardRepo.save(any())).thenAnswer((_) async {});
        when(() => awardRepo.getByUserId(_userId))
            .thenAnswer((_) async => _awards);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadBadges(_userId));
        final states = await future;
        await bloc.close();

        verify(() => remote.evaluateRetroactive(_userId)).called(1);
        verify(() => awardRepo.save(any())).called(2);

        final loaded = states[1] as BadgesLoaded;
        expect(loaded.catalog, hasLength(1));
        expect(loaded.catalog.first.name, 'First 5K');
        expect(loaded.awards, hasLength(2));
      });

      test('works offline with empty remote', () async {
        when(() => awardRepo.getByUserId(_userId))
            .thenAnswer((_) async => _awards);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadBadges(_userId));
        final states = await future;
        await bloc.close();

        verifyNever(() => awardRepo.save(any()));
        final loaded = states[1] as BadgesLoaded;
        expect(loaded.catalog, isEmpty);
        expect(loaded.awards, hasLength(2));
      });
    });
  });
}
