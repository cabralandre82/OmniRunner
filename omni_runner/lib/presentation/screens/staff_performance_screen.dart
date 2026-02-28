import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/presentation/screens/staff_retention_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/staff_weekly_report_screen.dart';

/// Assessoria performance dashboard — 4 KPIs + drill-down.
///
/// Data sources (Supabase, RLS-safe — caller is staff of the group):
///   • coaching_members   → active athletes
///   • sessions           → weekly runs (via user_ids in group)
///   • challenges / challenge_participants → challenges involving group members
///   • championship_participants → championship participation
///
/// No monetary values. No prohibited terms. Complies with GAMIFICATION_POLICY §5.
class StaffPerformanceScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const StaffPerformanceScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<StaffPerformanceScreen> createState() => _StaffPerformanceScreenState();
}

class _StaffPerformanceScreenState extends State<StaffPerformanceScreen> {
  bool _loading = true;
  String? _error;

  int _activeAthletes = 0;
  int _totalMembers = 0;
  int _weeklyRuns = 0;
  double _weeklyDistanceKm = 0;
  int _prevWeekRuns = 0;
  double _prevWeekDistanceKm = 0;
  int _challengesDone = 0;
  int _challengesWon = 0;
  int _champParticipants = 0;
  int _champCompleted = 0;

  List<_AthleteActivity> _topAthletes = [];

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

      // 1. Members of the group (athletes only)
      final membersRes = await db
          .from('coaching_members')
          .select('user_id, display_name, role')
          .eq('group_id', widget.groupId);

      final members = (membersRes as List).cast<Map<String, dynamic>>();
      final athletes = members
          .where((m) => m['role'] == 'atleta')
          .toList();
      final athleteIds =
          athletes.map((m) => m['user_id'] as String).toList();

      _totalMembers = athletes.length;

      if (athleteIds.isEmpty) {
        _setEmpty();
        return;
      }

      // Week boundary (Monday 00:00 UTC of current ISO week)
      final now = DateTime.now().toUtc();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final weekStart =
          DateTime.utc(monday.year, monday.month, monday.day);
      final weekStartMs = weekStart.millisecondsSinceEpoch;

      // 2. Sessions this week for group athletes
      try {
        final sessionsRes = await db
            .from('sessions')
            .select('user_id, total_distance_m, is_verified')
            .inFilter('user_id', athleteIds)
            .eq('status', 3)
            .gte('start_time_ms', weekStartMs)
            .eq('is_verified', true)
            .gte('total_distance_m', 1000);

        final sessions = (sessionsRes as List).cast<Map<String, dynamic>>();
        _weeklyRuns = sessions.length;
        _weeklyDistanceKm = sessions.fold<double>(
            0,
            (sum, s) =>
                sum + ((s['total_distance_m'] as num?)?.toDouble() ?? 0)) /
            1000;

        final activeIds = sessions
            .map((s) => s['user_id'] as String)
            .toSet();
        _activeAthletes = activeIds.length;

        final runCounts = <String, int>{};
        final distanceSums = <String, double>{};
        for (final s in sessions) {
          final uid = s['user_id'] as String;
          runCounts[uid] = (runCounts[uid] ?? 0) + 1;
          distanceSums[uid] = (distanceSums[uid] ?? 0) +
              ((s['total_distance_m'] as num?)?.toDouble() ?? 0);
        }

        final nameMap = <String, String>{};
        for (final m in athletes) {
          nameMap[m['user_id'] as String] =
              (m['display_name'] as String?) ?? 'Atleta';
        }

        final sorted = runCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        _topAthletes = sorted.take(5).map((e) {
          return _AthleteActivity(
            name: nameMap[e.key] ?? 'Atleta',
            runs: e.value,
            distanceKm: (distanceSums[e.key] ?? 0) / 1000,
          );
        }).toList();
        // Previous week comparison
        final prevWeekStart = weekStart.subtract(const Duration(days: 7));
        final prevWeekStartMs = prevWeekStart.millisecondsSinceEpoch;
        try {
          final prevRes = await db
              .from('sessions')
              .select('total_distance_m')
              .inFilter('user_id', athleteIds)
              .eq('status', 3)
              .gte('start_time_ms', prevWeekStartMs)
              .lt('start_time_ms', weekStartMs)
              .eq('is_verified', true)
              .gte('total_distance_m', 1000);

          final prev = (prevRes as List).cast<Map<String, dynamic>>();
          _prevWeekRuns = prev.length;
          _prevWeekDistanceKm = prev.fold<double>(
              0,
              (sum, s) =>
                  sum +
                  ((s['total_distance_m'] as num?)?.toDouble() ?? 0)) /
              1000;
        } catch (_) {}
      } catch (e) {
        AppLogger.warn('Performance: sessions query failed: $e', tag: 'StaffPerf');
      }

