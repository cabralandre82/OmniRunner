import 'package:equatable/equatable.dart';

enum BillingCycle { monthly, quarterly }

String billingCycleToString(BillingCycle c) => switch (c) {
      BillingCycle.monthly => 'monthly',
      BillingCycle.quarterly => 'quarterly',
    };

BillingCycle billingCycleFromString(String s) => switch (s) {
      'quarterly' => BillingCycle.quarterly,
      _ => BillingCycle.monthly,
    };

enum PlanStatus { active, inactive }

String planStatusToString(PlanStatus s) => switch (s) {
      PlanStatus.active => 'active',
      PlanStatus.inactive => 'inactive',
    };

PlanStatus planStatusFromString(String s) => switch (s) {
      'inactive' => PlanStatus.inactive,
      _ => PlanStatus.active,
    };

final class CoachingPlanEntity extends Equatable {
  final String id;
  final String groupId;
  final String name;
  final String? description;
  final double monthlyPrice;
  final BillingCycle billingCycle;
  final int? maxWorkoutsPerWeek;
  final PlanStatus status;
  final DateTime createdAt;

  const CoachingPlanEntity({
    required this.id,
    required this.groupId,
    required this.name,
    this.description,
    required this.monthlyPrice,
    this.billingCycle = BillingCycle.monthly,
    this.maxWorkoutsPerWeek,
    this.status = PlanStatus.active,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, groupId, name];
}
