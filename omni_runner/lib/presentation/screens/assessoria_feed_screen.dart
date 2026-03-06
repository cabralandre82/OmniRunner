import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/feed_item_entity.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_event.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_state.dart';
import 'package:omni_runner/l10n/l10n.dart';

/// Lightweight social feed scoped to the user's assessoria.
///
/// Shows recent activities from group members:
/// completed runs, challenge wins, badges, championships, etc.
class AssessoriaFeedScreen extends StatelessWidget {
  const AssessoriaFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.assessoriaFeed),
      ),
      body: BlocBuilder<AssessoriaFeedBloc, AssessoriaFeedState>(
        builder: (context, state) => switch (state) {
          FeedInitial() => const Center(child: CircularProgressIndicator()),
          FeedLoading() => const Center(child: CircularProgressIndicator()),
          FeedEmpty() => _EmptyState(),
          FeedError(:final message) => _ErrorState(message: message),
          FeedLoaded(:final items, :final hasMore, :final loadingMore) =>
            _FeedList(
              items: items,
              hasMore: hasMore,
              loadingMore: loadingMore,
            ),
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Feed list with pull-to-refresh and infinite scroll
// ═════════════════════════════════════════════════════════════════════════════

class _FeedList extends StatelessWidget {
  final List<FeedItemEntity> items;
  final bool hasMore;
  final bool loadingMore;

  const _FeedList({
    required this.items,
    required this.hasMore,
    required this.loadingMore,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<AssessoriaFeedBloc>().add(const RefreshFeed());
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              hasMore &&
              !loadingMore &&
              notification.metrics.extentAfter < 200) {
            context
                .read<AssessoriaFeedBloc>()
                .add(const LoadMoreFeed());
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
          itemCount: items.length + (loadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return const Padding(
                padding: EdgeInsets.all(DesignTokens.spacingMd),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _FeedTile(item: items[index]);
          },
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Individual feed item tile
// ═════════════════════════════════════════════════════════════════════════════

class _FeedTile extends StatelessWidget {
  final FeedItemEntity item;

  const _FeedTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = sl<UserIdentityProvider>().userId;
    final isMe = item.actorUserId == uid;

    final (icon, color, description) = _eventVisuals(item, isMe);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(30),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        description,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _formatTimeAgo(item.createdAtMs),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
    );
  }

  static (IconData, Color, String) _eventVisuals(
      FeedItemEntity item, bool isMe) {
    final name = isMe ? 'Você' : item.actorName;
    final p = item.payload;

    return switch (item.eventType) {
      FeedEventType.sessionCompleted => (
          Icons.directions_run,
          DesignTokens.primary,
          _sessionText(name, p),
        ),
      FeedEventType.challengeWon => (
          Icons.emoji_events,
          DesignTokens.warning,
          '$name venceu um desafio!',
        ),
      FeedEventType.badgeUnlocked => (
          Icons.military_tech,
          DesignTokens.info,
          '$name desbloqueou "${p['badge_name'] ?? 'uma conquista'}"',
        ),
      FeedEventType.championshipStarted => (
          Icons.flag,
          DesignTokens.success,
          'Campeonato "${p['championship_name'] ?? ''}" começou!',
        ),
      FeedEventType.streakMilestone => (
          Icons.local_fire_department,
          DesignTokens.warning,
          '$name atingiu ${p['streak_days'] ?? '?'} dias de sequência!',
        ),
      FeedEventType.levelUp => (
          Icons.trending_up,
          DesignTokens.success,
          '$name subiu para o nível ${p['level'] ?? '?'}!',
        ),
      FeedEventType.memberJoined => (
          Icons.person_add,
          DesignTokens.primary,
          '$name entrou na assessoria!',
        ),
    };
  }

  static String _sessionText(String name, Map<String, dynamic> p) {
    final distKm = p['distance_km'] as num?;
    if (distKm != null && distKm > 0) {
      return '$name completou ${distKm.toStringAsFixed(1)} km';
    }
    return '$name completou uma corrida';
  }

  static String _formatTimeAgo(int timestampMs) {
    final diff =
        DateTime.now().millisecondsSinceEpoch - timestampMs;
    final minutes = diff ~/ 60000;
    if (minutes < 1) return 'agora';
    if (minutes < 60) return 'há $minutes min';
    final hours = minutes ~/ 60;
    if (hours < 24) return 'há ${hours}h';
    final days = hours ~/ 24;
    if (days == 1) return 'ontem';
    if (days < 30) return 'há $days dias';
    return _formatDate(timestampMs);
  }

  static String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Empty and error states
// ═════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'Nenhuma atividade ainda',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Quando alguém da assessoria correr, vencer um desafio ou '
              'conquistar um badge, aparecerá aqui.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}
