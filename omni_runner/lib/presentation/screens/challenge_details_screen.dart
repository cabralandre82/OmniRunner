import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/screens/challenge_result_screen.dart';
import 'package:omni_runner/presentation/widgets/dispute_status_card.dart';
import 'package:omni_runner/presentation/widgets/verification_gate.dart';

class ChallengeDetailsScreen extends StatelessWidget {
  final String challengeId;

  const ChallengeDetailsScreen({super.key, required this.challengeId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.challengeDetails)),
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

class _Body extends StatefulWidget {
  final ChallengeEntity challenge;
  final ChallengeResultEntity? result;

  const _Body({required this.challenge, this.result});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _settlementTriggered = false;

  ChallengeEntity get challenge => widget.challenge;
  ChallengeResultEntity? get result => widget.result;

  @override
  void initState() {
    super.initState();
    _tryAutoSettle();
  }

  void _tryAutoSettle() {
    if (_settlementTriggered) return;
    if (challenge.status != ChallengeStatus.active) return;
    if (challenge.endsAtMs == null) return;
    if (result != null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= challenge.endsAtMs!) return;

    _settlementTriggered = true;
    AppLogger.info(
      'Challenge ${challenge.id} window expired, triggering settlement',
      tag: 'ChallengeDetails',
    );
    Supabase.instance.client.functions
        .invoke('settle-challenge', body: {'challenge_id': challenge.id})
        .then((_) {
      if (!mounted) return;
      final uid = sl<UserIdentityProvider>().userId;
      context.read<ChallengesBloc>().add(ViewChallengeDetails(challenge.id));
      context.read<ChallengesBloc>().add(LoadChallenges(uid));
    })
        .catchError((e) {
      AppLogger.warn('Auto-settle failed: $e', tag: 'ChallengeDetails');
    });
  }

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

