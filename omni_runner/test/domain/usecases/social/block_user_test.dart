import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/domain/usecases/social/block_user.dart';

class _FakeFriendshipRepo implements IFriendshipRepo {
  FriendshipEntity? existing;
  FriendshipEntity? saved;
  FriendshipEntity? updatedWith;
  String? deletedId;

  @override
  Future<FriendshipEntity?> findBetween(String a, String b) async => existing;
  @override
  Future<void> save(FriendshipEntity f) async => saved = f;
  @override
  Future<void> update(FriendshipEntity f) async => updatedWith = f;
  @override
  Future<void> deleteById(String id) async => deletedId = id;
  @override
  Future<FriendshipEntity?> getById(String id) async => null;
  @override
  Future<List<FriendshipEntity>> getByUserId(String u) async => [];
  @override
  Future<List<FriendshipEntity>> getAcceptedByUserId(String u) async => [];
  @override
  Future<List<FriendshipEntity>> getPendingForUser(String u) async => [];
  @override
  Future<bool> isBlocked(String a, String b) async => false;
  @override
  Future<int> countAccepted(String u) async => 0;
  @override
  Future<int> countPendingSent(String u) async => 0;
}

void main() {
  late _FakeFriendshipRepo repo;
  late BlockUser usecase;

  setUp(() {
    repo = _FakeFriendshipRepo();
    usecase = BlockUser(friendshipRepo: repo);
  });

  test('creates block record when no existing friendship', () async {
    final result = await usecase.call(
      blockerUserId: 'alice',
      blockedUserId: 'bob',
      uuidGenerator: () => 'block-id',
      nowMs: 1000,
    );

    expect(result.status, FriendshipStatus.blocked);
    expect(result.userIdA, 'alice');
    expect(repo.saved, isNotNull);
  });

  test('transitions existing friendship when blocker is userIdA', () async {
    repo.existing = FriendshipEntity(
      id: 'f1',
      userIdA: 'alice',
      userIdB: 'bob',
      status: FriendshipStatus.accepted,
      createdAtMs: 100,
    );

    final result = await usecase.call(
      blockerUserId: 'alice',
      blockedUserId: 'bob',
      uuidGenerator: () => 'id',
      nowMs: 1000,
    );

    expect(result.status, FriendshipStatus.blocked);
    expect(repo.updatedWith, isNotNull);
  });

  test('reorients and recreates when blocker is userIdB', () async {
    repo.existing = FriendshipEntity(
      id: 'f1',
      userIdA: 'bob',
      userIdB: 'alice',
      status: FriendshipStatus.accepted,
      createdAtMs: 100,
    );

    final result = await usecase.call(
      blockerUserId: 'alice',
      blockedUserId: 'bob',
      uuidGenerator: () => 'new-id',
      nowMs: 1000,
    );

    expect(result.status, FriendshipStatus.blocked);
    expect(result.userIdA, 'alice');
    expect(repo.deletedId, 'f1');
    expect(repo.saved, isNotNull);
  });
}