      // 3. Challenges completed involving group athletes
      try {
        final challRes = await db
            .from('challenge_participants')
            .select('user_id, challenge_id, status')
            .inFilter('user_id', athleteIds);

        final challParts = (challRes as List).cast<Map<String, dynamic>>();
        final completedChallIds = <String>{};
        for (final cp in challParts) {
          if (cp['status'] == 'accepted' || cp['status'] == 'invited') {
            completedChallIds.add(cp['challenge_id'] as String);
          }
        }
        _challengesDone = completedChallIds.length;

        if (completedChallIds.isNotEmpty) {
          try {
            final resultsRes = await db
                .from('challenge_results')
                .select('challenge_id, winner_user_id')
                .inFilter('challenge_id', completedChallIds.toList());
            final results = (resultsRes as List).cast<Map<String, dynamic>>();
            _challengesWon = results
                .where((r) => athleteIds.contains(r['winner_user_id']))
                .length;
          } catch (_) {
            _challengesWon = 0;
          }
        }
      } catch (e) {
        AppLogger.warn('Performance: challenges query failed: $e', tag: 'StaffPerf');
      }

      // 4. Championship participation
      try {
        final champRes = await db
            .from('championship_participants')
            .select('user_id, status')
            .inFilter('user_id', athleteIds);

        final champParts = (champRes as List).cast<Map<String, dynamic>>();
        _champParticipants = champParts.length;
        _champCompleted = champParts
            .where((c) => c['status'] == 'completed')
            .length;
      } catch (e) {
        AppLogger.warn('Performance: championships query failed: $e', tag: 'StaffPerf');
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      AppLogger.error('Performance: load failed: $e', tag: 'StaffPerf', error: e);
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar os dados.';
          _loading = false;
        });
      }
    }
  }

  void _setEmpty() {
    if (mounted) {
      setState(() {
        _activeAthletes = 0;
        _weeklyRuns = 0;
        _weeklyDistanceKm = 0;
        _challengesDone = 0;
        _challengesWon = 0;
        _champParticipants = 0;
        _champCompleted = 0;
        _topAthletes = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance'),
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
                      _SectionTitle(widget.groupName),
                      const SizedBox(height: 12),
                      _KpiGrid(
                        activeAthletes: _activeAthletes,
                        totalMembers: _totalMembers,
                        weeklyRuns: _weeklyRuns,
                        weeklyDistanceKm: _weeklyDistanceKm,
                        prevWeekRuns: _prevWeekRuns,
                        prevWeekDistanceKm: _prevWeekDistanceKm,
                        challengesDone: _challengesDone,
                        challengesWon: _challengesWon,
                        champParticipants: _champParticipants,
                        champCompleted: _champCompleted,
                      ),
                      const SizedBox(height: 24),
                      _TopAthletesSection(athletes: _topAthletes),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context)
                                    .push(MaterialPageRoute<void>(
                                  builder: (_) => StaffWeeklyReportScreen(
                                    groupId: widget.groupId,
                                    groupName: widget.groupName,
                                  ),
                                ));
                              },
                              icon: const Icon(
                                  Icons.summarize_rounded, size: 18),
                              label:
                                  const Text('Relatório'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context)
                                    .push(MaterialPageRoute<void>(
                                  builder: (_) =>
                                      StaffRetentionDashboardScreen(
                                    groupId: widget.groupId,
                                    groupName: widget.groupName,
                                  ),
                                ));
                              },
                              icon: const Icon(
                                  Icons.show_chart_rounded, size: 18),
                              label: const Text('Retenção'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section title
// ═══════════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String groupName;
  const _SectionTitle(this.groupName);

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
          'Visão geral da semana',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KPI grid — 4 metric cards
// ═══════════════════════════════════════════════════════════════════════════

class _KpiGrid extends StatelessWidget {
  final int activeAthletes;
  final int totalMembers;
  final int weeklyRuns;
  final double weeklyDistanceKm;
  final int prevWeekRuns;
  final double prevWeekDistanceKm;
  final int challengesDone;
  final int challengesWon;
  final int champParticipants;
  final int champCompleted;

  const _KpiGrid({
    required this.activeAthletes,
    required this.totalMembers,
    required this.weeklyRuns,
    required this.weeklyDistanceKm,
    required this.prevWeekRuns,
    required this.prevWeekDistanceKm,
    required this.challengesDone,
    required this.challengesWon,
    required this.champParticipants,
    required this.champCompleted,
  });

  static String? _trendLabel(int current, int previous) {
    if (previous == 0) return null;
    final diff = current - previous;
    final pct = ((diff / previous) * 100).round();
    if (pct == 0) return '= sem. anterior';
    final sign = pct > 0 ? '+' : '';
    return '$sign$pct% vs sem. anterior';
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _KpiCard(
          icon: Icons.directions_run_rounded,
          title: 'Atletas ativos',
          value: '$activeAthletes',
          subtitle: 'de $totalMembers ${totalMembers == 1 ? 'atleta' : 'atletas'}',
          color: Colors.blue,
        ),
        _KpiCard(
          icon: Icons.route_rounded,
          title: 'Corridas na semana',
          value: '$weeklyRuns',
          subtitle: '${weeklyDistanceKm.toStringAsFixed(1)} km totais',
          color: Colors.green,
          trend: prevWeekRuns > 0
              ? _trendLabel(weeklyRuns, prevWeekRuns)
              : null,
          trendUp: weeklyRuns >= prevWeekRuns,
        ),
        _KpiCard(
          icon: Icons.flash_on_rounded,
          title: 'Desafios',
          value: '$challengesDone',
          subtitle: '$challengesWon ${challengesWon == 1 ? 'vitória' : 'vitórias'}',
          color: Colors.deepPurple,
        ),
        _KpiCard(
          icon: Icons.emoji_events_rounded,
          title: 'Campeonatos',
          value: '$champParticipants',
          subtitle: '$champCompleted ${champCompleted == 1 ? 'concluído' : 'concluídos'}',
          color: Colors.amber.shade800,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final String? trend;
  final bool trendUp;

  const _KpiCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    this.trend,
    this.trendUp = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (trend != null) ...[
            const SizedBox(height: 4),
            Text(
              trend!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: trendUp ? Colors.green.shade700 : Colors.red.shade700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Top athletes — weekly leaderboard
// ═══════════════════════════════════════════════════════════════════════════

class _TopAthletesSection extends StatelessWidget {
  final List<_AthleteActivity> athletes;

  const _TopAthletesSection({required this.athletes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Destaques da semana', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (athletes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_run_outlined,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhuma corrida registrada esta semana',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Incentive seus atletas a começar!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...athletes.asMap().entries.map((e) =>
              _AthleteActivityTile(rank: e.key + 1, activity: e.value)),
      ],
    );
  }
}

class _AthleteActivity {
  final String name;
  final int runs;
  final double distanceKm;

  const _AthleteActivity({
    required this.name,
    required this.runs,
    required this.distanceKm,
  });
}

class _AthleteActivityTile extends StatelessWidget {
  final int rank;
  final _AthleteActivity activity;

  const _AthleteActivityTile({
    required this.rank,
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTop3 = rank <= 3;

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
            color: isTop3 ? Colors.amber.shade900 : theme.colorScheme.outline,
          ),
        ),
      ),
      title: Text(activity.name),
      subtitle: Text(
        '${activity.distanceKm.toStringAsFixed(1)} km',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '${activity.runs} ${activity.runs == 1 ? 'corrida' : 'corridas'}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
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
