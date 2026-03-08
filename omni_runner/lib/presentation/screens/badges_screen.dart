import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_bloc.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_event.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_state.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.badges),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<BadgesBloc>().add(const RefreshBadges()),
          ),
        ],
      ),
      body: BlocBuilder<BadgesBloc, BadgesState>(
        builder: (context, state) => switch (state) {
          BadgesInitial() => const _EmptyState(),
          BadgesLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          BadgesLoaded(:final catalog, :final awards) => catalog.isEmpty
              ? const _EmptyState()
              : _LoadedBody(catalog: catalog, awards: awards),
          BadgesError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ),
              ),
            ),
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Empty state
// ═════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.military_tech_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Suas conquistas aparecem aqui',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Complete corridas e desafios para desbloquear badges. '
              'Mantenha sua sequência e suba de nível!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Loaded body
// ═════════════════════════════════════════════════════════════════════════════

class _LoadedBody extends StatelessWidget {
  final List<BadgeEntity> catalog;
  final List<BadgeAwardEntity> awards;

  const _LoadedBody({required this.catalog, required this.awards});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlockedIds = {for (final a in awards) a.badgeId};
    final unlockedCount =
        catalog.where((b) => unlockedIds.contains(b.id)).length;

    final recentAwards = [...awards]
      ..sort((a, b) => b.unlockedAtMs.compareTo(a.unlockedAtMs));
    final recentBadges = recentAwards.take(6).map((a) {
      final badge = catalog.where((b) => b.id == a.badgeId).firstOrNull;
      return badge != null ? (badge: badge, award: a) : null;
    }).whereType<({BadgeEntity badge, BadgeAwardEntity award})>().toList();

    final grouped = <BadgeCategory, List<BadgeEntity>>{};
    for (final badge in catalog) {
      grouped.putIfAbsent(badge.category, () => []).add(badge);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingLg),
      children: [
        // ── Tip banner ───────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingSm, DesignTokens.spacingMd, 0),
          child: TipBanner(
            tipKey: TipKey.badgesHowTo,
            icon: Icons.lightbulb_outline_rounded,
            text: 'Conquistas são desbloqueadas automaticamente '
                'quando você atinge o critério. Corra, desafie e '
                'mantenha a sequência!',
          ),
        ),

        // ── Summary header ───────────────────────────────────────────
        _SummaryHeader(total: catalog.length, unlocked: unlockedCount),

        // ── Recent unlocks ───────────────────────────────────────────
        if (recentBadges.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 20, DesignTokens.spacingMd, DesignTokens.spacingSm),
            child: Text(
              'Desbloqueadas recentemente',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
              itemCount: recentBadges.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final r = recentBadges[i];
                return _RecentBadgeCard(
                  badge: r.badge,
                  award: r.award,
                );
              },
            ),
          ),
        ],

        // ── No unlocks yet ───────────────────────────────────────────
        if (recentBadges.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 20, DesignTokens.spacingMd, DesignTokens.spacingXs),
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Row(
                  children: [
                    Icon(Icons.military_tech_outlined,
                        size: 32, color: theme.colorScheme.outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Nenhuma conquista desbloqueada ainda. '
                        'Complete corridas e desafios para desbloquear badges!',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Collection by category ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 20, DesignTokens.spacingMd, DesignTokens.spacingXs),
          child: Text(
            'Coleção',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 14, DesignTokens.spacingMd, DesignTokens.spacingSm),
            child: Text(
              _categoryLabel(entry.key),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ...entry.value.map((b) => _BadgeListTile(
                badge: b,
                unlocked: unlockedIds.contains(b.id),
                award: awards.where((a) => a.badgeId == b.id).firstOrNull,
              )),
        ],
      ],
    );
  }

  static String _categoryLabel(BadgeCategory c) => switch (c) {
        BadgeCategory.distance => 'Distância',
        BadgeCategory.frequency => 'Frequência',
        BadgeCategory.speed => 'Velocidade',
        BadgeCategory.endurance => 'Resistência',
        BadgeCategory.social => 'Social',
        BadgeCategory.special => 'Especial',
      };
}

// ═════════════════════════════════════════════════════════════════════════════
// Summary header
// ═════════════════════════════════════════════════════════════════════════════

class _SummaryHeader extends StatelessWidget {
  final int total;
  final int unlocked;

