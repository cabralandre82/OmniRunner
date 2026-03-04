import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_entry_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_state.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class GroupRankingsScreen extends StatelessWidget {
  final String groupName;

  const GroupRankingsScreen({super.key, required this.groupName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ranking · $groupName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CoachingRankingsBloc>()
                .add(const RefreshCoachingRanking()),
          ),
        ],
      ),
      body: BlocBuilder<CoachingRankingsBloc, CoachingRankingsState>(
        builder: (context, state) => switch (state) {
          CoachingRankingsInitial() =>
            const Center(child: Text('Selecione um ranking.')),
          CoachingRankingsLoading(:final metric, :final period) =>
            _FilteredShell(
              selectedMetric: metric,
              selectedPeriod: period,
              child: const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          CoachingRankingsLoaded(
            :final ranking,
            :final selectedMetric,
            :final selectedPeriod,
          ) =>
            _FilteredShell(
              selectedMetric: selectedMetric,
              selectedPeriod: selectedPeriod,
              child: Expanded(child: _RankingList(ranking: ranking)),
            ),
          CoachingRankingsEmpty(
            :final selectedMetric,
            :final selectedPeriod,
          ) =>
            _FilteredShell(
              selectedMetric: selectedMetric,
              selectedPeriod: selectedPeriod,
              child: Expanded(child: _EmptyState()),
            ),
          CoachingRankingsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
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

// ── Filter bar + content shell ──

class _FilteredShell extends StatelessWidget {
  final CoachingRankingMetric selectedMetric;
  final CoachingRankingPeriod selectedPeriod;
  final Widget child;

  const _FilteredShell({
    required this.selectedMetric,
    required this.selectedPeriod,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PeriodFilterBar(selected: selectedPeriod),
        _MetricFilterBar(selected: selectedMetric),
        child,
      ],
    );
  }
}

// ── Period filter ──

class _PeriodFilterBar extends StatelessWidget {
  final CoachingRankingPeriod selected;
  const _PeriodFilterBar({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 12, DesignTokens.spacingMd, 0),
      child: Row(
        children: CoachingRankingPeriod.values
            .where((p) => p != CoachingRankingPeriod.custom)
            .map((p) => Padding(
                  padding: const EdgeInsets.only(right: DesignTokens.spacingSm),
                  child: ChoiceChip(
                    label: Text(_periodLabel(p)),
                    selected: p == selected,
                    onSelected: (_) {
                      context.read<CoachingRankingsBloc>().add(
                            ChangePeriodFilter(
                              period: p,
                              periodKey: _currentPeriodKey(p),
                            ),
                          );
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }

  static String _periodLabel(CoachingRankingPeriod p) => switch (p) {
        CoachingRankingPeriod.weekly => 'Semanal',
        CoachingRankingPeriod.monthly => 'Mensal',
        CoachingRankingPeriod.custom => 'Custom',
      };

  static String _currentPeriodKey(CoachingRankingPeriod p) {
    final now = DateTime.now().toUtc();
    return switch (p) {
      CoachingRankingPeriod.weekly => _isoWeekKey(now),
      CoachingRankingPeriod.monthly =>
        '${now.year}-${now.month.toString().padLeft(2, '0')}',
      CoachingRankingPeriod.custom => 'custom',
    };
  }

  static String _isoWeekKey(DateTime dt) {
    final thursday = dt.add(Duration(days: DateTime.thursday - dt.weekday));
    final jan1 = DateTime.utc(thursday.year, 1, 1);
    final week =
        ((thursday.difference(jan1).inDays) / 7).ceil().clamp(1, 53);
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }
}

// ── Metric filter ──

class _MetricFilterBar extends StatelessWidget {
  final CoachingRankingMetric selected;
  const _MetricFilterBar({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingSm, DesignTokens.spacingMd, DesignTokens.spacingSm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: CoachingRankingMetric.values
              .map((m) => Padding(
                    padding: const EdgeInsets.only(right: DesignTokens.spacingSm),
                    child: ChoiceChip(
                      label: Text(_metricLabel(m)),
                      selected: m == selected,
                      onSelected: (_) {
                        context
                            .read<CoachingRankingsBloc>()
                            .add(ChangeMetricFilter(m));
                      },
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  static String _metricLabel(CoachingRankingMetric m) => switch (m) {
        CoachingRankingMetric.volumeDistance => 'Distância',
        CoachingRankingMetric.totalTime => 'Tempo',
        CoachingRankingMetric.bestPace => 'Pace',
        CoachingRankingMetric.consistencyDays => 'Consistência',
      };
}

// ── Empty state ──

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.leaderboard_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Ranking vazio', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Nenhum dado para este período.\nCorra para aparecer no ranking!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

// ── Ranking list ──

class _RankingList extends StatelessWidget {
  final CoachingGroupRankingEntity ranking;
  const _RankingList({required this.ranking});

  @override
  Widget build(BuildContext context) {
    final entries = ranking.entries;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
      itemCount: entries.length,
      itemBuilder: (context, index) =>
          _RankingEntryTile(entry: entries[index], metric: ranking.metric),
    );
  }
}

// ── Single entry tile ──

class _RankingEntryTile extends StatelessWidget {
  final CoachingRankingEntryEntity entry;
  final CoachingRankingMetric metric;

  const _RankingEntryTile({required this.entry, required this.metric});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTop3 = entry.rank <= 3;

    final rankColor = switch (entry.rank) {
      1 => DesignTokens.warning,
      2 => DesignTokens.textMuted,
      3 => DesignTokens.warning,
      _ => theme.colorScheme.outline,
    };

    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Center(
          child: isTop3
              ? Icon(Icons.emoji_events, color: rankColor, size: 28)
              : Text(
                  '${entry.rank}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: rankColor,
                  ),
                ),
        ),
      ),
      title: Text(
        entry.displayName,
        style: theme.textTheme.bodyLarge
            ?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${entry.sessionCount} corrida${entry.sessionCount == 1 ? '' : 's'}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: Text(
        _formatValue(entry.value, metric),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  static String _formatValue(double value, CoachingRankingMetric metric) =>
      switch (metric) {
        CoachingRankingMetric.volumeDistance =>
          '${(value / 1000).toStringAsFixed(1)} km',
        CoachingRankingMetric.totalTime =>
          '${(value / 3600000).toStringAsFixed(1)} h',
        CoachingRankingMetric.bestPace => _formatPace(value),
        CoachingRankingMetric.consistencyDays =>
          '${value.toStringAsFixed(0)} dias',
      };

  static String _formatPace(double secPerKm) {
    if (secPerKm == double.infinity) return '—';
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).toInt();
    return '$min:${sec.toString().padLeft(2, '0')}/km';
  }
}
