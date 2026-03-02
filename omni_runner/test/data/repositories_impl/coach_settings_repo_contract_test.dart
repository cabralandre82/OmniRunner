import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coach_settings_entity.dart';
import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';

final class InMemoryCoachSettingsRepo implements ICoachSettingsRepo {
  CoachSettingsEntity? _stored;

  @override
  Future<CoachSettingsEntity> load() async {
    return _stored ?? const CoachSettingsEntity();
  }

  @override
  Future<void> save(CoachSettingsEntity settings) async {
    _stored = settings;
  }
}

void main() {
  late InMemoryCoachSettingsRepo repo;

  setUp(() => repo = InMemoryCoachSettingsRepo());

  group('ICoachSettingsRepo contract', () {
    test('load returns defaults when nothing saved', () async {
      final s = await repo.load();
      expect(s.kmEnabled, isTrue);
      expect(s.ghostEnabled, isTrue);
      expect(s.periodicEnabled, isTrue);
      expect(s.hrZoneEnabled, isTrue);
      expect(s.maxHr, 190);
      expect(s.useImperial, isFalse);
      expect(s.profileVisibleInRanking, isTrue);
      expect(s.shareActivityInFeed, isTrue);
    });

    test('save and load round-trip preserves all fields', () async {
      const custom = CoachSettingsEntity(
        kmEnabled: false,
        ghostEnabled: false,
        periodicEnabled: true,
        hrZoneEnabled: false,
        maxHr: 185,
        useImperial: true,
        profileVisibleInRanking: false,
        shareActivityInFeed: false,
      );

      await repo.save(custom);
      final loaded = await repo.load();
      expect(loaded, equals(custom));
    });

    test('save overwrites previous settings', () async {
      await repo.save(const CoachSettingsEntity(maxHr: 180));
      await repo.save(const CoachSettingsEntity(maxHr: 200));

      final loaded = await repo.load();
      expect(loaded.maxHr, 200);
    });

    test('CoachSettingsEntity.copyWith works correctly', () {
      const original = CoachSettingsEntity();
      final updated = original.copyWith(
        kmEnabled: false,
        maxHr: 175,
        useImperial: true,
      );

      expect(updated.kmEnabled, isFalse);
      expect(updated.maxHr, 175);
      expect(updated.useImperial, isTrue);
      expect(updated.ghostEnabled, isTrue);
    });
  });
}
