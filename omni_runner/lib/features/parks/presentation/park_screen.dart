import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/config/feature_flags.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/features/parks/domain/park_entity.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';

/// Main park hub — shows leaderboard, community, segments for a given park.
///
/// Tabs:
///   1. Ranking — multi-category leaderboard with tier recognition
///   2. Comunidade — who runs here, social run detection
///   3. Segmentos — park segments with records
class ParkScreen extends StatefulWidget {
  final ParkEntity park;
  const ParkScreen({super.key, required this.park});

  @override
  State<ParkScreen> createState() => _ParkScreenState();
}

class _ParkScreenState extends State<ParkScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;

  List<ParkLeaderboardEntry> _rankings = [];
  List<_ParkRunner> _community = [];
  List<ParkSegmentEntity> _segments = [];
  _ParkStats? _parkStats;
  String _currentUserId = '';
  ParkLeaderboardCategory _selectedCategory = ParkLeaderboardCategory.pace;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _currentUserId = sl<UserIdentityProvider>().userId;
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    try {
      if (AppConfig.isSupabaseReady) {
        await _ensureParkBackfill();

        await Future.wait([
          _loadRankings(),
          _loadCommunity(),
          _loadSegments(),
          _loadStats(),
        ]);
      } else {
        _rankings = [];
        _community = [];
        _segments = [];
        _parkStats = null;
      }

      if (mounted) setState(() => _loading = false);
    } on Exception {
      if (mounted) {
        setState(() {
          _rankings = [];
          _community = [];
          _segments = [];
          _parkStats = const _ParkStats(
              runnersToday: 0, runnersWeek: 0, totalActivities: 0);
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadRankings() async {
    try {
      final res = await Supabase.instance.client
          .from('park_leaderboard')
          .select()
          .eq('park_id', widget.park.id)
          .order('rank', ascending: true)
          .limit(50);

      _rankings = (res as List)
          .map((r) => ParkLeaderboardEntry(
                parkId: r['park_id'] as String,
                userId: r['user_id'] as String,
                displayName: r['display_name'] as String? ?? 'Atleta',
                category: ParkLeaderboardCategory.values.firstWhere(
                  (c) => c.name == r['category'],
                  orElse: () => ParkLeaderboardCategory.pace,
                ),
                rank: r['rank'] as int,
                tier: ParkLeaderboardEntry.tierFromRank(r['rank'] as int),
                value: (r['value'] as num).toDouble(),
                period: r['period'] as String? ?? '',
              ))
          .toList();
    } on Exception {
      _rankings = [];
    }
  }

  Future<void> _loadCommunity() async {
    try {
      final res = await Supabase.instance.client
          .from('park_activities')
          .select('user_id, display_name, start_time, distance_m')
          .eq('park_id', widget.park.id)
          .order('start_time', ascending: false)
          .limit(100);

      final seen = <String>{};
      _community = [];
      for (final r in res as List) {
        final uid = r['user_id'] as String;
        if (seen.contains(uid)) continue;
        seen.add(uid);
        _community.add(_ParkRunner(
          userId: uid,
          displayName: r['display_name'] as String? ?? 'Atleta',
          lastRunDate:
              DateTime.tryParse(r['start_time'] as String? ?? '') ??
                  DateTime.now(),
          totalRuns: 0,
        ));
      }
    } on Exception {
      _community = [];
    }
  }

  Future<void> _loadSegments() async {
    try {
      final res = await Supabase.instance.client
          .from('park_segments')
          .select()
          .eq('park_id', widget.park.id);

      _segments = (res as List)
          .map((r) => ParkSegmentEntity(
                id: r['id'] as String,
                parkId: r['park_id'] as String,
                name: r['name'] as String? ?? 'Segmento',
                path: const [],
                lengthM: (r['length_m'] as num?)?.toDouble() ?? 0,
                recordHolderName: r['record_holder_name'] as String?,
                recordPaceSecPerKm:
                    (r['record_pace_sec_per_km'] as num?)?.toDouble(),
              ))
          .toList();
    } on Exception {
      _segments = [];
    }
  }

  Future<void> _loadStats() async {
    try {
      final now = DateTime.now().toUtc();
      final todayStart =
          DateTime.utc(now.year, now.month, now.day).toIso8601String();
      final weekStart = DateTime.utc(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1))
          .toIso8601String();

      final todayCount = await Supabase.instance.client
          .from('park_activities')
          .select('id')
          .eq('park_id', widget.park.id)
          .gte('start_time', todayStart);

      final weekCount = await Supabase.instance.client
          .from('park_activities')
          .select('id')
          .eq('park_id', widget.park.id)
          .gte('start_time', weekStart);

      _parkStats = _ParkStats(
        runnersToday: (todayCount as List).length,
        runnersWeek: (weekCount as List).length,
        totalActivities: 0,
      );
    } on Exception {
      _parkStats = const _ParkStats(
          runnersToday: 0, runnersWeek: 0, totalActivities: 0);
    }
  }

  Future<void> _ensureParkBackfill() async {
    try {
      final controller = sl<StravaConnectController>();
      final connected = await controller.isConnected;
      if (!connected) return;

      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      await controller.importStravaHistory(count: 30);
      await Supabase.instance.client
          .rpc('backfill_strava_sessions', params: {'p_user_id': uid});
      await Supabase.instance.client
          .rpc('backfill_park_activities', params: {'p_user_id': uid});
    } catch (e) {
      AppLogger.warn('Park backfill skipped: $e', tag: 'ParkScreen');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.park.name),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.leaderboard), text: 'Ranking'),
            Tab(icon: Icon(Icons.people), text: 'Comunidade'),
            Tab(icon: Icon(Icons.route), text: 'Segmentos'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
                  children: [
                    // Park stats header
                    _ParkStatsHeader(
                      park: widget.park,
                      stats: _parkStats,
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _buildRankingTab(theme, cs),
                          _buildCommunityTab(theme, cs),
                          _buildSegmentsTab(theme, cs),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  // ── Ranking Tab ────────────────────────────────────────────────────────────

  Widget _buildRankingTab(ThemeData theme, ColorScheme cs) {
    final filtered = _rankings
        .where((r) => r.category == _selectedCategory)
        .toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));

    return Column(
      children: [
        // Category selector
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ParkLeaderboardCategory.values.map((cat) {
                final selected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(_categoryLabel(cat)),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = cat),
                    avatar: Icon(_categoryIcon(cat), size: 16),
                    showCheckmark: false,
                    selectedColor: cs.primaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Tier legend
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const _TierBadge(tier: ParkLeaderboardTier.rei, compact: true),
              const SizedBox(width: 4),
              const _TierBadge(tier: ParkLeaderboardTier.elite, compact: true),
              const SizedBox(width: 4),
              const _TierBadge(tier: ParkLeaderboardTier.destaque, compact: true),
              const SizedBox(width: 4),
              const _TierBadge(tier: ParkLeaderboardTier.pelotao, compact: true),
              const Spacer(),
              Text(
                '${filtered.length} atletas',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events_outlined,
                          size: 48, color: cs.outline),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhum ranking ainda nesta categoria',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Corra neste parque para aparecer!',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _RankingTile(
                    entry: filtered[i],
                    category: _selectedCategory,
                    isCurrentUser: filtered[i].userId == _currentUserId,
                  ),
                ),
        ),
      ],
    );
  }

  // ── Community Tab ──────────────────────────────────────────────────────────

  Widget _buildCommunityTab(ThemeData theme, ColorScheme cs) {
    if (_community.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text('Ninguém por aqui ainda',
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: cs.outline)),
          ],
        ),
      );
    }

    // Detect social runs (overlapping times)
    final socialRuns = _detectSocialRuns();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (socialRuns.isNotEmpty) ...[
          _SocialRunsCard(socialRuns: socialRuns),
          const SizedBox(height: 12),
        ],

        Text(
          'Quem corre aqui',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        ...List.generate(_community.length, (i) {
          final runner = _community[i];
          final isMe = runner.userId == _currentUserId;
          return _RunnerTile(runner: runner, isMe: isMe);
        }),
      ],
    );
  }

  List<String> _detectSocialRuns() {
    // Placeholder: in production, the backend detects overlapping runs
    // and returns pairs of users. For now, show a hint.
    return [];
  }

  // ── Segments Tab ───────────────────────────────────────────────────────────

  Widget _buildSegmentsTab(ThemeData theme, ColorScheme cs) {
    final segmentsEnabled = sl<FeatureFlagService>().isEnabled('park_segments_enabled');
    if (_segments.isEmpty || !segmentsEnabled) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text('Nenhum segmento definido',
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: cs.outline)),
            const SizedBox(height: 4),
            Text(
              'Segmentos populares serão habilitados em breve.\n'
              'Acompanhe as novidades no app!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _segments.length,
      itemBuilder: (_, i) => _SegmentTile(segment: _segments[i]),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _categoryLabel(ParkLeaderboardCategory c) => switch (c) {
        ParkLeaderboardCategory.pace => 'Pace',
        ParkLeaderboardCategory.distance => 'Distância',
        ParkLeaderboardCategory.frequency => 'Frequência',
        ParkLeaderboardCategory.streak => 'Sequência',
        ParkLeaderboardCategory.evolution => 'Evolução',
        ParkLeaderboardCategory.longestRun => 'Maior corrida',
      };

  static IconData _categoryIcon(ParkLeaderboardCategory c) => switch (c) {
        ParkLeaderboardCategory.pace => Icons.speed,
        ParkLeaderboardCategory.distance => Icons.straighten,
        ParkLeaderboardCategory.frequency => Icons.calendar_today,
        ParkLeaderboardCategory.streak => Icons.local_fire_department,
        ParkLeaderboardCategory.evolution => Icons.trending_up,
        ParkLeaderboardCategory.longestRun => Icons.timer,
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// Park Stats Header
// ═══════════════════════════════════════════════════════════════════════════════

class _ParkStatsHeader extends StatelessWidget {
  final ParkEntity park;
  final _ParkStats? stats;

  const _ParkStatsHeader({required this.park, this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.park, color: cs.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${park.city}, ${park.state}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                if (stats != null)
                  Row(
                    children: [
                      _MiniStat(
                        icon: Icons.directions_run,
                        label: '${stats!.runnersToday} hoje',
                      ),
                      const SizedBox(width: 16),
                      _MiniStat(
                        icon: Icons.calendar_today,
                        label: '${stats!.runnersWeek} na semana',
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Ranking Tile
// ═══════════════════════════════════════════════════════════════════════════════

class _RankingTile extends StatelessWidget {
  final ParkLeaderboardEntry entry;
  final ParkLeaderboardCategory category;
  final bool isCurrentUser;

  const _RankingTile({
    required this.entry,
    required this.category,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tierColor = _tierColor(entry.tier);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : null,
        borderRadius: BorderRadius.circular(12),
        border: isCurrentUser
            ? Border.all(color: cs.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 44,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '#${entry.rank}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: tierColor,
                  ),
                ),
              ),
              _TierBadge(tier: entry.tier, compact: true),
            ],
          ),
        ),
        title: Text(
          isCurrentUser ? '${entry.displayName} (você)' : entry.displayName,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        trailing: Text(
          _formatValue(entry.value, category),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: tierColor,
          ),
        ),
      ),
    );
  }

  static String _formatValue(double v, ParkLeaderboardCategory cat) =>
      switch (cat) {
        ParkLeaderboardCategory.pace =>
          '${(v ~/ 60)}:${(v % 60).round().toString().padLeft(2, '0')}/km',
        ParkLeaderboardCategory.distance =>
          '${(v / 1000).toStringAsFixed(1)}km',
        ParkLeaderboardCategory.frequency => '${v.round()}x',
        ParkLeaderboardCategory.streak => '${v.round()} dias',
        ParkLeaderboardCategory.evolution =>
          '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}%',
        ParkLeaderboardCategory.longestRun =>
          '${(v / 1000).toStringAsFixed(1)}km',
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tier Badge
// ═══════════════════════════════════════════════════════════════════════════════

class _TierBadge extends StatelessWidget {
  final ParkLeaderboardTier tier;
  final bool compact;

  const _TierBadge({required this.tier, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final emoji = _tierEmoji(tier);
    final label = _tierLabel(tier);
    final color = _tierColor(tier);

    if (compact) {
      return Tooltip(
        message: label,
        child: Text(emoji, style: const TextStyle(fontSize: 14)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

String _tierEmoji(ParkLeaderboardTier t) => switch (t) {
      ParkLeaderboardTier.rei => '👑',
      ParkLeaderboardTier.elite => '⭐',
      ParkLeaderboardTier.destaque => '🏅',
      ParkLeaderboardTier.pelotao => '🎯',
      ParkLeaderboardTier.frequentador => '🏃',
    };

String _tierLabel(ParkLeaderboardTier t) => switch (t) {
      ParkLeaderboardTier.rei => 'Rei do Parque',
      ParkLeaderboardTier.elite => 'Elite',
      ParkLeaderboardTier.destaque => 'Destaque',
      ParkLeaderboardTier.pelotao => 'Pelotão',
      ParkLeaderboardTier.frequentador => 'Frequentador',
    };

Color _tierColor(ParkLeaderboardTier t) => switch (t) {
      ParkLeaderboardTier.rei => const Color(0xFFFFD700),
      ParkLeaderboardTier.elite => Colors.orange.shade700,
      ParkLeaderboardTier.destaque => Colors.blue.shade700,
      ParkLeaderboardTier.pelotao => Colors.teal.shade600,
      ParkLeaderboardTier.frequentador => Colors.grey.shade600,
    };

// ═══════════════════════════════════════════════════════════════════════════════
// Social Runs Detection Card
// ═══════════════════════════════════════════════════════════════════════════════

class _SocialRunsCard extends StatelessWidget {
  final List<String> socialRuns;
  const _SocialRunsCard({required this.socialRuns});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups, size: 20, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              Text(
                'Corridas sociais detectadas!',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Parece que você e outros atletas correram '
            'aqui no mesmo horário. Quer adicionar como amigos?',
            style: TextStyle(fontSize: 12, color: Colors.purple.shade600),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Runner Tile (Community)
// ═══════════════════════════════════════════════════════════════════════════════

class _RunnerTile extends StatelessWidget {
  final _ParkRunner runner;
  final bool isMe;

  const _RunnerTile({required this.runner, this.isMe = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final daysAgo = DateTime.now().difference(runner.lastRunDate).inDays;
    final recency = daysAgo == 0
        ? 'Hoje'
        : daysAgo == 1
            ? 'Ontem'
            : '$daysAgo dias atrás';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: isMe ? cs.primaryContainer : cs.surfaceContainerHighest,
        child: Icon(Icons.person,
            color: isMe ? cs.primary : cs.onSurfaceVariant, size: 20),
      ),
      title: Text(
        isMe ? '${runner.displayName} (você)' : runner.displayName,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isMe ? FontWeight.bold : null,
        ),
      ),
      subtitle: Text('Última corrida: $recency'),
      trailing: null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Segment Tile
// ═══════════════════════════════════════════════════════════════════════════════

class _SegmentTile extends StatelessWidget {
  final ParkSegmentEntity segment;
  const _SegmentTile({required this.segment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final distLabel = segment.lengthM >= 1000
        ? '${(segment.lengthM / 1000).toStringAsFixed(1)} km'
        : '${segment.lengthM.round()} m';

    String? recordLabel;
    if (segment.recordPaceSecPerKm != null) {
      final m = segment.recordPaceSecPerKm! ~/ 60;
      final s = (segment.recordPaceSecPerKm! % 60).round();
      recordLabel = '$m:${s.toString().padLeft(2, '0')}/km';
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.route, color: cs.primary, size: 22),
        ),
        title: Text(segment.name,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(distLabel),
        trailing: recordLabel != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(recordLabel,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800)),
                  if (segment.recordHolderName != null)
                    Text(segment.recordHolderName!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              )
            : Text('Sem recorde',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════════════════════════

class _ParkStats {
  final int runnersToday;
  final int runnersWeek;
  final int totalActivities;

  const _ParkStats({
    required this.runnersToday,
    required this.runnersWeek,
    required this.totalActivities,
  });
}

class _ParkRunner {
  final String userId;
  final String displayName;
  final DateTime lastRunDate;
  final int totalRuns;

  const _ParkRunner({
    required this.userId,
    required this.displayName,
    required this.lastRunDate,
    required this.totalRuns,
  });
}