    final windowExpired = challenge.status == ChallengeStatus.active &&
        challenge.endsAtMs != null &&
        DateTime.now().millisecondsSinceEpoch > challenge.endsAtMs! &&
        result == null;

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
                    _chip(_metricLabel(challenge.rules.goal), cs),
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
            hasStake: challenge.rules.entryFeeCoins > 0,
          ),
          const SizedBox(height: 12),
        ],

        // ── Share / Invite (creator on pending) ──────────────────────
        if (isPending && isCreator) ...[
          _ShareInviteCard(challenge: challenge),
          const SizedBox(height: 12),
        ],

        // ── Group acceptance countdown ────────────────────────────────
        if (isPending &&
            (challenge.type == ChallengeType.group || challenge.type == ChallengeType.team) &&
            challenge.acceptDeadlineMs != null) ...[
          _AcceptDeadlineCard(deadlineMs: challenge.acceptDeadlineMs!),
          const SizedBox(height: 12),
        ],

        // ── Warmup countdown ──────────────────────────────────────────
        if (challenge.status == ChallengeStatus.active &&
            challenge.startsAtMs != null &&
            challenge.startsAtMs! > DateTime.now().millisecondsSinceEpoch) ...[
          _WarmupCard(startsAtMs: challenge.startsAtMs!),
          const SizedBox(height: 12),
        ],

        // ── Rules (always visible) ───────────────────────────────────
        _RulesCard(challenge: challenge),
        const SizedBox(height: 12),

        // ── Group live progress ─────────────────────────────────────
        if (challenge.type == ChallengeType.group &&
            challenge.status == ChallengeStatus.active &&
            challenge.rules.target != null &&
            challenge.rules.target! > 0) ...[
          _GroupLiveProgressCard(challenge: challenge),
          const SizedBox(height: 12),
        ],

        // ── Participants ─────────────────────────────────────────────
        _ParticipantsCard(
          challenge: challenge,
          currentUserId: uid,
        ),
        const SizedBox(height: 12),

        // ── Settling indicator ─────────────────────────────────────────
        if (windowExpired) ...[
          Card(
            elevation: 0,
            color: Colors.orange.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.orange.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calculando resultado...',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'O período do desafio terminou. O resultado será exibido em instantes.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

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
        ChallengeType.oneVsOne => 'Desafio 1 vs 1',
        ChallengeType.group => 'Desafio em Grupo',
        ChallengeType.team => 'Desafio Time A vs B',
      };

  static String _typeLabel(ChallengeType t) => switch (t) {
        ChallengeType.oneVsOne => '1 vs 1',
        ChallengeType.group => 'Grupo competitivo',
        ChallengeType.team => 'Time A vs Time B',
      };

  static String _metricLabel(ChallengeGoal m) => switch (m) {
        ChallengeGoal.fastestAtDistance => 'Mais rápido',
        ChallengeGoal.mostDistance => 'Mais km',
        ChallengeGoal.bestPaceAtDistance => 'Melhor pace',
        ChallengeGoal.collectiveDistance => 'Meta coletiva',
      };

  static String _modeLabel(ChallengeStartMode m) => switch (m) {
        ChallengeStartMode.onAccept => '5 min após aceite',
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
// Group acceptance deadline card
// ═════════════════════════════════════════════════════════════════════════════

class _AcceptDeadlineCard extends StatefulWidget {
  final int deadlineMs;
  const _AcceptDeadlineCard({required this.deadlineMs});

  @override
  State<_AcceptDeadlineCard> createState() => _AcceptDeadlineCardState();
}

class _AcceptDeadlineCardState extends State<_AcceptDeadlineCard> {
  late final Stream<int> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(seconds: 1), (_) {
      return widget.deadlineMs - DateTime.now().millisecondsSinceEpoch;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<int>(
      stream: _ticker,
      initialData: widget.deadlineMs - DateTime.now().millisecondsSinceEpoch,
      builder: (context, snap) {
        final remainMs = snap.data ?? 0;
        if (remainMs <= 0) {
          return Card(
            elevation: 0,
            color: Colors.grey.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.timer_off, color: Colors.grey, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Prazo para aceitar encerrado',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey)),
                  ),
                ],
              ),
            ),
          );
        }

        final min = remainMs ~/ 60000;
        final sec = (remainMs % 60000) ~/ 1000;
        final countdown = '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';

        return Card(
          elevation: 0,
          color: Colors.blue.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.group_add_rounded, color: Colors.blue, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Aguardando todos aceitarem',
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(countdown,
                    style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.blue.shade800,
                        letterSpacing: 3)),
                const SizedBox(height: 4),
                Text('Quando todos aceitarem, a corrida inicia em 5 minutos.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Warmup countdown card
// ═════════════════════════════════════════════════════════════════════════════

class _WarmupCard extends StatefulWidget {
  final int startsAtMs;
  const _WarmupCard({required this.startsAtMs});

  @override
  State<_WarmupCard> createState() => _WarmupCardState();
}

class _WarmupCardState extends State<_WarmupCard> {
  late final Stream<int> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(seconds: 1), (_) {
      return widget.startsAtMs - DateTime.now().millisecondsSinceEpoch;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<int>(
      stream: _ticker,
      initialData: widget.startsAtMs - DateTime.now().millisecondsSinceEpoch,
      builder: (context, snap) {
        final remainMs = snap.data ?? 0;
        if (remainMs <= 0) {
          return Card(
            elevation: 0,
            color: Colors.green.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.directions_run, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Valendo! Vá correr!',
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold, color: Colors.green)),
                  ),
                ],
              ),
            ),
          );
        }

        final min = (remainMs ~/ 60000);
        final sec = ((remainMs % 60000) ~/ 1000);
        final countdown = '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';

        return Card(
          elevation: 0,
          color: Colors.orange.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_rounded, color: Colors.orange, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Preparem-se!',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(countdown,
                    style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.orange.shade800,
                        letterSpacing: 4)),
                const SizedBox(height: 4),
                Text('O desafio começa em breve. Use esse tempo para se preparar!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Accept / Decline card
// ═════════════════════════════════════════════════════════════════════════════

class _AcceptDeclineCard extends StatefulWidget {
  final ChallengeEntity challenge;
  final String userId;
  final bool hasStake;

  const _AcceptDeclineCard({
    required this.challenge,
    required this.userId,
    required this.hasStake,
  });

  @override
  State<_AcceptDeclineCard> createState() => _AcceptDeclineCardState();
}

class _AcceptDeclineCardState extends State<_AcceptDeclineCard> {
  VerificationBloc? _verificationBloc;

  @override
  void initState() {
    super.initState();
    if (widget.hasStake) {
      _verificationBloc = sl<VerificationBloc>()
        ..add(const LoadVerificationState());
    }
  }

  @override
  void dispose() {
    _verificationBloc?.close();
    super.dispose();
  }

  Future<void> _onAccept() async {
    if (widget.hasStake) {
      final canProceed = await checkVerificationGate(
        context,
        verification: _verificationBloc?.cached,
        entryFeeCoins: widget.challenge.rules.entryFeeCoins,
      );
      if (!canProceed) return;
    }
    if (!mounted) return;
    context.read<ChallengesBloc>().add(
          JoinChallengeRequested(
            challengeId: widget.challenge.id,
            userId: widget.userId,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final challenge = widget.challenge;

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
                  ? 'Ao aceitar, todos terão 5 minutos para se preparar. '
                    'Depois disso, valendo! Corra no seu local — funciona em qualquer cidade!'
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
                    onPressed: _onAccept,
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
                              challengeId: widget.challenge.id,
                              userId: widget.userId,
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
      ChallengeType.oneVsOne => 'Desafio 1 vs 1',
      ChallengeType.group => 'Desafio em Grupo',
      ChallengeType.team => 'Desafio Time A vs B',
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
                          _metricLabel(challenge.rules.goal);
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

  static String _metricLabel(ChallengeGoal m) => switch (m) {
        ChallengeGoal.fastestAtDistance => 'Mais rápido',
        ChallengeGoal.mostDistance => 'Mais km',
        ChallengeGoal.bestPaceAtDistance => 'Melhor pace',
        ChallengeGoal.collectiveDistance => 'Coletivo',
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
            _row('Objetivo', _metricExplain(rules.goal)),
            if (rules.target != null)
              _row('Meta', _formatTarget(rules.target!, rules.goal)),
            _row('Duração', _formatWindow(rules.windowMs)),
            _row('Início',
                rules.startMode == ChallengeStartMode.onAccept
                    ? '5 min após todos aceitarem'
                    : _formatScheduled(rules.fixedStartMs)),
            if (rules.acceptWindowMin != null)
              _row('Prazo p/ aceitar', '${rules.acceptWindowMin} min'),
            _row('Corrida mínima',
                '${(rules.minSessionDistanceM / 1000).toStringAsFixed(1)} km'),
            _row('Validação', 'Padrão (GPS + anti-cheat)'),
            const Divider(height: 16),
            _row('Vencedor', _winnerExplain(challenge.type, rules.goal)),
            if (challenge.rules.entryFeeCoins > 0)
              _row('Prêmio', _prizeExplain(challenge.type, challenge.rules.entryFeeCoins)),
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

  static String _metricExplain(ChallengeGoal m) => switch (m) {
        ChallengeGoal.fastestAtDistance =>
          'Cada corredor faz uma corrida cobrindo a distância. Vence quem completar no menor tempo.',
        ChallengeGoal.mostDistance =>
          'Pode correr quantas vezes quiser no período. Vence quem acumular mais km no total.',
        ChallengeGoal.bestPaceAtDistance =>
          'Cada corredor faz uma corrida cobrindo a distância mínima. Vence quem tiver o menor pace médio (min/km).',
        ChallengeGoal.collectiveDistance =>
          'Cada membro corre o que puder — os km do time somam. O time com mais km vence.',
      };

  static String _formatTarget(double value, ChallengeGoal metric) =>
      switch (metric) {
        ChallengeGoal.fastestAtDistance ||
        ChallengeGoal.mostDistance ||
        ChallengeGoal.bestPaceAtDistance ||
        ChallengeGoal.collectiveDistance =>
          '${(value / 1000).toStringAsFixed(1)} km',
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

  static String _winnerExplain(ChallengeType type, ChallengeGoal goal) {
    if (type == ChallengeType.team) {
      return switch (goal) {
        ChallengeGoal.fastestAtDistance =>
          'Tempo do time = tempo do último membro a completar. Time mais rápido vence.',
        ChallengeGoal.mostDistance =>
          'Km do time = soma de todos os membros. Time com mais km vence.',
        ChallengeGoal.bestPaceAtDistance =>
          'Pace do time = média dos paces dos membros. Time com menor pace vence.',
        ChallengeGoal.collectiveDistance =>
          'Km do time = soma de todos os membros. Time com mais km vence.',
      };
    }
    if (goal == ChallengeGoal.collectiveDistance) {
      return 'Cooperativo por time — os km de cada time somam. O time com mais km vence.';
    }
    return switch (goal) {
      ChallengeGoal.fastestAtDistance =>
        'Quem completar a distância no menor tempo.',
      ChallengeGoal.mostDistance =>
        'Quem acumular mais km no período.',
      ChallengeGoal.bestPaceAtDistance =>
        'Quem tiver o menor pace médio (min/km).',
      ChallengeGoal.collectiveDistance =>
        'Cooperativo por time — o time com mais km vence.',
    };
  }

  static String _prizeExplain(ChallengeType type, int fee) {
    return switch (type) {
      ChallengeType.oneVsOne =>
        'O vencedor leva $fee OmniCoins do oponente. Empate: todos recebem de volta.',
      ChallengeType.group =>
        'O 1.o lugar leva todo o pool (${fee} x participantes). Empate: divisão igual.',
      ChallengeType.team =>
        'Cada membro do time vencedor recebe o dobro da inscrição. '
        'Empate: todos recebem de volta.',
    };
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
            ...challenge.participants.map((p) => _participantTile(
                  context,
                  p,
                  isMe: p.userId == currentUserId,
                  hideProgress: challenge.status == ChallengeStatus.active,
                )),
          ],
        ),
      ),
    );
  }

  Widget _participantTile(
    BuildContext context,
    ChallengeParticipantEntity p, {
    required bool isMe,
    required bool hideProgress,
  }) {
    final theme = Theme.of(context);

    final (statusIcon, statusColor) = switch (p.status) {
      ParticipantStatus.accepted => (Icons.check_circle, Colors.green),
      ParticipantStatus.invited => (Icons.hourglass_empty, Colors.orange),
      ParticipantStatus.declined => (Icons.cancel, Colors.red),
      ParticipantStatus.withdrawn => (Icons.exit_to_app, Colors.grey),
    };

    // During active challenges, only show own progress.
    // For opponents: show "Completou" or "Aguardando" only.
    Widget? trailing;
    if (hideProgress && !isMe) {
      final hasSubmitted = p.contributingSessionIds.isNotEmpty ||
          p.progressValue > 0;
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: hasSubmitted
              ? Colors.green.shade50
              : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          hasSubmitted ? 'Correu' : 'Aguardando',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: hasSubmitted
                ? Colors.green.shade700
                : Colors.orange.shade700,
          ),
        ),
      );
    } else if (p.progressValue > 0) {
      trailing = Text(
        _formatProgress(p.progressValue, challenge.rules.goal),
        style: const TextStyle(fontWeight: FontWeight.bold),
      );
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(statusIcon, color: statusColor, size: 20),
      title: Row(
        children: [
          if (p.team != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: p.team == 'A'
                    ? Colors.blue.shade100
                    : Colors.red.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                p.team!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: p.team == 'A'
                      ? Colors.blue.shade800
                      : Colors.red.shade800,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
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
      trailing: trailing,
    );
  }

  static String _formatProgress(double value, ChallengeGoal metric) =>
      switch (metric) {
        ChallengeGoal.fastestAtDistance =>
          '${(value / 60).toStringAsFixed(1)} min',
        ChallengeGoal.mostDistance ||
        ChallengeGoal.collectiveDistance =>
          '${(value / 1000).toStringAsFixed(2)} km',
        ChallengeGoal.bestPaceAtDistance =>
          '${(value / 60).toStringAsFixed(1)} min/km',
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
      subtitle: Text(_fmtResultProgress(pr.finalValue, ch.rules.goal)),
      trailing: pr.coinsEarned > 0
          ? Text('+${pr.coinsEarned} OmniCoins',
              style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12))
          : null,
    );
  }

  static String _fmtResultProgress(double value, ChallengeGoal metric) =>
      switch (metric) {
        ChallengeGoal.fastestAtDistance =>
          '${(value / 60).toStringAsFixed(1)} min',
        ChallengeGoal.mostDistance ||
        ChallengeGoal.collectiveDistance =>
          '${(value / 1000).toStringAsFixed(2)} km',
        ChallengeGoal.bestPaceAtDistance =>
          '${(value / 60).toStringAsFixed(1)} min/km',
      };
}

