import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/value_objects/milestone_kind.dart';

/// Concrete milestone achievement detected for the current user.
///
/// Produced by `MilestoneDetector`, consumed by the celebration
/// presenter. Carries the [kind] (which drives copy / art), the
/// [achievedAtMs] timestamp, and — for distance-anchored kinds —
/// the exact [triggerDistanceM] so the UI can render "You just ran
/// 5.03 km!" instead of the generic threshold.
///
/// Finding reference: L22-09.
final class MilestoneEntity extends Equatable {
  final MilestoneKind kind;
  final int achievedAtMs;

  /// The distance (meters) that triggered this milestone. Null
  /// for kinds whose `distanceThresholdM` is also null.
  final double? triggerDistanceM;

  /// Optional integer companion metric: for streak kinds this is
  /// the streak count; for [MilestoneKind.firstWeek] this is the
  /// weekly session count. Null otherwise.
  final int? triggerCount;

  const MilestoneEntity({
    required this.kind,
    required this.achievedAtMs,
    this.triggerDistanceM,
    this.triggerCount,
  });

  /// Runtime-augmented dedup key. For [MilestoneKind.longestRunEver]
  /// we append the distance (rounded to 10 m) so consecutive new
  /// records can each fire once. For every other kind this returns
  /// the raw [MilestoneKind.dedupKey].
  String get dedupKey {
    if (kind == MilestoneKind.longestRunEver && triggerDistanceM != null) {
      final decameters = (triggerDistanceM! / 10).round();
      return '${kind.dedupKey}:$decameters';
    }
    return kind.dedupKey;
  }

  @override
  List<Object?> get props => [kind, achievedAtMs, triggerDistanceM, triggerCount];
}
