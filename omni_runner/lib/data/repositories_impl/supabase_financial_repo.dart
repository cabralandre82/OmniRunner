import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/coaching_plan_entity.dart';
import 'package:omni_runner/domain/entities/coaching_subscription_entity.dart';
import 'package:omni_runner/domain/repositories/i_financial_repo.dart';

final class SupabaseFinancialRepo implements IFinancialRepo {
  final SupabaseClient _db;

  const SupabaseFinancialRepo(this._db);

  // ── Plans ──

  @override
  Future<List<CoachingPlanEntity>> listPlans(String groupId) async {
    try {
      final rows = await _db
          .from('coaching_plans')
          .select('id, group_id, name, description, monthly_price, billing_cycle, max_workouts_per_week, status, created_at')
          .eq('group_id', groupId)
          .order('name');
      return rows.map(_fromPlanRow).toList();
    } catch (e, st) {
      AppLogger.error('Financial.listPlans failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<CoachingPlanEntity> createPlan(CoachingPlanEntity plan) async {
    try {
      final row = await _db.from('coaching_plans').insert({
        'id': plan.id,
        'group_id': plan.groupId,
        'name': plan.name,
        'description': plan.description,
        'monthly_price': plan.monthlyPrice,
        'billing_cycle': billingCycleToString(plan.billingCycle),
        'max_workouts_per_week': plan.maxWorkoutsPerWeek,
        'status': planStatusToString(plan.status),
      }).select('id, group_id, name, description, monthly_price, billing_cycle, max_workouts_per_week, status, created_at').single();
      return _fromPlanRow(row);
    } catch (e, st) {
      AppLogger.error('Financial.createPlan failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<CoachingPlanEntity> updatePlan(CoachingPlanEntity plan) async {
    try {
      final row = await _db
          .from('coaching_plans')
          .update({
            'name': plan.name,
            'description': plan.description,
            'monthly_price': plan.monthlyPrice,
            'billing_cycle': billingCycleToString(plan.billingCycle),
            'max_workouts_per_week': plan.maxWorkoutsPerWeek,
            'status': planStatusToString(plan.status),
          })
          .eq('id', plan.id)
          .select('id, group_id, name, description, monthly_price, billing_cycle, max_workouts_per_week, status, created_at')
          .single();
      return _fromPlanRow(row);
    } catch (e, st) {
      AppLogger.error('Financial.updatePlan failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Subscriptions ──

  @override
  Future<List<CoachingSubscriptionEntity>> listSubscriptions(
      String groupId) async {
    try {
      final rows = await _db
          .from('coaching_subscriptions')
          .select(
              '*, coaching_plans(name), profiles!athlete_user_id(display_name)')
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      return rows.map(_fromSubscriptionRow).toList();
    } catch (e, st) {
      AppLogger.error('Financial.listSubscriptions failed',
          error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<CoachingSubscriptionEntity?> getSubscription({
    required String groupId,
    required String athleteUserId,
  }) async {
    try {
      final row = await _db
          .from('coaching_subscriptions')
          .select(
              '*, coaching_plans(name), profiles!athlete_user_id(display_name)')
          .eq('group_id', groupId)
          .eq('athlete_user_id', athleteUserId)
          .maybeSingle();
      if (row == null) return null;
      return _fromSubscriptionRow(row);
    } catch (e, st) {
      AppLogger.error('Financial.getSubscription failed',
          error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> updateSubscriptionStatus(
      String subscriptionId, String newStatus) async {
    try {
      await _db.rpc('fn_update_subscription_status', params: {
        'p_subscription_id': subscriptionId,
        'p_new_status': newStatus,
      });
    } catch (e, st) {
      AppLogger.error('Financial.updateSubscriptionStatus failed',
          error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<CoachingSubscriptionEntity> createSubscription({
    required String groupId,
    required String athleteUserId,
    required String planId,
  }) async {
    try {
      final row = await _db.from('coaching_subscriptions').insert({
        'group_id': groupId,
        'athlete_user_id': athleteUserId,
        'plan_id': planId,
        'status': 'active',
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).select('id, group_id, athlete_user_id, plan_id, status, started_at, created_at, coaching_plans(name), profiles!athlete_user_id(display_name)').single();
      return _fromSubscriptionRow(row);
    } catch (e, st) {
      AppLogger.error('Financial.createSubscription failed',
          error: e, stack: st);
      rethrow;
    }
  }

  // ── Ledger ──

  @override
  Future<void> createLedgerEntry({
    required String groupId,
    required String type,
    required String category,
    required double amount,
    String? description,
  }) async {
    try {
      await _db.rpc('fn_create_ledger_entry', params: {
        'p_group_id': groupId,
        'p_type': type,
        'p_category': category,
        'p_amount': amount,
        'p_description': description,
      });
    } catch (e, st) {
      AppLogger.error('Financial.createLedgerEntry failed',
          error: e, stack: st);
      rethrow;
    }
  }

  // ── Mappers ──

  static CoachingPlanEntity _fromPlanRow(Map<String, dynamic> r) =>
      CoachingPlanEntity(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        name: r['name'] as String,
        description: r['description'] as String?,
        monthlyPrice: (r['monthly_price'] as num).toDouble(),
        billingCycle: billingCycleFromString(r['billing_cycle'] as String),
        maxWorkoutsPerWeek: r['max_workouts_per_week'] as int?,
        status: planStatusFromString(r['status'] as String),
        createdAt: DateTime.parse(r['created_at'] as String),
      );

  static CoachingSubscriptionEntity _fromSubscriptionRow(
          Map<String, dynamic> r) =>
      CoachingSubscriptionEntity(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        athleteUserId: r['athlete_user_id'] as String,
        planId: r['plan_id'] as String,
        status: subscriptionStatusFromString(r['status'] as String),
        nextDueDate: r['next_due_date'] != null
            ? DateTime.parse(r['next_due_date'] as String)
            : null,
        lastPaymentAt: r['last_payment_at'] != null
            ? DateTime.parse(r['last_payment_at'] as String)
            : null,
        startedAt: DateTime.parse(r['started_at'] as String),
        cancelledAt: r['cancelled_at'] != null
            ? DateTime.parse(r['cancelled_at'] as String)
            : null,
        createdAt: DateTime.parse(r['created_at'] as String),
        planName:
            (r['coaching_plans'] as Map<String, dynamic>?)?['name'] as String?,
        athleteDisplayName:
            (r['profiles'] as Map<String, dynamic>?)?['display_name']
                as String?,
      );
}
