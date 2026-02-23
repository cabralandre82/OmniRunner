import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_event.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_state.dart';

class GroupEvolutionScreen extends StatelessWidget {
  final String groupName;

  const GroupEvolutionScreen({super.key, required this.groupName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Evolução · $groupName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<GroupEvolutionBloc>()
                .add(const RefreshGroupEvolution()),
          ),
        ],
      ),
      body: BlocBuilder<GroupEvolutionBloc, GroupEvolutionState>(
        builder: (context, state) => switch (state) {
          GroupEvolutionInitial() =>
            const Center(child: Text('Carregando evolução do grupo...')),
          GroupEvolutionLoading(:final directionFilter) =>
            _DirectionFilterShell(
              selected: directionFilter,
              child: const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          GroupEvolutionLoaded(
            :final trends,
            :final directionFilter,
            :final improvingCount,
            :final stableCount,
            :final decliningCount,
            :final insufficientCount,
          ) =>
            _DirectionFilterShell(
              selected: directionFilter,
              child: Expanded(
                child: _GroupContent(
                  trends: trends,
                  improvingCount: improvingCount,
                  stableCount: stableCount,
                  decliningCount: decliningCount,
                  insufficientCount: insufficientCount,
                ),
              ),
            ),
          GroupEvolutionEmpty(:final directionFilter) =>
            _DirectionFilterShell(
              selected: directionFilter,
              child: const Expanded(child: _EmptyState()),
            ),
          GroupEvolutionError(:final message) => Center(
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

// ── Direction filter shell ──

class _DirectionFilterShell extends StatelessWidget {
  final TrendDirection? selected;
  final Widget child;

  const _DirectionFilterShell({required this.selected, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _DirectionFilterBar(selected: selected),
      child,
    ]);
  }
}

class _DirectionFilterBar extends StatelessWidget {
  final TrendDirection? selected;
  const _DirectionFilterBar({required this.selected});

  @override
  Widget build(BuildContext context) {
    final items = [null, ...TrendDirection.values];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((d) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_directionFilterLabel(d)),
                selected: d == selected,
                onSelected: (_) => context
                    .read<GroupEvolutionBloc>()
                    .add(ChangeDirectionFilter(d)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static String _directionFilterLabel(TrendDirection? d) => switch (d) {
        null => 'Todos',
        TrendDirection.improving => 'Melhorando',
        TrendDirection.stable => 'Estável',
        TrendDirection.declining => 'Em queda',
        TrendDirection.insufficient => 'Insuficiente',
      };
}

// ── Main content ──

class _GroupContent extends StatelessWidget {
  final List<AthleteTrendEntity> trends;
  final int improvingCount;
  final int stableCount;
  final int decliningCount;
  final int insufficientCount;

  const _GroupContent({
    required this.trends,
    required this.improvingCount,
    required this.stableCount,
    required this.decliningCount,
    required this.insufficientCount,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _SummaryBar(
          improving: improvingCount,
          stable: stableCount,
          declining: decliningCount,
          insufficient: insufficientCount,
        ),
        const SizedBox(height: 12),
        ...trends.map((t) => _AthleteTrendTile(trend: t)),
      ],
    );
  }
}

// ── Summary bar ──

class _SummaryBar extends StatelessWidget {
  final int improving;
  final int stable;
  final int declining;
  final int insufficient;

  const _SummaryBar({
    required this.improving,
    required this.stable,
    required this.declining,
    required this.insufficient,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _CountBadge(
              icon: Icons.trending_up,
              count: improving,
              color: Colors.green,
              label: 'Melhorando',
              theme: theme,
            ),
            _CountBadge(
              icon: Icons.trending_flat,
              count: stable,
              color: theme.colorScheme.primary,
              label: 'Estável',
              theme: theme,
            ),
            _CountBadge(
              icon: Icons.trending_down,
              count: declining,
              color: theme.colorScheme.error,
              label: 'Em queda',
              theme: theme,
            ),
            _CountBadge(
              icon: Icons.help_outline,
              count: insufficient,
              color: theme.colorScheme.outline,
              label: 'Insuf.',
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  final String label;
  final ThemeData theme;

  const _CountBadge({
    required this.icon,
    required this.count,
    required this.color,
    required this.label,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 2),
        Text('$count',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}

// ── Athlete trend tile ──

class _AthleteTrendTile extends StatelessWidget {
  final AthleteTrendEntity trend;
  const _AthleteTrendTile({required this.trend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _directionColor(trend.direction, cs);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(25),
          child: Icon(_directionIcon(trend.direction), color: color, size: 22),
        ),
        title: Text(
          trend.userId,
          style: theme.textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_metricLabel(trend.metric)} · ${_periodLabel(trend.period)} · '
          '${trend.latestPeriodKey}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.outline),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatChangePercent(trend),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              _formatMetricValue(trend.currentValue, trend.metric),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.outline),
            ),
          ],
        ),
        onTap: () {},
      ),
    );
  }

  static String _formatChangePercent(AthleteTrendEntity t) {
    final sign = t.changePercent >= 0 ? '+' : '';
    return '$sign${t.changePercent.toStringAsFixed(1)}%';
  }

  static IconData _directionIcon(TrendDirection d) => switch (d) {
        TrendDirection.improving => Icons.trending_up,
        TrendDirection.stable => Icons.trending_flat,
        TrendDirection.declining => Icons.trending_down,
        TrendDirection.insufficient => Icons.help_outline,
      };

  static Color _directionColor(TrendDirection d, ColorScheme cs) => switch (d) {
        TrendDirection.improving => Colors.green,
        TrendDirection.stable => cs.primary,
        TrendDirection.declining => cs.error,
        TrendDirection.insufficient => cs.outline,
      };

  static String _metricLabel(EvolutionMetric m) => switch (m) {
        EvolutionMetric.avgPace => 'Pace',
        EvolutionMetric.avgDistance => 'Distância',
        EvolutionMetric.weeklyVolume => 'Volume',
        EvolutionMetric.weeklyFrequency => 'Frequência',
        EvolutionMetric.avgHeartRate => 'FC Média',
        EvolutionMetric.avgMovingTime => 'Tempo Ativo',
      };

  static String _periodLabel(EvolutionPeriod p) => switch (p) {
        EvolutionPeriod.weekly => 'Semanal',
        EvolutionPeriod.monthly => 'Mensal',
      };

  static String _formatMetricValue(double value, EvolutionMetric metric) =>
      switch (metric) {
        EvolutionMetric.avgPace => _formatPace(value),
        EvolutionMetric.avgDistance =>
          '${(value / 1000).toStringAsFixed(2)} km',
        EvolutionMetric.weeklyVolume =>
          '${(value / 1000).toStringAsFixed(1)} km',
        EvolutionMetric.weeklyFrequency =>
          '${value.toStringAsFixed(1)} sess/sem',
        EvolutionMetric.avgHeartRate => '${value.toStringAsFixed(0)} bpm',
        EvolutionMetric.avgMovingTime =>
          '${(value / 60000).toStringAsFixed(1)} min',
      };

  static String _formatPace(double secPerKm) {
    if (secPerKm == double.infinity || secPerKm <= 0) return '—';
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).toInt();
    return '$min:${sec.toString().padLeft(2, '0')}/km';
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
          Icon(Icons.insights_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Sem dados de evolução', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Nenhum dado de tendência encontrado\npara este grupo com o filtro atual.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
