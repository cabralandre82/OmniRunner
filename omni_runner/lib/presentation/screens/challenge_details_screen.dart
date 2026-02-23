import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/presentation/screens/challenge_result_screen.dart';
import 'package:omni_runner/presentation/widgets/dispute_status_card.dart';

class ChallengeDetailsScreen extends StatelessWidget {
  final String challengeId;

  const ChallengeDetailsScreen({super.key, required this.challengeId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do Desafio')),
      body: BlocBuilder<ChallengesBloc, ChallengesState>(
        builder: (context, state) => switch (state) {
          ChallengeDetailLoaded(:final challenge, :final result) =>
            _Body(challenge: challenge, result: result),
          ChallengesLoading() =>
            const Center(child: CircularProgressIndicator()),
          ChallengesError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final ChallengeEntity challenge;
  final ChallengeResultEntity? result;

  const _Body({required this.challenge, this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final uid = sl<UserIdentityProvider>().userId;
    final myParticipant = challenge.participants
        .where((p) => p.userId == uid)
        .firstOrNull;
    final isCreator = challenge.creatorUserId == uid;
    final isPending = challenge.status == ChallengeStatus.pending;
    final isInvited = myParticipant?.status == ParticipantStatus.invited;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header ───────────────────────────────────────────────────
        Card(
          elevation: 0,
          color: cs.primaryContainer.withValues(alpha: 0.3),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_statusIcon(challenge.status),
                        color: _statusColor(challenge.status, theme)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        challenge.title ?? _defaultTitle(challenge),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _statusChip(challenge.status, theme),
                    _chip(_typeLabel(challenge.type), cs),
                    _chip(_metricLabel(challenge.rules.metric), cs),
                    _chip(_modeLabel(challenge.rules.startMode), cs),
                    if (challenge.rules.entryFeeCoins > 0)
                      _chip(
                          '${challenge.rules.entryFeeCoins} OmniCoins', cs),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Accept / Decline actions ─────────────────────────────────
        if (isPending && isInvited && !isCreator) ...[
          _AcceptDeclineCard(
            challenge: challenge,
            userId: uid,
          ),
          const SizedBox(height: 12),
        ],

        // ── Share / Invite (creator on pending) ──────────────────────
        if (isPending && isCreator) ...[
          _ShareInviteCard(challenge: challenge),
          const SizedBox(height: 12),
        ],

        // ── Rules (always visible) ───────────────────────────────────
        _RulesCard(challenge: challenge),
        const SizedBox(height: 12),

        // ── Participants ─────────────────────────────────────────────
        _ParticipantsCard(
          challenge: challenge,
          currentUserId: uid,
        ),
        const SizedBox(height: 12),

        // ── Results ──────────────────────────────────────────────────
        if (result != null) ...[
          _ResultsCard(challenge: challenge, result: result!),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.emoji_events_rounded, size: 18),
              label: const Text('Ver resultado completo'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChallengeResultScreen(
                    challenge: challenge,
                    result: result!,
                  ),
                ));
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Dispute / Clearing status ────────────────────────────────
        if (challenge.status == ChallengeStatus.completed ||
            challenge.status == ChallengeStatus.completing)
          _ClearingInfo(challengeId: challenge.id),

        // ── Cancel action ────────────────────────────────────────────
        if (isPending && isCreator)
          OutlinedButton.icon(
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancelar Desafio'),
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            onPressed: () {
              context.read<ChallengesBloc>().add(
                    CancelChallengeRequested(
                      challengeId: challenge.id,
                      userId: uid,
                    ),
                  );
              Navigator.of(context).pop();
            },
          ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ── Shared widgets ─────────────────────────────────────────────────────

  Widget _chip(String label, ColorScheme cs) => Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
        backgroundColor: cs.surfaceContainerHighest,
      );

  Widget _statusChip(ChallengeStatus s, ThemeData theme) {
    final color = _statusColor(s, theme);
    return Chip(
      label: Text(_statusLabel(s),
          style: TextStyle(fontSize: 12, color: color,
              fontWeight: FontWeight.bold)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }

  static String _defaultTitle(ChallengeEntity c) => switch (c.type) {
        ChallengeType.oneVsOne => 'Desafio 1v1',
        ChallengeType.teamVsTeam => 'Desafio de Equipe',
        ChallengeType.group => 'Desafio em Grupo',
      };

  static String _typeLabel(ChallengeType t) => switch (t) {
        ChallengeType.oneVsOne => '1v1',
        ChallengeType.group => 'Grupo',
        ChallengeType.teamVsTeam => 'Equipe vs Equipe',
      };

  static String _metricLabel(ChallengeMetric m) => switch (m) {
        ChallengeMetric.distance => 'Distância',
        ChallengeMetric.pace => 'Pace',
        ChallengeMetric.time => 'Tempo',
      };

  static String _modeLabel(ChallengeStartMode m) => switch (m) {
        ChallengeStartMode.onAccept => 'Começa ao aceitar',
        ChallengeStartMode.scheduled => 'Agendado',
      };

  static String _statusLabel(ChallengeStatus s) => switch (s) {
        ChallengeStatus.pending => 'Aguardando',
        ChallengeStatus.active => 'Em andamento',
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
}

// ═════════════════════════════════════════════════════════════════════════════
// Accept / Decline card
// ═════════════════════════════════════════════════════════════════════════════

class _AcceptDeclineCard extends StatelessWidget {
  final ChallengeEntity challenge;
  final String userId;

  const _AcceptDeclineCard({
    required this.challenge,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: Colors.amber.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text('Você foi convidado!',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              challenge.rules.startMode == ChallengeStartMode.onAccept
                  ? 'O desafio começa assim que você aceitar. '
                    'Corra no seu local — funciona em qualquer cidade!'
                  : 'O desafio está agendado. Aceite para participar. '
                    'Corra no seu local — funciona em qualquer cidade!',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (challenge.rules.entryFeeCoins > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Inscrição: ${challenge.rules.entryFeeCoins} OmniCoins',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Aceitar'),
                    onPressed: () {
                      context.read<ChallengesBloc>().add(
                            JoinChallengeRequested(
                              challengeId: challenge.id,
                              userId: userId,
                            ),
                          );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Recusar'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error),
                    onPressed: () {
                      context.read<ChallengesBloc>().add(
                            DeclineChallengeRequested(
                              challengeId: challenge.id,
                              userId: userId,
                            ),
                          );
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Share / Invite card (for creator on pending challenges)
// ═════════════════════════════════════════════════════════════════════════════

class _ShareInviteCard extends StatelessWidget {
  final ChallengeEntity challenge;

  const _ShareInviteCard({required this.challenge});

  String get _deepLink => 'https://omnirunner.app/challenge/${challenge.id}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = challenge.title ?? switch (challenge.type) {
      ChallengeType.oneVsOne => 'Desafio 1v1',
      ChallengeType.teamVsTeam => 'Desafio de Equipe',
      ChallengeType.group => 'Desafio em Grupo',
    };
    final needsOpponent = challenge.type == ChallengeType.oneVsOne &&
        challenge.acceptedCount < 2;

    return Card(
      elevation: 0,
      color: cs.secondaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.secondaryContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded,
                    size: 20, color: cs.secondary),
                const SizedBox(width: 8),
                Text(
                  needsOpponent
                      ? 'Convide seu oponente!'
                      : 'Convide mais participantes',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Envie o link para quem quiser desafiar. '
              'Funciona mesmo em cidades diferentes!',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Enviar convite'),
                    onPressed: () {
                      final metric =
                          _metricLabel(challenge.rules.metric);
                      final window =
                          _formatWindow(challenge.rules.windowMs);
                      SharePlus.instance.share(
                        ShareParams(
                          text:
                              'Participe do meu desafio "$title" no Omni Runner!\n'
                              'Modalidade: $metric\n'
                              'Duração: $window\n\n'
                              '$_deepLink',
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  tooltip: 'Copiar link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _deepLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link copiado!'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _metricLabel(ChallengeMetric m) => switch (m) {
        ChallengeMetric.distance => 'Distância',
        ChallengeMetric.pace => 'Pace',
        ChallengeMetric.time => 'Tempo',
      };

  static String _formatWindow(int ms) {
    if (ms < 3600000) return '${ms ~/ 60000} minutos';
    if (ms < 86400000) return '${ms ~/ 3600000} horas';
    final days = ms ~/ 86400000;
    return '$days ${days == 1 ? "dia" : "dias"}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Rules card
// ═════════════════════════════════════════════════════════════════════════════

class _RulesCard extends StatelessWidget {
  final ChallengeEntity challenge;

  const _RulesCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rules = challenge.rules;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Como funciona',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            _row('O que conta', _metricExplain(rules.metric)),
            if (rules.target != null)
              _row('Meta', _formatTarget(rules.target!, rules.metric)),
            _row('Duração', _formatWindow(rules.windowMs)),
            _row('Início',
                rules.startMode == ChallengeStartMode.onAccept
                    ? 'Quando todos aceitarem'
                    : _formatScheduled(rules.fixedStartMs)),
            _row('Corrida mínima',
                '${(rules.minSessionDistanceM / 1000).toStringAsFixed(1)} km'),
            _row('Validação',
                rules.antiCheatPolicy == ChallengeAntiCheatPolicy.strict
                    ? 'Avançada (frequência cardíaca obrigatória)'
                    : 'Padrão (GPS + anti-cheat)'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Builder(builder: (context) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
    });
  }

  static String _metricExplain(ChallengeMetric m) => switch (m) {
        ChallengeMetric.distance =>
          'Distância total percorrida (soma de corridas)',
        ChallengeMetric.pace =>
          'Melhor pace médio em uma única corrida',
        ChallengeMetric.time =>
          'Tempo total em movimento (soma de corridas)',
      };

  static String _formatTarget(double value, ChallengeMetric metric) =>
      switch (metric) {
        ChallengeMetric.distance =>
          '${(value / 1000).toStringAsFixed(1)} km',
        ChallengeMetric.pace =>
          '${(value / 60).toStringAsFixed(1)} min/km',
        ChallengeMetric.time =>
          '${(value / 60000).toStringAsFixed(0)} min',
      };

  static String _formatWindow(int ms) {
    if (ms < 3600000) return '${ms ~/ 60000} minutos';
    if (ms < 86400000) return '${ms ~/ 3600000} horas';
    final days = ms ~/ 86400000;
    return '$days ${days == 1 ? "dia" : "dias"}';
  }

  static String _formatScheduled(int? ms) {
    if (ms == null) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} às '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Participants card
// ═════════════════════════════════════════════════════════════════════════════

class _ParticipantsCard extends StatelessWidget {
  final ChallengeEntity challenge;
  final String currentUserId;

  const _ParticipantsCard({
    required this.challenge,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Participantes (${challenge.acceptedCount})',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...challenge.participants.map((p) =>
                _participantTile(context, p, p.userId == currentUserId)),
          ],
        ),
      ),
    );
  }

  Widget _participantTile(
      BuildContext context, ChallengeParticipantEntity p, bool isMe) {
    final theme = Theme.of(context);

    final (statusIcon, statusColor) = switch (p.status) {
      ParticipantStatus.accepted => (Icons.check_circle, Colors.green),
      ParticipantStatus.invited => (Icons.hourglass_empty, Colors.orange),
      ParticipantStatus.declined => (Icons.cancel, Colors.red),
      ParticipantStatus.withdrawn => (Icons.exit_to_app, Colors.grey),
    };

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(statusIcon, color: statusColor, size: 20),
      title: Row(
        children: [
          Flexible(
            child: Text(p.displayName, overflow: TextOverflow.ellipsis),
          ),
          if (isMe) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Você',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary, fontSize: 10)),
            ),
          ],
        ],
      ),
      trailing: p.progressValue > 0
          ? Text(
              _formatProgress(p.progressValue, challenge.rules.metric),
              style: const TextStyle(fontWeight: FontWeight.bold),
            )
          : null,
    );
  }

  static String _formatProgress(double value, ChallengeMetric metric) =>
      switch (metric) {
        ChallengeMetric.distance =>
          '${(value / 1000).toStringAsFixed(2)} km',
        ChallengeMetric.pace =>
          '${(value / 60).toStringAsFixed(1)} min/km',
        ChallengeMetric.time =>
          '${(value / 60000).toStringAsFixed(0)} min',
      };
}

// ═════════════════════════════════════════════════════════════════════════════
// Results card
// ═════════════════════════════════════════════════════════════════════════════

class _ResultsCard extends StatelessWidget {
  final ChallengeEntity challenge;
  final ChallengeResultEntity result;

  const _ResultsCard({required this.challenge, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resultado',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...result.results
                .map((pr) => _resultTile(context, pr, challenge)),
            if (result.totalCoinsDistributed > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Total distribuído: ${result.totalCoinsDistributed} OmniCoins',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultTile(
      BuildContext context, ParticipantResult pr, ChallengeEntity ch) {
    final (icon, color) = switch (pr.outcome) {
      ParticipantOutcome.won => (Icons.emoji_events, Colors.amber),
      ParticipantOutcome.tied => (Icons.handshake, Colors.blue),
      ParticipantOutcome.completedTarget =>
        (Icons.check_circle, Colors.green),
      _ => (Icons.directions_run, Colors.grey),
    };

    final displayName = ch.participants
        .where((p) => p.userId == pr.userId)
        .map((p) => p.displayName)
        .firstOrNull ?? 'Corredor';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        '${pr.rank != null ? "#${pr.rank} " : ""}$displayName',
      ),
      subtitle: Text(_fmtResultProgress(pr.finalValue, ch.rules.metric)),
      trailing: pr.coinsEarned > 0
          ? Text('+${pr.coinsEarned} OmniCoins',
              style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12))
          : null,
    );
  }

  static String _fmtResultProgress(double value, ChallengeMetric metric) =>
      switch (metric) {
        ChallengeMetric.distance =>
          '${(value / 1000).toStringAsFixed(2)} km',
        ChallengeMetric.pace =>
          '${(value / 60).toStringAsFixed(1)} min/km',
        ChallengeMetric.time =>
          '${(value / 60000).toStringAsFixed(0)} min',
      };
}

// ═════════════════════════════════════════════════════════════════════════════
// Clearing info (async lookup for cross-assessoria challenges)
// ═════════════════════════════════════════════════════════════════════════════

class _ClearingInfo extends StatefulWidget {
  final String challengeId;
  const _ClearingInfo({required this.challengeId});

  @override
  State<_ClearingInfo> createState() => _ClearingInfoState();
}

class _ClearingInfoState extends State<_ClearingInfo> {
  DisputePhase? _phase;
  int? _amount;
  DateTime? _deadline;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final items = await db
          .from('clearing_case_items')
          .select('case_id, amount')
          .eq('challenge_id', widget.challengeId)
          .limit(1);

      if ((items as List).isEmpty) {
        if (mounted) setState(() => _loaded = true);
        return;
      }

      final caseId = items[0]['case_id'] as String;
      final amount = items[0]['amount'] as int;

      final caseData = await db
          .from('clearing_cases')
          .select('status, deadline_at')
          .eq('id', caseId)
          .maybeSingle();

      if (caseData == null) {
        if (mounted) setState(() => _loaded = true);
        return;
      }

      final status = caseData['status'] as String;
      final deadline = DateTime.parse(caseData['deadline_at'] as String);

      final phase = switch (status) {
        'OPEN' => DisputePhase.pendingClearing,
        'SENT_CONFIRMED' => DisputePhase.sentConfirmed,
        'DISPUTED' => DisputePhase.disputed,
        'PAID_CONFIRMED' => DisputePhase.cleared,
        'EXPIRED' => DisputePhase.expired,
        _ => DisputePhase.pendingClearing,
      };

      if (mounted) {
        setState(() {
          _phase = phase;
          _amount = amount;
          _deadline = deadline;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _phase == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DisputeStatusCard(
        phase: _phase!,
        coinsAmount: _amount,
        deadlineAt: _deadline,
      ),
    );
  }
}
