import 'package:equatable/equatable.dart';

enum GoalMetric { distance, time }

enum GoalStatus { active, completed, missed }

/// A single weekly goal for a user.
///
/// Goals are auto-generated each ISO week. They track accumulated
/// distance (meters) or time (seconds) against a target derived
/// from the athlete's recent history.
final class WeeklyGoalEntity extends Equatable {
  final String id;
  final String userId;
  final DateTime weekStart;
  final GoalMetric metric;
  final double targetValue;
  final double currentValue;
  final GoalStatus status;
  final int xpAwarded;
  final DateTime? completedAt;

  const WeeklyGoalEntity({
    required this.id,
    required this.userId,
    required this.weekStart,
    this.metric = GoalMetric.distance,
    required this.targetValue,
    this.currentValue = 0,
    this.status = GoalStatus.active,
    this.xpAwarded = 0,
    this.completedAt,
  });

  double get progressFraction =>
      targetValue > 0 ? (currentValue / targetValue).clamp(0.0, 1.0) : 0.0;

  double get progressPercent => progressFraction * 100;

  bool get isCompleted => status == GoalStatus.completed;

  String get targetLabel {
    if (metric == GoalMetric.distance) {
      final km = targetValue / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
    final min = targetValue / 60;
    return '${min.toStringAsFixed(0)} min';
  }

  String get currentLabel {
    if (metric == GoalMetric.distance) {
      final km = currentValue / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
    final min = currentValue / 60;
    return '${min.toStringAsFixed(0)} min';
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        weekStart,
        metric,
        targetValue,
        currentValue,
        status,
        xpAwarded,
        completedAt,
      ];
}
