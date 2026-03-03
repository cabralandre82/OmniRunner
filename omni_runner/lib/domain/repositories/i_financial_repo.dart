import 'package:omni_runner/domain/entities/coaching_plan_entity.dart';
import 'package:omni_runner/domain/entities/coaching_subscription_entity.dart';

abstract interface class IFinancialRepo {
  // Plans
  Future<List<CoachingPlanEntity>> listPlans(String groupId);
  Future<CoachingPlanEntity> createPlan(CoachingPlanEntity plan);
  Future<CoachingPlanEntity> updatePlan(CoachingPlanEntity plan);

  // Subscriptions
  Future<List<CoachingSubscriptionEntity>> listSubscriptions(String groupId);
  Future<CoachingSubscriptionEntity?> getSubscription({
    required String groupId,
    required String athleteUserId,
  });
  Future<void> updateSubscriptionStatus(
      String subscriptionId, String newStatus);
  Future<CoachingSubscriptionEntity> createSubscription({
    required String groupId,
    required String athleteUserId,
    required String planId,
  });

  // Ledger
  Future<void> createLedgerEntry({
    required String groupId,
    required String type,
    required String category,
    required double amount,
    String? description,
  });
}
