import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';

/// Displays personal performance evolution over the last 12 weeks.
///
/// Three charts:
///   1. Average pace (min/km) — line chart, lower is better
///   2. Weekly distance (km) — bar chart
///   3. Weekly frequency (# runs) — bar chart
///
/// Data sourced directly from `sessions` table, aggregated client-side
/// into ISO week buckets.
class PersonalEvolutionScreen extends StatefulWidget {
  const PersonalEvolutionScreen({super.key});

  @override
  State<PersonalEvolutionScreen> createState() =>
      _PersonalEvolutionScreenState();
}

class _PersonalEvolutionScreenState extends State<PersonalEvolutionScreen> {
  static const _weeks = 12;

  bool _loading = true;
  String? _error;
  List<_WeekBucket> _buckets = [];

  // Personal records
  double? _prPaceSecKm;
  double? _prDistanceM;

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
      final uid = sl<UserIdentityProvider>().userId;
      final cutoff =
          DateTime.now().subtract(const Duration(days: _weeks * 7));
      final cutoffMs = cutoff.millisecondsSinceEpoch;

      final rows = await Supabase.instance.client
          .from('sessions')
          .select('start_time_ms, end_time_ms, total_distance_m, is_verified')
          .eq('user_id', uid)
          .gte('start_time_ms', cutoffMs)
          .eq('is_verified', true)
          .order('start_time_ms');

