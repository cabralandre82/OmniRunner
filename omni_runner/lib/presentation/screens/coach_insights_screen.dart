import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/coach_insight_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_bloc.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_event.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_state.dart';

class CoachInsightsScreen extends StatelessWidget {
  final String groupName;

  const CoachInsightsScreen({super.key, required this.groupName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Insights · $groupName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CoachInsightsBloc>()
                .add(const RefreshCoachInsights()),
          ),
        ],
      ),
      body: BlocBuilder<CoachInsightsBloc, CoachInsightsState>(
        builder: (context, state) => switch (state) {
          CoachInsightsInitial() =>
            const Center(child: Text('Carregando insights...')),
          CoachInsightsLoading() =>
            const Center(child: CircularProgressIndicator()),
          CoachInsightsLoaded(
            :final insights,
            :final unreadCount,
            :final typeFilter,
            :final unreadOnly,
          ) =>
            _LoadedBody(
              insights: insights,
              unreadCount: unreadCount,
              typeFilter: typeFilter,
              unreadOnly: unreadOnly,
            ),
          CoachInsightsEmpty(:final typeFilter, :final unreadOnly) =>
            _FilterShell(
              typeFilter: typeFilter,
              unreadOnly: unreadOnly,
              unreadCount: 0,
              child: const Expanded(child: _EmptyState()),
            ),
          CoachInsightsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        },
      ),
    );
  }
}

// ── Loaded body ──

class _LoadedBody extends StatelessWidget {
  final List<CoachInsightEntity> insights;
  final int unreadCount;
  final InsightType? typeFilter;
  final bool unreadOnly;

  const _LoadedBody({
    required this.insights,
    required this.unreadCount,
    required this.typeFilter,
    required this.unreadOnly,
  });

  @override
  Widget build(BuildContext context) {
    return _FilterShell(
      typeFilter: typeFilter,
      unreadOnly: unreadOnly,
      unreadCount: unreadCount,
      child: Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: insights.length,
          itemBuilder: (context, i) =>
              _InsightCard(insight: insights[i]),
        ),
      ),
    );
  }
}

// ── Filter shell ──

class _FilterShell extends StatelessWidget {
  final InsightType? typeFilter;
  final bool unreadOnly;
  final int unreadCount;
  final Widget child;

  const _FilterShell({
    required this.typeFilter,
    required this.unreadOnly,
    required this.unreadCount,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (unreadCount > 0)
        _UnreadBanner(count: unreadCount, active: unreadOnly),
      _TypeFilterBar(selected: typeFilter),
      child,
    ]);
  }
}

// ── Unread banner ──

class _UnreadBanner extends StatelessWidget {
  final int count;
  final bool active;

