/// Canonical steps an athlete traverses when joining a coaching group.
///
/// L23-12 — the finding states that today the athlete lifecycle is
/// binary: coach clicks "invite" and the athlete gets an email; the
/// app has **no guided post-signup flow**. In particular it never
/// asks "import 6 months of Strava history to calibrate zones" — the
/// coach ends up shipping the first training plan blind.
///
/// This enum is the single source of truth for *where* each athlete
/// is in the onboarding funnel. All coach dashboards, notifications,
/// nudges, and analytics events read from it; a new step is a
/// domain-level decision that must be reflected here.
///
/// The order of the enum matters and is enforced by CI:
/// `ordinal` is used by [AthleteOnboardingService] to decide whether
/// a state transition is forward (allowed) or backward (rejected).
enum AthleteOnboardingStep {
  /// Coach dispatched the invitation (email / link). The athlete has
  /// **not** clicked through or signed up yet.
  invited,

  /// The athlete signed up / signed in and joined the group. We now
  /// know their `auth.users.id`. Nothing is known about them beyond
  /// that.
  joined,

  /// The athlete filled the profile form (name, birthdate, running
  /// experience, goal distance). This is the minimum the coach needs
  /// to prescribe anything useful.
  profileCompleted,

  /// The athlete has made an explicit decision about Strava history
  /// import — either they linked their account (and the 6-month
  /// backfill is queued / done) or they explicitly opted out. **Both
  /// paths** converge here — the finding is about removing the
  /// ambiguous "no decision yet" state that silently defaulted to
  /// "no history".
  stravaChoiceMade,

  /// Training zones (HR, pace) are populated on the athlete profile.
  /// Either derived from imported Strava history or from the test
  /// protocol (time trial, L23-14) or from coach-defined defaults.
  zonesReady,

  /// Onboarding is complete. The first training plan can ship.
  completed,
}

extension AthleteOnboardingStepWire on AthleteOnboardingStep {
  /// Stable snake_case wire string. Used as the persistence value
  /// (future column `coaching_members.onboarding_step`) and as the
  /// analytics event discriminator. Changing any of these is a
  /// breaking change; the CI guard pins them.
  String get wire {
    switch (this) {
      case AthleteOnboardingStep.invited:
        return 'invited';
      case AthleteOnboardingStep.joined:
        return 'joined';
      case AthleteOnboardingStep.profileCompleted:
        return 'profile_completed';
      case AthleteOnboardingStep.stravaChoiceMade:
        return 'strava_choice_made';
      case AthleteOnboardingStep.zonesReady:
        return 'zones_ready';
      case AthleteOnboardingStep.completed:
        return 'completed';
    }
  }
}

/// Null-safe resolver for the wire strings above. Returns `null`
/// when the input doesn't match any known step — never throws.
AthleteOnboardingStep? athleteOnboardingStepFromWire(String? wire) {
  if (wire == null) return null;
  for (final s in AthleteOnboardingStep.values) {
    if (s.wire == wire) return s;
  }
  return null;
}

/// Canonical bounds for athlete-onboarding timing / policy. Kept in
/// the value-object layer (not remote config) so the CI guard can
/// enforce them — changing a bound is a content-change that must be
/// reviewed alongside the coach-dashboard copy that depends on it.
abstract final class AthleteOnboardingBounds {
  /// After this many days in `invited` status without progressing to
  /// `joined`, the invite is considered stale and the coach dashboard
  /// should surface a "resend / revoke" action.
  ///
  /// The number comes from the finding context: the coach doesn't
  /// want to nag the athlete every day, but a two-week silence means
  /// the invite got buried or the email is wrong. 14 days is also
  /// the default unsubscribe grace window on most transactional
  /// platforms.
  static const int staleInviteDays = 14;

  /// After this many days in `joined` without completing the profile
  /// the athlete is nudged (and the coach is told). Shorter than
  /// [staleInviteDays] because we already have a signed-in user — the
  /// cost of a nudge is near-zero and signup drop-off is a real
  /// funnel risk.
  static const int stalledProfileDays = 3;
}
