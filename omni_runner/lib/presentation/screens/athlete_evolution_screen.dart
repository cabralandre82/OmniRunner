import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_event.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_state.dart';

class AthleteEvolutionScreen extends StatelessWidget {
  final String athleteName;

  const AthleteEvolutionScreen({super.key, required this.athleteName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Evolução · $athleteName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<AthleteEvolutionBloc>()
                .add(const RefreshAthleteEvolution()),
          ),
        ],
      ),
      body: BlocBuilder<AthleteEvolutionBloc, AthleteEvolutionState>(
        builder: (context, state) => switch (state) {
          AthleteEvolutionInitial() =>
            const Center(child: Text('Carregando evolução...')),
          AthleteEvolutionLoading(:final metric, :final period) =>
            _FilteredShell(
              selectedMetric: metric,
              selectedPeriod: period,
              child: const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          AthleteEvolutionLoaded(
            :final trends,
            :final baselines,
            :final selectedMetric,
            :final selectedPeriod,
            :final selectedTrend,
            :final selectedBaseline,
          ) =>
            _FilteredShell(
              selectedMetric: selectedMetric,
              selectedPeriod: selectedPeriod,
              child: Expanded(
                child: _EvolutionContent(
                  trends: trends,
                  baselines: baselines,
                  selectedTrend: selectedTrend,
                  selectedBaseline: selectedBaseline,
                  selectedMetric: selectedMetric,
                ),
              ),
            ),
          AthleteEvolutionEmpty(:final metric, :final period) =>
            _FilteredShell(
              selectedMetric: metric,
              selectedPeriod: period,
              child: const Expanded(child: _EmptyState()),
            ),
          AthleteEvolutionError(:final message) => Center(
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

// ── Filter shell ──

class _FilteredShell extends StatelessWidget {
  final EvolutionMetric selectedMetric;
  final EvolutionPeriod selectedPeriod;
  final Widget child;

  const _FilteredShell({
    required this.selectedMetric,
    required this.selectedPeriod,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PeriodFilterBar(selected: selectedPeriod),
      _MetricFilterBar(selected: selectedMetric),
      child,
    ]);
  }
}

// ── Period filter ──

class _PeriodFilterBar extends StatelessWidget {
  final EvolutionPeriod selected;
  const _PeriodFilterBar({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: EvolutionPeriod.values.map((p) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_periodLabel(p)),
              selected: p == selected,
              onSelected: (_) => context
                  .read<AthleteEvolutionBloc>()
                  .add(ChangeEvolutionPeriod(p)),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _periodLabel(EvolutionPeriod p) => switch (p) {
        EvolutionPeriod.weekly => 'Semanal',
        EvolutionPeriod.monthly => 'Mensal',
      };
}

// ── Metric filter ──

class _MetricFilterBar extends StatelessWidget {
  final EvolutionMetric selected;
  const _MetricFilterBar({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: EvolutionMetric.values.map((m) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_metricLabel(m)),
                selected: m == selected,
                onSelected: (_) => context
                    .read<AthleteEvolutionBloc>()
                    .add(ChangeEvolutionMetric(m)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static String _metricLabel(EvolutionMetric m) => switch (m) {
        EvolutionMetric.avgPace => 'Pace',
        EvolutionMetric.avgDistance => 'Distância',
        EvolutionMetric.weeklyVolume => 'Volume',
        EvolutionMetric.weeklyFrequency => 'Frequência',
        EvolutionMetric.avgHeartRate => 'FC Média',
        EvolutionMetric.avgMovingTime => 'Tempo Ativo',
      };
}

// ── Main content ──

class _EvolutionContent extends StatelessWidget {
  final List<AthleteTrendEntity> trends;
  final List<AthleteBaselineEntity> baselines;
  final AthleteTrendEntity? selectedTrend;
  final AthleteBaselineEntity? selectedBaseline;
  final EvolutionMetric selectedMetric;

  const _EvolutionContent({
    required this.trends,
    required this.baselines,
    required this.selectedTrend,
    required this.selectedBaseline,
    required this.selectedMetric,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedTrend == null && selectedBaseline == null) {
      return const _EmptyState();
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (selectedTrend != null) _TrendCard(trend: selectedTrend!),
        if (selectedBaseline != null) ...[
          const SizedBox(height: 12),
          _BaselineCard(
            baseline: selectedBaseline!,
            metric: selectedMetric,
          ),
        ],
        const SizedBox(height: 20),
        _MetricSummaryGrid(trends: trends, baselines: baselines),
      ],
    );
  }
}

// ── Trend card ──

class _TrendCard extends StatelessWidget {
  final AthleteTrendEntity trend;
  const _TrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(_directionIcon(trend.direction),
                  color: _directionColor(trend.direction, cs), size: 28),
              const SizedBox(width: 8),
              Text(
                _directionLabel(trend.direction),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _directionColor(trend.direction, cs),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _directionColor(trend.direction, cs).withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatChangePercent(trend),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _directionColor(trend.direction, cs),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ValueColumn(
                  label: 'Atual',
                  value: _formatMetricValue(trend.currentValue, trend.metric),
                ),
                _ValueColumn(
                  label: 'Baseline',
                  value: _formatMetricValue(trend.baselineValue, trend.metric),
                ),
                _ValueColumn(
                  label: 'Período',
                  value: trend.latestPeriodKey,
                ),
                _ValueColumn(
                  label: 'Pontos',
                  value: '${trend.dataPoints}',
                ),
              ],
            ),
          ],
        ),
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

  static String _directionLabel(TrendDirection d) => switch (d) {
        TrendDirection.improving => 'Melhorando',
        TrendDirection.stable => 'Estável',
        TrendDirection.declining => 'Em queda',
        TrendDirection.insufficient => 'Dados insuficientes',
      };

  static Color _directionColor(TrendDirection d, ColorScheme cs) => switch (d) {
        TrendDirection.improving => Colors.green,
        TrendDirection.stable => cs.primary,
        TrendDirection.declining => cs.error,
        TrendDirection.insufficient => cs.outline,
      };
}

// ── Baseline card ──

class _BaselineCard extends StatelessWidget {
  final AthleteBaselineEntity baseline;
  final EvolutionMetric metric;

  const _BaselineCard({required this.baseline, required this.metric});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Baseline',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ValueColumn(
                  label: 'Valor',
                  value: _formatMetricValue(baseline.value, metric),
                ),
                _ValueColumn(
                  label: 'Sessões',
                  value: '${baseline.sampleSize}',
                ),
                _ValueColumn(
                  label: 'Confiável',
                  value: baseline.isReliable ? 'Sim' : 'Não',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Value column helper ──

class _ValueColumn extends StatelessWidget {
  final String label;
  final String value;

  const _ValueColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Summary grid (all metrics at a glance) ──

class _MetricSummaryGrid extends StatelessWidget {
  final List<AthleteTrendEntity> trends;
  final List<AthleteBaselineEntity> baselines;

  const _MetricSummaryGrid({
    required this.trends,
    required this.baselines,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionable = trends.where((t) => t.isActionable).toList();

    if (actionable.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Visão geral',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: actionable.map((t) => _MiniTrendChip(trend: t)).toList(),
        ),
      ],
    );
  }
}

class _MiniTrendChip extends StatelessWidget {
  final AthleteTrendEntity trend;
  const _MiniTrendChip({required this.trend});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _TrendCard._directionColor(trend.direction, cs);

    return Chip(
      avatar: Icon(
        _TrendCard._directionIcon(trend.direction),
        size: 18,
        color: color,
      ),
      label: Text(
        '${_metricShort(trend.metric)} ${_changeLabel(trend)}',
        style: TextStyle(fontSize: 12, color: color),
      ),
      backgroundColor: color.withAlpha(20),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  static String _metricShort(EvolutionMetric m) => switch (m) {
        EvolutionMetric.avgPace => 'Pace',
        EvolutionMetric.avgDistance => 'Dist',
        EvolutionMetric.weeklyVolume => 'Vol',
        EvolutionMetric.weeklyFrequency => 'Freq',
        EvolutionMetric.avgHeartRate => 'FC',
        EvolutionMetric.avgMovingTime => 'Tempo',
      };

  static String _changeLabel(AthleteTrendEntity t) {
    final sign = t.changePercent >= 0 ? '+' : '';
    return '$sign${t.changePercent.toStringAsFixed(1)}%';
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
            'Continue correndo para gerar análises\nde evolução do seu desempenho.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

// ── Shared formatters ──

String _formatMetricValue(double value, EvolutionMetric metric) =>
    switch (metric) {
      EvolutionMetric.avgPace => _formatPace(value),
      EvolutionMetric.avgDistance => '${(value / 1000).toStringAsFixed(2)} km',
      EvolutionMetric.weeklyVolume => '${(value / 1000).toStringAsFixed(1)} km',
      EvolutionMetric.weeklyFrequency =>
        '${value.toStringAsFixed(1)} sess/sem',
      EvolutionMetric.avgHeartRate => '${value.toStringAsFixed(0)} bpm',
      EvolutionMetric.avgMovingTime =>
        '${(value / 60000).toStringAsFixed(1)} min',
    };

String _formatPace(double secPerKm) {
  if (secPerKm == double.infinity || secPerKm <= 0) return '—';
  final min = secPerKm ~/ 60;
  final sec = (secPerKm % 60).toInt();
  return '$min:${sec.toString().padLeft(2, '0')}/km';
}
