import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/presentation/blocs/events/events_bloc.dart';
import 'package:omni_runner/presentation/blocs/events/events_event.dart';
import 'package:omni_runner/presentation/blocs/events/events_state.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.events),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<EventsBloc>().add(const RefreshEvents()),
          ),
        ],
      ),
      body: BlocBuilder<EventsBloc, EventsState>(
        builder: (context, state) => switch (state) {
          EventsInitial() =>
            const Center(child: Text('Carregue os eventos.')),
          EventsLoading() =>
            const Center(child: CircularProgressIndicator()),
          EventsLoaded() => _body(context, state),
          EventsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
                child: Text(message,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
        },
      ),
    );
  }

  static Widget _body(BuildContext context, EventsLoaded state) {
    if (state.activeEvents.isEmpty &&
        state.upcomingEvents.isEmpty &&
        state.completedEvents.isEmpty) {
      return _empty(context);
    }

    return ListView(
      children: [
        if (state.activeEvents.isNotEmpty) ...[
          _SectionHeader(
              title: 'Em andamento',
              count: state.activeEvents.length,
              icon: Icons.directions_run,
              color: DesignTokens.success),
          ...state.activeEvents.map((e) =>
              _EventCard(event: e, participation: state.participations[e.id])),
        ],
        if (state.upcomingEvents.isNotEmpty) ...[
          _SectionHeader(
              title: 'Em breve',
              count: state.upcomingEvents.length,
              icon: Icons.schedule,
              color: DesignTokens.primary),
          ...state.upcomingEvents.map((e) =>
              _EventCard(event: e, participation: state.participations[e.id])),
        ],
        if (state.completedEvents.isNotEmpty) ...[
          _SectionHeader(
              title: 'Encerrados',
              count: state.completedEvents.length,
              icon: Icons.check_circle,
              color: DesignTokens.textMuted),
          ...state.completedEvents.map((e) =>
              _EventCard(event: e, participation: state.participations[e.id])),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  static Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Nenhum evento disponível', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Novos eventos aparecem regularmente.\nFique atento!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingSm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventEntity event;
  final EventParticipationEntity? participation;

  const _EventCard({required this.event, this.participation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isJoined = participation != null;
    final statusColor = switch (event.status) {
      EventStatus.active => DesignTokens.success,
      EventStatus.upcoming => DesignTokens.primary,
      EventStatus.completed => DesignTokens.textMuted,
      EventStatus.cancelled => DesignTokens.error,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
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
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                    ),
                    child: Icon(
                      event.createdBySystem ? Icons.star : Icons.event,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(event.title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatDate(event.startsAtMs)} – '
                          '${_formatDate(event.endsAtMs)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  if (isJoined)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
                      decoration: BoxDecoration(
                        color: DesignTokens.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      ),
                      child: Text('Inscrito',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: DesignTokens.success,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (event.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(event.description,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
              if (participation != null && event.targetValue != null) ...[
                const SizedBox(height: 10),
                _ProgressBar(
                  fraction: participation!.progressFraction(event.targetValue),
                  completed: participation!.completed,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _InfoChip(
                      icon: Icons.emoji_events,
                      label:
                          '${event.rewards.xpCompletion} XP + ${event.rewards.coinsCompletion} Coins'),
                  if (event.rewards.badgeId != null) ...[
                    const SizedBox(width: 8),
                    const _InfoChip(icon: Icons.military_tech, label: 'Badge'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}';
  }
}

class _ProgressBar extends StatelessWidget {
  final double fraction;
  final bool completed;

  const _ProgressBar({required this.fraction, required this.completed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = completed ? DesignTokens.success : theme.colorScheme.primary;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(fraction * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
