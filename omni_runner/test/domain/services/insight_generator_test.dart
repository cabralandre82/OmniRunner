import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';
import 'package:omni_runner/domain/services/insight_generator.dart';

void main() {
  const gen = InsightGenerator();
  const msPerDay = 24 * 60 * 60 * 1000;

  int seq = 0;
  String nextId() => 'id-${seq++}';

  AthleteTrendEntity makeTrend({
    required String userId,
    EvolutionMetric metric = EvolutionMetric.avgPace,
    TrendDirection direction = TrendDirection.improving,
    double changePercent = 10.0,
    double currentValue = 300,
    double baselineValue = 330,
    int dataPoints = 4,
  }) =>
      AthleteTrendEntity(
        id: nextId(),
        userId: userId,
        groupId: 'g1',
        metric: metric,
        period: EvolutionPeriod.weekly,
        direction: direction,
        currentValue: currentValue,
        baselineValue: baselineValue,
        changePercent: changePercent,
        dataPoints: dataPoints,
        latestPeriodKey: '2026-W08',
        analyzedAtMs: 0,
      );

  AthleteActivitySummary makeActivity({
    required String userId,
    int lastSessionMs = 0,
    int sessionsLast7Days = 3,
    double distanceLast7DaysM = 20000,
  }) =>
      AthleteActivitySummary(
        userId: userId,
        displayName: userId,
        lastSessionMs: lastSessionMs,
        sessionsLast7Days: sessionsLast7Days,
        distanceLast7DaysM: distanceLast7DaysM,
      );

  AthleteBaselineEntity makeBaseline({
    required String userId,
    required EvolutionMetric metric,
    required double value,
    int sampleSize = 5,
  }) =>
      AthleteBaselineEntity(
        id: nextId(),
        userId: userId,
        groupId: 'g1',
        metric: metric,
        value: value,
        sampleSize: sampleSize,
        windowStartMs: 0,
        windowEndMs: 1000,
        computedAtMs: 0,
      );

  setUp(() => seq = 0);

  group('InsightGenerator', () {
    test('performance improvement insight for improving athlete', () {
      final insights = gen.generate(
        groupId: 'g1',
        trends: [
          makeTrend(
            userId: 'u1',
            direction: TrendDirection.improving,
            changePercent: 15,
          ),
        ],
        baselinesByUser: {},
        activities: [makeActivity(userId: 'u1', lastSessionMs: 100)],
        nowMs: 100,
        idGenerator: nextId,
      );

      final types = insights.map((i) => i.type).toList();
      expect(types, contains(InsightType.performanceImprovement));
    });

    test('performance decline insight for declining athlete', () {
      final insights = gen.generate(
        groupId: 'g1',
        trends: [
          makeTrend(
            userId: 'u1',
            direction: TrendDirection.declining,
            changePercent: -20,
          ),
        ],
        baselinesByUser: {},
        activities: [makeActivity(userId: 'u1', lastSessionMs: 100)],
        nowMs: 100,
        idGenerator: nextId,
      );

      final types = insights.map((i) => i.type).toList();
      expect(types, contains(InsightType.performanceDecline));
    });

    test('inactivity warning when no sessions ever recorded', () {
      final insights = gen.generate(
        groupId: 'g1',
        trends: [],
        baselinesByUser: {},
        activities: [makeActivity(userId: 'u1', lastSessionMs: 0)],
        nowMs: 100,
        idGenerator: nextId,
      );

      final inactivity = insights
          .where((i) => i.type == InsightType.inactivityWarning)
          .toList();
      expect(inactivity, hasLength(1));
      expect(inactivity.first.targetUserId, 'u1');
    });

    test('inactivity warning when last session exceeds threshold', () {
      const nowMs = 8 * msPerDay;
      final insights = gen.generate(
        groupId: 'g1',
        trends: [],
        baselinesByUser: {},
        activities: [makeActivity(userId: 'u1', lastSessionMs: 1)],
        nowMs: nowMs,
        idGenerator: nextId,
      );

      final inactivity = insights
          .where((i) => i.type == InsightType.inactivityWarning)
          .toList();
      expect(inactivity, hasLength(1));
    });

    test('no inactivity warning when active recently', () {
      const nowMs = 3 * msPerDay;
      final insights = gen.generate(
        groupId: 'g1',
        trends: [],
        baselinesByUser: {},
        activities: [makeActivity(userId: 'u1', lastSessionMs: nowMs - 1)],
        nowMs: nowMs,
        idGenerator: nextId,
      );

      final inactivity = insights
          .where((i) => i.type == InsightType.inactivityWarning)
          .toList();
      expect(inactivity, isEmpty);
    });

    test('consistency drop when weekly frequency drops ≥40%', () {
      final baselines = {
        'u1': {
          EvolutionMetric.weeklyFrequency: makeBaseline(
            userId: 'u1',
            metric: EvolutionMetric.weeklyFrequency,
            value: 5.0,
          ),
        },
      };

      final insights = gen.generate(
        groupId: 'g1',
        trends: [],
        baselinesByUser: baselines,
        activities: [
          makeActivity(userId: 'u1', sessionsLast7Days: 2, lastSessionMs: 100),
        ],
        nowMs: 100,
        idGenerator: nextId,
      );

      final drops = insights
          .where((i) => i.type == InsightType.consistencyDrop)
          .toList();
      expect(drops, hasLength(1));
    });

    test('overtraining risk when volume spikes ≥50% above baseline', () {
      final baselines = {
        'u1': {
          EvolutionMetric.weeklyVolume: makeBaseline(
            userId: 'u1',
            metric: EvolutionMetric.weeklyVolume,
            value: 20000,
          ),
        },
      };

      final insights = gen.generate(
        groupId: 'g1',
        trends: [],
        baselinesByUser: baselines,
        activities: [
          makeActivity(
            userId: 'u1',
            distanceLast7DaysM: 31000,
            lastSessionMs: 100,
          ),
        ],
        nowMs: 100,
        idGenerator: nextId,
      );

      final risks = insights
          .where((i) => i.type == InsightType.overtrainingRisk)
          .toList();
      expect(risks, hasLength(1));
      expect(risks.first.priority, InsightPriority.critical);
    });

    test('group summary insight is generated when trends exist', () {
      final insights = gen.generate(
        groupId: 'g1',
        trends: [
          makeTrend(userId: 'u1', direction: TrendDirection.improving),
          makeTrend(userId: 'u2', direction: TrendDirection.declining),
        ],
        baselinesByUser: {},
        activities: [
          makeActivity(userId: 'u1', lastSessionMs: 100),
          makeActivity(userId: 'u2', lastSessionMs: 100),
        ],
        nowMs: 100,
        idGenerator: nextId,
      );

      final summaries = insights
          .where((i) => i.type == InsightType.groupTrendSummary)
          .toList();
      expect(summaries, hasLength(1));
      expect(summaries.first.message, contains('2 atletas'));
    });

    test('no group summary when trends are empty', () {
      final insights = gen.generate(
        groupId: 'g1',
        trends: [],
        baselinesByUser: {},
        activities: [],
        nowMs: 100,
        idGenerator: nextId,
      );

      final summaries = insights
          .where((i) => i.type == InsightType.groupTrendSummary)
          .toList();
      expect(summaries, isEmpty);
    });

    test('skips unreliable baselines for consistency and overtraining', () {
      final baselines = {
        'u1': {
          EvolutionMetric.weeklyFrequency: makeBaseline(
            userId: 'u1',
            metric: EvolutionMetric.weeklyFrequency,
            value: 5.0,
            sampleSize: 1,
          ),
          EvolutionMetric.weeklyVolume: makeBaseline(
            userId: 'u1',
            metric: EvolutionMetric.weeklyVolume,
            value: 10000,
            sampleSize: 2,
          ),
        },
      };

      final insights = gen.generate(
        groupId: 'g1',
        trends: [],
        baselinesByUser: baselines,
        activities: [
          makeActivity(
            userId: 'u1',
            sessionsLast7Days: 0,
            distanceLast7DaysM: 50000,
            lastSessionMs: 100,
          ),
        ],
        nowMs: 100,
        idGenerator: nextId,
      );

      final drops = insights
          .where((i) =>
              i.type == InsightType.consistencyDrop ||
              i.type == InsightType.overtrainingRisk)
          .toList();
      expect(drops, isEmpty);
    });
  });
}
