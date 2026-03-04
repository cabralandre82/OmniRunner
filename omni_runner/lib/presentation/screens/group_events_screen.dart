import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/presentation/blocs/race_events/race_events_bloc.dart';
import 'package:omni_runner/presentation/blocs/race_events/race_events_event.dart';
import 'package:omni_runner/presentation/blocs/race_events/race_events_state.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class GroupEventsScreen extends StatelessWidget {
  final String groupName;

  const GroupEventsScreen({super.key, required this.groupName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Provas · $groupName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<RaceEventsBloc>()
                .add(const RefreshRaceEvents()),
          ),
        ],
      ),
      body: BlocBuilder<RaceEventsBloc, RaceEventsState>(
        builder: (context, state) => switch (state) {
          RaceEventsInitial() =>
            const Center(child: Text('Carregando provas...')),
          RaceEventsLoading() =>
            const Center(child: CircularProgressIndicator()),
          RaceEventsLoaded(:final events, :final participantCounts) =>
            _EventList(events: events, participantCounts: participantCounts),
          RaceEventsEmpty() => const _EmptyState(),
          RaceEventsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
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

// ── Event list ──

class _EventList extends StatelessWidget {
  final List<RaceEventEntity> events;
  final Map<String, int> participantCounts;

  const _EventList({
    required this.events,
    required this.participantCounts,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return _RaceEventCard(
          event: event,
          participantCount: participantCounts[event.id] ?? 0,
        );
      },
    );
  }
}

// ── Event card ──

class _RaceEventCard extends StatelessWidget {
  final RaceEventEntity event;
  final int participantCount;

  const _RaceEventCard({
    required this.event,
    required this.participantCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(event.status);
    final statusLabel = _statusLabel(event.status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.emoji_events_outlined,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (event.location.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            event.location,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.calendar_today,
                    label: _formatDateRange(event.startsAtMs, event.endsAtMs),
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.people_outline,
                    label: '$participantCount participantes',
                  ),
                  if (event.targetDistanceM != null) ...[
                    const SizedBox(width: 12),
                    _InfoChip(
                      icon: Icons.flag_outlined,
                      label: _formatDistance(event.targetDistanceM!),
                    ),
                  ],
                ],
              ),
              if (event.xpReward > 0 || event.coinsReward > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (event.xpReward > 0)
                      _RewardBadge(
                        label: '${event.xpReward} XP',
                        color: DesignTokens.warning,
                      ),
                    if (event.xpReward > 0 && event.coinsReward > 0)
                      const SizedBox(width: 6),
                    if (event.coinsReward > 0)
                      _RewardBadge(
                        label: '${event.coinsReward} Coins',
                        color: DesignTokens.info,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(RaceEventStatus s) => switch (s) {
        RaceEventStatus.active => DesignTokens.success,
        RaceEventStatus.upcoming => DesignTokens.primary,
        RaceEventStatus.completed => DesignTokens.textMuted,
        RaceEventStatus.cancelled => DesignTokens.error,
      };

  static String _statusLabel(RaceEventStatus s) => switch (s) {
        RaceEventStatus.active => 'Em andamento',
        RaceEventStatus.upcoming => 'Em breve',
        RaceEventStatus.completed => 'Encerrado',
        RaceEventStatus.cancelled => 'Cancelado',
      };

  static String _formatDateRange(int startMs, int endMs) {
    final s = DateTime.fromMillisecondsSinceEpoch(startMs);
    final e = DateTime.fromMillisecondsSinceEpoch(endMs);
    return '${_d(s.day)}/${_d(s.month)} — ${_d(e.day)}/${_d(e.month)}';
  }

  static String _d(int v) => v.toString().padLeft(2, '0');

  static String _formatDistance(double meters) {
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

// ── Info chip ──

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}

// ── Reward badge ──

class _RewardBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _RewardBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
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
          Icon(Icons.emoji_events_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Nenhuma prova cadastrada',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'O coach ainda não criou provas\npara este grupo.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
