import 'dart:math' as math;

import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';

/// Result of an XP award attempt.
final class XpAwardResult {
  final bool awarded;
  final int xpAwarded;

  /// XP that was forfeited due to daily cap.
  final int xpCapped;
  final String? rejectionReason;

  const XpAwardResult._({
    required this.awarded,
    this.xpAwarded = 0,
    this.xpCapped = 0,
    this.rejectionReason,
  });

  const XpAwardResult.success(int xp, {int capped = 0})
      : this._(awarded: true, xpAwarded: xp, xpCapped: capped);

  const XpAwardResult.rejected(String reason)
      : this._(awarded: false, rejectionReason: reason);
}

/// Calculates and credits XP for a completed, verified workout session.
///
/// Formula (PROGRESSION_SPEC §3.1):
///   sessionXp = baseXp(20) + distanceBonus + durationBonus + hrBonus
///
/// Enforces daily session XP cap (1000/day, §4).
/// Deduplicates via [XpSource.session] + session ID.
/// Updates [ProfileProgressEntity] with new totals and lifetime stats.
final class AwardXpForWorkout {
  final IXpTransactionRepo _xpRepo;
  final IProfileProgressRepo _profileRepo;

  static const _baseXp = 20;
  static const _distanceXpPerKm = 10;
  static const _maxDistanceKm = 50.0;
  static const _durationXpPer5Min = 2;
  static const _maxDurationMin = 300.0;
  static const _hrBonus = 10;
  static const _dailySessionXpCap = 1000;

  /// Sessions shorter than this are ignored to prevent micro-farming.
  static const _minDistanceM = 200.0;

  const AwardXpForWorkout({
    required IXpTransactionRepo xpRepo,
    required IProfileProgressRepo profileRepo,
  })  : _xpRepo = xpRepo,
        _profileRepo = profileRepo;

  Future<XpAwardResult> call({
    required WorkoutSessionEntity session,
    required double totalDistanceM,
    required int movingMs,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    if (session.status != WorkoutStatus.completed) {
      return const XpAwardResult.rejected('session_not_completed');
    }
    if (!session.isVerified) {
      return const XpAwardResult.rejected('session_not_verified');
    }
    if (totalDistanceM < _minDistanceM) {
      return const XpAwardResult.rejected('below_min_distance');
    }

    final userId = session.userId;
    if (userId == null || userId.isEmpty) {
      return const XpAwardResult.rejected('no_user_id');
    }

    final existing = await _xpRepo.getByRefId(session.id);
    if (existing.any((tx) => tx.source == XpSource.session)) {
      return const XpAwardResult.rejected('already_awarded');
    }

    final rawXp = calculateSessionXp(
      distanceM: totalDistanceM,
      movingMs: movingMs,
      hasHr: session.avgBpm != null,
    );

    final todaySessionXp = await _xpRepo.sumSessionXpToday(userId);
    final remaining = math.max(0, _dailySessionXpCap - todaySessionXp);

    if (remaining <= 0) {
      return const XpAwardResult.rejected('daily_cap_reached');
    }

    final effectiveXp = math.min(rawXp, remaining);
    final capped = rawXp - effectiveXp;

    final tx = XpTransactionEntity(
      id: uuidGenerator(),
      userId: userId,
      xp: effectiveXp,
      source: XpSource.session,
      refId: session.id,
      createdAtMs: nowMs,
    );
    await _xpRepo.append(tx);

    final profile = await _profileRepo.getByUserId(userId);
    await _profileRepo.save(profile.copyWith(
      totalXp: profile.totalXp + effectiveXp,
      seasonXp: profile.seasonXp + effectiveXp,
      lifetimeSessionCount: profile.lifetimeSessionCount + 1,
      lifetimeDistanceM: profile.lifetimeDistanceM + totalDistanceM,
      lifetimeMovingMs: profile.lifetimeMovingMs + movingMs,
    ));

    return XpAwardResult.success(effectiveXp, capped: capped);
  }

  /// Pure calculation — no side effects. Exposed for testing.
  static int calculateSessionXp({
    required double distanceM,
    required int movingMs,
    required bool hasHr,
  }) {
    final distKm = math.min(distanceM / 1000.0, _maxDistanceKm);
    final durMin = math.min(movingMs / 60000.0, _maxDurationMin);

    final distBonus = (distKm * _distanceXpPerKm).floor();
    final durBonus = (durMin / 5).floor() * _durationXpPer5Min;
    final hrBonusVal = hasHr ? _hrBonus : 0;

    return _baseXp + distBonus + durBonus + hrBonusVal;
  }
}
