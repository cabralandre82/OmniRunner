import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_onboarding_state.dart';
import 'package:omni_runner/domain/services/athlete_onboarding_service.dart';
import 'package:omni_runner/domain/value_objects/athlete_onboarding_step.dart';

void main() {
  const svc = AthleteOnboardingService();
  final invitedAt = DateTime.utc(2026, 4, 1, 10);

  AthleteOnboardingState fresh() => svc.invite(
        groupId: 'group-123',
        invitedByCoachUserId: 'coach-456',
        now: invitedAt,
      );

  group('AthleteOnboardingService — enum + wire contract', () {
    test('AthleteOnboardingStep has exactly 6 values in canonical order',
        () {
      expect(AthleteOnboardingStep.values, hasLength(6));
      expect(AthleteOnboardingStep.values.first,
          AthleteOnboardingStep.invited);
      expect(AthleteOnboardingStep.values.last,
          AthleteOnboardingStep.completed);
    });

    test('wire strings are the documented snake_case contract', () {
      expect(AthleteOnboardingStep.invited.wire, 'invited');
      expect(AthleteOnboardingStep.joined.wire, 'joined');
      expect(AthleteOnboardingStep.profileCompleted.wire,
          'profile_completed');
      expect(AthleteOnboardingStep.stravaChoiceMade.wire,
          'strava_choice_made');
      expect(AthleteOnboardingStep.zonesReady.wire, 'zones_ready');
      expect(AthleteOnboardingStep.completed.wire, 'completed');
    });

    test('fromWire round-trips every value and rejects garbage', () {
      for (final s in AthleteOnboardingStep.values) {
        expect(athleteOnboardingStepFromWire(s.wire), s);
      }
      expect(athleteOnboardingStepFromWire(null), isNull);
      expect(athleteOnboardingStepFromWire(''), isNull);
      expect(athleteOnboardingStepFromWire('done'), isNull);
    });

    test('StravaImportChoice wire strings are stable', () {
      expect(StravaImportChoice.undecided.wire, 'undecided');
      expect(StravaImportChoice.imported.wire, 'imported');
      expect(StravaImportChoice.skipped.wire, 'skipped');
    });

    test('Bounds are pinned to the documented values', () {
      expect(AthleteOnboardingBounds.staleInviteDays, 14);
      expect(AthleteOnboardingBounds.stalledProfileDays, 3);
    });
  });

  group('AthleteOnboardingService — invite', () {
    test('produces state anchored at invited', () {
      final s = fresh();
      expect(s.currentStep, AthleteOnboardingStep.invited);
      expect(s.userId, isNull);
      expect(s.joinedAt, isNull);
      expect(s.stravaChoice, StravaImportChoice.undecided);
      expect(s.zonesReady, isFalse);
      expect(s.invitedAt.isUtc, isTrue);
    });

    test('rejects empty groupId / coach id', () {
      expect(
        () => svc.invite(
          groupId: '',
          invitedByCoachUserId: 'coach-x',
          now: invitedAt,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => svc.invite(
          groupId: 'g',
          invitedByCoachUserId: '',
          now: invitedAt,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('normalises invitedAt to UTC', () {
      final local = DateTime(2026, 4, 1, 10).toLocal();
      final s = svc.invite(
        groupId: 'g',
        invitedByCoachUserId: 'c',
        now: local,
      );
      expect(s.invitedAt.isUtc, isTrue);
    });
  });

  group('AthleteOnboardingService — forward transitions (happy path)', () {
    test('invited → joined → profile → strava → zones → completed', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u-1', now: DateTime.utc(2026, 4, 2));
      expect(s.currentStep, AthleteOnboardingStep.joined);
      expect(s.userId, 'u-1');
      expect(s.joinedAt, DateTime.utc(2026, 4, 2));

      s = svc.markProfileCompleted(s);
      expect(s.currentStep, AthleteOnboardingStep.profileCompleted);

      s = svc.markStravaChoice(s, choice: StravaImportChoice.imported);
      expect(s.currentStep, AthleteOnboardingStep.stravaChoiceMade);
      expect(s.stravaChoice, StravaImportChoice.imported);

      s = svc.markZonesReady(s);
      expect(s.currentStep, AthleteOnboardingStep.zonesReady);
      expect(s.zonesReady, isTrue);

      s = svc.markCompleted(s);
      expect(s.currentStep, AthleteOnboardingStep.completed);
      expect(s.isComplete, isTrue);
    });

    test('skipped Strava path also completes cleanly', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: DateTime.utc(2026, 4, 2));
      s = svc.markProfileCompleted(s);
      s = svc.markStravaChoice(s, choice: StravaImportChoice.skipped);
      expect(s.stravaChoice, StravaImportChoice.skipped);
      s = svc.markZonesReady(s);
      s = svc.markCompleted(s);
      expect(s.isComplete, isTrue);
    });
  });

  group('AthleteOnboardingService — rejects backward / out-of-order moves',
      () {
    test('markJoined on already-joined state throws', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: invitedAt);
      expect(
        () => svc.markJoined(s, userId: 'u2', now: invitedAt),
        throwsA(isA<AthleteOnboardingTransitionError>()),
      );
    });

    test('markProfileCompleted before markJoined throws', () {
      expect(
        () => svc.markProfileCompleted(fresh()),
        throwsA(isA<AthleteOnboardingTransitionError>()),
      );
    });

    test('markStravaChoice before markProfileCompleted throws', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: invitedAt);
      expect(
        () => svc.markStravaChoice(s, choice: StravaImportChoice.skipped),
        throwsA(isA<AthleteOnboardingTransitionError>()),
      );
    });

    test('markStravaChoice with undecided throws ArgumentError', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: invitedAt);
      s = svc.markProfileCompleted(s);
      expect(
        () =>
            svc.markStravaChoice(s, choice: StravaImportChoice.undecided),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('markZonesReady before strava choice throws', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: invitedAt);
      s = svc.markProfileCompleted(s);
      expect(
        () => svc.markZonesReady(s),
        throwsA(isA<AthleteOnboardingTransitionError>()),
      );
    });

    test('markCompleted before zones throws', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: invitedAt);
      s = svc.markProfileCompleted(s);
      s = svc.markStravaChoice(s, choice: StravaImportChoice.imported);
      expect(
        () => svc.markCompleted(s),
        throwsA(isA<AthleteOnboardingTransitionError>()),
      );
    });

    test('markJoined with empty userId throws ArgumentError', () {
      expect(
        () => svc.markJoined(fresh(), userId: '', now: invitedAt),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AthleteOnboardingService — nextStep', () {
    test('progresses through every step and returns null when complete', () {
      var s = fresh();
      expect(svc.nextStep(s), AthleteOnboardingStep.joined);
      s = svc.markJoined(s, userId: 'u', now: invitedAt);
      expect(svc.nextStep(s), AthleteOnboardingStep.profileCompleted);
      s = svc.markProfileCompleted(s);
      expect(svc.nextStep(s), AthleteOnboardingStep.stravaChoiceMade);
      s = svc.markStravaChoice(s, choice: StravaImportChoice.imported);
      expect(svc.nextStep(s), AthleteOnboardingStep.zonesReady);
      s = svc.markZonesReady(s);
      expect(svc.nextStep(s), AthleteOnboardingStep.completed);
      s = svc.markCompleted(s);
      expect(svc.nextStep(s), isNull);
    });
  });

  group('AthleteOnboardingService — nudgeFor', () {
    test('fresh invite within window → none', () {
      final s = fresh();
      final now = invitedAt.add(const Duration(days: 3));
      expect(svc.nudgeFor(s, now: now), AthleteOnboardingNudge.none);
    });

    test('invite exactly at stale threshold → staleInvite', () {
      final s = fresh();
      final now = invitedAt.add(const Duration(
          days: AthleteOnboardingBounds.staleInviteDays));
      expect(
          svc.nudgeFor(s, now: now), AthleteOnboardingNudge.staleInvite);
    });

    test('joined athlete before stalled threshold → none', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: DateTime.utc(2026, 4, 2));
      final now = DateTime.utc(2026, 4, 3);
      expect(svc.nudgeFor(s, now: now), AthleteOnboardingNudge.none);
    });

    test('joined athlete stalled on profile → profileStalled', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: DateTime.utc(2026, 4, 2));
      final now = DateTime.utc(2026, 4, 6); // 4 days later
      expect(svc.nudgeFor(s, now: now),
          AthleteOnboardingNudge.profileStalled);
    });

    test('profile completed → stravaChoiceRequired', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: DateTime.utc(2026, 4, 2));
      s = svc.markProfileCompleted(s);
      expect(
        svc.nudgeFor(s, now: DateTime.utc(2026, 4, 2)),
        AthleteOnboardingNudge.stravaChoiceRequired,
      );
    });

    test('strava chosen + zones missing → zonesMissing', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: DateTime.utc(2026, 4, 2));
      s = svc.markProfileCompleted(s);
      s = svc.markStravaChoice(s, choice: StravaImportChoice.skipped);
      expect(
        svc.nudgeFor(s, now: DateTime.utc(2026, 4, 2)),
        AthleteOnboardingNudge.zonesMissing,
      );
    });

    test('zones ready → readyForFirstPlan', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: DateTime.utc(2026, 4, 2));
      s = svc.markProfileCompleted(s);
      s = svc.markStravaChoice(s, choice: StravaImportChoice.imported);
      s = svc.markZonesReady(s);
      expect(
        svc.nudgeFor(s, now: DateTime.utc(2026, 4, 3)),
        AthleteOnboardingNudge.readyForFirstPlan,
      );
    });

    test('completed → readyForFirstPlan', () {
      var s = fresh();
      s = svc.markJoined(s, userId: 'u', now: DateTime.utc(2026, 4, 2));
      s = svc.markProfileCompleted(s);
      s = svc.markStravaChoice(s, choice: StravaImportChoice.imported);
      s = svc.markZonesReady(s);
      s = svc.markCompleted(s);
      expect(
        svc.nudgeFor(s, now: DateTime.utc(2026, 4, 3)),
        AthleteOnboardingNudge.readyForFirstPlan,
      );
    });

    test('accepts non-UTC now and normalises', () {
      final s = fresh();
      final localNow = DateTime(2026, 4, 20).toLocal();
      expect(
        svc.nudgeFor(s, now: localNow),
        AthleteOnboardingNudge.staleInvite,
      );
    });
  });

  group('AthleteOnboardingState — props', () {
    test('equality is structural', () {
      final a = AthleteOnboardingState.initial(
        groupId: 'g',
        invitedByCoachUserId: 'c',
        invitedAt: invitedAt,
      );
      final b = AthleteOnboardingState.initial(
        groupId: 'g',
        invitedByCoachUserId: 'c',
        invitedAt: invitedAt,
      );
      expect(a, equals(b));
    });

    test('copyWith advances currentStep without clobbering history', () {
      final a = fresh();
      final b = a.copyWith(currentStep: AthleteOnboardingStep.joined);
      expect(b.currentStep, AthleteOnboardingStep.joined);
      expect(b.groupId, a.groupId);
      expect(b.invitedByCoachUserId, a.invitedByCoachUserId);
      expect(b.invitedAt, a.invitedAt);
    });
  });
}
