import 'package:equatable/equatable.dart';

enum SubscriptionStatus { active, late, paused, cancelled }

String subscriptionStatusToString(SubscriptionStatus s) => switch (s) {
      SubscriptionStatus.active => 'active',
      SubscriptionStatus.late => 'late',
      SubscriptionStatus.paused => 'paused',
      SubscriptionStatus.cancelled => 'cancelled',
    };

SubscriptionStatus subscriptionStatusFromString(String s) => switch (s) {
      'late' => SubscriptionStatus.late,
      'paused' => SubscriptionStatus.paused,
      'cancelled' => SubscriptionStatus.cancelled,
      _ => SubscriptionStatus.active,
    };

final class CoachingSubscriptionEntity extends Equatable {
  final String id;
  final String groupId;
  final String athleteUserId;
  final String planId;
  final SubscriptionStatus status;
  final DateTime? nextDueDate;
  final DateTime? lastPaymentAt;
  final DateTime startedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;

  // Joined fields
  final String? planName;
  final String? athleteDisplayName;

  const CoachingSubscriptionEntity({
    required this.id,
    required this.groupId,
    required this.athleteUserId,
    required this.planId,
    this.status = SubscriptionStatus.active,
    this.nextDueDate,
    this.lastPaymentAt,
    required this.startedAt,
    this.cancelledAt,
    required this.createdAt,
    this.planName,
    this.athleteDisplayName,
  });

  @override
  List<Object?> get props => [id, groupId, athleteUserId, planId];
}