// ═════════════════════════════════════════════════════════════════════════════
// Clearing info (async lookup for cross-assessoria challenges)
// ═════════════════════════════════════════════════════════════════════════════

class _GroupLiveProgressCard extends StatelessWidget {
  final ChallengeEntity challenge;
  const _GroupLiveProgressCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final target = challenge.rules.target!;
    final metric = challenge.rules.goal;
    final lowerIsBetter = metric == ChallengeGoal.bestPaceAtDistance ||
        metric == ChallengeGoal.fastestAtDistance;

    final accepted = challenge.participants
        .where((p) => p.status == ParticipantStatus.accepted)
        .toList();

    final double collective;
    if (lowerIsBetter) {
      final runners = accepted.where((p) => p.progressValue > 0).toList();
      collective = runners.isEmpty
          ? 0
          : runners.map((p) => p.progressValue).reduce((a, b) => a + b) /
              runners.length;
    } else {
      collective =
          accepted.map((p) => p.progressValue).fold(0.0, (a, b) => a + b);
    }

    final double fraction;
    if (lowerIsBetter) {
      fraction = collective <= 0
          ? 0.0
          : (target / collective).clamp(0.0, 1.0);
    } else {
      fraction = (collective / target).clamp(0.0, 1.0);
    }

    final metTarget = lowerIsBetter
        ? (collective > 0 && collective <= target)
        : (collective >= target);
    final progressColor = metTarget ? Colors.green : cs.primary;
    final pct = (fraction * 100).toStringAsFixed(0);

    String formatVal(double v) => switch (metric) {
          ChallengeGoal.fastestAtDistance =>
            '${(v / 60).toStringAsFixed(1)} min',
          ChallengeGoal.mostDistance ||
          ChallengeGoal.collectiveDistance =>
            '${(v / 1000).toStringAsFixed(1)} km',
          ChallengeGoal.bestPaceAtDistance =>
            '${(v / 60).toStringAsFixed(1)} min/km',
        };

    return Card(
      elevation: 0,
      color: cs.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Progresso do Grupo',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '$pct%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: progressColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 12,
                backgroundColor: cs.surfaceContainerHighest,
                color: progressColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lowerIsBetter
                      ? 'Média: ${formatVal(collective)}'
                      : 'Total: ${formatVal(collective)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Meta: ${formatVal(target)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.outline,
                  ),
                ),
              ],
            ),
            if (metTarget) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        size: 15, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Meta atingida!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'ChallengeDetailsScreen', error: e);
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
