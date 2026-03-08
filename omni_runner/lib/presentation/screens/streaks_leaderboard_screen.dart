import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Shows who's on a streak and a consistency ranking for the user's assessoria.
///
/// Two sections:
///   1. "Em sequência agora" — athletes with streak_current ≥ 1, sorted desc
///   2. "Ranking de consistência" — all athletes sorted by streak_best desc
///
/// Data: coaching_members (group athletes) + v_user_progression (streak data).
/// Falls back gracefully when athlete has no assessoria.
///
/// No monetary values. No prohibited terms. Complies with GAMIFICATION_POLICY §5.
class StreaksLeaderboardScreen extends StatefulWidget {
  const StreaksLeaderboardScreen({super.key});

  @override
  State<StreaksLeaderboardScreen> createState() =>
      _StreaksLeaderboardScreenState();
}

class _StreaksLeaderboardScreenState extends State<StreaksLeaderboardScreen> {
  bool _loading = true;
  String? _error;
  String _groupName = '';
  String _currentUserId = '';

  List<_StreakEntry> _activeStreaks = [];
  List<_StreakEntry> _consistencyRanking = [];

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
      final db = sl<SupabaseClient>();
      final uid = sl<UserIdentityProvider>().userId;
      _currentUserId = uid;

      // Find the user's active group
      final profileRow = await db
          .from('profiles')
          .select('active_coaching_group_id')
          .eq('id', uid)
          .maybeSingle();

      final groupId = profileRow?['active_coaching_group_id'] as String?;

      if (groupId == null || groupId.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'no_group';
            _loading = false;
          });
        }
        return;
      }

      // Group name
      final groupRow = await db
          .from('coaching_groups')
          .select('name')
          .eq('id', groupId)
          .maybeSingle();

      _groupName = (groupRow?['name'] as String?) ?? 'Assessoria';

      // Group athletes
      final membersRes = await db
          .from('coaching_members')
          .select('user_id')
          .eq('group_id', groupId)
          .inFilter('role', ['athlete', 'atleta']);

      final members = (membersRes as List).cast<Map<String, dynamic>>();
      final athleteIds = members.map((m) => m['user_id'] as String).toList();

      // Include the current user even if they have a different role
      if (!athleteIds.contains(uid)) athleteIds.add(uid);

      if (athleteIds.isEmpty) {
        _setEmpty();
        return;
      }

      // Progression data
      final progRes = await db
          .from('v_user_progression')
          .select(
              'user_id, display_name, streak_current, streak_best, level, total_xp')
          .inFilter('user_id', athleteIds);

      final progs = (progRes as List).cast<Map<String, dynamic>>();

      final entries = progs.map((p) {
        return _StreakEntry(
          userId: p['user_id'] as String,
          name: (p['display_name'] as String?) ?? 'Atleta',
          streakCurrent: (p['streak_current'] as int?) ?? 0,
          streakBest: (p['streak_best'] as int?) ?? 0,
          level: (p['level'] as int?) ?? 0,
        );
      }).toList();

      _activeStreaks = entries
          .where((e) => e.streakCurrent >= 1)
          .toList()
        ..sort((a, b) => b.streakCurrent.compareTo(a.streakCurrent));

      _consistencyRanking = List.of(entries)
        ..sort((a, b) {
          final cmp = b.streakBest.compareTo(a.streakBest);
          if (cmp != 0) return cmp;
          return b.streakCurrent.compareTo(a.streakCurrent);
        });

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'StreaksLeaderboardScreen', error: e);
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar a consistência.';
          _loading = false;
        });
      }
    }
  }

  void _setEmpty() {
    if (mounted) {
      setState(() {
        _activeStreaks = [];
        _consistencyRanking = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.consistency)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == 'no_group'
              ? const _NoGroupBody()
              : _error != null
                  ? _ErrorBody(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(DesignTokens.spacingMd),
                        children: [
                          Text(
                            _groupName,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Quem está mantendo a consistência',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Section 1: Active streaks
                          const _SectionHeader(
                            icon: Icons.local_fire_department_rounded,
                            title: 'Correndo consecutivamente',
                            color: DesignTokens.warning,
                          ),
                          const SizedBox(height: 8),
                          if (_activeStreaks.isEmpty)
                            const _EmptyHint(
                                'Nenhum atleta correndo consecutivamente no momento.')
                          else
                            ..._activeStreaks.map((e) => _ActiveStreakTile(
                                  entry: e,
                                  isCurrentUser:
                                      e.userId == _currentUserId,
                                )),

                          const SizedBox(height: 28),

                          // Section 2: Consistency ranking
                          const _SectionHeader(
                            icon: Icons.emoji_events_rounded,
                            title: 'Ranking de consistência',
                            color: DesignTokens.warning,
                          ),
                          const SizedBox(height: 8),
                          if (_consistencyRanking.isEmpty)
                            const _EmptyHint(
                                'Nenhum dado de consistência disponível.')
                          else
                            ..._consistencyRanking
                                .asMap()
                                .entries
                                .map((e) => _ConsistencyTile(
                                      rank: e.key + 1,
                                      entry: e.value,
                                      isCurrentUser:
                                          e.value.userId == _currentUserId,
                                    )),
                        ],
                      ),
                    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data model
// ═══════════════════════════════════════════════════════════════════════════

class _StreakEntry {
  final String userId;
  final String name;
  final int streakCurrent;
  final int streakBest;
  final int level;

  const _StreakEntry({
    required this.userId,
    required this.name,
    required this.streakCurrent,
    required this.streakBest,
    required this.level,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Section header
// ═══════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Active streak tile — shows fire icon + current streak
// ═══════════════════════════════════════════════════════════════════════════

class _ActiveStreakTile extends StatelessWidget {
  final _StreakEntry entry;
  final bool isCurrentUser;

  const _ActiveStreakTile({
    required this.entry,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DesignTokens.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: isCurrentUser
            ? Border.all(color: DesignTokens.warning.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: DesignTokens.warning, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCurrentUser ? '${entry.name} (você)' : entry.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight:
                        isCurrentUser ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                Text(
                  'Nível ${entry.level}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.streakCurrent} ${entry.streakCurrent == 1 ? 'dia' : 'dias'}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: DesignTokens.warning,
                ),
              ),
              Text(
                'recorde: ${entry.streakBest}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Consistency ranking tile — sorted by streak_best
// ═══════════════════════════════════════════════════════════════════════════

class _ConsistencyTile extends StatelessWidget {
  final int rank;
  final _StreakEntry entry;
  final bool isCurrentUser;

  const _ConsistencyTile({
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
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
            ? DesignTokens.warning
            : theme.colorScheme.surfaceContainerHighest,
        child: Text(
          '$rank',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color:
                isTop3 ? DesignTokens.warning : theme.colorScheme.outline,
          ),
        ),
      ),
      title: Text(
        isCurrentUser ? '${entry.name} (você)' : entry.name,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(Icons.local_fire_department_rounded,
              size: 14,
              color: entry.streakCurrent > 0
                  ? DesignTokens.warning
                  : theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            entry.streakCurrent > 0
                ? '${entry.streakCurrent} ${entry.streakCurrent == 1 ? 'dia' : 'dias'} ativa'
                : 'sem dias consecutivos',
            style: theme.textTheme.bodySmall?.copyWith(
              color: entry.streakCurrent > 0
                  ? DesignTokens.warning
                  : theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${entry.streakBest} dias',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          Text(
            'melhor',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty / error / no-group states
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _NoGroupBody extends StatelessWidget {
  const _NoGroupBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Sem assessoria',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Entre em uma assessoria para ver\n'
              'a consistência dos outros atletas.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
