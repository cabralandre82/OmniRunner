import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/domain/entities/race_participation_entity.dart';
import 'package:omni_runner/domain/entities/race_result_entity.dart';
import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_bloc.dart';
import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_event.dart';
import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_state.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class RaceEventDetailsScreen extends StatelessWidget {
  const RaceEventDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RaceEventDetailsBloc, RaceEventDetailsState>(
      builder: (context, state) => switch (state) {
        RaceEventDetailsInitial() => Scaffold(
            appBar: AppBar(title: const Text('Prova')),
            body: const Center(child: Text('Carregando...')),
          ),
        RaceEventDetailsLoading() => Scaffold(
            appBar: AppBar(title: const Text('Prova')),
            body: const Center(child: CircularProgressIndicator()),
          ),
        RaceEventDetailsLoaded() => _LoadedBody(state: state),
        RaceEventDetailsError(:final message) => Scaffold(
            appBar: AppBar(title: const Text('Prova')),
            body: Center(
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
          ),
      },
    );
  }
}

// ── Loaded body ──

class _LoadedBody extends StatelessWidget {
  final RaceEventDetailsLoaded state;
  const _LoadedBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final event = state.event;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<RaceEventDetailsBloc>()
                .add(const RefreshRaceEventDetails()),
          ),
        ],
      ),
      body: ListView(
        children: [
          _BannerCard(event: event),
          if (state.myParticipation != null && !state.isCompleted)
            _MyProgressCard(
              participation: state.myParticipation!,
              event: event,
            ),
          if (state.myResult != null)
            _MyResultCard(result: state.myResult!),
          _RewardsCard(event: event),
          _InfoCard(event: event, participantCount: state.participations.length),
          if (state.isCompleted && state.results.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingSm),
              child: Text(
                'Resultados (${state.results.length})',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...state.results.map((r) => _ResultTile(
                  result: r,
                  isCurrentUser: r.userId == state.currentUserId,
                )),
          ] else if (!state.isCompleted && state.participations.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingSm),
              child: Text(
                'Participantes (${state.participations.length})',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...state.participations.map((p) => _ParticipantTile(
                  participation: p,
                  event: event,
                  isCurrentUser: p.userId == state.currentUserId,
                )),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Banner card ──

class _BannerCard extends StatelessWidget {
  final RaceEventEntity event;
  const _BannerCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(event.status);
    final statusLabel = _statusLabel(event.status);

    return Card(
      margin: const EdgeInsets.all(DesignTokens.spacingMd),
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
                    color: statusColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                  child: Icon(Icons.emoji_events,
                      color: statusColor, size: 28),
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
                            horizontal: DesignTokens.spacingSm, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
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
            if (event.location.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(event.location,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── My progress card (active events) ──

class _MyProgressCard extends StatelessWidget {
  final RaceParticipationEntity participation;
  final RaceEventEntity event;

  const _MyProgressCard({
    required this.participation,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = participation.progressFraction(event.targetDistanceM);
    final color =
        participation.completed ? DesignTokens.success : theme.colorScheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Meu progresso',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (event.targetDistanceM != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatColumn(
                  label: 'Distância',
                  value: _fmtDist(participation.totalDistanceM),
                ),
                _StatColumn(
                  label: 'Tempo',
                  value: _fmtTime(participation.totalMovingMs),
                ),
                _StatColumn(
                  label: 'Pace',
                  value: _fmtPace(participation.bestPaceSecPerKm),
                ),
                _StatColumn(
                  label: 'Corridas',
                  value: '${participation.contributingSessionCount}',
                ),
              ],
            ),
            if (participation.completed) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: DesignTokens.success, size: 18),
                  const SizedBox(width: 6),
                  Text('Meta atingida!',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: DesignTokens.success)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── My result card (completed events) ──

class _MyResultCard extends StatelessWidget {
  final RaceResultEntity result;
  const _MyResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rankColor = switch (result.finalRank) {
      1 => DesignTokens.warning,
      2 => DesignTokens.textMuted,
      3 => DesignTokens.warning,
      _ => theme.colorScheme.primary,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Meu resultado',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (result.isPodium)
                  Icon(Icons.emoji_events, color: rankColor, size: 24),
                const SizedBox(width: 4),
                Text('#${result.finalRank}',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: rankColor)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatColumn(
                    label: 'Distância',
                    value: _fmtDist(result.totalDistanceM)),
                _StatColumn(
                    label: 'Tempo', value: _fmtTime(result.totalMovingMs)),
                _StatColumn(
                    label: 'Pace',
                    value: _fmtPace(result.bestPaceSecPerKm)),
                _StatColumn(
                    label: 'Corridas', value: '${result.sessionCount}'),
              ],
            ),
            if (result.xpAwarded > 0 || result.coinsAwarded > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (result.xpAwarded > 0) ...[
                    Icon(Icons.star, size: 16, color: DesignTokens.warning),
                    const SizedBox(width: 4),
                    Text('+${result.xpAwarded} XP',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: DesignTokens.warning)),
                    const SizedBox(width: 12),
                  ],
                  if (result.coinsAwarded > 0) ...[
                    const Icon(Icons.monetization_on,
                        size: 16, color: DesignTokens.success),
                    const SizedBox(width: 4),
                    Text('+${result.coinsAwarded} Coins',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: DesignTokens.success)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Rewards card ──

class _RewardsCard extends StatelessWidget {
  final RaceEventEntity event;
  const _RewardsCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (event.xpReward <= 0 && event.coinsReward <= 0 && event.badgeId == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recompensas',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (event.xpReward > 0)
              _RewardRow(
                icon: Icons.star,
                color: DesignTokens.warning,
                label: 'Completar meta',
                detail: '${event.xpReward} XP',
              ),
            if (event.coinsReward > 0)
              _RewardRow(
                icon: Icons.monetization_on,
                color: DesignTokens.success,
                label: 'Completar meta',
                detail: '${event.coinsReward} Coins',
              ),
            if (event.badgeId != null)
              const _RewardRow(
                icon: Icons.military_tech,
                color: DesignTokens.info,
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(detail,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ── Info card ──

class _InfoCard extends StatelessWidget {
  final RaceEventEntity event;
  final int participantCount;

  const _InfoCard({required this.event, required this.participantCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metricLabel = switch (event.metric) {
      RaceEventMetric.distance => 'Distância',
      RaceEventMetric.time => 'Tempo',
      RaceEventMetric.pace => 'Pace',
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detalhes',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _DetailRow(label: 'Métrica', value: metricLabel),
            if (event.targetDistanceM != null)
              _DetailRow(
                  label: 'Meta',
                  value: _fmtDist(event.targetDistanceM!)),
            _DetailRow(
                label: 'Início', value: _fmtDate(event.startsAtMs)),
            _DetailRow(
                label: 'Fim', value: _fmtDate(event.endsAtMs)),
            _DetailRow(
                label: 'Participantes', value: '$participantCount'),
            if (event.maxParticipants != null)
              _DetailRow(
                  label: 'Máx. participantes',
                  value: '${event.maxParticipants}'),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(int ms) {
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

// ── Result tile (completed events) ──

class _ResultTile extends StatelessWidget {
  final RaceResultEntity result;
  final bool isCurrentUser;

  const _ResultTile({required this.result, this.isCurrentUser = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rankColor = switch (result.finalRank) {
      1 => DesignTokens.warning,
      2 => DesignTokens.textMuted,
      3 => DesignTokens.warning,
      _ => theme.colorScheme.outline,
    };

    final name =
        isCurrentUser ? '${result.displayName} (você)' : result.displayName;

    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Center(
          child: result.isPodium
              ? Icon(Icons.emoji_events, color: rankColor, size: 28)
              : Text('${result.finalRank}',
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: rankColor)),
        ),
      ),
      title: Text(name,
          style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500)),
      subtitle: Text(
        '${_fmtDist(result.totalDistanceM)} · ${result.formattedPace}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: result.targetCompleted
          ? const Icon(Icons.check_circle, color: DesignTokens.success, size: 20)
          : null,
    );
  }
}

// ── Participant tile (active events) ──

class _ParticipantTile extends StatelessWidget {
  final RaceParticipationEntity participation;
  final RaceEventEntity event;
  final bool isCurrentUser;

  const _ParticipantTile({
    required this.participation,
    required this.event,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = isCurrentUser
        ? '${participation.displayName} (você)'
        : participation.displayName;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: participation.completed
            ? DesignTokens.success.withAlpha(30)
            : theme.colorScheme.surfaceContainerHighest,
        child: participation.completed
            ? const Icon(Icons.check, color: DesignTokens.success, size: 20)
            : Icon(Icons.person, color: theme.colorScheme.outline),
      ),
      title: Text(name,
          style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500)),
      subtitle: Text(
        '${_fmtDist(participation.totalDistanceM)} · '
        '${participation.contributingSessionCount} corrida(s)',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: event.targetDistanceM != null
          ? SizedBox(
              width: 50,
              child: Text(
                '${(participation.progressFraction(event.targetDistanceM) * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: participation.completed
                      ? DesignTokens.success
                      : theme.colorScheme.primary,
                ),
              ),
            )
          : null,
    );
  }
}

// ── Stat column ──

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Shared formatters ──

Color _statusColor(RaceEventStatus s) => switch (s) {
      RaceEventStatus.active => DesignTokens.success,
      RaceEventStatus.upcoming => DesignTokens.primary,
      RaceEventStatus.completed => DesignTokens.textMuted,
      RaceEventStatus.cancelled => DesignTokens.error,
    };

String _statusLabel(RaceEventStatus s) => switch (s) {
      RaceEventStatus.active => 'Em andamento',
      RaceEventStatus.upcoming => 'Em breve',
      RaceEventStatus.completed => 'Encerrado',
      RaceEventStatus.cancelled => 'Cancelado',
    };

String _fmtDist(double meters) => '${(meters / 1000).toStringAsFixed(1)} km';

String _fmtTime(int ms) {
  final totalSec = ms ~/ 1000;
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}m';
  return '${m}m${s.toString().padLeft(2, '0')}s';
}

String _fmtPace(double? secPerKm) {
  if (secPerKm == null || secPerKm == double.infinity || secPerKm <= 0) {
    return '—';
  }
  final min = secPerKm ~/ 60;
  final sec = (secPerKm % 60).toInt();
  return '$min:${sec.toString().padLeft(2, '0')}/km';
}
