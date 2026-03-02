import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/domain/usecases/social/accept_friend.dart';

class _FakeFriendshipRepo implements IFriendshipRepo {
  FriendshipEntity? stored;
  FriendshipEntity? updatedWith;
  int countA = 0;
  int countB = 0;

  @override
  Future<FriendshipEntity?> getById(String id) async => stored;
  @override
  Future<void> update(FriendshipEntity f) async => updatedWith = f;
  @override
  Future<int> countAccepted(String userId) async =>
      userId == stored?.userIdA ? countA : countB;
  @override
  Future<void> save(FriendshipEntity f) async {}
  @override
  Future<List<FriendshipEntity>> getByUserId(String u) async => [];
  @override
  Future<List<FriendshipEntity>> getAcceptedByUserId(String u) async => [];
  @override
  Future<List<FriendshipEntity>> getPendingForUser(String u) async => [];
  @override
  Future<FriendshipEntity?> findBetween(String a, String b) async => null;
  @override
  Future<bool> isBlocked(String a, String b) async => false;
  @override
  Future<int> countPendingSent(String u) async => 0;
  @override
  Future<void> deleteById(String id) async {}
}

FriendshipEntity _pendingRequest({
  String id = 'f1',
  String userIdA = 'alice',
  String userIdB = 'bob',
}) =>
    FriendshipEntity(
      id: id,
      userIdA: userIdA,
      userIdB: userIdB,
      status: FriendshipStatus.pending,
      createdAtMs: 100,
    );

void main() {
  late _FakeFriendshipRepo repo;
  late AcceptFriend usecase;

  setUp(() {
    repo = _FakeFriendshipRepo();
    usecase = AcceptFriend(friendshipRepo: repo);
  });

  test('accepts pending request from recipient', () async {
    repo.stored = _pendingRequest();

    final result = await usecase.call(
      friendshipId: 'f1',
      acceptingUserId: 'bob',
      nowMs: 500,
    );

    expect(result.status, FriendshipStatus.accepted);
    expect(result.acceptedAtMs, 500);
    expect(repo.updatedWith, isNotNull);
  });

  test('throws when friendship not found', () {
    repo.stored = null;

    expect(
      () => usecase.call(
        friendshipId: 'unknown',
        acceptingUserId: 'bob',
        nowMs: 500,
      ),
      throwsA(isA<FriendshipNotFound>()),
    );
  });

  test('throws when friendship is not pending', () {
    repo.stored = FriendshipEntity(
      id: 'f1',
      userIdA: 'alice',
      userIdB: 'bob',
      status: FriendshipStatus.accepted,
      createdAtMs: 100,
    );

    expect(
      () => usecase.call(
        friendshipId: 'f1',
        acceptingUserId: 'bob',
        nowMs: 500,
      ),
      throwsA(isA<InvalidFriendshipStatus>()),
    );
  });

  test('throws when wrong user tries to accept', () {
    repo.stored = _pendingRequest();

    expect(
      () => usecase.call(
        friendshipId: 'f1',
        acceptingUserId: 'alice',
        nowMs: 500,
      ),
      throwsA(isA<InvalidFriendshipStatus>()),
    );
  });

  test('throws when sender has 500 friends', () {
    repo.stored = _pendingRequest();
    repo.countA = 500;

    expect(
      () => usecase.call(
        friendshipId: 'f1',
        acceptingUserId: 'bob',
        nowMs: 500,
      ),
      throwsA(isA<FriendLimitReached>()),
    );
  });
}
