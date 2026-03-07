import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/coach_insight_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Result DTOs
// ═════════════════════════════════════════════════════════════════════════════

/// Result of a [submitAnalyticsData] call.
final class AnalyticsSubmitResult {
  final bool alreadyProcessed;
  final int baselinesUpdated;
  final int trendsUpdated;
  final int insightsGenerated;

  const AnalyticsSubmitResult({
    this.alreadyProcessed = false,
    this.baselinesUpdated = 0,
    this.trendsUpdated = 0,
    this.insightsGenerated = 0,
  });
}

/// Combined result of [fetchEvolutionMetrics].
final class EvolutionMetricsResult {
  final List<AthleteTrendEntity> trends;
  final List<AthleteBaselineEntity> baselines;

  const EvolutionMetricsResult({
    required this.trends,
    required this.baselines,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// Exceptions
// ═════════════════════════════════════════════════════════════════════════════

sealed class AnalyticsSyncException implements Exception {
  final String message;
  const AnalyticsSyncException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

final class AnalyticsNotConfigured extends AnalyticsSyncException {
  const AnalyticsNotConfigured()
      : super('Supabase not configured — analytics unavailable');
}

final class AnalyticsNotAuthenticated extends AnalyticsSyncException {
  const AnalyticsNotAuthenticated() : super('User not authenticated');
}

final class AnalyticsServerError extends AnalyticsSyncException {
  final int? statusCode;
  const AnalyticsServerError(super.message, {this.statusCode});
}

final class AnalyticsValidationError extends AnalyticsSyncException {
  final String code;
  const AnalyticsValidationError({required this.code, required String message})
      : super(message);
}

// ═════════════════════════════════════════════════════════════════════════════
// Service
// ═════════════════════════════════════════════════════════════════════════════

/// Low-level datasource for coaching analytics sync with Supabase.
///
/// Implements the three operations defined in `contracts/analytics_api.md`:
/// - [submitAnalyticsData] — POST to Edge Function
/// - [fetchGroupInsights] — GET from `coach_insights` table
/// - [fetchEvolutionMetrics] — GET from `athlete_trends` + `athlete_baselines`
///
/// Also exposes [markInsightRead] and [dismissInsight] for PATCH operations.
///
/// All methods require an authenticated Supabase session.
class AnalyticsSyncService {
  static const _tag = 'AnalyticsSyncService';
  static const _edgeFnSubmit = 'submit-analytics';
  static const _insightsTable = 'coach_insights';
  static const _trendsTable = 'athlete_trends';
  static const _baselinesTable = 'athlete_baselines';
  static const _defaultLimit = 50;
  static const _maxLimit = 200;

  SupabaseClient get _client {
    if (!AppConfig.isSupabaseReady) {
      throw const AnalyticsNotConfigured();
    }
    return sl<SupabaseClient>();
  }

  String? get _userId {
    if (!AppConfig.isSupabaseReady) return null;
    try {
      return sl<SupabaseClient>().auth.currentUser?.id;
    } on Exception {
      return null;
    }
  }

  void _requireConfigured() {
    if (!AppConfig.isSupabaseReady) {
      throw const AnalyticsNotConfigured();
    }
  }

  void _requireAuth() {
    _requireConfigured();
    if (_userId == null) throw const AnalyticsNotAuthenticated();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1 — submitAnalyticsData
  // ═══════════════════════════════════════════════════════════════════════════

  /// Submits a session's analytics data to the backend Edge Function.
  ///
  /// The Edge Function recalculates baselines, trends, and insights.
  /// Idempotent: duplicate `sessionId` returns [alreadyProcessed].
  Future<AnalyticsSubmitResult> submitAnalyticsData({
    required String sessionId,
    required String groupId,
    required int startTimeMs,
    required int endTimeMs,
    required double distanceM,
    required int movingMs,
    double? avgPaceSecPerKm,
    int? avgBpm,
  }) async {
    _requireAuth();
    final userId = _userId!;

    final body = <String, Object?>{
      'session_id': sessionId,
      'user_id': userId,
      'group_id': groupId,
      'start_time_ms': startTimeMs,
      'end_time_ms': endTimeMs,
      'distance_m': distanceM,
      'moving_ms': movingMs,
      if (avgPaceSecPerKm != null) 'avg_pace_sec_per_km': avgPaceSecPerKm,
      if (avgBpm != null) 'avg_bpm': avgBpm,
    };

    AppLogger.info('Submitting analytics for session $sessionId', tag: _tag);

    try {
      final response = await _client.functions.invoke(
        _edgeFnSubmit,
        body: body,
      );

      final data = response.data as Map<String, dynamic>? ?? {};
      final status = data['status'] as String? ?? '';

      if (status == 'already_processed') {
        AppLogger.info('Session $sessionId already processed', tag: _tag);
        return const AnalyticsSubmitResult(alreadyProcessed: true);
      }

      if (status == 'error') {
        final code = data['code'] as String? ?? 'unknown';
        final msg = data['message'] as String? ?? 'Unknown error';
        throw AnalyticsValidationError(code: code, message: msg);
      }

      final result = AnalyticsSubmitResult(
        baselinesUpdated: data['baselines_updated'] as int? ?? 0,
        trendsUpdated: data['trends_updated'] as int? ?? 0,
        insightsGenerated: data['insights_generated'] as int? ?? 0,
      );

      AppLogger.info(
        'Analytics submitted: ${result.baselinesUpdated} baselines, '
        '${result.trendsUpdated} trends, '
        '${result.insightsGenerated} insights',
        tag: _tag,
      );
      return result;
    } on FunctionException catch (e) {
      throw AnalyticsServerError(
        e.reasonPhrase ?? 'Edge function error',
        statusCode: e.status,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2 — fetchGroupInsights
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetches coaching insights for a group, newest first.
  Future<List<CoachInsightEntity>> fetchGroupInsights({
    required String groupId,
    InsightType? type,
    InsightPriority? priority,
    bool unreadOnly = false,
    bool excludeDismissed = true,
    int limit = _defaultLimit,
    int offset = 0,
  }) async {
    _requireAuth();
    final clampedLimit = limit.clamp(1, _maxLimit);

    var query = _client
        .from(_insightsTable)
        .select()
        .eq('group_id', groupId);

    if (type != null) {
      query = query.eq('type', _camelToSnake(type.name));
    }
    if (priority != null) {
      query = query.eq('priority', priority.name);
    }
    if (unreadOnly) {
      query = query.isFilter('read_at_ms', null);
    }
    if (excludeDismissed) {
      query = query.eq('dismissed', false);
    }

    final rows = await query
        .order('created_at_ms', ascending: false)
        .range(offset, offset + clampedLimit - 1);

    AppLogger.debug(
      'Fetched ${rows.length} insights for group $groupId',
      tag: _tag,
    );
    return rows.map(_insightFromJson).toList();
  }

  /// Counts unread, non-dismissed insights for badge display.
  Future<int> countUnreadInsights(String groupId) async {
    _requireAuth();
    final result = await _client
        .from(_insightsTable)
        .select()
        .eq('group_id', groupId)
        .isFilter('read_at_ms', null)
        .eq('dismissed', false)
        .count(CountOption.exact);
    return result.count;
  }

  /// Marks an insight as read.
  Future<void> markInsightRead(String insightId, int nowMs) async {
    _requireAuth();
    await _client
        .from(_insightsTable)
        .update({'read_at_ms': nowMs})
        .eq('id', insightId);
    AppLogger.debug('Insight $insightId marked read', tag: _tag);
  }

  /// Dismisses an insight.
  Future<void> dismissInsight(String insightId) async {
    _requireAuth();
    await _client
        .from(_insightsTable)
        .update({'dismissed': true})
        .eq('id', insightId);
    AppLogger.debug('Insight $insightId dismissed', tag: _tag);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3 — fetchEvolutionMetrics
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetches trends and baselines for a coaching group.
  ///
  /// If [userId] is provided, only that athlete's data is returned.
  Future<EvolutionMetricsResult> fetchEvolutionMetrics({
    required String groupId,
    String? userId,
    EvolutionMetric? metric,
    EvolutionPeriod? period,
    TrendDirection? direction,
    int limit = 100,
  }) async {
    _requireAuth();

    final trends = await _fetchTrends(
      groupId: groupId,
      userId: userId,
      metric: metric,
      period: period,
      direction: direction,
      limit: limit,
    );

    final baselines = await _fetchBaselines(
      groupId: groupId,
      userId: userId,
      metric: metric,
    );

    AppLogger.debug(
      'Fetched ${trends.length} trends, ${baselines.length} baselines '
      'for group $groupId',
      tag: _tag,
    );

    return EvolutionMetricsResult(trends: trends, baselines: baselines);
  }

  Future<List<AthleteTrendEntity>> _fetchTrends({
    required String groupId,
    String? userId,
    EvolutionMetric? metric,
    EvolutionPeriod? period,
    TrendDirection? direction,
    required int limit,
  }) async {
    var query = _client
        .from(_trendsTable)
        .select()
        .eq('group_id', groupId);

    if (userId != null) query = query.eq('user_id', userId);
    if (metric != null) {
      query = query.eq('metric', _camelToSnake(metric.name));
    }
    if (period != null) query = query.eq('period', period.name);
    if (direction != null) query = query.eq('direction', direction.name);

    final rows = await query
        .order('analyzed_at_ms', ascending: false)
        .limit(limit.clamp(1, _maxLimit));

    return rows.map(_trendFromJson).toList();
  }

  Future<List<AthleteBaselineEntity>> _fetchBaselines({
    required String groupId,
    String? userId,
    EvolutionMetric? metric,
  }) async {
    var query = _client
        .from(_baselinesTable)
        .select()
        .eq('group_id', groupId);

    if (userId != null) query = query.eq('user_id', userId);
    if (metric != null) {
      query = query.eq('metric', _camelToSnake(metric.name));
    }

    final rows = await query.order('computed_at_ms', ascending: false);
    return rows.map(_baselineFromJson).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JSON → Entity mappers
  // ═══════════════════════════════════════════════════════════════════════════

  static CoachInsightEntity _insightFromJson(Map<String, dynamic> j) {
    return CoachInsightEntity(
      id: j['id'] as String,
      groupId: j['group_id'] as String,
      targetUserId: j['target_user_id'] as String?,
      targetDisplayName: j['target_display_name'] as String?,
      type: InsightType.values.byName(_snakeToCamel(j['type'] as String)),
      priority:
          InsightPriority.values.byName(j['priority'] as String),
      title: j['title'] as String,
      message: j['message'] as String,
      metric: j['metric'] != null
          ? EvolutionMetric.values
              .byName(_snakeToCamel(j['metric'] as String))
          : null,
      referenceValue: (j['reference_value'] as num?)?.toDouble(),
      changePercent: (j['change_percent'] as num?)?.toDouble(),
      relatedEntityId: j['related_entity_id'] as String?,
      createdAtMs: j['created_at_ms'] as int,
      readAtMs: j['read_at_ms'] as int?,
      dismissed: j['dismissed'] as bool? ?? false,
    );
  }

  static AthleteTrendEntity _trendFromJson(Map<String, dynamic> j) {
    return AthleteTrendEntity(
      id: j['id'] as String,
      userId: j['user_id'] as String,
      groupId: j['group_id'] as String,
      metric: EvolutionMetric.values
          .byName(_snakeToCamel(j['metric'] as String)),
      period: EvolutionPeriod.values.byName(j['period'] as String),
      direction: TrendDirection.values.byName(j['direction'] as String),
      currentValue: (j['current_value'] as num).toDouble(),
      baselineValue: (j['baseline_value'] as num).toDouble(),
      changePercent: (j['change_percent'] as num).toDouble(),
      dataPoints: j['data_points'] as int,
      latestPeriodKey: j['latest_period_key'] as String,
      analyzedAtMs: j['analyzed_at_ms'] as int,
    );
  }

  static AthleteBaselineEntity _baselineFromJson(Map<String, dynamic> j) {
    return AthleteBaselineEntity(
      id: j['id'] as String,
      userId: j['user_id'] as String,
      groupId: j['group_id'] as String,
      metric: EvolutionMetric.values
          .byName(_snakeToCamel(j['metric'] as String)),
      value: (j['value'] as num).toDouble(),
      sampleSize: j['sample_size'] as int,
      windowStartMs: j['window_start_ms'] as int,
      windowEndMs: j['window_end_ms'] as int,
      computedAtMs: j['computed_at_ms'] as int,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // String converters (snake_case ↔ camelCase)
  // ═══════════════════════════════════════════════════════════════════════════

  /// `avg_pace` → `avgPace`
  static String _snakeToCamel(String s) {
    final parts = s.split('_');
    return parts.first +
        parts
            .skip(1)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
            .join();
  }

  /// `avgPace` → `avg_pace`
  static String _camelToSnake(String s) {
    return s.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '_${m[0]!.toLowerCase()}',
    );
  }
}
