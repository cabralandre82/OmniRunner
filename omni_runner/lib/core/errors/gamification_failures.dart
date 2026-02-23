/// Failures specific to the gamification engine.
///
/// Sealed hierarchy — enables exhaustive pattern matching in BLoC.
/// See `docs/GAMIFICATION_POLICY.md` for business rules.
sealed class GamificationFailure {
  const GamificationFailure();
}

/// Session is not verified — cannot generate Coins or count for challenges.
final class UnverifiedSession extends GamificationFailure {
  final String sessionId;
  const UnverifiedSession(this.sessionId);
}

/// Daily Coins cap reached (max 10 rewarded sessions per day).
final class DailyLimitReached extends GamificationFailure {
  final int currentCount;
  const DailyLimitReached(this.currentCount);
}

/// Challenge not found.
final class ChallengeNotFound extends GamificationFailure {
  final String challengeId;
  const ChallengeNotFound(this.challengeId);
}

/// Challenge is not in the expected status for the requested operation.
final class InvalidChallengeStatus extends GamificationFailure {
  final String challengeId;
  final String expected;
  final String actual;
  const InvalidChallengeStatus(this.challengeId, this.expected, this.actual);
}

/// User is not a participant in the challenge.
final class NotAParticipant extends GamificationFailure {
  final String userId;
  final String challengeId;
  const NotAParticipant(this.userId, this.challengeId);
}

/// Participant has already been invited / already joined.
final class AlreadyParticipant extends GamificationFailure {
  final String userId;
  final String challengeId;
  const AlreadyParticipant(this.userId, this.challengeId);
}

/// Group challenge is full (max 50 participants).
final class ChallengeFull extends GamificationFailure {
  final String challengeId;
  const ChallengeFull(this.challengeId);
}

/// Session does not meet the minimum requirements for the challenge.
final class SessionBelowMinimum extends GamificationFailure {
  final String sessionId;
  final double required_;
  final double actual;
  const SessionBelowMinimum(this.sessionId, this.required_, this.actual);
}

/// Duplicate: this session has already been submitted to this challenge.
final class SessionAlreadySubmitted extends GamificationFailure {
  final String sessionId;
  final String challengeId;
  const SessionAlreadySubmitted(this.sessionId, this.challengeId);
}

/// Wallet has insufficient balance for the requested spend.
final class InsufficientBalance extends GamificationFailure {
  final int available;
  final int requested;
  const InsufficientBalance(this.available, this.requested);
}

/// Duplicate ledger entry (idempotency guard).
final class DuplicateLedgerEntry extends GamificationFailure {
  final String entryId;
  const DuplicateLedgerEntry(this.entryId);
}

/// Only the creator can cancel a challenge.
final class NotChallengeCreator extends GamificationFailure {
  final String userId;
  final String challengeId;
  const NotChallengeCreator(this.userId, this.challengeId);
}

/// Session is not in [WorkoutStatus.completed] — cannot be rewarded.
final class SessionNotCompleted extends GamificationFailure {
  final String sessionId;
  final String actualStatus;
  const SessionNotCompleted(this.sessionId, this.actualStatus);
}

/// Session has no associated user ID — cannot credit Coins.
final class SessionNoUser extends GamificationFailure {
  final String sessionId;
  const SessionNoUser(this.sessionId);
}
