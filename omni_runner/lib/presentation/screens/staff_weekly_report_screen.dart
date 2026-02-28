import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Weekly report for the assessoria staff.
///
/// Shows a past-week summary that can be navigated (prev/next week).
/// Three sections:
///   1. Summary — total runs, distance, active athletes, avg per athlete
///   2. Average progression — mean XP, level, streak across group athletes
///   3. Internal ranking — all athletes sorted by distance, with runs & avg pace
///
/// Data sources: coaching_members, sessions, v_user_progression (all RLS-safe).
/// No monetary values. No prohibited terms. Complies with GAMIFICATION_POLICY §5.
class StaffWeeklyReportScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const StaffWeeklyReportScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<StaffWeeklyReportScreen> createState() =>
      _StaffWeeklyReportScreenState();
}

class _StaffWeeklyReportScreenState extends State<StaffWeeklyReportScreen> {
  bool _loading = true;
  String? _error;

  late DateTime _weekStart;

  int _totalRuns = 0;
  double _totalDistanceKm = 0;
  int _activeAthletes = 0;
  int _totalAthletes = 0;
  double _avgRunsPerAthlete = 0;
  double _avgDistancePerAthlete = 0;

  double _avgXp = 0;
  double _avgLevel = 0;
  double _avgStreak = 0;

