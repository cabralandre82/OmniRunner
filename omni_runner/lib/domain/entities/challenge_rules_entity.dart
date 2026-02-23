import 'package:equatable/equatable.dart';

/// The metric a challenge is measured by.
enum ChallengeMetric {
  /// Total distance in meters accumulated during the window.
  distance,

  /// Best average pace (seconds/km) for a single verified session.
  pace,

  /// Total moving time in milliseconds accumulated during the window.
  time,
}

/// How the challenge window begins.
enum ChallengeStartMode {
  /// Window starts when the last participant accepts.
  onAccept,

  /// Window starts at [ChallengeRulesEntity.fixedStartMs].
  scheduled,
}

/// Anti-cheat enforcement level for a challenge.
enum ChallengeAntiCheatPolicy {
  /// All default integrity checks apply (speed, teleport, steps).
  standard,

  /// Standard + HR correlation required (BLE or HealthKit/Health Connect).
  strict,
}

/// Immutable rules that govern a challenge.
///
/// Defined at creation time and never modified.
/// Domain-pure — no Flutter or platform imports.
final class ChallengeRulesEntity extends Equatable {
  /// What is being measured.
  final ChallengeMetric metric;

  /// Target value the participant must reach (meters, sec/km, or ms).
  ///
  /// Null for "open-ended" challenges where the best result wins.
  final double? target;

  /// Duration of the challenge window in milliseconds.
  ///
  /// E.g. 7 days = 604_800_000 ms.
  final int windowMs;

  /// How the window timer begins.
  final ChallengeStartMode startMode;

  /// Fixed start timestamp (ms since epoch, UTC).
  /// Only used when [startMode] is [ChallengeStartMode.scheduled].
  final int? fixedStartMs;

  /// Minimum distance (meters) for a session to count.
  final double minSessionDistanceM;

  /// Anti-cheat enforcement level.
  final ChallengeAntiCheatPolicy antiCheatPolicy;

  /// Entry fee in OmniCoins each participant must pay to join.
  ///
  /// 0 = free challenge (no pool). Must be ≥ 0.
  /// The pool (sum of all fees) is transferred to the winner on settlement.
  /// See `docs/GAMIFICATION_POLICY.md` §4 — Coins are non-convertible.
  final int entryFeeCoins;

  const ChallengeRulesEntity({
    required this.metric,
    this.target,
    required this.windowMs,
    this.startMode = ChallengeStartMode.onAccept,
    this.fixedStartMs,
    this.minSessionDistanceM = 1000.0,
    this.antiCheatPolicy = ChallengeAntiCheatPolicy.standard,
    this.entryFeeCoins = 0,
  });

  @override
  List<Object?> get props => [
        metric,
        target,
        windowMs,
        startMode,
        fixedStartMs,
        minSessionDistanceM,
        antiCheatPolicy,
        entryFeeCoins,
      ];
}
