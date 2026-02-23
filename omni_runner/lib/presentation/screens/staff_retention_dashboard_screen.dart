import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Staff retention dashboard — engagement and growth metrics.
///
/// Sections:
///   1. DAU / WAU gauge — today's and this week's active athletes
///   2. Weekly retention — 4-week retention trend (% returning athletes)
///   3. Active users per assessoria — for multi-group staff visibility
///
/// Data: sessions (verified runs), coaching_members, coaching_groups.
/// All queries are RLS-safe (caller is admin_master/professor).
/// No monetary values. No prohibited terms.
class StaffRetentionDashboardScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const StaffRetentionDashboardScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<StaffRetentionDashboardScreen> createState() =>
      _StaffRetentionDashboardScreenState();
}

class _StaffRetentionDashboardScreenState
    extends State<StaffRetentionDashboardScreen> {
  bool _loading = true;
  String? _error;

  int _dau = 0;
  int _wau = 0;
  int _totalAthletes = 0;

  List<_WeekRetention> _weeklyRetention = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = Supabase.instance.client;

      // 1. Fetch all athletes in the group
      final membersRes = await db
          .from('coaching_members')
          .select('user_id, role')
          .eq('group_id', widget.groupId);

      final members = (membersRes as List).cast<Map<String, dynamic>>();
      final athleteIds = members
          .where((m) => m['role'] == 'athlete')
          .map((m) => m['user_id'] as String)
          .toList();

      _totalAthletes = athleteIds.length;

      if (athleteIds.isEmpty) {
        _setEmpty();
        return;
      }

      // Time boundaries
      final now = DateTime.now().toUtc();
      final todayStart = DateTime.utc(now.year, now.month, now.day);
      final todayStartMs = todayStart.millisecondsSinceEpoch;

      final monday = now.subtract(Duration(days: now.weekday - 1));
      final weekStart = DateTime.utc(monday.year, monday.month, monday.day);
      final weekStartMs = weekStart.millisecondsSinceEpoch;

      // 4 weeks ago for retention trend
      final fourWeeksAgoMs =
          weekStart.subtract(const Duration(days: 21)).millisecondsSinceEpoch;

      // 2. Fetch sessions for group athletes over the last 4 weeks
      final sessionsRes = await db
          .from('sessions')
          .select('user_id, start_time_ms')
          .inFilter('user_id', athleteIds)
          .gte('start_time_ms', fourWeeksAgoMs)
          .eq('is_verified', true);

      final sessions = (sessionsRes as List).cast<Map<String, dynamic>>();

      // DAU: distinct users with sessions today
      final dauSet = <String>{};
      final wauSet = <String>{};

      for (final s in sessions) {
        final uid = s['user_id'] as String;
        final startMs = s['start_time_ms'] as int;

        if (startMs >= todayStartMs) dauSet.add(uid);
        if (startMs >= weekStartMs) wauSet.add(uid);
      }

      _dau = dauSet.length;
      _wau = wauSet.length;

      // 3. Weekly retention: bucket sessions into ISO weeks, compute retention
      _weeklyRetention = _computeWeeklyRetention(sessions, weekStart);

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar os dados.';
          _loading = false;
        });
      }
    }
  }

  List<_WeekRetention> _computeWeeklyRetention(
    List<Map<String, dynamic>> sessions,
    DateTime currentWeekStart,
  ) {
    final weeks = <int, Set<String>>{};

    for (final s in sessions) {
      final uid = s['user_id'] as String;
      final startMs = s['start_time_ms'] as int;
      final dt = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);

      final daysDiff = currentWeekStart.difference(dt).inDays;
      final weekIndex = daysDiff ~/ 7;
      // weekIndex 0 = current week, 1 = last week, etc.
      if (weekIndex >= 0 && weekIndex <= 3) {
        weeks.putIfAbsent(weekIndex, () => <String>{}).add(uid);
      }
    }

    final result = <_WeekRetention>[];

    for (var i = 3; i >= 0; i--) {
      final activeUsers = weeks[i] ?? <String>{};
      final count = activeUsers.length;
      final rate =
          _totalAthletes > 0 ? (count / _totalAthletes * 100) : 0.0;

      final weekDate =
          currentWeekStart.subtract(Duration(days: i * 7));
      final label =
          '${weekDate.day.toString().padLeft(2, '0')}/${weekDate.month.toString().padLeft(2, '0')}';

      // Returning = users also active in the previous week
      int returning = 0;
      if (i < 3) {
        final prevActive = weeks[i + 1] ?? <String>{};
        returning = activeUsers.intersection(prevActive).length;
      }

      result.add(_WeekRetention(
        label: label,
        activeCount: count,
        returningCount: returning,
        retentionPercent: rate,
      ));
    }

    return result;
  }

  void _setEmpty() {
    if (mounted) {
      setState(() {
        _dau = 0;
        _wau = 0;
        _weeklyRetention = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retenção'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _SectionHeader(widget.groupName),
                      const SizedBox(height: 16),
                      _EngagementCards(
                        dau: _dau,
                        wau: _wau,
                        totalAthletes: _totalAthletes,
                      ),
                      const SizedBox(height: 24),
                      _RetentionChart(weeks: _weeklyRetention),
                      const SizedBox(height: 24),
                      _RetentionTable(
                        weeks: _weeklyRetention,
                        totalAthletes: _totalAthletes,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data models
// ═══════════════════════════════════════════════════════════════════════════

class _WeekRetention {
  final String label;
  final int activeCount;
  final int returningCount;
  final double retentionPercent;

  const _WeekRetention({
    required this.label,
    required this.activeCount,
    required this.returningCount,
    required this.retentionPercent,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Section header
// ═══════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String groupName;
  const _SectionHeader(this.groupName);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          groupName,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          'Engajamento e retenção',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Engagement cards (DAU / WAU / Total)
// ═══════════════════════════════════════════════════════════════════════════

class _EngagementCards extends StatelessWidget {
  final int dau;
  final int wau;
  final int totalAthletes;

  const _EngagementCards({
    required this.dau,
    required this.wau,
    required this.totalAthletes,
  });

  @override
  Widget build(BuildContext context) {
    final wauRate = totalAthletes > 0
        ? (wau / totalAthletes * 100).toStringAsFixed(0)
        : '0';

    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            icon: Icons.today_rounded,
            label: 'Ativos hoje',
            value: '$dau',
            sublabel: 'DAU',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            icon: Icons.date_range_rounded,
            label: 'Ativos na semana',
            value: '$wau',
            sublabel: '$wauRate% do total',
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            icon: Icons.group_rounded,
            label: 'Total de atletas',
            value: '$totalAthletes',
            sublabel: 'cadastrados',
            color: Colors.deepPurple,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sublabel;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sublabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Retention bar chart (visual)
// ═══════════════════════════════════════════════════════════════════════════

class _RetentionChart extends StatelessWidget {
  final List<_WeekRetention> weeks;

  const _RetentionChart({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (weeks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Sem dados de retenção',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final maxActive = weeks
        .map((w) => w.activeCount)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, double.maxFinite.toInt());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Atividade semanal',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Atletas com pelo menos 1 corrida na semana',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: weeks.map((w) {
              final fraction = w.activeCount / maxActive;
              final isCurrentWeek = w == weeks.last;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${w.activeCount}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isCurrentWeek
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: fraction.clamp(0.05, 1.0),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: isCurrentWeek
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary
                                      .withValues(alpha: 0.35),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        w.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Retention table (detailed numbers)
// ═══════════════════════════════════════════════════════════════════════════

class _RetentionTable extends StatelessWidget {
  final List<_WeekRetention> weeks;
  final int totalAthletes;

  const _RetentionTable({
    required this.weeks,
    required this.totalAthletes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (weeks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Retenção semanal',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Atletas que retornaram da semana anterior',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              _TableHeader(theme: theme),
              ...weeks.asMap().entries.map((e) {
                final isLast = e.key == weeks.length - 1;
                return _TableRow(
                  week: e.value,
                  totalAthletes: totalAthletes,
                  isCurrentWeek: isLast,
                  showDivider: !isLast,
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InsightCard(weeks: weeks, totalAthletes: totalAthletes),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final ThemeData theme;
  const _TableHeader({required this.theme});

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(11)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Semana', style: style)),
          Expanded(child: Text('Ativos', style: style, textAlign: TextAlign.center)),
          Expanded(child: Text('Retorno', style: style, textAlign: TextAlign.center)),
          Expanded(child: Text('Taxa', style: style, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final _WeekRetention week;
  final int totalAthletes;
  final bool isCurrentWeek;
  final bool showDivider;

  const _TableRow({
    required this.week,
    required this.totalAthletes,
    required this.isCurrentWeek,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall;
    final boldStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w600,
      color: isCurrentWeek ? theme.colorScheme.primary : null,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(week.label, style: boldStyle),
                if (isCurrentWeek) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'atual',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${week.activeCount}',
              style: boldStyle,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              '${week.returningCount}',
              style: baseStyle,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              '${week.retentionPercent.toStringAsFixed(0)}%',
              style: boldStyle?.copyWith(
                color: _rateColor(week.retentionPercent, theme),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Color _rateColor(double rate, ThemeData theme) {
    if (rate >= 60) return Colors.green.shade700;
    if (rate >= 30) return Colors.orange.shade700;
    return theme.colorScheme.error;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Insight card — automated textual insight
// ═══════════════════════════════════════════════════════════════════════════

class _InsightCard extends StatelessWidget {
  final List<_WeekRetention> weeks;
  final int totalAthletes;

  const _InsightCard({required this.weeks, required this.totalAthletes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insight = _generateInsight();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: insight.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: insight.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(insight.icon, size: 20, color: insight.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: insight.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _Insight _generateInsight() {
    if (weeks.length < 2 || totalAthletes == 0) {
      return const _Insight(
        icon: Icons.info_outline_rounded,
        color: Colors.grey,
        title: 'Dados insuficientes',
        message: 'São necessárias pelo menos 2 semanas de dados.',
      );
    }

    final current = weeks.last;
    final previous = weeks[weeks.length - 2];

    final currentRate = current.retentionPercent;
    final previousRate = previous.retentionPercent;
    final diff = currentRate - previousRate;

    if (diff > 10) {
      return _Insight(
        icon: Icons.trending_up_rounded,
        color: Colors.green.shade700,
        title: 'Engajamento crescendo',
        message:
            'A taxa de participação subiu ${diff.toStringAsFixed(0)} pontos '
            'esta semana. Continue incentivando seus atletas!',
      );
    } else if (diff < -10) {
      return _Insight(
        icon: Icons.trending_down_rounded,
        color: Colors.orange.shade700,
        title: 'Atenção ao engajamento',
        message:
            'A participação caiu ${diff.abs().toStringAsFixed(0)} pontos '
            'esta semana. Considere criar um desafio ou campeonato.',
      );
    } else {
      return _Insight(
        icon: Icons.trending_flat_rounded,
        color: Colors.blue.shade700,
        title: 'Engajamento estável',
        message:
            '${current.activeCount} atletas ativos de $totalAthletes '
            'cadastrados. A participação está consistente.',
      );
    }
  }
}

class _Insight {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _Insight({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Error body
// ═══════════════════════════════════════════════════════════════════════════

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
