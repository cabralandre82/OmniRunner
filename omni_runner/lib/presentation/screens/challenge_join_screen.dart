import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/widgets/login_required_sheet.dart';
import 'package:omni_runner/presentation/widgets/success_overlay.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Screen shown when a user opens a challenge deep link.
///
/// Fetches challenge details from the backend (not local Isar), shows
/// a summary, and lets the user join with a single tap.
class ChallengeJoinScreen extends StatefulWidget {
  final String challengeId;

  const ChallengeJoinScreen({super.key, required this.challengeId});

  @override
  State<ChallengeJoinScreen> createState() => _ChallengeJoinScreenState();
}

class _ChallengeJoinScreenState extends State<ChallengeJoinScreen> {
  static const _tag = 'ChallengeJoin';

  bool _loading = true;
  bool _joining = false;
  String? _error;
  _ChallengeData? _challenge;
  List<_ParticipantData> _participants = [];
  String _callerUserId = '';
  bool _alreadyJoined = false;
  String? _selectedTeam;

  SupabaseClient get _db => sl<SupabaseClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _db.functions.invoke('challenge-get', body: {
        'challenge_id': widget.challengeId,
      });

      final data = res.data as Map<String, dynamic>? ?? {};

      if (data['ok'] != true) {
        final err = data['error'] as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _error = err?['message'] as String? ?? 'Desafio não encontrado.';
            _loading = false;
          });
        }
        return;
      }

      final cData = data['challenge'] as Map<String, dynamic>;
      _callerUserId = (data['caller_user_id'] as String?) ?? '';

      _challenge = _ChallengeData(
        id: cData['id'] as String,
        creatorUserId: cData['creator_user_id'] as String,
        status: (cData['status'] as String?) ?? 'pending',
        type: (cData['type'] as String?) ?? 'one_vs_one',
        title: cData['title'] as String?,
        goal: (cData['goal'] as String?) ?? (cData['metric'] as String?) ?? 'most_distance',
        target: (cData['target'] as num?)?.toDouble(),
        windowMs: (cData['window_ms'] as num?)?.toInt() ?? 0,
        startMode: (cData['start_mode'] as String?) ?? 'on_accept',
        fixedStartMs: (cData['fixed_start_ms'] as num?)?.toInt(),
        entryFeeCoins: (cData['entry_fee_coins'] as num?)?.toInt() ?? 0,
        minSessionDistanceM: (cData['min_session_distance_m'] as num?)?.toDouble() ?? 1000,
      );

      final parts = (data['participants'] as List<dynamic>?) ?? [];
      _participants = parts.map((p) {
        final m = p as Map<String, dynamic>;
        return _ParticipantData(
          userId: (m['user_id'] as String?) ?? '',
          displayName: (m['display_name'] as String?) ?? 'Corredor',
          status: (m['status'] as String?) ?? 'invited',
        );
      }).toList();

      _alreadyJoined = _participants.any(
        (p) => p.userId == _callerUserId && p.status == 'accepted',
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      AppLogger.error('Load challenge failed: $e', tag: _tag, error: e);
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar o desafio.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _join() async {
    if (LoginRequiredSheet.guard(context, feature: 'Desafios')) return;

    setState(() => _joining = true);

    try {
      final displayName = sl<UserIdentityProvider>().displayName;

      final payload = <String, dynamic>{
        'challenge_id': widget.challengeId,
        'display_name': displayName,
      };
      if (_challenge?.type == 'team' && _selectedTeam != null) {
        payload['team'] = _selectedTeam;
      }

      final res = await _db.functions.invoke('challenge-join', body: payload);

      final data = res.data as Map<String, dynamic>? ?? {};

      if (data['ok'] == true) {
        if (mounted) {
          final newStatus = data['status'] as String? ?? 'pending';
          showSuccessOverlay(
            context,
            message: newStatus == 'active'
                ? 'Desafio aceito e iniciado!'
                : 'Desafio aceito!',
          );
          setState(() {
            _alreadyJoined = true;
            _joining = false;
          });
          _load();
        }
      } else {
        final err = data['error'] as Map<String, dynamic>?;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err?['message'] as String? ?? 'Erro ao aceitar desafio.'),
            ),
          );
          setState(() => _joining = false);
        }
      }
    } catch (e) {
      AppLogger.error('Join challenge failed: $e', tag: _tag, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao aceitar desafio.')),
        );
        setState(() => _joining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Convite de Desafio')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(theme)
              : _buildContent(theme, cs),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme cs) {
    final c = _challenge!;
    final isCreator = c.creatorUserId == _callerUserId;
    final canJoin = c.status == 'pending' && !isCreator && !_alreadyJoined;
    final creatorName = _participants
        .where((p) => p.userId == c.creatorUserId)
        .map((p) => p.displayName)
        .firstOrNull ?? 'Corredor';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        const Icon(Icons.emoji_events_rounded,
            size: 56, color: DesignTokens.warning),
        const SizedBox(height: 12),
        Text(
          c.title ?? _defaultTitle(c.type),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Criado por $creatorName',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),

        // Rules card
        Card(
          elevation: 0,
          color: cs.primaryContainer.withValues(alpha: 0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.primaryContainer.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.rule_rounded, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('Regras do desafio',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                _ruleRow(theme, 'Tipo', switch (c.type) {
                  'one_vs_one' => '1 vs 1 (duelo direto)',
                  'team' => 'Time A vs Time B',
                  'group' => 'Grupo competitivo (ranking individual)',
                  _ => 'Grupo',
                }),
                _ruleRow(theme, 'Objetivo', _goalLabel(c.goal)),
                if (c.target != null)
                  _ruleRow(theme, 'Distância', '${(c.target! / 1000).toStringAsFixed(1)} km'),
                _ruleRow(theme, 'Duração', _formatWindow(c.windowMs)),
                _ruleRow(theme, 'Início',
                    c.startMode == 'on_accept'
                        ? 'Quando todos aceitarem'
                        : 'Agendado'),
                _ruleRow(theme, 'Corrida mínima',
                    '${(c.minSessionDistanceM / 1000).toStringAsFixed(1)} km'),
                if (c.entryFeeCoins > 0)
                  _ruleRow(theme, 'Inscrição', '${c.entryFeeCoins} OmniCoins'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Explainer
        Card(
          elevation: 0,
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
                const SizedBox(height: 10),
                Text(
                  'Cada corredor corre no seu local, na hora que quiser, '
                  'dentro do prazo de ${_formatWindow(c.windowMs)}. '
                  'Funciona em qualquer cidade! '
                  'Apenas corridas verificadas por GPS contam.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Winner determination explainer
        Card(
          elevation: 0,
          color: cs.secondaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.secondaryContainer),
          ),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.emoji_events_rounded, size: 20, color: cs.secondary),
                    const SizedBox(width: 8),
                    Text('Como o vencedor é decidido',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold, color: cs.secondary)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _winnerExplain(c.type, c.goal),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSecondaryContainer, height: 1.5),
                ),
                if (c.entryFeeCoins > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    _prizeExplain(c.type, c.entryFeeCoins),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Participants
        Text('Participantes (${_participants.where((p) => p.status == 'accepted').length})',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._participants.map((p) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                p.status == 'accepted'
                    ? Icons.check_circle
                    : Icons.hourglass_empty,
                color:
                    p.status == 'accepted' ? DesignTokens.success : DesignTokens.warning,
                size: 20,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(p.displayName,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (p.userId == _callerUserId) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Você',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onPrimary, fontSize: 10)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                p.status == 'accepted' ? 'Confirmado' : 'Aguardando',
                style: theme.textTheme.bodySmall,
              ),
            )),
        const SizedBox(height: 24),

        // Team selection for team challenges
        if (canJoin && c.type == 'team') ...[
          Text('Escolha seu time',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TeamButton(
                  label: 'Time A',
                  color: DesignTokens.primary,
                  selected: _selectedTeam == 'A',
                  onTap: () => setState(() => _selectedTeam = 'A'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TeamButton(
                  label: 'Time B',
                  color: DesignTokens.error,
                  selected: _selectedTeam == 'B',
                  onTap: () => setState(() => _selectedTeam = 'B'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Join button
        if (canJoin)
          FilledButton.icon(
            onPressed: _joining
                ? null
                : (c.type == 'team' && _selectedTeam == null)
                    ? null
                    : _join,
            icon: _joining
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_joining ? 'Aceitando...' : 'Aceitar Desafio'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

        if (_alreadyJoined)
          Container(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            decoration: BoxDecoration(
              color: DesignTokens.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DesignTokens.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: DesignTokens.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Você já está participando deste desafio!',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

        if (isCreator)
          Container(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Você criou este desafio. Compartilhe o link para convidar oponentes!',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

        if (c.status != 'pending')
          Container(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(_statusIcon(c.status), color: _statusColor(c.status)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Desafio ${_statusLabel(c.status).toLowerCase()}.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _ruleRow(ThemeData theme, String label, String value) {
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
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  static String _defaultTitle(String type) => switch (type) {
        'one_vs_one' => 'Desafio 1v1',
        'team' => 'Desafio de Time',
        _ => 'Desafio em Grupo',
      };

  static String _goalLabel(String m) => switch (m) {
        'fastest_at_distance' => 'Quem corre a distância mais rápido',
        'most_distance' => 'Quem acumula mais km no período',
        'best_pace_at_distance' => 'Quem faz o melhor pace na distância',
        'collective_distance' => 'Meta coletiva (km somam)',
        'distance' => 'Quem acumula mais km no período',
        'pace' => 'Quem faz o melhor pace na distância',
        _ => m,
      };

  static String _formatWindow(int ms) {
    if (ms < 3600000) return '${ms ~/ 60000} minutos';
    if (ms < 86400000) {
      final h = ms ~/ 3600000;
      return '$h ${h == 1 ? "hora" : "horas"}';
    }
    final days = ms ~/ 86400000;
    return '$days ${days == 1 ? "dia" : "dias"}';
  }

  static String _statusLabel(String s) => switch (s) {
        'pending' => 'Aguardando',
        'active' => 'Em andamento',
        'completing' => 'Finalizando',
        'completed' => 'Concluído',
        'cancelled' => 'Cancelado',
        'expired' => 'Expirado',
        _ => s,
      };

  static IconData _statusIcon(String s) => switch (s) {
        'active' => Icons.directions_run,
        'completing' => Icons.timer,
        'completed' => Icons.emoji_events,
        'cancelled' => Icons.cancel_outlined,
        'expired' => Icons.schedule,
        _ => Icons.hourglass_empty,
      };

  static Color _statusColor(String s) => switch (s) {
        'pending' => DesignTokens.warning,
        'active' => DesignTokens.success,
        'completing' => DesignTokens.primary,
        'completed' => DesignTokens.info,
        'cancelled' => DesignTokens.error,
        'expired' => DesignTokens.textMuted,
        _ => DesignTokens.textMuted,
      };

  static String _winnerExplain(String type, String goal) {
    if (type == 'team') {
      return switch (goal) {
        'fastest_at_distance' =>
          'Cada membro do time corre a distância. O tempo do time = tempo do ULTIMO membro a completar. Ganha o time que completar mais rapido.',
        'most_distance' =>
          'Os km de todos os membros somam. Ganha o time com mais km totais.',
        'best_pace_at_distance' =>
          'Pace do time = media dos paces dos membros. Ganha o time com o menor pace medio.',
        _ => 'O grupo soma km para atingir a meta.',
      };
    }
    if (goal == 'collective_distance') {
      return 'Cooperativo por time: cada membro corre o que puder - os km do time somam. O time com mais km vence e leva os coins do adversário.';
    }
    return switch (goal) {
      'fastest_at_distance' =>
        'Cada corredor faz uma corrida cobrindo a distancia. Ganha quem completar no menor tempo.',
      'most_distance' =>
        'Pode correr quantas vezes quiser no periodo. Ganha quem acumular mais km no total.',
      'best_pace_at_distance' =>
        'Cada corredor faz uma corrida cobrindo a distancia minima. Ganha quem tiver o menor pace medio (min/km).',
      _ => 'O vencedor e decidido pelo resultado da corrida.',
    };
  }

  static String _prizeExplain(String type, int fee) {
    return switch (type) {
      'one_vs_one' =>
        'Premio: O vencedor leva $fee OmniCoins do oponente. Empate: todos recebem de volta.',
      'group' =>
        'Premio: O 1.o lugar leva todo o pool. Empate: divisao igual entre empatados.',
      'team' =>
        'Premio: Cada membro do time vencedor recebe o dobro da inscricao. Empate: todos recebem de volta.',
      _ =>
        'Premio: Distribuido conforme resultado.',
    };
  }
}

class _ChallengeData {
  final String id, creatorUserId, status, type, goal, startMode;
  final String? title;
  final double? target;
  final int windowMs, entryFeeCoins;
  final int? fixedStartMs;
  final double minSessionDistanceM;

  const _ChallengeData({
    required this.id,
    required this.creatorUserId,
    required this.status,
    required this.type,
    required this.title,
    required this.goal,
    required this.target,
    required this.windowMs,
    required this.startMode,
    required this.fixedStartMs,
    required this.entryFeeCoins,
    required this.minSessionDistanceM,
  });
}

class _ParticipantData {
  final String userId, displayName, status;
  const _ParticipantData({
    required this.userId,
    required this.displayName,
    required this.status,
  });
}

class _TeamButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TeamButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : DesignTokens.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.shield_rounded, size: 32,
                color: selected ? color : DesignTokens.textMuted),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: selected ? color : DesignTokens.textMuted,
                )),
          ],
        ),
      ),
    );
  }
}
