import 'package:equatable/equatable.dart';

/// Types of events that appear in the assessoria feed.
enum FeedEventType {
  sessionCompleted,
  challengeWon,
  badgeUnlocked,
  championshipStarted,
  streakMilestone,
  levelUp,
  memberJoined,
}

/// A single item in the assessoria social feed.
///
/// Immutable value object. Privacy-scoped to a single coaching group.
final class FeedItemEntity extends Equatable {
  final String id;
  final String actorUserId;
  final String actorName;
  final FeedEventType eventType;
  final Map<String, dynamic> payload;
  final int createdAtMs;

  const FeedItemEntity({
    required this.id,
    required this.actorUserId,
    required this.actorName,
    required this.eventType,
    required this.payload,
    required this.createdAtMs,
  });

  @override
  List<Object?> get props => [
        id,
        actorUserId,
        actorName,
        eventType,
        payload,
        createdAtMs,
      ];
}
