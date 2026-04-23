import 'package:omni_runner/domain/entities/athlete_onboarding_state.dart';
import 'package:omni_runner/domain/value_objects/athlete_onboarding_step.dart';

/// Per-step nudge category returned by [AthleteOnboardingService.nudgeFor].
///
/// The coach dashboard and the transactional-email runner (L15-04)
/// map these to locale-aware copy. Keeping them as an enum lets the
/// CI guard on L15-04 / L22-06 enforce that every coach-facing locale
/// has a translation for every category.
enum AthleteOnboardingNudge {
  /// No nudge needed right now.
  none,

  /// Invite dispatched but not accepted after
  /// [AthleteOnboardingBounds.staleInviteDays]. Coach should resend
  /// or revoke.
  staleInvite,

  /// Athlete joined but hasn't filled the profile after
  /// [AthleteOnboardingBounds.stalledProfileDays].
  profileStalled,

  /// Athlete must explicitly decide about Strava history. This is
  /// the UX step the finding specifically asked for.
  stravaChoiceRequired,

  /// Zones missing. Either Strava backfill in progress (transient)
  /// or the athlete needs to schedule a test (L23-14).
  zonesMissing,

  /// All onboarding steps done — dashboard can greet the athlete
  /// with "ready for first plan".
  readyForFirstPlan,
}

/// Error raised when a transition would move the state machine
/// backwards. The domain layer never auto-rolls back; moving an
/// athlete back to an earlier step requires a coach action with its
/// own audit trail (future: `fn_reset_onboarding`).
class AthleteOnboardingTransitionError extends ArgumentError {
  AthleteOnboardingTransitionError(super.message);
}

/// Pure, stateless service that implements the onboarding
/// state-machine invariants.
///
/// Why pure / stateless:
/// - it is consumed by the coach dashboard, the athlete's wizard,
///   the email runner, and the analytics collector — inline logic
///   in any of those would diverge fast;
/// - pure Dart means the same rules apply to tests, CI, and server
///   edge functions (via `dart compile` in the future).
///
/// Transitions are **one-way forward**: calling [markJoined] when
/// state is already `profileCompleted` is an error, not a no-op.
/// Reason: silently accepting backward moves would mask bugs (e.g.
/// a repo reading stale rows would look like it "worked").
final class AthleteOnboardingService {
  const AthleteOnboardingService();

  /// Resolve the next UX step for the athlete's wizard.
  ///
  /// Returns `null` when onboarding is complete — the caller should
  /// dismiss the wizard.
  AthleteOnboardingStep? nextStep(AthleteOnboardingState state) {
    switch (state.currentStep) {
      case AthleteOnboardingStep.invited:
        return AthleteOnboardingStep.joined;
      case AthleteOnboardingStep.joined:
        return AthleteOnboardingStep.profileCompleted;
      case AthleteOnboardingStep.profileCompleted:
        return AthleteOnboardingStep.stravaChoiceMade;
      case AthleteOnboardingStep.stravaChoiceMade:
        return AthleteOnboardingStep.zonesReady;
      case AthleteOnboardingStep.zonesReady:
        return AthleteOnboardingStep.completed;
      case AthleteOnboardingStep.completed:
        return null;
    }
  }

  /// Compute the nudge category for the athlete, given the current
  /// time. `now` is injected so tests are deterministic and server-
  /// side callers can feed a mocked clock.
  AthleteOnboardingNudge nudgeFor(
    AthleteOnboardingState state, {
    required DateTime now,
  }) {
    final nowUtc = now.toUtc();

    switch (state.currentStep) {
      case AthleteOnboardingStep.invited:
        final ageDays = _daysBetween(state.invitedAt, nowUtc);
        if (ageDays >= AthleteOnboardingBounds.staleInviteDays) {
          return AthleteOnboardingNudge.staleInvite;
        }
        return AthleteOnboardingNudge.none;
      case AthleteOnboardingStep.joined:
        final joinedAt = state.joinedAt;
        if (joinedAt != null) {
          final ageDays = _daysBetween(joinedAt, nowUtc);
          if (ageDays >= AthleteOnboardingBounds.stalledProfileDays) {
            return AthleteOnboardingNudge.profileStalled;
          }
        }
        return AthleteOnboardingNudge.none;
      case AthleteOnboardingStep.profileCompleted:
        return AthleteOnboardingNudge.stravaChoiceRequired;
      case AthleteOnboardingStep.stravaChoiceMade:
        return state.zonesReady
            ? AthleteOnboardingNudge.none
            : AthleteOnboardingNudge.zonesMissing;
      case AthleteOnboardingStep.zonesReady:
      case AthleteOnboardingStep.completed:
        return AthleteOnboardingNudge.readyForFirstPlan;
    }
  }

