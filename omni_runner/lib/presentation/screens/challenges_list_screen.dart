import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/presentation/screens/challenge_create_screen.dart';
import 'package:omni_runner/presentation/screens/challenge_details_screen.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';

class ChallengesListScreen extends StatelessWidget {
  const ChallengesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desafios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Criar desafio',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BlocProvider.value(
                  value: context.read<ChallengesBloc>(),
                  child: const ChallengeCreateScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: BlocBuilder<ChallengesBloc, ChallengesState>(
        builder: (context, state) => switch (state) {
          ChallengesInitial() => const Center(
              child: Text('Carregando...'),
            ),
          ChallengesLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          ChallengesLoaded(:final challenges) => challenges.isEmpty
              ? _empty(context)
              : _listWithTip(context, challenges),
          ChallengeCreated(:final challenge) => _list(context, [challenge]),
          ChallengeDetailLoaded() => const SizedBox.shrink(),
          ChallengesError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 72,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 20),
            Text(
              'Nenhum desafio ainda',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Crie um desafio e convide corredores\npara competir com você!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BlocProvider.value(
                    value: context.read<ChallengesBloc>(),
                    child: const ChallengeCreateScreen(),
                  ),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar desafio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listWithTip(
    BuildContext context,
    List<ChallengeEntity> challenges,
  ) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TipBanner(
            tipKey: TipKey.challengeHowTo,
            icon: Icons.emoji_events_outlined,
            text: 'Toque no "+" para criar um novo desafio. '
                'Escolha distância, pace ou tempo, defina o prazo '
                'e convide seus amigos!',
          ),
        ),
        Expanded(child: _list(context, challenges)),
      ],
    );
  }

  Widget _list(BuildContext context, List<ChallengeEntity> challenges) {
    final active = challenges
        .where((c) =>
            c.status == ChallengeStatus.pending ||
            c.status == ChallengeStatus.active ||
            c.status == ChallengeStatus.completing)
        .toList();
    final completed = challenges
        .where((c) =>
            c.status == ChallengeStatus.completed ||
            c.status == ChallengeStatus.cancelled ||
            c.status == ChallengeStatus.expired)
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (active.isNotEmpty) ...[
          _SectionHeader(title: 'Ativos', count: active.length),
          ...active.map((c) => _ChallengeListTile(challenge: c)),
        ],
        if (completed.isNotEmpty) ...[
          _SectionHeader(title: 'Concluídos', count: completed.length),
          ...completed.map((c) => _ChallengeListTile(challenge: c)),
        ],
      ],
    );
  }
}

class _ChallengeListTile extends StatelessWidget {
  final ChallengeEntity challenge;

  const _ChallengeListTile({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(challenge.status, theme);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(_statusIcon(challenge.status), color: statusColor),
      ),
      title: Text(
        challenge.title ?? _defaultTitle(challenge),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_metricLabel(challenge.rules.metric)}'
        ' · ${challenge.acceptedCount} participantes'
        ' · ${_modeTag(challenge.rules)}'
        ' · ${_statusLabel(challenge.status)}',
      ),
      trailing: challenge.rules.entryFeeCoins > 0
          ? Chip(
              label: Text('${challenge.rules.entryFeeCoins} OmniCoins',
                  style: const TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )
          : null,
      onTap: () {
        context
            .read<ChallengesBloc>()
            .add(ViewChallengeDetails(challenge.id));
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BlocProvider.value(
              value: context.read<ChallengesBloc>(),
              child: ChallengeDetailsScreen(challengeId: challenge.id),
            ),
          ),
        );
      },
    );
  }

  static String _defaultTitle(ChallengeEntity c) => switch (c.type) {
        ChallengeType.oneVsOne => 'Desafio 1v1',
        ChallengeType.teamVsTeam => 'Desafio de Equipe',
        ChallengeType.group => 'Desafio em Grupo',
      };

  static String _metricLabel(ChallengeMetric m) => switch (m) {
        ChallengeMetric.distance => 'Distância',
        ChallengeMetric.pace => 'Pace',
        ChallengeMetric.time => 'Tempo',
      };

  static String _statusLabel(ChallengeStatus s) => switch (s) {
        ChallengeStatus.pending => 'Pendente',
        ChallengeStatus.active => 'Ativo',
        ChallengeStatus.completing => 'Finalizando',
        ChallengeStatus.completed => 'Concluído',
        ChallengeStatus.cancelled => 'Cancelado',
        ChallengeStatus.expired => 'Expirado',
      };

  static IconData _statusIcon(ChallengeStatus s) => switch (s) {
        ChallengeStatus.pending => Icons.hourglass_empty,
        ChallengeStatus.active => Icons.directions_run,
        ChallengeStatus.completing => Icons.timer,
        ChallengeStatus.completed => Icons.emoji_events,
        ChallengeStatus.cancelled => Icons.cancel_outlined,
        ChallengeStatus.expired => Icons.schedule,
      };

  static Color _statusColor(ChallengeStatus s, ThemeData theme) => switch (s) {
        ChallengeStatus.pending => Colors.orange,
        ChallengeStatus.active => Colors.green,
        ChallengeStatus.completing => Colors.blue,
        ChallengeStatus.completed => Colors.teal,
        ChallengeStatus.cancelled => theme.colorScheme.error,
        ChallengeStatus.expired => Colors.grey,
      };

  static String _modeTag(ChallengeRulesEntity rules) =>
      rules.startMode == ChallengeStartMode.scheduled
          ? 'Agendado'
          : 'Imediato';
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
