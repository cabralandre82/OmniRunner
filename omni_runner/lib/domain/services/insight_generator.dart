import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/coach_insight_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';

/// Lightweight snapshot of an athlete's recent activity.
///
/// The caller aggregates this from session records before invoking the
/// generator, keeping the service free of persistence coupling.
final class AthleteActivitySummary {
  final String userId;
  final String displayName;

  /// Timestamp of the most recent session (ms since epoch). 0 if none found.
  final int lastSessionMs;

  /// Number of sessions in the trailing 7-day window.
  final int sessionsLast7Days;

  /// Total distance (meters) in the trailing 7-day window.
  final double distanceLast7DaysM;

  const AthleteActivitySummary({
    required this.userId,
    required this.displayName,
    required this.lastSessionMs,
    required this.sessionsLast7Days,
    required this.distanceLast7DaysM,
  });
}

/// Pure, stateless domain service that generates coaching insights from
/// pre-computed trends, baselines and activity summaries.
///
/// No I/O, no repos — takes pre-fetched data in, returns insights out.
///
/// Detection rules:
///
/// | Rule | InsightType | Input |
/// |------|-------------|-------|
/// | Athlete improving (most significant metric) | `performanceImprovement` | trends |
/// | Athlete declining (most significant metric) | `performanceDecline` | trends |
/// | No sessions for ≥ [inactivityDaysThreshold] days | `inactivityWarning` | activities |
/// | Weekly frequency dropped ≥ [consistencyDropPercent]% vs baseline | `consistencyDrop` | activities + baselines |
/// | Weekly volume spiked ≥ [overtrainingVolumePercent]% above baseline | `overtrainingRisk` | activities + baselines |
/// | Periodic group-wide trend distribution | `groupTrendSummary` | trends |
final class InsightGenerator {
  static const int _msPerDay = 24 * 60 * 60 * 1000;

  /// Days without a session before an [inactivityWarning] is emitted.
  final int inactivityDaysThreshold;

  /// % spike in weekly volume (above baseline) that triggers [overtrainingRisk].
  final double overtrainingVolumePercent;

  /// % drop in weekly frequency (below baseline) that triggers [consistencyDrop].
  final double consistencyDropPercent;

  const InsightGenerator({
    this.inactivityDaysThreshold = 7,
    this.overtrainingVolumePercent = 50.0,
    this.consistencyDropPercent = 40.0,
  });