      final sessions = (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((r) => _SessionRow(
                startMs: (r['start_time_ms'] as num).toInt(),
                endMs: (r['end_time_ms'] as num?)?.toInt(),
                distanceM: (r['total_distance_m'] as num?)?.toDouble(),
              ))
          .where((s) => s.distanceM != null && s.distanceM! > 100)
          .toList();

      // Compute week buckets
      final now = DateTime.now();
      final buckets = <_WeekBucket>[];
      for (var i = _weeks - 1; i >= 0; i--) {
        final weekStart = _startOfWeek(now.subtract(Duration(days: i * 7)));
        final weekEnd = weekStart.add(const Duration(days: 7));
        final weekSessions = sessions.where((s) {
          final dt = DateTime.fromMillisecondsSinceEpoch(s.startMs);
          return !dt.isBefore(weekStart) && dt.isBefore(weekEnd);
        }).toList();

        double totalDistKm = 0;
        double totalPaceSec = 0;
        int paceCount = 0;

        for (final s in weekSessions) {
          final distKm = s.distanceM! / 1000;
          totalDistKm += distKm;

          if (s.endMs != null && s.distanceM! > 500) {
            final durationSec = (s.endMs! - s.startMs) / 1000;
            final paceSecKm = durationSec / distKm;
            if (paceSecKm > 120 && paceSecKm < 1200) {
              totalPaceSec += paceSecKm;
              paceCount++;
            }
          }
        }

        buckets.add(_WeekBucket(
          label: _weekLabel(weekStart),
          runs: weekSessions.length,
          distanceKm: totalDistKm,
          avgPaceSecKm: paceCount > 0 ? totalPaceSec / paceCount : null,
        ));
      }

      // PRs
      double? bestPace;
      double? longestRun;
      for (final s in sessions) {
        if (s.distanceM != null) {
          if (longestRun == null || s.distanceM! > longestRun) {
            longestRun = s.distanceM!;
          }
          if (s.endMs != null && s.distanceM! > 500) {
            final pace = (s.endMs! - s.startMs) / 1000 / (s.distanceM! / 1000);
            if (pace > 120 && pace < 1200) {
              if (bestPace == null || pace < bestPace) bestPace = pace;
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _buckets = buckets;
        _prPaceSecKm = bestPace;
        _prDistanceM = longestRun;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao carregar dados: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha Evolução'),
        backgroundColor: cs.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: cs.error),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _prCards(theme),
                      const SizedBox(height: 24),
                      _sectionTitle(theme, 'Pace médio (min/km)', Icons.speed),
                      const SizedBox(height: 8),
                      _paceChart(theme),
                      const SizedBox(height: 24),
                      _sectionTitle(
                          theme, 'Volume semanal (km)', Icons.straighten),
                      const SizedBox(height: 8),
                      _distanceChart(theme),
                      const SizedBox(height: 24),
                      _sectionTitle(
                          theme, 'Corridas por semana', Icons.directions_run),
                      const SizedBox(height: 8),
                      _frequencyChart(theme),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _prCards(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _PrCard(
            icon: Icons.bolt_rounded,
            label: 'Melhor pace',
            value: _prPaceSecKm != null
                ? _formatPace(_prPaceSecKm!)
                : '—',
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PrCard(
            icon: Icons.route_rounded,
            label: 'Maior distância',
            value: _prDistanceM != null
                ? '${(_prDistanceM! / 1000).toStringAsFixed(1)} km'
                : '—',
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Pace line chart ──────────────────────────────────────────────────────

  Widget _paceChart(ThemeData theme) {
    final cs = theme.colorScheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < _buckets.length; i++) {
      final p = _buckets[i].avgPaceSecKm;
      if (p != null) spots.add(FlSpot(i.toDouble(), p / 60));
    }

    if (spots.length < 2) {
      return _emptyChart('Corra mais para ver seu pace ao longo do tempo');
    }

    final minY = spots.map((s) => s.y).reduce(min) - 0.5;
    final maxY = spots.map((s) => s.y).reduce(max) + 0.5;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: minY > 0 ? minY : 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) => Text(
                  '${v.toStringAsFixed(0)}\'',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 2,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= _buckets.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_buckets[idx].label,
                        style: theme.textTheme.labelSmall),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: cs.primary,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 3,
                  color: cs.primary,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: cs.primary.withValues(alpha: 0.1),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        _formatPace(s.y * 60),
                        TextStyle(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Distance bar chart ───────────────────────────────────────────────────

  Widget _distanceChart(ThemeData theme) {
    final cs = theme.colorScheme;
    final hasData = _buckets.any((b) => b.distanceKm > 0);
    if (!hasData) {
      return _emptyChart('Corra mais para ver seu volume semanal');
    }

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          barGroups: List.generate(_buckets.length, (i) {
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: _buckets[i].distanceKm,
                width: 14,
                color: Colors.blue.shade400,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]);
          }),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  '${v.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= _buckets.length) return const SizedBox();
                  if (idx % 2 != 0) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_buckets[idx].label,
                        style: theme.textTheme.labelSmall),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIdx, rod, rodIdx) =>
                  BarTooltipItem(
                '${rod.toY.toStringAsFixed(1)} km',
                TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Frequency bar chart ──────────────────────────────────────────────────

  Widget _frequencyChart(ThemeData theme) {
    final cs = theme.colorScheme;
    final hasData = _buckets.any((b) => b.runs > 0);
    if (!hasData) {
      return _emptyChart('Corra mais para ver sua frequência semanal');
    }

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          barGroups: List.generate(_buckets.length, (i) {
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: _buckets[i].runs.toDouble(),
                width: 14,
                color: Colors.green.shade400,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]);
          }),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= _buckets.length) return const SizedBox();
                  if (idx % 2 != 0) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_buckets[idx].label,
                        style: theme.textTheme.labelSmall),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIdx, rod, rodIdx) =>
                  BarTooltipItem(
                '${rod.toY.toInt()} corrida${rod.toY.toInt() == 1 ? '' : 's'}',
                TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyChart(String message) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.outline)),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static DateTime _startOfWeek(DateTime dt) {
    final weekday = dt.weekday;
    return DateTime(dt.year, dt.month, dt.day - (weekday - 1));
  }

  static String _weekLabel(DateTime weekStart) {
    return '${weekStart.day}/${weekStart.month}';
  }

  static String _formatPace(double secPerKm) {
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).toInt();
    return "$min'${sec.toString().padLeft(2, '0')}'";
  }
}

class _SessionRow {
  final int startMs;
  final int? endMs;
  final double? distanceM;
  const _SessionRow({required this.startMs, this.endMs, this.distanceM});
}

class _WeekBucket {
  final String label;
  final int runs;
  final double distanceKm;
  final double? avgPaceSecKm;
  const _WeekBucket({
    required this.label,
    required this.runs,
    required this.distanceKm,
    this.avgPaceSecKm,
  });
}

class _PrCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _PrCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
