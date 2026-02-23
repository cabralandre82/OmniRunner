import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';

/// An automatically generated insight delivered to a coach.
///
/// Insights are produced by the Insight Generator Engine, which analyses
/// athlete trends, baselines, event progress and rankings to surface
/// actionable observations without the coach having to look at every
/// individual metric manually.
///
/// Each insight is scoped to a [groupId]. When [targetUserId] is non-null
/// the insight refers to a specific athlete; otherwise it is a group-wide
/// observation (e.g. [InsightType.groupTrendSummary]).
///
/// Immutable value object. See Phase 16 — Insight Generator.
final class CoachInsightEntity extends Equatable {
  /// Unique identifier (UUID v4).
  final String id;

  /// Coaching group this insight belongs to.
  final String groupId;

  /// Athlete this insight refers to. Null for group-wide insights.
  final String? targetUserId;

  /// Display name of the target athlete. Null for group-wide insights.
  final String? targetDisplayName;

  final InsightType type;
  final InsightPriority priority;

  /// Short headline shown in the coach dashboard list.
  final String title;

  /// Longer explanation / recommendation for the coach.
  final String message;

  /// The metric that triggered this insight, if applicable.
  final EvolutionMetric? metric;

  /// The value that triggered this insight (e.g. current pace, weekly km).
  final double? referenceValue;

  /// Signed percentage change that triggered this insight (trend-based).
  final double? changePercent;

  /// ID of a related domain entity (e.g. race event, ranking snapshot).
  /// Allows the UI to deep-link to the relevant detail screen.
  final String? relatedEntityId;

  /// When the insight was generated (ms since epoch, UTC).
  final int createdAtMs;

  /// When the coach read this insight. Null = unread.
  final int? readAtMs;

  /// Whether the coach explicitly dismissed this insight.
  final bool dismissed;

  const CoachInsightEntity({
    required this.id,
    required this.groupId,
    this.targetUserId,
    this.targetDisplayName,
    required this.type,
    required this.priority,
    required this.title,
    required this.message,
    this.metric,
    this.referenceValue,
    this.changePercent,
    this.relatedEntityId,
    required this.createdAtMs,
    this.readAtMs,
    this.dismissed = false,
  });

  /// Whether the insight has been read by the coach.
  bool get isRead => readAtMs != null;

  /// Whether this insight targets a specific athlete (vs. group-wide).
  bool get isAthleteSpecific => targetUserId != null;

  /// Whether this insight is still actionable (unread and not dismissed).
  bool get isActionable => !isRead && !dismissed;

  CoachInsightEntity markRead(int nowMs) => CoachInsightEntity(
        id: id,
        groupId: groupId,
        targetUserId: targetUserId,
        targetDisplayName: targetDisplayName,
        type: type,
        priority: priority,
        title: title,
        message: message,
        metric: metric,
        referenceValue: referenceValue,
        changePercent: changePercent,
        relatedEntityId: relatedEntityId,
        createdAtMs: createdAtMs,
        readAtMs: nowMs,
        dismissed: dismissed,
      );

  CoachInsightEntity markDismissed() => CoachInsightEntity(
        id: id,
        groupId: groupId,
        targetUserId: targetUserId,
        targetDisplayName: targetDisplayName,
        type: type,
        priority: priority,
        title: title,
        message: message,
        metric: metric,
        referenceValue: referenceValue,
        changePercent: changePercent,
        relatedEntityId: relatedEntityId,
        createdAtMs: createdAtMs,
        readAtMs: readAtMs,
        dismissed: true,
      );

  @override
  List<Object?> get props => [
        id,
        groupId,
        targetUserId,
        targetDisplayName,
        type,
        priority,
        title,
        message,
        metric,
        referenceValue,
        changePercent,
        relatedEntityId,
        createdAtMs,
        readAtMs,
        dismissed,
      ];
}
