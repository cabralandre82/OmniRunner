import 'package:omni_runner/domain/entities/coaching_subscription_entity.dart';
import 'package:omni_runner/domain/repositories/i_financial_repo.dart';

final class ManageSubscription {
  final IFinancialRepo _repo;

  const ManageSubscription({required IFinancialRepo repo}) : _repo = repo;

  Future<List<CoachingSubscriptionEntity>> list({required String groupId}) {
    return _repo.listSubscriptions(groupId);
  }

  Future<CoachingSubscriptionEntity?> get({
    required String groupId,
    required String athleteUserId,
  }) {
    return _repo.getSubscription(
        groupId: groupId, athleteUserId: athleteUserId);
  }

  Future<CoachingSubscriptionEntity> create({
    required String groupId,
    required String athleteUserId,
    required String planId,
  }) {
    return _repo.createSubscription(
      groupId: groupId,
      athleteUserId: athleteUserId,
      planId: planId,
    );
  }

  Future<void> updateStatus(String subscriptionId, String newStatus) {
    return _repo.updateSubscriptionStatus(subscriptionId, newStatus);
  }
}