  /// Generate all applicable insights for a coaching group.
  ///
  /// [trends] — most recent `AthleteTrendEntity` per (userId, metric).
  /// [baselinesByUser] — `userId → { metric → baseline }`.
  /// [activities] — one per athlete in the group.
  /// [idGenerator] — produces unique IDs (UUID v4) for each insight.
  List<CoachInsightEntity> generate({
    required String groupId,
    required List<AthleteTrendEntity> trends,
    required Map<String, Map<EvolutionMetric, AthleteBaselineEntity>>
        baselinesByUser,
    required List<AthleteActivitySummary> activities,
    required int nowMs,
    required String Function() idGenerator,
  }) {
    final insights = <CoachInsightEntity>[];

    final trendsByUser = _groupTrendsByUser(trends);
    final activityByUser = {for (final a in activities) a.userId: a};

    // 1 — Atletas em evolução / declínio
    insights.addAll(
      _evolutionInsights(groupId, trendsByUser, activityByUser, nowMs, idGenerator),
    );

    // 2 — Atletas inativos
    insights.addAll(
      _inactivityInsights(groupId, activities, nowMs, idGenerator),
    );

    // 3 — Padrões semanais (consistência + overtraining)
    insights.addAll(
      _weeklyPatternInsights(
          groupId, activities, baselinesByUser, nowMs, idGenerator),
    );

    // 4 — Média / resumo do grupo
    final summary = _groupSummaryInsight(groupId, trends, nowMs, idGenerator);
    if (summary != null) insights.add(summary);

    return insights;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1 — Evolution insights (improving / declining)
  // ═══════════════════════════════════════════════════════════════════════════

  List<CoachInsightEntity> _evolutionInsights(
    String groupId,
    Map<String, List<AthleteTrendEntity>> trendsByUser,
    Map<String, AthleteActivitySummary> activityByUser,
    int nowMs,
    String Function() idGenerator,
  ) {
    final results = <CoachInsightEntity>[];

    for (final entry in trendsByUser.entries) {
      final userId = entry.key;
      final userTrends = entry.value;
      final name =
          activityByUser[userId]?.displayName ?? userId;

      final improving = userTrends
          .where((t) => t.direction == TrendDirection.improving && t.isActionable)
          .toList()
        ..sort((a, b) => b.absoluteChange.compareTo(a.absoluteChange));

      final declining = userTrends
          .where((t) => t.direction == TrendDirection.declining && t.isActionable)
          .toList()
        ..sort((a, b) => b.absoluteChange.compareTo(a.absoluteChange));

      if (improving.isNotEmpty) {
        final best = improving.first;
        results.add(CoachInsightEntity(
          id: idGenerator(),
          groupId: groupId,
          targetUserId: userId,
          targetDisplayName: name,
          type: InsightType.performanceImprovement,
          priority: InsightPriority.medium,
          title: '$name evoluindo em ${_metricLabel(best.metric)}',
          message: '${_metricLabel(best.metric)} melhorou '
              '${best.absoluteChange.toStringAsFixed(1)}% '
              'em relação ao baseline.',
          metric: best.metric,
          referenceValue: best.currentValue,
          changePercent: best.changePercent,
          createdAtMs: nowMs,
        ));
      }

      if (declining.isNotEmpty) {
        final worst = declining.first;
        results.add(CoachInsightEntity(
          id: idGenerator(),
          groupId: groupId,
          targetUserId: userId,
          targetDisplayName: name,
          type: InsightType.performanceDecline,
          priority: InsightPriority.high,
          title: '$name em queda em ${_metricLabel(worst.metric)}',
          message: '${_metricLabel(worst.metric)} caiu '
              '${worst.absoluteChange.toStringAsFixed(1)}% '
              'em relação ao baseline.',
          metric: worst.metric,
          referenceValue: worst.currentValue,
          changePercent: worst.changePercent,
          createdAtMs: nowMs,
        ));
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2 — Inactivity
  // ═══════════════════════════════════════════════════════════════════════════

  List<CoachInsightEntity> _inactivityInsights(
    String groupId,
    List<AthleteActivitySummary> activities,
    int nowMs,
    String Function() idGenerator,
  ) {
    final threshold = inactivityDaysThreshold * _msPerDay;
    final results = <CoachInsightEntity>[];

    for (final a in activities) {
      if (a.lastSessionMs <= 0) {
        results.add(CoachInsightEntity(
          id: idGenerator(),
          groupId: groupId,
          targetUserId: a.userId,
          targetDisplayName: a.displayName,
          type: InsightType.inactivityWarning,
          priority: InsightPriority.high,
          title: '${a.displayName} sem sessões registradas',
          message: 'Nenhuma sessão encontrada para este atleta.',
          createdAtMs: nowMs,
        ));
        continue;
      }

      final elapsed = nowMs - a.lastSessionMs;
      if (elapsed >= threshold) {
        final days = elapsed ~/ _msPerDay;
        results.add(CoachInsightEntity(
          id: idGenerator(),
          groupId: groupId,
          targetUserId: a.userId,
          targetDisplayName: a.displayName,
          type: InsightType.inactivityWarning,
          priority: days >= inactivityDaysThreshold * 2
              ? InsightPriority.critical
              : InsightPriority.high,
          title: '${a.displayName} inativo há $days dias',
          message: 'Última sessão registrada há $days dias.',
          createdAtMs: nowMs,
        ));
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3 — Weekly patterns (consistency drop + overtraining risk)
  // ═══════════════════════════════════════════════════════════════════════════

  List<CoachInsightEntity> _weeklyPatternInsights(
    String groupId,
    List<AthleteActivitySummary> activities,
    Map<String, Map<EvolutionMetric, AthleteBaselineEntity>> baselinesByUser,
    int nowMs,
    String Function() idGenerator,
  ) {
    final results = <CoachInsightEntity>[];

    for (final a in activities) {
      final userBaselines = baselinesByUser[a.userId];
      if (userBaselines == null) continue;

      // ── Consistency drop ──
      final freqBaseline = userBaselines[EvolutionMetric.weeklyFrequency];
      if (freqBaseline != null &&
          freqBaseline.isReliable &&
          freqBaseline.value > 0) {
        final dropPct =
            (freqBaseline.value - a.sessionsLast7Days) / freqBaseline.value * 100;
        if (dropPct >= consistencyDropPercent) {
          results.add(CoachInsightEntity(
            id: idGenerator(),
            groupId: groupId,
            targetUserId: a.userId,
            targetDisplayName: a.displayName,
            type: InsightType.consistencyDrop,
            priority: InsightPriority.medium,
            title: '${a.displayName} reduziu frequência',
            message: '${a.sessionsLast7Days} sessão(ões) na última semana '
                'vs ${freqBaseline.value.toStringAsFixed(1)} sessões/semana '
                'no baseline (−${dropPct.toStringAsFixed(0)}%).',
            metric: EvolutionMetric.weeklyFrequency,
            referenceValue: a.sessionsLast7Days.toDouble(),
            changePercent: -dropPct,
            createdAtMs: nowMs,
          ));
        }
      }

      // ── Overtraining risk ──
      final volBaseline = userBaselines[EvolutionMetric.weeklyVolume];
      if (volBaseline != null &&
          volBaseline.isReliable &&
          volBaseline.value > 0) {
        final spikePct =
            (a.distanceLast7DaysM - volBaseline.value) / volBaseline.value * 100;
        if (spikePct >= overtrainingVolumePercent) {
          final currentKm = (a.distanceLast7DaysM / 1000).toStringAsFixed(1);
          final baseKm = (volBaseline.value / 1000).toStringAsFixed(1);
          results.add(CoachInsightEntity(
            id: idGenerator(),
            groupId: groupId,
            targetUserId: a.userId,
            targetDisplayName: a.displayName,
            type: InsightType.overtrainingRisk,
            priority: InsightPriority.critical,
            title: '${a.displayName} com volume excessivo',
            message: '$currentKm km na semana vs baseline de '
                '$baseKm km (+${spikePct.toStringAsFixed(0)}%). '
                'Risco de lesão.',
            metric: EvolutionMetric.weeklyVolume,
            referenceValue: a.distanceLast7DaysM,
            changePercent: spikePct,
            createdAtMs: nowMs,
          ));
        }
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4 — Group trend summary
  // ═══════════════════════════════════════════════════════════════════════════

  CoachInsightEntity? _groupSummaryInsight(
    String groupId,
    List<AthleteTrendEntity> trends,
    int nowMs,
    String Function() idGenerator,
  ) {
    if (trends.isEmpty) return null;

    final uniqueUsers = <String>{};
    int improving = 0;
    int stable = 0;
    int declining = 0;
    int insufficient = 0;

    final bestPerUser = <String, TrendDirection>{};
    for (final t in trends) {
      uniqueUsers.add(t.userId);
      final existing = bestPerUser[t.userId];
      if (existing == null || _directionRank(t.direction) > _directionRank(existing)) {
        bestPerUser[t.userId] = t.direction;
      }
    }

    for (final dir in bestPerUser.values) {
      switch (dir) {
        case TrendDirection.improving:
          improving++;
        case TrendDirection.stable:
          stable++;
        case TrendDirection.declining:
          declining++;
        case TrendDirection.insufficient:
          insufficient++;
      }
    }

    final total = uniqueUsers.length;
    final parts = <String>[];
    if (improving > 0) parts.add('$improving evoluindo');
    if (stable > 0) parts.add('$stable estáveis');
    if (declining > 0) parts.add('$declining em queda');
    if (insufficient > 0) parts.add('$insufficient com dados insuficientes');

    return CoachInsightEntity(
      id: idGenerator(),
      groupId: groupId,
      type: InsightType.groupTrendSummary,
      priority: declining > total / 2
          ? InsightPriority.high
          : InsightPriority.low,
      title: 'Resumo do grupo',
      message: '$total atletas: ${parts.join(', ')}.',
      createdAtMs: nowMs,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  static Map<String, List<AthleteTrendEntity>> _groupTrendsByUser(
    List<AthleteTrendEntity> trends,
  ) {
    final map = <String, List<AthleteTrendEntity>>{};
    for (final t in trends) {
      (map[t.userId] ??= []).add(t);
    }
    return map;
  }

  /// Higher rank = more "noteworthy" direction for the summary.
  static int _directionRank(TrendDirection d) => switch (d) {
        TrendDirection.declining => 3,
        TrendDirection.improving => 2,
        TrendDirection.stable => 1,
        TrendDirection.insufficient => 0,
      };

  static String _metricLabel(EvolutionMetric m) => switch (m) {
        EvolutionMetric.avgPace => 'pace médio',
        EvolutionMetric.avgDistance => 'distância média',
        EvolutionMetric.weeklyVolume => 'volume semanal',
        EvolutionMetric.weeklyFrequency => 'frequência semanal',
        EvolutionMetric.avgHeartRate => 'FC média',
        EvolutionMetric.avgMovingTime => 'tempo médio',
      };
}
