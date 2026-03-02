import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/domain/usecases/social/accept_friend.dart';
import 'package:omni_runner/domain/usecases/social/send_friend_invite.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_event.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_state.dart';

class MockFriendshipRepo extends Mock implements IFriendshipRepo {}

class MockNotificationRulesService extends Mock
    implements NotificationRulesService {}

const _userId = 'user-1';
const _otherUserId = 'user-2';

const _accepted = FriendshipEntity(
  id: 'f-1',
  userIdA: _userId,
  userIdB: _otherUserId,
  status: FriendshipStatus.accepted,
  createdAtMs: 1000000,
  acceptedAtMs: 2000000,
  invitedBy: _userId,
);

const _pendingReceived = FriendshipEntity(
  id: 'f-2',
  userIdA: 'user-3',
  userIdB: _userId,
  status: FriendshipStatus.pending,
  createdAtMs: 3000000,
  invitedBy: 'user-3',
);

Future<List<FriendsState>> _collectStates(
  FriendsBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <FriendsState>[];
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
  late MockFriendshipRepo friendshipRepo;
  late MockNotificationRulesService notifyRules;
  late SendFriendInvite sendInvite;
  late AcceptFriend acceptFriend;

  setUp(() {
    friendshipRepo = MockFriendshipRepo();
    notifyRules = MockNotificationRulesService();
    sendInvite = SendFriendInvite(friendshipRepo: friendshipRepo);
    acceptFriend = AcceptFriend(friendshipRepo: friendshipRepo);
  });

  setUpAll(() {
    registerFallbackValue(const FriendshipEntity(
      id: '',
      userIdA: '',
      userIdB: '',
      status: FriendshipStatus.pending,
      createdAtMs: 0,
    ));
  });

  FriendsBloc buildBloc() => FriendsBloc(
        friendshipRepo: friendshipRepo,
        sendInvite: sendInvite,
        acceptFriend: acceptFriend,
        notifyRules: notifyRules,
      );

  group('FriendsBloc', () {
    test('initial state is FriendsInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const FriendsInitial());
      bloc.close();
    });

    group('LoadFriends', () {
      test('emits [Loading, Loaded] splitting accepted/pending', () async {
        when(() => friendshipRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_accepted, _pendingReceived]);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadFriends(_userId));
        final states = await future;

        expect(states[0], isA<FriendsLoading>());
        expect(states[1], isA<FriendsLoaded>());
        final loaded = states[1] as FriendsLoaded;
        expect(loaded.accepted.length, 1);
        expect(loaded.pendingReceived.length, 1);
        expect(loaded.pendingSent, isEmpty);
        await bloc.close();
      });

      test('emits [Loading, Loaded] with empty lists', () async {
        when(() => friendshipRepo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadFriends(_userId));
        final states = await future;

        final loaded = states[1] as FriendsLoaded;
        expect(loaded.accepted, isEmpty);
        expect(loaded.totalFriends, 0);
        await bloc.close();
      });

      test('emits [Loading, Error] on exception', () async {
        when(() => friendshipRepo.getByUserId(_userId))
            .thenThrow(Exception('network'));

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadFriends(_userId));
        final states = await future;

        expect(states[0], isA<FriendsLoading>());
        expect(states[1], isA<FriendsError>());
        await bloc.close();
      });
    });

    group('DeclineFriendEvent', () {
      test('updates friendship to declined and re-fetches', () async {
        // Initial load includes the pending request
        when(() => friendshipRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_accepted, _pendingReceived]);
        when(() => friendshipRepo.getById('f-2'))
            .thenAnswer((_) async => _pendingReceived);
        when(() => friendshipRepo.update(any())).thenAnswer((_) async {});

        final bloc = buildBloc();
        var future = _collectStates(bloc, count: 2);
        bloc.add(const LoadFriends(_userId));
        await future;

        // After decline, the pending request is gone
        when(() => friendshipRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_accepted]);

        future = _collectStates(bloc, count: 1);
        bloc.add(const DeclineFriendEvent('f-2'));
        final states = await future;

        verify(() => friendshipRepo.update(any(
          that: isA<FriendshipEntity>().having(
            (f) => f.status,
            'status',
            FriendshipStatus.declined,
          ),
        ))).called(1);
        expect(states[0], isA<FriendsLoaded>());
        final loaded = states[0] as FriendsLoaded;
        expect(loaded.pendingReceived, isEmpty);
        await bloc.close();
      });
    });

    group('RemoveFriend', () {
      test('deletes friendship and re-fetches', () async {
        // Initial load includes a friend
        when(() => friendshipRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_accepted]);

        final bloc = buildBloc();
        var future = _collectStates(bloc, count: 2);
        bloc.add(const LoadFriends(_userId));
        await future;

        when(() => friendshipRepo.deleteById('f-1'))
            .thenAnswer((_) async {});
        // After removal, no friends left
        when(() => friendshipRepo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        future = _collectStates(bloc, count: 1);
        bloc.add(const RemoveFriend('f-1'));
        final states = await future;

        verify(() => friendshipRepo.deleteById('f-1')).called(1);
        expect(states[0], isA<FriendsLoaded>());
        final loaded = states[0] as FriendsLoaded;
        expect(loaded.accepted, isEmpty);
        await bloc.close();
      });
    });
  });
}
