import 'package:flutter/material.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';

class EventDetailsScreen extends StatelessWidget {
  final EventEntity event;
  final EventParticipationEntity? myParticipation;
  final List<EventParticipationEntity> allParticipations;

  const EventDetailsScreen({
    super.key,
    required this.event,
    this.myParticipation,
    this.allParticipations = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(event.title)),
      body: ListView(
        children: [
          _BannerSection(event: event),
          if (myParticipation != null)
            _MyProgressCard(event: event, participation: myParticipation!),
          _RewardsCard(rewards: event.rewards),
          _InfoCard(event: event),
          if (allParticipations.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Participantes (${allParticipations.length})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            ...allParticipations.map((p) =>
                _ParticipantTile(participation: p, event: event)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BannerSection extends StatelessWidget {
  final EventEntity event;
  const _BannerSection({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (event.status) {
      EventStatus.active => Colors.green,
      EventStatus.upcoming => Colors.blue,
      EventStatus.completed => Colors.grey,
      EventStatus.cancelled => Colors.red,
    };
    final statusLabel = switch (event.status) {
      EventStatus.active => 'Em andamento',
      EventStatus.upcoming => 'Em breve',
      EventStatus.completed => 'Encerrado',
      EventStatus.cancelled => 'Cancelado',
    };

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    event.createdBySystem ? Icons.star : Icons.event,
                    color: statusColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(statusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(event.description, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _MyProgressCard extends StatelessWidget {
  final EventEntity event;
  final EventParticipationEntity participation;

  const _MyProgressCard(
      {required this.event, required this.participation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = participation.progressFraction(event.targetValue);
    final color =
        participation.completed ? Colors.teal : theme.colorScheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Meu progresso',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatMetric(
                      participation.currentValue, event.metric),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (event.targetValue != null)
                  Text(
                    'Meta: ${_formatMetric(event.targetValue!, event.metric)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
            ),
            if (participation.rank != null && participation.rank! > 0) ...[
              const SizedBox(height: 4),
              Text('Posição: #${participation.rank}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ],
            if (participation.completed) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.teal, size: 18),
                  const SizedBox(width: 6),
                  Text('Meta atingida!',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.teal)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatMetric(double value, GoalMetric metric) =>
      switch (metric) {
        GoalMetric.distance => '${(value / 1000).toStringAsFixed(1)} km',
        GoalMetric.sessions => '${value.toStringAsFixed(0)} corridas',
        GoalMetric.movingTime =>
          '${(value / 3600000).toStringAsFixed(1)} horas',
      };
}

class _RewardsCard extends StatelessWidget {
  final EventRewards rewards;
  const _RewardsCard({required this.rewards});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recompensas',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (rewards.xpCompletion > 0 || rewards.coinsCompletion > 0)
              _RewardRow(
                icon: Icons.emoji_events,
                color: Colors.amber,
                label: 'Completar meta',
                detail: [
                  if (rewards.xpCompletion > 0) '${rewards.xpCompletion} XP',
                  if (rewards.coinsCompletion > 0)
                    '${rewards.coinsCompletion} Coins',
                ].join(' + '),
              ),
            if (rewards.xpParticipation > 0)
              _RewardRow(
                icon: Icons.directions_run,
                color: Colors.green,
                label: 'Participação',
                detail: '${rewards.xpParticipation} XP',
              ),
            if (rewards.badgeId != null)
              const _RewardRow(
                icon: Icons.military_tech,
                color: Colors.purple,
                label: 'Badge exclusiva',
                detail: 'Desbloqueada ao completar',
              ),
          ],
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String detail;

  const _RewardRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final EventEntity event;
  const _InfoCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeLabel = switch (event.type) {
      EventType.individual => 'Individual',
      EventType.team => 'Equipe',
    };
    final metricLabel = switch (event.metric) {
      GoalMetric.distance => 'Distância',
      GoalMetric.sessions => 'Corridas',
      GoalMetric.movingTime => 'Tempo',
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detalhes',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _DetailRow(label: 'Tipo', value: typeLabel),
            _DetailRow(label: 'Métrica', value: metricLabel),
            _DetailRow(
                label: 'Início', value: _formatDate(event.startsAtMs)),
            _DetailRow(
                label: 'Fim', value: _formatDate(event.endsAtMs)),
            if (event.maxParticipants != null)
              _DetailRow(
                  label: 'Máx. participantes',
                  value: '${event.maxParticipants}'),
            _DetailRow(
                label: 'Origem',
                value: event.createdBySystem ? 'Oficial' : 'Usuário'),
          ],
        ),
      ),
    );
  }

  static String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final EventParticipationEntity participation;
  final EventEntity event;

  const _ParticipantTile(
      {required this.participation, required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: participation.completed
            ? Colors.teal.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest,
        child: participation.rank != null && participation.rank! > 0
            ? Text('${participation.rank}',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold))
            : Icon(Icons.person, color: theme.colorScheme.outline),
      ),
      title: Text(participation.displayName,
          style:
              theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: Text(
        '${participation.contributingSessionCount} corrida(s)',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: participation.completed
          ? const Icon(Icons.check_circle, color: Colors.teal, size: 20)
          : null,
    );
  }
}
