import 'package:equatable/equatable.dart';

/// The goal of a challenge — determines what is measured and how winners are chosen.
enum ChallengeGoal {
  /// Fastest time to complete a target distance in a single session.
  /// Required: target (distance in meters).
  /// Winner: lowest elapsed time for a session >= target distance.
  fastestAtDistance,

  /// Most distance accumulated across all sessions in the window.
  /// Target optional (collective target for groups).
  /// Winner: highest total distance.
  mostDistance,

  /// Best average pace in a single session >= target distance.
  /// Required: target (qualifying distance in meters).
  /// Winner: lowest pace (sec/km).
  bestPaceAtDistance,

  /// Group cooperative: collective distance toward a shared target.
  /// Required: target (collective distance in meters).
  /// All members contribute; everyone wins or loses together.
  collectiveDistance,
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
  /// What this challenge measures and how winners are determined.
  final ChallengeGoal goal;

  /// Target value in meters (distance to run).
  ///
  /// - [ChallengeGoal.fastestAtDistance]: the distance to complete (e.g. 10000 = 10km). REQUIRED.
  /// - [ChallengeGoal.mostDistance]: optional collective target for groups.
  /// - [ChallengeGoal.bestPaceAtDistance]: qualifying session distance (e.g. 5000 = 5km). REQUIRED.
  /// - [ChallengeGoal.collectiveDistance]: collective target (e.g. 200000 = 200km). REQUIRED.
  final double? target;

  /// Duration of the challenge window in milliseconds.
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
  /// 0 = free challenge (no pool). Must be >= 0.
  final int entryFeeCoins;

  /// For group challenges: how long (in minutes) participants have to accept.
  final int? acceptWindowMin;

  /// Max participants for group challenges. Null = unlimited.
  final int? maxParticipants;

  const ChallengeRulesEntity({
    required this.goal,
    this.target,
    required this.windowMs,
    this.startMode = ChallengeStartMode.onAccept,
    this.fixedStartMs,
    this.minSessionDistanceM = 1000.0,
    this.antiCheatPolicy = ChallengeAntiCheatPolicy.standard,
    this.entryFeeCoins = 0,
    this.acceptWindowMin,
    this.maxParticipants,
  });

  @override
  List<Object?> get props => [
        goal,
        target,
        windowMs,
        startMode,
        fixedStartMs,
        minSessionDistanceM,
        antiCheatPolicy,
        entryFeeCoins,
        acceptWindowMin,
        maxParticipants,
      ];
}