  const _SummaryHeader({required this.total, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fraction = total > 0 ? unlocked / total : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingLg, horizontal: DesignTokens.spacingLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.primary.withValues(alpha: 0.12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Text(
            '$unlocked / $total',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'conquistas desbloqueadas',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onPrimaryContainer.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Recent badge card (horizontal scroll)
// ═════════════════════════════════════════════════════════════════════════════

class _RecentBadgeCard extends StatelessWidget {
  final BadgeEntity badge;
  final BadgeAwardEntity award;

  const _RecentBadgeCard({required this.badge, required this.award});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tierColor = _tierColor(badge.tier);

    return GestureDetector(
      onTap: () => _showBadgeDetail(context, badge, true, award),
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tierColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(color: tierColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.military_tech, size: 36, color: tierColor),
            const SizedBox(height: 8),
            Text(
              badge.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _tierLabel(badge.tier),
              style: theme.textTheme.labelSmall?.copyWith(
                color: tierColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              _formatDate(award.unlockedAtMs),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Badge list tile (collection)
// ═════════════════════════════════════════════════════════════════════════════

class _BadgeListTile extends StatelessWidget {
  final BadgeEntity badge;
  final bool unlocked;
  final BadgeAwardEntity? award;

  const _BadgeListTile({
    required this.badge,
    required this.unlocked,
    this.award,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tierColor = _tierColor(badge.tier);
    final isHidden = badge.isSecret && !unlocked;

    return ListTile(
      onTap: () => _showBadgeDetail(context, badge, unlocked, award),
      contentPadding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: unlocked
              ? tierColor.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          border: unlocked
              ? Border.all(color: tierColor.withValues(alpha: 0.4))
              : null,
        ),
        child: Icon(
          unlocked ? Icons.military_tech : Icons.lock_outline,
          size: 24,
          color: unlocked ? tierColor : theme.colorScheme.outline,
        ),
      ),
      title: Text(
        isHidden ? '???' : badge.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: unlocked ? FontWeight.bold : FontWeight.normal,
          color: unlocked ? null : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        isHidden
            ? 'Conquista secreta'
            : 'Como ganhar: ${badge.description}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _tierLabel(badge.tier),
            style: theme.textTheme.labelSmall?.copyWith(
              color: tierColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '+${badge.xpReward} XP',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Detail bottom sheet
// ═════════════════════════════════════════════════════════════════════════════

void _showBadgeDetail(
  BuildContext context,
  BadgeEntity badge,
  bool unlocked,
  BadgeAwardEntity? award,
) {
  final theme = Theme.of(context);
  final tierColor = _tierColor(badge.tier);
  final isHidden = badge.isSecret && !unlocked;

  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingLg, 20, DesignTokens.spacingLg, DesignTokens.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked
                  ? tierColor.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: unlocked ? tierColor : theme.colorScheme.outline,
                width: 2,
              ),
            ),
            child: Icon(
              unlocked ? Icons.military_tech : Icons.lock_outline,
              size: 32,
              color: unlocked ? tierColor : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isHidden ? '???' : badge.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Chip(
            label: Text(_tierLabel(badge.tier)),
            backgroundColor: tierColor.withValues(alpha: 0.1),
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 12),

          // "Como ganhar" section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlocked ? 'Critério' : 'Como ganhar',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isHidden ? 'Conquista secreta — corra para descobrir!' : badge.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Rewards
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RewardTag(
                icon: Icons.auto_awesome,
                value: '+${badge.xpReward} XP',
                color: DesignTokens.primary,
              ),
              if (badge.coinsReward > 0) ...[
                const SizedBox(width: 16),
                _RewardTag(
                  icon: Icons.toll_rounded,
                  value: '+${badge.coinsReward} OmniCoins',
                  color: DesignTokens.warning,
                ),
              ],
            ],
          ),

          if (unlocked && award != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle,
                    size: 16, color: DesignTokens.success),
                const SizedBox(width: 6),
                Text(
                  'Desbloqueada em ${_formatDate(award.unlockedAtMs)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DesignTokens.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ═════════════════════════════════════════════════════════════════════════════

Color _tierColor(BadgeTier t) => switch (t) {
      BadgeTier.bronze => const Color(0xFFCD7F32),
      BadgeTier.silver => const Color(0xFFA0A0A0),
      BadgeTier.gold => const Color(0xFFFFD700),
      BadgeTier.diamond => const Color(0xFF29B6F6),
    };

String _tierLabel(BadgeTier t) => switch (t) {
      BadgeTier.bronze => 'Bronze',
      BadgeTier.silver => 'Prata',
      BadgeTier.gold => 'Ouro',
      BadgeTier.diamond => 'Diamante',
    };

String _formatDate(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

class _RewardTag extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _RewardTag({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
