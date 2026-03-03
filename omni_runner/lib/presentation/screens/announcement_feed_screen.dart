import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_event.dart';
import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_state.dart';
import 'package:omni_runner/presentation/screens/announcement_create_screen.dart';
import 'package:omni_runner/presentation/screens/announcement_detail_screen.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

/// Feed of announcements for both staff and athletes.
class AnnouncementFeedScreen extends StatelessWidget {
  final String groupId;
  final bool isStaff;

  const AnnouncementFeedScreen({
    super.key,
    required this.groupId,
    required this.isStaff,
  });

  static String _relativeDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) {
      return 'Hoje ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) {
      return 'Ontem';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AnnouncementFeedBloc>()..add(LoadAnnouncements(groupId)),
      child: _AnnouncementFeedView(
        groupId: groupId,
        isStaff: isStaff,
      ),
    );
  }
}

class _AnnouncementFeedView extends StatelessWidget {
  final String groupId;
  final bool isStaff;

  const _AnnouncementFeedView({
    required this.groupId,
    required this.isStaff,
  });

  Future<void> _onRefresh(BuildContext context) async {
    context.read<AnnouncementFeedBloc>().add(const RefreshAnnouncements());
    await context.read<AnnouncementFeedBloc>().stream
        .where((s) => s is AnnouncementFeedLoaded || s is AnnouncementFeedError)
        .first;
  }

  Future<void> _openCreate(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AnnouncementCreateScreen(groupId: groupId),
      ),
    );
    if (result == true && context.mounted) {
      context.read<AnnouncementFeedBloc>().add(const RefreshAnnouncements());
    }
  }

  void _openDetail(BuildContext context, String announcementId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnnouncementDetailScreen(
          announcementId: announcementId,
          isStaff: isStaff,
        ),
      ),
    ).then((_) {
      if (context.mounted) {
        context.read<AnnouncementFeedBloc>().add(const RefreshAnnouncements());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<AnnouncementFeedBloc, AnnouncementFeedState>(
          buildWhen: (a, b) {
            if (a is! AnnouncementFeedLoaded || b is! AnnouncementFeedLoaded) {
              return true;
            }
            return a.unreadCount != b.unreadCount;
          },
          builder: (context, state) {
            final unread = switch (state) {
              AnnouncementFeedLoaded(:final unreadCount) => unreadCount,
              _ => 0,
            };
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Mural de Avisos'),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Badge(
                    label: Text('$unread'),
                    backgroundColor: cs.primary,
                  ),
                ],
              ],
            );
          },
        ),
      ),
      body: BlocBuilder<AnnouncementFeedBloc, AnnouncementFeedState>(
        builder: (context, state) {
          return switch (state) {
            AnnouncementFeedInitial() || AnnouncementFeedLoading() =>
              ListView(children: List.generate(5, (_) => const ShimmerCard())),
            AnnouncementFeedError(:final message) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: cs.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: cs.error,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => context
                            .read<AnnouncementFeedBloc>()
                            .add(LoadAnnouncements(groupId)),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            AnnouncementFeedLoaded(:final announcements) => announcements.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_outlined, size: 64, color: cs.onSurfaceVariant.withOpacity(0.4)),
                          const SizedBox(height: 16),
                          Text('Nenhum aviso publicado', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            'Avisos publicados pela assessoria aparecerão aqui',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _onRefresh(context),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: announcements.length,
                      itemBuilder: (context, index) {
                        final a = announcements[index];
                        return _AnnouncementCard(
                          announcement: a,
                          onTap: () => _openDetail(context, a.id),
                          relativeDate: AnnouncementFeedScreen._relativeDate,
                        );
                      },
                    ),
                  ),
          };
        },
      ),
      floatingActionButton: isStaff
          ? FloatingActionButton.extended(
              onPressed: () => _openCreate(context),
              icon: const Icon(Icons.add),
              label: const Text('Novo Aviso'),
            )
          : null,
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final AnnouncementEntity announcement;
  final VoidCallback onTap;
  final String Function(DateTime) relativeDate;

  const _AnnouncementCard({
    required this.announcement,
    required this.onTap,
    required this.relativeDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: announcement.pinned
            ? Icon(Icons.push_pin, color: cs.primary, size: 24)
            : null,
        title: Text(
          announcement.title,
          style: TextStyle(
            fontWeight: announcement.isRead ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${announcement.authorDisplayName ?? 'Desconhecido'} • ${relativeDate(announcement.createdAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.outline,
          ),
        ),
        trailing: !announcement.isRead
            ? Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