  List<_RankedAthlete> _ranking = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _weekStart = _mondayOf(now);
    _load();
  }

  static DateTime _mondayOf(DateTime d) {
    final shifted = d.subtract(Duration(days: d.weekday - 1));
    return DateTime.utc(shifted.year, shifted.month, shifted.day);
  }

  void _prevWeek() {
    setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
    _load();
  }

  void _nextWeek() {
    final next = _weekStart.add(const Duration(days: 7));
    if (!next.isAfter(DateTime.now().toUtc())) {
      setState(() => _weekStart = next);
      _load();
    }
  }

  bool get _canGoNext =>
      !_weekStart.add(const Duration(days: 7)).isAfter(DateTime.now().toUtc());

  String get _weekLabel {
    final end = _weekStart.add(const Duration(days: 6));
    return '${_fmt(_weekStart)} — ${_fmt(end)}';
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = Supabase.instance.client;

      // 1. Group athletes
      final membersRes = await db
          .from('coaching_members')
          .select('user_id, display_name')
          .eq('group_id', widget.groupId)
          .eq('role', 'atleta');

      final athletes = (membersRes as List).cast<Map<String, dynamic>>();
      _totalAthletes = athletes.length;

      if (athletes.isEmpty) {
        _setEmpty();
        return;
      }

      final athleteIds = athletes.map((m) => m['user_id'] as String).toList();
      final nameMap = <String, String>{
        for (final m in athletes)
          m['user_id'] as String: (m['display_name'] as String?) ?? 'Atleta',
      };

      final weekStartMs = _weekStart.millisecondsSinceEpoch;
      final weekEndMs =
          _weekStart.add(const Duration(days: 7)).millisecondsSinceEpoch;

      // 2. Sessions in the selected week
      final sessionsRes = await db
          .from('sessions')
          .select('user_id, total_distance_m, moving_ms, avg_pace_sec_km')
          .inFilter('user_id', athleteIds)
          .eq('status', 3)
          .gte('start_time_ms', weekStartMs)
          .lt('start_time_ms', weekEndMs)
          .eq('is_verified', true)
          .gte('total_distance_m', 1000);

      final sessions = (sessionsRes as List).cast<Map<String, dynamic>>();

      _totalRuns = sessions.length;
      _totalDistanceKm = sessions.fold<double>(
              0, (s, r) => s + ((r['total_distance_m'] as num?)?.toDouble() ?? 0)) /
          1000;

      // Per-athlete aggregation
      final perAthlete = <String, _AthleteStat>{};
      for (final s in sessions) {
        final uid = s['user_id'] as String;
        final stat = perAthlete.putIfAbsent(uid, _AthleteStat.new);
        stat.runs++;
        stat.distanceM += (s['total_distance_m'] as num?)?.toDouble() ?? 0;
        stat.movingMs += (s['moving_ms'] as num?)?.toInt() ?? 0;
        final pace = (s['avg_pace_sec_km'] as num?)?.toDouble();
        if (pace != null && pace > 0) {
          stat.paceSum += pace;
          stat.paceCount++;
        }
      }

      _activeAthletes = perAthlete.length;
      _avgRunsPerAthlete =
          _totalAthletes > 0 ? _totalRuns / _totalAthletes : 0;
      _avgDistancePerAthlete =
          _totalAthletes > 0 ? _totalDistanceKm / _totalAthletes : 0;

      // Build ranking (sorted by distance desc)
      _ranking = athleteIds.map((uid) {
        final stat = perAthlete[uid];
        return _RankedAthlete(
          name: nameMap[uid] ?? 'Atleta',
          runs: stat?.runs ?? 0,
          distanceKm: (stat?.distanceM ?? 0) / 1000,
          avgPaceSecKm: stat != null && stat.paceCount > 0
              ? stat.paceSum / stat.paceCount
              : null,
        );
      }).toList()
        ..sort((a, b) => b.distanceKm.compareTo(a.distanceKm));

      // 3. Average progression (XP, level, streak)
      final progRes = await db
          .from('v_user_progression')
          .select('user_id, total_xp, level, streak_current')
          .inFilter('user_id', athleteIds);

      final progs = (progRes as List).cast<Map<String, dynamic>>();
      if (progs.isNotEmpty) {
        double xpSum = 0, lvlSum = 0, streakSum = 0;
        for (final p in progs) {
          xpSum += (p['total_xp'] as num?)?.toDouble() ?? 0;
          lvlSum += (p['level'] as num?)?.toDouble() ?? 0;
          streakSum += (p['streak_current'] as num?)?.toDouble() ?? 0;
        }
        _avgXp = xpSum / progs.length;
        _avgLevel = lvlSum / progs.length;
        _avgStreak = streakSum / progs.length;
      } else {
        _avgXp = 0;
        _avgLevel = 0;
        _avgStreak = 0;
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível gerar o relatório.';
          _loading = false;
        });
      }
    }
  }

  void _setEmpty() {
    if (mounted) {
      setState(() {
        _totalRuns = 0;
        _totalDistanceKm = 0;
        _activeAthletes = 0;
        _avgRunsPerAthlete = 0;
        _avgDistancePerAthlete = 0;
        _avgXp = 0;
        _avgLevel = 0;
        _avgStreak = 0;
        _ranking = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Relatório semanal')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Week navigator
                      _WeekNav(
                        label: _weekLabel,
                        onPrev: _prevWeek,
                        onNext: _canGoNext ? _nextWeek : null,
                      ),
                      const SizedBox(height: 16),

                      // Section 1 — Summary
                      Text('Resumo da semana',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _SummaryCard(
                        totalRuns: _totalRuns,
                        totalDistanceKm: _totalDistanceKm,
                        activeAthletes: _activeAthletes,
                        totalAthletes: _totalAthletes,
                        avgRuns: _avgRunsPerAthlete,
                        avgDistanceKm: _avgDistancePerAthlete,
                      ),
                      const SizedBox(height: 24),

                      // Section 2 — Average progression
                      Text('Progresso médio dos atletas',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _ProgressionCard(
                        avgXp: _avgXp,
                        avgLevel: _avgLevel,
                        avgStreak: _avgStreak,
                      ),
                      const SizedBox(height: 24),

                      // Section 3 — Internal ranking
                      Text('Ranking interno',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_ranking.isEmpty ||
                          _ranking.every((a) => a.runs == 0))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Nenhuma corrida registrada nesta semana.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._ranking
                            .where((a) => a.runs > 0)
                            .toList()
                            .asMap()
                            .entries
                            .map((e) => _RankingTile(
                                rank: e.key + 1, athlete: e.value)),
                    ],
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

class _AthleteStat {
  int runs = 0;
  double distanceM = 0;
  int movingMs = 0;
  double paceSum = 0;
  int paceCount = 0;
}

class _RankedAthlete {
  final String name;
  final int runs;
  final double distanceKm;
  final double? avgPaceSecKm;

  const _RankedAthlete({
    required this.name,
    required this.runs,
    required this.distanceKm,
    this.avgPaceSecKm,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Week navigator
// ═══════════════════════════════════════════════════════════════════════════

class _WeekNav extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _WeekNav({
    required this.label,
    required this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: Icon(
            Icons.chevron_right_rounded,
            color: onNext != null ? null : theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Summary card
// ═══════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final int totalRuns;
  final double totalDistanceKm;
  final int activeAthletes;
  final int totalAthletes;
  final double avgRuns;
  final double avgDistanceKm;

  const _SummaryCard({
    required this.totalRuns,
    required this.totalDistanceKm,
    required this.activeAthletes,
    required this.totalAthletes,
    required this.avgRuns,
    required this.avgDistanceKm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Corridas',
                  value: '$totalRuns',
                  icon: Icons.route_rounded,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'Distância total',
                  value: '${totalDistanceKm.toStringAsFixed(1)} km',
                  icon: Icons.straighten_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Atletas ativos',
                  value: '$activeAthletes / $totalAthletes',
                  icon: Icons.directions_run_rounded,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'Média por atleta',
                  value:
                      '${avgRuns.toStringAsFixed(1)} corridas · ${avgDistanceKm.toStringAsFixed(1)} km',
                  icon: Icons.person_outline_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Progression card
// ═══════════════════════════════════════════════════════════════════════════

class _ProgressionCard extends StatelessWidget {
  final double avgXp;
  final double avgLevel;
  final double avgStreak;

  const _ProgressionCard({
    required this.avgXp,
    required this.avgLevel,
    required this.avgStreak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ProgStat(
            label: 'XP médio',
            value: avgXp.toStringAsFixed(0),
            icon: Icons.star_rounded,
            color: Colors.amber.shade700,
          ),
          Container(width: 1, height: 40, color: Colors.deepPurple.shade100),
          _ProgStat(
            label: 'Nível médio',
            value: avgLevel.toStringAsFixed(1),
            icon: Icons.trending_up_rounded,
            color: Colors.deepPurple,
          ),
          Container(width: 1, height: 40, color: Colors.deepPurple.shade100),
          _ProgStat(
            label: 'Sequência média',
            value: '${avgStreak.toStringAsFixed(1)} dias',
            icon: Icons.local_fire_department_rounded,
            color: Colors.deepOrange,
          ),
        ],
      ),
    );
  }
}

class _ProgStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ProgStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Ranking tile
// ═══════════════════════════════════════════════════════════════════════════

class _RankingTile extends StatelessWidget {
  final int rank;
  final _RankedAthlete athlete;

  const _RankingTile({required this.rank, required this.athlete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTop3 = rank <= 3;

    final paceText = athlete.avgPaceSecKm != null
        ? _formatPace(athlete.avgPaceSecKm!)
        : '—';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isTop3
            ? Colors.amber.shade100
            : theme.colorScheme.surfaceContainerHighest,
        child: Text(
          '$rank',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color:
                isTop3 ? Colors.amber.shade900 : theme.colorScheme.outline,
          ),
        ),
      ),
      title: Text(athlete.name),
      subtitle: Text(
        '${athlete.runs} ${athlete.runs == 1 ? 'corrida' : 'corridas'} · pace $paceText',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '${athlete.distanceKm.toStringAsFixed(1)} km',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  static String _formatPace(double secPerKm) {
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).round();
    return "$min'${sec.toString().padLeft(2, '0')}\"";
  }
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
