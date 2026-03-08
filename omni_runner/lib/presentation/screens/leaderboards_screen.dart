import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/domain/entities/leaderboard_entity.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_bloc.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_event.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_state.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  LeaderboardPeriod _period = LeaderboardPeriod.weekly;

  String? _coachingGroupId;
  String? _coachingGroupName;
  List<_ChampOption> _championships = const [];

  String? _selectedChampId;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    _loadUserContext();
  }

  Future<void> _loadUserContext() async {
    final uid = sl<UserIdentityProvider>().userId;
    final sb = sl<SupabaseClient>();

    try {
      final profileFuture = sb
          .from('profiles')
          .select('active_coaching_group_id')
          .eq('id', uid)
          .maybeSingle();

      final champsFuture = sb
          .from('championship_participants')
          .select('championship_id, championships!inner(id, name, status)')
          .eq('user_id', uid);

      final results = await Future.wait<dynamic>([profileFuture, champsFuture]);
      final profileRes = results[0];
      final champsRes = results[1];

      final groupId =
          (profileRes as Map<String, dynamic>?)?['active_coaching_group_id'] as String?;
      String? groupName;

      if (groupId != null) {
        final g = await sb
            .from('coaching_groups')
            .select('name')
            .eq('id', groupId)
            .maybeSingle();
        groupName = g?['name'] as String?;
      }

      final champsList =
          List<Map<String, dynamic>>.from((champsRes as List?) ?? []);
      final champs = champsList
          .where((Map<String, dynamic> row) {
            final c = row['championships'] as Map<String, dynamic>?;
            if (c == null) return false;
            final status = c['status'] as String?;
            return status == 'open' || status == 'active' || status == 'completed';
          })
          .map((Map<String, dynamic> row) {
            final c = row['championships'] as Map<String, dynamic>;
            return _ChampOption(
              id: c['id'] as String,
              name: c['name'] as String,
            );
          })
          .toList();

      if (mounted) {
        setState(() {
          _coachingGroupId = groupId;
          _coachingGroupName = groupName;
          _championships = champs;
          if (champs.isNotEmpty) _selectedChampId = champs.first.id;
        });
        _dispatchLoad();
      }
    } on Exception catch (e) {
      AppLogger.warn('Caught error', tag: 'LeaderboardsScreen', error: e);
      if (mounted) _dispatchLoad();
    }
  }

  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging) return;
    _dispatchLoad();
  }

  void _dispatchLoad() {
    final bloc = context.read<LeaderboardsBloc>();
    final scope = _scopeForTab(_tabCtrl.index);

    bloc.add(LoadLeaderboard(
      scope: scope,
      period: _period,
      groupId: scope == LeaderboardScope.assessoria ? _coachingGroupId : null,
      championshipId:
          scope == LeaderboardScope.championship ? _selectedChampId : null,
    ));
  }

  LeaderboardScope _scopeForTab(int index) => switch (index) {
        0 => LeaderboardScope.assessoria,
        1 => LeaderboardScope.championship,
        _ => LeaderboardScope.global,
      };

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.leaderboards),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Assessoria'),
            Tab(text: 'Campeonato'),
            Tab(text: 'Global'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<LeaderboardsBloc>().add(const RefreshLeaderboard()),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Tip banner ─────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingSm, DesignTokens.spacingMd, 0),
            child: TipBanner(
              tipKey: TipKey.rankingsHowTo,
              icon: Icons.lightbulb_outline_rounded,
              text: 'Sua pontuação é calculada pela distância percorrida '
                  '(1 pt por km) + vitórias em desafios (5 pts cada). '
                  'Corra mais e vença desafios para subir!',
            ),
          ),

          // ── Period filter ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingSm, DesignTokens.spacingMd, DesignTokens.spacingXs),
            child: Row(
              children: [
                _PeriodChip(
                  label: 'Semana',
                  selected: _period == LeaderboardPeriod.weekly,
                  onTap: () => _setPeriod(LeaderboardPeriod.weekly),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'Mês',
                  selected: _period == LeaderboardPeriod.monthly,
                  onTap: () => _setPeriod(LeaderboardPeriod.monthly),
                ),
                const Spacer(),
                // Championship picker (tab 1 only)
                if (_tabCtrl.index == 1 && _championships.isNotEmpty)
                  _ChampDropdown(
                    options: _championships,
                    selectedId: _selectedChampId,
                    onChanged: (id) {
                      setState(() => _selectedChampId = id);
                      _dispatchLoad();
                    },
                  ),
              ],
            ),
          ),

          // ── Content ────────────────────────────────────────────────
          Expanded(
            child: BlocBuilder<LeaderboardsBloc, LeaderboardsState>(
              builder: (context, state) => switch (state) {
                LeaderboardsInitial() => _buildEmptyForTab(theme),
                LeaderboardsLoading() =>
                  const ShimmerListLoader(),
                LeaderboardsLoaded(:final leaderboard) =>
                  leaderboard.entries.isEmpty
                      ? _buildEmptyForTab(theme)
                      : _LeaderboardList(
                          leaderboard: leaderboard,
                          currentUserId: sl<UserIdentityProvider>().userId,
                        ),
                LeaderboardsError(:final message) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(DesignTokens.spacingLg),
                      child: Text(message,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyForTab(ThemeData theme) {
    final scope = _scopeForTab(_tabCtrl.index);
    final (icon, title, subtitle) = switch (scope) {
      LeaderboardScope.assessoria when _coachingGroupId == null => (
          Icons.group_outlined,
          'Sem assessoria',
          'Entre em uma assessoria para ver o ranking do grupo.',
        ),
      LeaderboardScope.assessoria => (
          Icons.leaderboard_outlined,
          'Ranking vazio',
          '${_coachingGroupName ?? "Sua assessoria"} ainda não tem dados '
              'para este período.',
        ),
      LeaderboardScope.championship when _championships.isEmpty => (
          Icons.emoji_events_outlined,
          'Sem campeonatos',
          'Participe de um campeonato para ver o ranking.',
        ),
      LeaderboardScope.championship => (
          Icons.leaderboard_outlined,
          'Ranking vazio',
          'Este campeonato ainda não tem dados para este período.',
        ),
      _ => (
          Icons.leaderboard_outlined,
          'Ranking vazio',
          'Corra para aparecer no ranking!\n'
              'Apenas sessões verificadas contam.',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }

  void _setPeriod(LeaderboardPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _dispatchLoad();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Period chip
// ═════════════════════════════════════════════════════════════════════════════

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: cs.primaryContainer,
      showCheckmark: false,
      side: selected ? BorderSide.none : null,
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Championship dropdown
// ═════════════════════════════════════════════════════════════════════════════

class _ChampOption {
  final String id;
  final String name;
  const _ChampOption({required this.id, required this.name});
}

class _ChampDropdown extends StatelessWidget {
  final List<_ChampOption> options;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _ChampDropdown({
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: selectedId,
      underline: const SizedBox.shrink(),
      isDense: true,
      items: options
          .map((o) => DropdownMenuItem(
                value: o.id,
                child: Text(
                  o.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Leaderboard list
// ═════════════════════════════════════════════════════════════════════════════

class _LeaderboardList extends StatelessWidget {
  final LeaderboardEntity leaderboard;
  final String currentUserId;

  const _LeaderboardList({
    required this.leaderboard,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final entries = leaderboard.entries;
    final metric = leaderboard.metric;

    return ListView.builder(
      padding: const EdgeInsets.only(top: DesignTokens.spacingXs, bottom: DesignTokens.spacingLg),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return _ScoringExplanation(metric: metric);
        }
        return RepaintBoundary(
          child: _EntryTile(
            entry: entries[index],
            metric: metric,
            isCurrentUser: entries[index].userId == currentUserId,
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Entry tile
// ═════════════════════════════════════════════════════════════════════════════

class _EntryTile extends StatelessWidget {
  final LeaderboardEntryEntity entry;
  final LeaderboardMetric metric;
  final bool isCurrentUser;

  const _EntryTile({
    required this.entry,
    required this.metric,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isTop3 = entry.rank <= 3;

    final rankColor = switch (entry.rank) {
      1 => DesignTokens.warning,
      2 => DesignTokens.textMuted,
      3 => DesignTokens.warning,
      _ => cs.outline,
    };

    return Container(
      color: isCurrentUser ? cs.primaryContainer.withValues(alpha: 0.3) : null,
      child: ListTile(
        leading: SizedBox(
          width: 40,
          child: Center(
            child: isTop3
                ? Icon(Icons.emoji_events, color: rankColor, size: 28)
                : Text('${entry.rank}',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: rankColor)),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                entry.displayName,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight:
                      isCurrentUser ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            if (isCurrentUser) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Text('Você',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onPrimary, fontSize: 10)),
              ),
            ],
          ],
        ),
        subtitle: Text('Nível ${entry.level}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.outline)),
        trailing: Text(
          _formatValue(entry.value, metric),
          style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold, color: cs.primary),
        ),
      ),
    );
  }

  static String _formatValue(double value, LeaderboardMetric metric) =>
      switch (metric) {
        LeaderboardMetric.distance =>
          '${(value / 1000).toStringAsFixed(1)} km',
        LeaderboardMetric.sessions => '${value.toStringAsFixed(0)} corridas',
        LeaderboardMetric.movingTime =>
          '${(value / 3600000).toStringAsFixed(1)} h',
        LeaderboardMetric.avgPace => _formatPace(value),
        LeaderboardMetric.seasonXp => '${value.toStringAsFixed(0)} XP',
        LeaderboardMetric.composite => '${value.toStringAsFixed(0)} pts',
      };

  static String _formatPace(double secPerKm) {
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).toInt();
    return '$min:${sec.toString().padLeft(2, '0')}/km';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Scoring explanation
// ═════════════════════════════════════════════════════════════════════════════

class _ScoringExplanation extends StatelessWidget {
  final LeaderboardMetric metric;

  const _ScoringExplanation({required this.metric});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final explanation = switch (metric) {
      LeaderboardMetric.composite => 'Pontuação = km percorridos + vitórias em desafios (×5 pts cada)',
      LeaderboardMetric.distance => 'Classificação por distância total percorrida',
      LeaderboardMetric.sessions => 'Classificação por número de corridas verificadas',
      LeaderboardMetric.movingTime => 'Classificação por tempo total em movimento',
      LeaderboardMetric.avgPace => 'Classificação por melhor pace médio (menor é melhor)',
      LeaderboardMetric.seasonXp => 'Classificação por XP da temporada',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 12, DesignTokens.spacingMd, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              explanation,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }
}
