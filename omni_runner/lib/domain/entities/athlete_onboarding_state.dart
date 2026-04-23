import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/value_objects/athlete_onboarding_step.dart';

/// Whether the athlete chose to import Strava history or explicitly
/// opted out. `undecided` is the initial value *before* the decision
/// has been made — the whole point of L23-12 is that we no longer
/// silently treat "undecided" as "opted out".
enum StravaImportChoice {
  undecided,
  imported,
  skipped,
}

extension StravaImportChoiceWire on StravaImportChoice {
  /// Stable snake_case wire string (persistence + analytics).
  String get wire {
    switch (this) {
      case StravaImportChoice.undecided:
        return 'undecided';
      case StravaImportChoice.imported:
        return 'imported';
      case StravaImportChoice.skipped:
        return 'skipped';
    }
  }
}

/// Immutable snapshot of an athlete's onboarding state.
///
/// Held in-memory by the coach dashboard and the athlete's own
/// post-signup wizard; persisted by a follow-up
/// (`L23-12-persistence`) that adds the matching columns /
/// `coaching_onboarding_state` table. The shape is deliberately
/// backend-agnostic — the domain layer doesn't know or care whether
/// each field lives on `coaching_members`, a dedicated table, or on
/// the user's JWT claims.
final class AthleteOnboardingState extends Equatable {
  /// The athlete being onboarded. `auth.users.id` once known; the
  /// object may be constructed with [userId] `null` when the invite
  /// has been dispatched but not accepted yet.
  final String? userId;

  /// The coaching group the athlete is being added to.
  final String groupId;

  /// The authenticated coach that dispatched the invite. Recorded
  /// for auditability — nudges and stale-invite alerts fan out to
  /// this user.
  final String invitedByCoachUserId;

  /// The current step in the funnel.
  final AthleteOnboardingStep currentStep;

  /// When the invite was dispatched. Used for stale-invite
  /// detection. UTC.
  final DateTime invitedAt;

  /// When the athlete signed in and joined the group. `null` until
  /// `currentStep >= joined`.
  final DateTime? joinedAt;

  /// Whether (and how) the athlete decided about Strava history.
  final StravaImportChoice stravaChoice;

  /// Whether training zones are populated — either from Strava
  /// backfill, from a calibration time trial (L23-14), or from the
  /// coach's manual override.
  final bool zonesReady;

  const AthleteOnboardingState({
    required this.groupId,
    required this.invitedByCoachUserId,
    required this.currentStep,
    required this.invitedAt,
    this.userId,
    this.joinedAt,
    this.stravaChoice = StravaImportChoice.undecided,
    this.zonesReady = false,
  });

  /// Convenience constructor for the initial state: coach dispatched
  /// the invite, nothing else has happened yet.
  factory AthleteOnboardingState.initial({
    required String groupId,
    required String invitedByCoachUserId,
    required DateTime invitedAt,
  }) {
    return AthleteOnboardingState(
      groupId: groupId,
      invitedByCoachUserId: invitedByCoachUserId,
      currentStep: AthleteOnboardingStep.invited,
      invitedAt: invitedAt.toUtc(),
    );
  }

  AthleteOnboardingState copyWith({
    String? userId,
    AthleteOnboardingStep? currentStep,
    DateTime? joinedAt,
    StravaImportChoice? stravaChoice,
    bool? zonesReady,
  }) {
    return AthleteOnboardingState(
      groupId: groupId,
      invitedByCoachUserId: invitedByCoachUserId,
      currentStep: currentStep ?? this.currentStep,
      invitedAt: invitedAt,
      userId: userId ?? this.userId,
      joinedAt: joinedAt ?? this.joinedAt,
      stravaChoice: stravaChoice ?? this.stravaChoice,
      zonesReady: zonesReady ?? this.zonesReady,
    );
  }

  /// `true` when onboarding is completed. Coaches filter out these
  /// rows from their "needs attention" panel.
  bool get isComplete => currentStep == AthleteOnboardingStep.completed;

  @override
  List<Object?> get props => [
        userId,
        groupId,
        invitedByCoachUserId,
        currentStep,
        invitedAt,
        joinedAt,
        stravaChoice,
        zonesReady,
      ];
}
