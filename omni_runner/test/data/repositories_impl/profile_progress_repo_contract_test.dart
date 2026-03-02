import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';

final class InMemoryProfileProgressRepo implements IProfileProgressRepo {
  final _store = <String, ProfileProgressEntity>{};

  @override
  Future<ProfileProgressEntity> getByUserId(String userId) async {
    if (_store.containsKey(userId)) return _store[userId]!;
    final fresh = ProfileProgressEntity(userId: userId);
    await save(fresh);
    return fresh;
  }

  @override
  Future<void> save(ProfileProgressEntity profile) async {
    _store[profile.userId] = profile;
  }
}

void main() {
  late InMemoryProfileProgressRepo repo;

  setUp(() => repo = InMemoryProfileProgressRepo());

  group('IProfileProgressRepo contract', () {
    test('getByUserId auto-creates zero-state profile', () async {
      final p = await repo.getByUserId('u1');
      expect(p.userId, 'u1');
      expect(p.totalXp, 0);
      expect(p.level, 0);
      expect(p.dailyStreakCount, 0);
      expect(p.lifetimeSessionCount, 0);
      expect(p.lifetimeDistanceM, 0.0);
    });

    test('save and getByUserId round-trip', () async {
      final p = ProfileProgressEntity(
        userId: 'u1',
        totalXp: 5000,
        dailyStreakCount: 7,
        lifetimeSessionCount: 42,
        lifetimeDistanceM: 210000,
      );
      await repo.save(p);

      final found = await repo.getByUserId('u1');
      expect(found, equals(p));
    });

    test('save overwrites existing', () async {
      await repo.save(const ProfileProgressEntity(
        userId: 'u1',
        totalXp: 100,
      ));
      await repo.save(const ProfileProgressEntity(
        userId: 'u1',
        totalXp: 500,
      ));

      final p = await repo.getByUserId('u1');
      expect(p.totalXp, 500);
    });

    test('users are isolated', () async {
      await repo.save(const ProfileProgressEntity(
        userId: 'u1',
        totalXp: 100,
      ));
      await repo.save(const ProfileProgressEntity(
        userId: 'u2',
        totalXp: 200,
      ));

      expect((await repo.getByUserId('u1')).totalXp, 100);
      expect((await repo.getByUserId('u2')).totalXp, 200);
    });
  });

  group('ProfileProgressEntity level math', () {
    test('level 0 at 0 XP', () {
      const p = ProfileProgressEntity(userId: 'u', totalXp: 0);
      expect(p.level, 0);
    });

    test('level increases with XP', () {
      const p = ProfileProgressEntity(userId: 'u', totalXp: 5000);
      expect(p.level, greaterThan(0));
    });

    test('xpForLevel is monotonically increasing', () {
      for (var i = 1; i < 50; i++) {
        expect(
          ProfileProgressEntity.xpForLevel(i + 1),
          greaterThan(ProfileProgressEntity.xpForLevel(i)),
        );
      }
    });

    test('xpToNextLevel is always positive for finite XP', () {
      const p = ProfileProgressEntity(userId: 'u', totalXp: 1000);
      expect(p.xpToNextLevel, greaterThan(0));
    });

    test('lifetimeDistanceKm converts correctly', () {
      const p = ProfileProgressEntity(
        userId: 'u',
        lifetimeDistanceM: 42195.0,
      );
      expect(p.lifetimeDistanceKm, closeTo(42.195, 0.001));
    });

    test('lifetimeMovingMin converts correctly', () {
      const p = ProfileProgressEntity(
        userId: 'u',
        lifetimeMovingMs: 3600000,
      );
      expect(p.lifetimeMovingMin, closeTo(60.0, 0.001));
    });
  });
}
