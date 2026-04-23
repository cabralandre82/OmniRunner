import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/milestone_entity.dart';
import 'package:omni_runner/domain/services/milestone_copy_builder.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';
import 'package:omni_runner/domain/value_objects/milestone_kind.dart';

void main() {
  group('MilestoneCopyBuilder — coverage', () {
    test('every MilestoneKind produces non-empty copy in every locale', () {
      for (final locale in AudioCoachLocale.values) {
        final builder = MilestoneCopyBuilder(locale: locale);
        for (final kind in MilestoneKind.values) {
          final copy = builder.build(MilestoneEntity(
            kind: kind,
            achievedAtMs: 1_700_000_000_000,
            triggerDistanceM:
                kind.distanceThresholdM != null ? 5100 : null,
            triggerCount: kind == MilestoneKind.firstWeek ? 3 : null,
          ));
          expect(copy.title.isNotEmpty, isTrue,
              reason: 'locale=${locale.languageTag} kind=$kind title empty');
          expect(copy.subtitle.isNotEmpty, isTrue,
              reason: 'locale=${locale.languageTag} kind=$kind subtitle empty');
          expect(copy.shareText.isNotEmpty, isTrue,
              reason: 'locale=${locale.languageTag} kind=$kind shareText empty');
        }
      }
    });

    test('pt-BR firstRun title carries the Portuguese phrasing', () {
      const builder = MilestoneCopyBuilder();
      final copy = builder.build(MilestoneEntity(
        kind: MilestoneKind.firstRun,
        achievedAtMs: 0,
      ));
      expect(copy.title, contains('Primeira corrida'));
    });

    test('en firstFiveK embeds the trigger distance', () {
      const builder = MilestoneCopyBuilder(locale: AudioCoachLocale.en);
      final copy = builder.build(MilestoneEntity(
        kind: MilestoneKind.firstFiveK,
        achievedAtMs: 0,
        triggerDistanceM: 5100,
      ));
      expect(copy.subtitle, contains('5.10 km'));
    });

    test('es streakThirty uses "30 días" phrasing', () {
      const builder = MilestoneCopyBuilder(locale: AudioCoachLocale.es);
      final copy = builder.build(MilestoneEntity(
        kind: MilestoneKind.streakThirty,
        achievedAtMs: 0,
        triggerCount: 30,
      ));
      expect(copy.title, contains('30 días'));
    });

    test('shareText always mentions Omni Runner for social reach', () {
      for (final locale in AudioCoachLocale.values) {
        final builder = MilestoneCopyBuilder(locale: locale);
        for (final kind in MilestoneKind.values) {
          final copy = builder.build(MilestoneEntity(
            kind: kind,
            achievedAtMs: 0,
            triggerDistanceM:
                kind.distanceThresholdM != null ? 5100 : null,
          ));
          expect(
            copy.shareText.contains('Omni Runner'),
            isTrue,
            reason:
                'locale=${locale.languageTag} kind=$kind missing "Omni Runner" in shareText',
          );
        }
      }
    });

    test('requiredKinds matches every enum value (CI invariant)', () {
      expect(MilestoneCopyBuilder.requiredKinds.toSet(),
          MilestoneKind.values.toSet());
    });

    test('MilestoneEntity dedup key for longestRunEver augments with distance',
        () {
      final a = const MilestoneEntity(
        kind: MilestoneKind.longestRunEver,
        achievedAtMs: 0,
        triggerDistanceM: 7800,
      );
      final b = const MilestoneEntity(
        kind: MilestoneKind.longestRunEver,
        achievedAtMs: 0,
        triggerDistanceM: 9200,
      );
      expect(a.dedupKey, 'longest_run_ever:780');
      expect(b.dedupKey, 'longest_run_ever:920');
      expect(a.dedupKey, isNot(b.dedupKey));
    });
  });
}
