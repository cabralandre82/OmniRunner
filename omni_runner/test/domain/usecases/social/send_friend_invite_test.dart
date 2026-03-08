import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/domain/usecases/social/send_friend_invite.dart';

class _FakeFriendshipRepo implements IFriendshipRepo {
  bool blocked = false;
  FriendshipEntity? existing;
  int pendingCount = 0;
  int friendCount = 0;
  FriendshipEntity? saved;
  FriendshipEntity? updatedWith;

  @override
  Future<bool> isBlocked(String a, String b) async => blocked;
  @override
  Future<FriendshipEntity?> findBetween(String a, String b) async => existing;
  @override
  Future<int> countPendingSent(String u) async => pendingCount;
  @override
  Future<int> countAccepted(String u) async => friendCount;
  @override
  Future<void> save(FriendshipEntity f) async => saved = f;
  @override
  Future<void> update(FriendshipEntity f) async => updatedWith = f;
  @override
  Future<FriendshipEntity?> getById(String id) async => null;
  @override
  Future<List<FriendshipEntity>> getByUserId(String u) async => [];
  @override
  Future<List<FriendshipEntity>> getAcceptedByUserId(String u) async => [];
  @override
  Future<List<FriendshipEntity>> getPendingForUser(String u) async => [];
  @override
  Future<void> deleteById(String id) async {}
}

void main() {
  late _FakeFriendshipRepo repo;
  late SendFriendInvite usecase;

  setUp(() {
    repo = _FakeFriendshipRepo();
    usecase = SendFriendInvite(friendshipRepo: repo);
  });

  test('creates pending friendship', () async {
    final result = await usecase.call(
      fromUserId: 'alice',
      toUserId: 'bob',
      uuidGenerator: () => 'f-id',
      nowMs: 1000,
    );

    expect(result.status, FriendshipStatus.pending);
    expect(result.userIdA, 'alice');
    expect(result.userIdB, 'bob');
    expect(repo.saved, isNotNull);
  });

  test('throws on self-friend', () {
    expect(
      () => usecase.call(
        fromUserId: 'alice',
        toUserId: 'alice',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<CannotFriendSelf>()),
    );
  });

  test('throws when blocked', () {
    repo.blocked = true;

    expect(
      () => usecase.call(
        fromUserId: 'alice',
        toUserId: 'bob',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<UserIsBlocked>()),
    );
  });

  test('reactivates declined friendship', () async {
    repo.existing = const FriendshipEntity(
      id: 'f1',
      userIdA: 'alice',
      userIdB: 'bob',
      status: FriendshipStatus.declined,
      createdAtMs: 100,
    );

    final result = await usecase.call(
      fromUserId: 'alice',
      toUserId: 'bob',
      uuidGenerator: () => 'id',
      nowMs: 1000,
    );

    expect(result.status, FriendshipStatus.pending);
    expect(repo.updatedWith, isNotNull);
  });

  test('throws when friendship already exists (not declined)', () {
    repo.existing = const FriendshipEntity(
      id: 'f1',
      userIdA: 'alice',
      userIdB: 'bob',
      status: FriendshipStatus.accepted,
      createdAtMs: 100,
    );

    expect(
      () => usecase.call(
        fromUserId: 'alice',
        toUserId: 'bob',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<FriendshipAlreadyExists>()),
    );
  });

  test('throws when pending request limit reached', () {
    repo.pendingCount = 50;

    expect(
      () => usecase.call(
        fromUserId: 'alice',
        toUserId: 'bob',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<FriendRequestLimitReached>()),
    );
  });

  test('throws when friend limit reached', () {
    repo.friendCount = 500;

    expect(
      () => usecase.call(
        fromUserId: 'alice',
        toUserId: 'bob',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<FriendLimitReached>()),
    );
  });
}
