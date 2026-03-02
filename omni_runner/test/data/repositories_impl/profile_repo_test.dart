import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/data/repositories_impl/profile_repo.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';

final class FakeProfileDatasource implements IProfileRepo {
  ProfileEntity? _stored;
  bool shouldThrow = false;

  @override
  Future<ProfileEntity?> getMyProfile() async {
    if (shouldThrow) throw Exception('network error');
    return _stored;
  }

  @override
  Future<ProfileEntity> upsertMyProfile(ProfilePatch patch) async {
    if (shouldThrow) throw Exception('network error');
    final now = DateTime.now();
    _stored = ProfileEntity(
      id: 'user-1',
      displayName: patch.displayName ?? _stored?.displayName ?? 'Runner',
      avatarUrl: patch.avatarUrl ?? _stored?.avatarUrl,
      createdAt: _stored?.createdAt ?? now,
      updatedAt: now,
    );
    return _stored!;
  }
}

void main() {
  late FakeProfileDatasource ds;
  late ProfileRepo repo;

  setUp(() {
    ds = FakeProfileDatasource();
    repo = ProfileRepo(datasource: ds);
  });

  group('ProfileRepo', () {
    test('getMyProfile returns profile when exists', () async {
      await ds.upsertMyProfile(const ProfilePatch(displayName: 'Alice'));
      final p = await repo.getMyProfile();
      expect(p, isNotNull);
      expect(p!.displayName, 'Alice');
    });

    test('getMyProfile auto-creates when datasource returns null', () async {
      final p = await repo.getMyProfile();
      expect(p, isNotNull);
      expect(p!.displayName, 'Runner');
    });

    test('getMyProfile returns null on error', () async {
      ds.shouldThrow = true;
      final p = await repo.getMyProfile();
      expect(p, isNull);
    });

    test('upsertMyProfile delegates and returns result', () async {
      final p = await repo.upsertMyProfile(
        const ProfilePatch(displayName: 'Bob', avatarUrl: 'https://img.test/a.png'),
      );
      expect(p.displayName, 'Bob');
      expect(p.avatarUrl, 'https://img.test/a.png');
    });

    test('upsertMyProfile rethrows on error', () async {
      ds.shouldThrow = true;
      expect(
        () => repo.upsertMyProfile(const ProfilePatch(displayName: 'X')),
        throwsException,
      );
    });

    test('ProfileEntity.fromJson parses correctly', () {
      final json = {
        'id': 'u1',
        'display_name': 'Test',
        'avatar_url': null,
        'onboarding_state': 'READY',
        'user_role': 'athlete',
        'created_via': 'google',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-06-15T12:00:00Z',
      };

      final p = ProfileEntity.fromJson(json);
      expect(p.id, 'u1');
      expect(p.displayName, 'Test');
      expect(p.onboardingState, OnboardingState.ready);
      expect(p.isOnboardingComplete, isTrue);
      expect(p.userRole, 'athlete');
    });

    test('ProfileEntity.toJson round-trips correctly', () {
      final p = ProfileEntity(
        id: 'u1',
        displayName: 'Test',
        onboardingState: OnboardingState.roleSelected,
        createdAt: DateTime.utc(2025),
        updatedAt: DateTime.utc(2025, 6),
      );

      final json = p.toJson();
      expect(json['display_name'], 'Test');
      expect(json['onboarding_state'], 'ROLE_SELECTED');
    });
  });
}