  const _UnreadBanner({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context
          .read<CoachInsightsBloc>()
          .add(FilterUnreadOnly(!active)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: active
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Icon(
              active ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              active
                  ? '$count não lido(s) · Mostrando apenas não lidos'
                  : '$count insight(s) não lido(s)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Type filter bar ──

class _TypeFilterBar extends StatelessWidget {
  final InsightType? selected;
  const _TypeFilterBar({required this.selected});

  @override
  Widget build(BuildContext context) {
    final items = <InsightType?>[null, ..._displayedTypes];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((t) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_typeFilterLabel(t)),
                selected: t == selected,
                onSelected: (_) => context
                    .read<CoachInsightsBloc>()
                    .add(FilterByType(t)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static const _displayedTypes = [
    InsightType.performanceDecline,
    InsightType.performanceImprovement,
    InsightType.inactivityWarning,
    InsightType.consistencyDrop,
    InsightType.overtrainingRisk,
    InsightType.groupTrendSummary,
  ];

  static String _typeFilterLabel(InsightType? t) => switch (t) {
        null => 'Todos',
        InsightType.performanceDecline => 'Em queda',
        InsightType.performanceImprovement => 'Evoluindo',
        InsightType.inactivityWarning => 'Inativos',
        InsightType.consistencyDrop => 'Consistência',
        InsightType.overtrainingRisk => 'Overtraining',
        InsightType.groupTrendSummary => 'Resumo',
        InsightType.personalRecord => 'PR',
        InsightType.raceReady => 'Prova',
        InsightType.eventMilestone => 'Milestone',
        InsightType.rankingChange => 'Ranking',
      };
}

// ── Insight card ──

class _InsightCard extends StatelessWidget {
  final CoachInsightEntity insight;
  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final priorityColor = _priorityColor(insight.priority, cs);
    final typeIcon = _typeIcon(insight.type);
    final isUnread = !insight.isRead && !insight.dismissed;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isUnread ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isUnread
            ? BorderSide(color: priorityColor.withAlpha(80), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!insight.isRead) {
            context
                .read<CoachInsightsBloc>()
                .add(MarkInsightRead(insight.id));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: priorityColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(typeIcon, color: priorityColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight:
                                isUnread ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            _PriorityBadge(
                                priority: insight.priority,
                                color: priorityColor),
                            const SizedBox(width: 8),
                            if (insight.isAthleteSpecific)
                              Icon(Icons.person_outline,
                                  size: 14, color: cs.outline)
                            else
                              Icon(Icons.groups_outlined,
                                  size: 14, color: cs.outline),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                insight.targetDisplayName ?? 'Grupo',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: cs.outline),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isUnread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                insight.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isUnread ? cs.onSurface : cs.outline,
                ),
              ),
              if (insight.changePercent != null) ...[
                const SizedBox(height: 8),
                _ChangeChip(changePercent: insight.changePercent!),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    _formatTimestamp(insight.createdAtMs),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.outline),
                  ),
                  const Spacer(),
                  if (!insight.dismissed)
                    _DismissButton(insightId: insight.id),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Priority badge ──

class _PriorityBadge extends StatelessWidget {
  final InsightPriority priority;
  final Color color;

  const _PriorityBadge({required this.priority, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _priorityLabel(priority),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  static String _priorityLabel(InsightPriority p) => switch (p) {
        InsightPriority.low => 'INFO',
        InsightPriority.medium => 'MÉDIO',
        InsightPriority.high => 'ALTO',
        InsightPriority.critical => 'URGENTE',
      };
}

// ── Change chip ──

class _ChangeChip extends StatelessWidget {
  final double changePercent;
  const _ChangeChip({required this.changePercent});

  @override
  Widget build(BuildContext context) {
    final isPositive = changePercent >= 0;
    final color = isPositive ? Colors.green : Colors.red;
    final sign = isPositive ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.trending_up : Icons.trending_down,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '$sign${changePercent.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dismiss button ──

class _DismissButton extends StatelessWidget {
  final String insightId;
  const _DismissButton({required this.insightId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context
          .read<CoachInsightsBloc>()
          .add(DismissInsight(insightId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close,
                size: 14, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 4),
            Text(
              'Dispensar',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ──

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lightbulb_outline,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Nenhum insight encontrado',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Os insights serão gerados automaticamente\n'
            'com base nas atividades dos atletas.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ──

IconData _typeIcon(InsightType t) => switch (t) {
      InsightType.performanceDecline => Icons.trending_down,
      InsightType.performanceImprovement => Icons.trending_up,
      InsightType.consistencyDrop => Icons.event_busy,
      InsightType.inactivityWarning => Icons.snooze,
      InsightType.personalRecord => Icons.emoji_events,
      InsightType.overtrainingRisk => Icons.warning_amber_rounded,
      InsightType.raceReady => Icons.flag,
      InsightType.groupTrendSummary => Icons.insights,
      InsightType.eventMilestone => Icons.stars,
      InsightType.rankingChange => Icons.leaderboard,
    };

Color _priorityColor(InsightPriority p, ColorScheme cs) => switch (p) {
      InsightPriority.low => cs.outline,
      InsightPriority.medium => Colors.amber.shade700,
      InsightPriority.high => Colors.deepOrange,
      InsightPriority.critical => cs.error,
    };