  /// Transition: coach dispatched a fresh invite. Constructs an
  /// initial state. Present as a method (vs using
  /// [AthleteOnboardingState.initial] directly) so callers hit the
  /// service facade consistently.
  AthleteOnboardingState invite({
    required String groupId,
    required String invitedByCoachUserId,
    required DateTime now,
  }) {
    if (groupId.isEmpty) {
      throw ArgumentError.value(groupId, 'groupId', 'must not be empty');
    }
    if (invitedByCoachUserId.isEmpty) {
      throw ArgumentError.value(
          invitedByCoachUserId, 'invitedByCoachUserId', 'must not be empty');
    }
    return AthleteOnboardingState.initial(
      groupId: groupId,
      invitedByCoachUserId: invitedByCoachUserId,
      invitedAt: now,
    );
  }

  /// Transition: athlete signed in and joined the group. Sets the
  /// `userId` and advances the step.
  AthleteOnboardingState markJoined(
    AthleteOnboardingState state, {
    required String userId,
    required DateTime now,
  }) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    _requireAt(state, AthleteOnboardingStep.invited, 'markJoined');
    return state.copyWith(
      userId: userId,
      currentStep: AthleteOnboardingStep.joined,
      joinedAt: now.toUtc(),
    );
  }

  /// Transition: athlete filled the required profile fields.
  AthleteOnboardingState markProfileCompleted(
    AthleteOnboardingState state,
  ) {
    _requireAt(state, AthleteOnboardingStep.joined, 'markProfileCompleted');
    return state.copyWith(
      currentStep: AthleteOnboardingStep.profileCompleted,
    );
  }

  /// Transition: athlete explicitly chose whether to import Strava
  /// history. Both `imported` and `skipped` are valid outcomes;
  /// passing `undecided` is an error (that's why we're here).
  AthleteOnboardingState markStravaChoice(
    AthleteOnboardingState state, {
    required StravaImportChoice choice,
  }) {
    if (choice == StravaImportChoice.undecided) {
      throw ArgumentError.value(
        choice,
        'choice',
        'strava choice must be explicit (imported or skipped)',
      );
    }
    _requireAt(
      state,
      AthleteOnboardingStep.profileCompleted,
      'markStravaChoice',
    );
    return state.copyWith(
      stravaChoice: choice,
      currentStep: AthleteOnboardingStep.stravaChoiceMade,
    );
  }

  /// Transition: zones were populated (Strava backfill, test
  /// protocol, or coach override). The source is recorded upstream
  /// in the `athlete_zones` row (L21-05 pending), not here.
  AthleteOnboardingState markZonesReady(AthleteOnboardingState state) {
    _requireAt(state, AthleteOnboardingStep.stravaChoiceMade, 'markZonesReady');
    return state.copyWith(
      currentStep: AthleteOnboardingStep.zonesReady,
      zonesReady: true,
    );
  }

  /// Transition: coach confirms the athlete is ready for the first
  /// plan. This is a deliberate coach-in-the-loop step — we don't
  /// auto-complete from `zonesReady` so the coach has a moment to
  /// sanity-check zones before the first prescription lands.
  AthleteOnboardingState markCompleted(AthleteOnboardingState state) {
    _requireAt(state, AthleteOnboardingStep.zonesReady, 'markCompleted');
    if (!state.zonesReady) {
      throw AthleteOnboardingTransitionError(
        'cannot complete onboarding while zones are not ready',
      );
    }
    return state.copyWith(currentStep: AthleteOnboardingStep.completed);
  }

  void _requireAt(
    AthleteOnboardingState state,
    AthleteOnboardingStep expected,
    String operation,
  ) {
    if (state.currentStep != expected) {
      throw AthleteOnboardingTransitionError(
        '$operation requires currentStep == ${expected.wire}, '
        'got ${state.currentStep.wire}',
      );
    }
  }

  int _daysBetween(DateTime from, DateTime to) {
    final fromDay = DateTime.utc(from.year, from.month, from.day);
    final toDay = DateTime.utc(to.year, to.month, to.day);
    return toDay.difference(fromDay).inDays;
  }
}
