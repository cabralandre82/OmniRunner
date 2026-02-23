import 'package:equatable/equatable.dart';

/// Visibility and join policy of a group.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum GroupPrivacy {
  /// Visible in search; anyone can join freely.
  open,

  /// Visible in search; admin/mod approval required to join.
  closed,

  /// Not visible in search; join by invite only.
  secret,
}

/// Metric used for group goals and events.
///
/// Shared between [GroupGoalEntity] and [EventEntity].
/// Append-only ordinal rule (DECISAO 018).
enum GoalMetric {
  /// Accumulated distance in meters.
  distance,

  /// Number of verified sessions.
  sessions,

  /// Accumulated moving time in milliseconds.
  movingTime,
}

/// Status of a group goal.
///
/// Append-only ordinal rule (DECISAO 018).
enum GoalStatus {
  /// Goal is accepting contributions.
  active,

  /// Target reached before deadline.
  completed,

  /// Deadline elapsed without reaching target.
  expired,
}

/// A community of runners with shared goals and a feed.
///
/// Immutable value object. No logic. No behavior.
/// See `docs/SOCIAL_SPEC.md` §3.
final class GroupEntity extends Equatable {
  /// Unique identifier (UUID v4).
  final String id;

  /// Display name (3–50 characters, profanity-filtered).
  final String name;

  /// Optional description (0–200 characters).
  final String description;

  /// URL of the group avatar. Null if not set.
  final String? avatarUrl;

  /// User who created the group (permanent admin).
  final String createdByUserId;

  /// When the group was created (ms since epoch, UTC).
  final int createdAtMs;

  final GroupPrivacy privacy;

  /// Maximum number of members allowed. Default 100, hard cap 200.
  final int maxMembers;

  /// Current member count (denormalized for fast reads).
  final int memberCount;

  const GroupEntity({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarUrl,
    required this.createdByUserId,
    required this.createdAtMs,
    required this.privacy,
    this.maxMembers = 100,
    this.memberCount = 0,
  });

  bool get isFull => memberCount >= maxMembers;

  GroupEntity copyWith({
    String? name,
    String? description,
    String? avatarUrl,
    GroupPrivacy? privacy,
    int? maxMembers,
    int? memberCount,
  }) =>
      GroupEntity(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        createdByUserId: createdByUserId,
        createdAtMs: createdAtMs,
        privacy: privacy ?? this.privacy,
        maxMembers: maxMembers ?? this.maxMembers,
        memberCount: memberCount ?? this.memberCount,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        avatarUrl,
        createdByUserId,
        createdAtMs,
        privacy,
        maxMembers,
        memberCount,
      ];
}

/// A collective goal for a group of runners.
///
/// Members' verified sessions automatically contribute to [currentValue].
/// Maximum 3 active goals per group.
///
/// Immutable value object. See `docs/SOCIAL_SPEC.md` §3.5.
final class GroupGoalEntity extends Equatable {
  final String id;
  final String groupId;

  /// Human-readable title (e.g. "500 km em janeiro").
  final String title;
  final String description;

  /// Target value in canonical units (meters, count, ms).
  final double targetValue;

  /// Current accumulated value from all contributing sessions.
  final double currentValue;

  final GoalMetric metric;

  /// When the goal window opens (ms since epoch, UTC).
  final int startsAtMs;

  /// When the goal window closes (ms since epoch, UTC).
  final int endsAtMs;

  /// User who created the goal.
  final String createdByUserId;

  final GoalStatus status;

  const GroupGoalEntity({
    required this.id,
    required this.groupId,
    required this.title,
    this.description = '',
    required this.targetValue,
    this.currentValue = 0.0,
    required this.metric,
    required this.startsAtMs,
    required this.endsAtMs,
    required this.createdByUserId,
    this.status = GoalStatus.active,
  });

  /// Progress as a fraction 0.0–1.0 (clamped).
  double get progressFraction =>
      targetValue > 0 ? (currentValue / targetValue).clamp(0.0, 1.0) : 0.0;

  bool get isCompleted => status == GoalStatus.completed;

  GroupGoalEntity copyWith({
    double? currentValue,
    GoalStatus? status,
  }) =>
      GroupGoalEntity(
        id: id,
        groupId: groupId,
        title: title,
        description: description,
        targetValue: targetValue,
        currentValue: currentValue ?? this.currentValue,
        metric: metric,
        startsAtMs: startsAtMs,
        endsAtMs: endsAtMs,
        createdByUserId: createdByUserId,
        status: status ?? this.status,
      );

  @override
  List<Object?> get props => [
        id,
        groupId,
        title,
        description,
        targetValue,
        currentValue,
        metric,
        startsAtMs,
        endsAtMs,
        createdByUserId,
        status,
      ];
}
