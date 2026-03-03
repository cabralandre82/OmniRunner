import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_plan_entity.dart';
import 'package:omni_runner/domain/entities/coaching_subscription_entity.dart';
import 'package:omni_runner/domain/repositories/i_financial_repo.dart';
import 'package:omni_runner/domain/usecases/financial/list_plans.dart';

CoachingPlanEntity _plan(String id, String groupId) => CoachingPlanEntity(
      id: id,
      groupId: groupId,
      name: 'Plan $id',
      monthlyPrice: 99.90,
      createdAt: DateTime(2026, 1, 1),
    );

class _FakeFinancialRepo implements IFinancialRepo {
  final List<CoachingPlanEntity> plans = [];
  String? lastGroupId;

  @override
  Future<List<CoachingPlanEntity>> listPlans(String groupId) async {
    lastGroupId = groupId;
    return plans.where((p) => p.groupId == groupId).toList();
  }

  @override
  Future<CoachingPlanEntity> createPlan(CoachingPlanEntity plan) async => plan;
  @override
  Future<CoachingPlanEntity> updatePlan(CoachingPlanEntity plan) async => plan;
  @override
  Future<List<CoachingSubscriptionEntity>> listSubscriptions(
          String groupId) async =>
      [];
  @override
  Future<CoachingSubscriptionEntity?> getSubscription({
    required String groupId,
    required String athleteUserId,
  }) async =>
      null;
  @override
  Future<void> updateSubscriptionStatus(
          String subscriptionId, String newStatus) async {}
  @override
  Future<CoachingSubscriptionEntity> createSubscription({
    required String groupId,
    required String athleteUserId,
    required String planId,
  }) async =>
      throw UnimplementedError();
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
  late ListPlans usecase;

  setUp(() {
    repo = _FakeFinancialRepo();
    usecase = ListPlans(repo: repo);
  });

  test('returns empty list when no plans exist', () async {
    final result = await usecase.call(groupId: 'group-1');
    expect(result, isEmpty);
  });

  test('returns plans for the given group', () async {
    repo.plans.addAll([
      _plan('p1', 'group-1'),
      _plan('p2', 'group-1'),
      _plan('p3', 'group-2'),
    ]);

    final result = await usecase.call(groupId: 'group-1');
    expect(result.length, 2);
    expect(result.every((p) => p.groupId == 'group-1'), isTrue);
  });

  test('passes group id to repo', () async {
    await usecase.call(groupId: 'group-42');
    expect(repo.lastGroupId, 'group-42');
  });
}
