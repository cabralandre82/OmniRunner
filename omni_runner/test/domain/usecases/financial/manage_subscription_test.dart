import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_plan_entity.dart';
import 'package:omni_runner/domain/entities/coaching_subscription_entity.dart';
import 'package:omni_runner/domain/repositories/i_financial_repo.dart';
import 'package:omni_runner/domain/usecases/financial/manage_subscription.dart';

class _FakeFinancialRepo implements IFinancialRepo {
  final List<CoachingSubscriptionEntity> subscriptions = [];
  int _seq = 0;
  String? lastStatusId;
  String? lastNewStatus;

  @override
  Future<List<CoachingSubscriptionEntity>> listSubscriptions(
      String groupId) async {
    return subscriptions.where((s) => s.groupId == groupId).toList();
  }

  @override
  Future<CoachingSubscriptionEntity?> getSubscription({
    required String groupId,
    required String athleteUserId,
  }) async {
    try {
      return subscriptions.firstWhere(
          (s) => s.groupId == groupId && s.athleteUserId == athleteUserId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CoachingSubscriptionEntity> createSubscription({
    required String groupId,
    required String athleteUserId,
    required String planId,
  }) async {
    final now = DateTime.now();
    final sub = CoachingSubscriptionEntity(
      id: 'sub-${++_seq}',
      groupId: groupId,
      athleteUserId: athleteUserId,
      planId: planId,
      startedAt: now,
      createdAt: now,
    );
    subscriptions.add(sub);
    return sub;
  }

  @override
  Future<void> updateSubscriptionStatus(
      String subscriptionId, String newStatus) async {
    lastStatusId = subscriptionId;
    lastNewStatus = newStatus;
  }

  @override
  Future<List<CoachingPlanEntity>> listPlans(String groupId) async => [];
  @override
  Future<CoachingPlanEntity> createPlan(CoachingPlanEntity plan) async => plan;
  @override
  Future<CoachingPlanEntity> updatePlan(CoachingPlanEntity plan) async => plan;
  @override
  Future<void> createLedgerEntry({
    required String groupId,
    required String type,
    required String category,
    required double amount,
    String? description,
  }) async {}
}

void main() {
  late _FakeFinancialRepo repo;
  late ManageSubscription usecase;

  setUp(() {
    repo = _FakeFinancialRepo();
    usecase = ManageSubscription(repo: repo);
  });

  test('creates a subscription', () async {
    final sub = await usecase.create(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      planId: 'plan-1',
    );

    expect(sub.groupId, 'group-1');
    expect(sub.athleteUserId, 'athlete-1');
    expect(sub.planId, 'plan-1');
    expect(sub.status, SubscriptionStatus.active);
  });

  test('lists subscriptions for a group', () async {
    await usecase.create(
        groupId: 'group-1', athleteUserId: 'a1', planId: 'p1');
    await usecase.create(
        groupId: 'group-1', athleteUserId: 'a2', planId: 'p1');
    await usecase.create(
        groupId: 'group-2', athleteUserId: 'a3', planId: 'p2');

    final result = await usecase.list(groupId: 'group-1');
    expect(result.length, 2);
  });

  test('gets subscription for specific athlete', () async {
    await usecase.create(
        groupId: 'group-1', athleteUserId: 'athlete-1', planId: 'plan-1');

    final result = await usecase.get(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
    );
    expect(result, isNotNull);
    expect(result!.athleteUserId, 'athlete-1');
  });

  test('returns null for non-existent subscription', () async {
    final result = await usecase.get(
      groupId: 'group-1',
      athleteUserId: 'athlete-99',
    );
    expect(result, isNull);
  });

  test('updates subscription status', () async {
    await usecase.updateStatus('sub-1', 'paused');

    expect(repo.lastStatusId, 'sub-1');
    expect(repo.lastNewStatus, 'paused');
  });
}
