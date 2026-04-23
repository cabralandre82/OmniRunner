import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/usecases/gamification/share_challenge_invite.dart';
import 'package:omni_runner/domain/value_objects/challenge_invite_link.dart';
import 'package:omni_runner/domain/value_objects/challenge_share_channel.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Post-creation screen: invite opponents via link or assessoria contacts.
///
/// Supports async challenges between runners in different cities by clearly
/// explaining how the challenge works (window, validation, etc.).
class ChallengeInviteScreen extends StatefulWidget {
  final ChallengeEntity challenge;

  const ChallengeInviteScreen({super.key, required this.challenge});

  @override
  State<ChallengeInviteScreen> createState() => _ChallengeInviteScreenState();
}

class _ChallengeInviteScreenState extends State<ChallengeInviteScreen> {
  late ChallengeEntity _challenge;
  bool _shared = false;

  final ShareChallengeInvite _shareInvite = ShareChallengeInvite();

  // L22-08: canonical deep link is now built via [ChallengeInviteLink]
  // so the host stays in lock-step with the `.well-known/*` verification
  // files served from `portal/public/.well-known/`.
  String get _deepLink =>
      ChallengeInviteLink.forId(_challenge.id).url;

  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
  }

  void _confirmClose(BuildContext context) {
    if (_shared || _challenge.acceptedCount > 1) {
      context.pop();
      return;
    }
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair sem compartilhar?'),
        content: const Text(
          'Você ainda não compartilhou o link. '
          'Sem oponentes, o desafio ficará pendente e poderá expirar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.pop();
            },
            child: const Text('Sair mesmo assim'),
          ),
        ],
      ),
    );
  }

  int get _pendingSlots {
    final accepted = _challenge.acceptedCount;
    if (_challenge.type == ChallengeType.oneVsOne) return 2 - accepted;
    return 50 - accepted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: _shared || _challenge.acceptedCount > 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose(context);
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Convidar Oponente'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmClose(context),
        ),
      ),
      body: BlocListener<ChallengesBloc, ChallengesState>(
        listener: (context, state) {
          if (state is ChallengeDetailLoaded) {
            setState(() => _challenge = state.challenge);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Convite enviado!')),
            );
          } else if (state is ChallengesError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Success header
            const Icon(Icons.check_circle_rounded,
                size: 56, color: DesignTokens.success),
            const SizedBox(height: 12),
            Text(
              'Desafio criado!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _challenge.title ?? _defaultTitle(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            // Async explanation card
            _AsyncExplainerCard(challenge: _challenge),
            const SizedBox(height: 20),

            // Share link section
            Text('Compartilhe o link do desafio',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: DesignTokens.spacingSm),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _deepLink,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.primary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    tooltip: 'Copiar link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _deepLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Link copiado!'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // L22-08: WhatsApp-specific button (viral loop between
            // friends). Routes through `wa.me/?text=<encoded>` via
            // url_launcher so Android App Links / iOS Universal
            // Links handle the deep link back into the app when the
            // recipient taps it.
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.chat_rounded),
              label: const Text('Convidar via WhatsApp'),
              onPressed: _shareViaWhatsApp,
            ),
            const SizedBox(height: 8),

            // Native share sheet (iOS/Android) — generic fallback
            // for recipients on Telegram, SMS, email, etc.
            OutlinedButton.icon(
              icon: const Icon(Icons.share_rounded),
              label: const Text('Outros apps'),
              onPressed: _shareViaNative,
            ),
            const SizedBox(height: 24),

            // Participants preview
            if (_challenge.participants.isNotEmpty) ...[
              Text('Participantes',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._challenge.participants.map((p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      p.status == ParticipantStatus.accepted
                          ? Icons.check_circle
                          : Icons.hourglass_empty,
                      color: p.status == ParticipantStatus.accepted
                          ? DesignTokens.success
                          : DesignTokens.warning,
                      size: 20,
                    ),
                    title: Text(p.displayName),
                    subtitle: Text(
                      p.status == ParticipantStatus.accepted
                          ? 'Confirmado'
                          : 'Aguardando',
                      style: theme.textTheme.bodySmall,
                    ),
                  )),
              if (_pendingSlots > 0)
                Padding(
                  padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
                  child: Text(
                    _challenge.type == ChallengeType.oneVsOne
                        ? 'Falta 1 oponente para iniciar'
                        : '$_pendingSlots vagas restantes',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                ),
            ],
            const SizedBox(height: 32),

            // Done button
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Concluir'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _shareViaWhatsApp() async {
    final intent = _shareInvite(
      challengeId: _challenge.id,
      channel: ChallengeShareChannel.whatsapp,
      challengeTitle: _challenge.title ?? _defaultTitle(),
    );
    final launchUrl = intent.platformLaunchUrl;
    if (launchUrl == null) return;
    final uri = Uri.parse(launchUrl);
    try {
      final ok = await launchUrl_(uri);
      if (ok) {
        _shared = true;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('WhatsApp não disponível. Usando compartilhamento nativo.')),
        );
        await _shareViaNative();
      }
    } on Object catch (e) {
      AppLogger.warn('WhatsApp launch failed: $e', tag: 'ChallengeInvite');
      if (!mounted) return;
      await _shareViaNative();
    }
  }

  Future<void> _shareViaNative() async {
    final intent = _shareInvite(
      challengeId: _challenge.id,
      channel: ChallengeShareChannel.native,
      challengeTitle: _challenge.title ?? _defaultTitle(),
    );
    _shared = true;
    await SharePlus.instance.share(ShareParams(text: intent.text));
  }

  // Thin wrapper around url_launcher so we can stub in tests.
  Future<bool> launchUrl_(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  String _defaultTitle() => switch (_challenge.type) {
        ChallengeType.oneVsOne => 'Desafio 1 vs 1',
        ChallengeType.group => 'Desafio em Grupo',
        ChallengeType.team => 'Desafio Time A vs B',
      };
}

/// Card explaining how async challenges work across different cities.
class _AsyncExplainerCard extends StatelessWidget {
  final ChallengeEntity challenge;

  const _AsyncExplainerCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isScheduled =
        challenge.rules.startMode == ChallengeStartMode.scheduled;
    final windowText = _formatWindow(challenge.rules.windowMs);

    return Card(
      elevation: 0,
      color: cs.primaryContainer.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: cs.primaryContainer.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Como funciona?',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.primary)),
              ],
            ),
            const SizedBox(height: 12),
            _step(theme, '1',
                'Envie o link para seu oponente (pode ser de qualquer cidade!)'),
            _step(theme, '2',
                isScheduled
                    ? 'O oponente aceita e aguarda a data agendada'
                    : 'Quando o oponente aceitar, o desafio começa automaticamente'),
            _step(theme, '3',
                'Cada um corre no seu local dentro da janela de $windowText'),
            _step(theme, '4',
                'Ao final do prazo, o resultado é calculado automaticamente'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Apenas corridas verificadas por GPS contam. '
                      'Distância mínima: '
                      '${(challenge.rules.minSessionDistanceM / 1000).toStringAsFixed(1)} km.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(ThemeData theme, String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(number,
                style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }

  static String _formatWindow(int ms) {
    if (ms < 3600000) return '${ms ~/ 60000} minutos';
    if (ms < 86400000) return '${ms ~/ 3600000} horas';
    final days = ms ~/ 86400000;
    return '$days ${days == 1 ? "dia" : "dias"}';
  }
}
