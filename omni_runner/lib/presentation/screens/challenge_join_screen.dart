import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/widgets/login_required_sheet.dart';

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
  String? _callerGroupId;
  bool _alreadyJoined = false;

  SupabaseClient get _db => Supabase.instance.client;

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
      _callerGroupId = data['caller_group_id'] as String?;

      _challenge = _ChallengeData(
        id: cData['id'] as String,
        creatorUserId: cData['creator_user_id'] as String,
        status: (cData['status'] as String?) ?? 'pending',
        type: (cData['type'] as String?) ?? 'one_vs_one',
        title: cData['title'] as String?,
        metric: (cData['metric'] as String?) ?? 'distance',
        target: (cData['target'] as num?)?.toDouble(),
        windowMs: (cData['window_ms'] as num?)?.toInt() ?? 0,
        startMode: (cData['start_mode'] as String?) ?? 'on_accept',
        fixedStartMs: (cData['fixed_start_ms'] as num?)?.toInt(),
        entryFeeCoins: (cData['entry_fee_coins'] as num?)?.toInt() ?? 0,
        minSessionDistanceM: (cData['min_session_distance_m'] as num?)?.toDouble() ?? 1000,
        teamAGroupName: cData['team_a_group_name'] as String?,
        teamBGroupName: cData['team_b_group_name'] as String?,
        teamAGroupId: cData['team_a_group_id'] as String?,
        teamBGroupId: cData['team_b_group_id'] as String?,
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

      final res = await _db.functions.invoke('challenge-join', body: {
        'challenge_id': widget.challengeId,
        'display_name': displayName,
      });

      final data = res.data as Map<String, dynamic>? ?? {};

      if (data['ok'] == true) {
        if (mounted) {
          final newStatus = data['status'] as String? ?? 'pending';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newStatus == 'active'
                    ? 'Desafio aceito e iniciado! Boa corrida!'
                    : 'Desafio aceito! Aguardando início.',
              ),
              backgroundColor: Colors.green,
            ),
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
        padding: const EdgeInsets.all(32),
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
    final bool teamOk;
    if (c.isTeamVsTeam) {
      final cData = _challenge!;
      teamOk = _callerGroupId != null &&
          (_callerGroupId == (cData.teamAGroupId) ||
           _callerGroupId == (cData.teamBGroupId));
    } else {
      teamOk = true;
    }
    final canJoin = c.status == 'pending' && !isCreator && !_alreadyJoined && teamOk;
    final creatorName = _participants
        .where((p) => p.userId == c.creatorUserId)
        .map((p) => p.displayName)
        .firstOrNull ?? 'Corredor';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Icon(Icons.emoji_events_rounded,
            size: 56, color: Colors.amber.shade700),
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
            padding: const EdgeInsets.all(16),
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
                  'one_vs_one' => '1v1',
                  'team_vs_team' => 'Equipe vs Equipe',
                  _ => 'Grupo',
                }),
                if (c.isTeamVsTeam && c.teamAGroupName != null)
                  _ruleRow(theme, 'Equipe A', c.teamAGroupName!),
                if (c.isTeamVsTeam && c.teamBGroupName != null)
                  _ruleRow(theme, 'Equipe B', c.teamBGroupName!),
                _ruleRow(theme, 'Modalidade', _metricLabel(c.metric)),
                if (c.target != null)
                  _ruleRow(theme, 'Meta', _formatTarget(c.target!, c.metric)),
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
            padding: const EdgeInsets.all(16),
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
                    p.status == 'accepted' ? Colors.green : Colors.orange,
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

        // Join button
        if (canJoin)
          FilledButton.icon(
            onPressed: _joining ? null : _join,
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
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
            padding: const EdgeInsets.all(16),
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

        if (c.isTeamVsTeam && !teamOk && !isCreator && !_alreadyJoined && c.status == 'pending')
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sua assessoria não participa deste desafio. '
                    'Apenas atletas das equipes convidadas podem entrar.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

        if (c.status != 'pending')
          Container(
            padding: const EdgeInsets.all(16),
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
        'team_vs_team' => 'Desafio de Equipe',
        _ => 'Desafio em Grupo',
      };

  static String _metricLabel(String m) => switch (m) {
        'distance' => 'Distância',
        'pace' => 'Pace',
        'time' => 'Tempo',
        _ => m,
      };

  static String _formatTarget(double value, String metric) => switch (metric) {
        'distance' => '${(value / 1000).toStringAsFixed(1)} km',
        'pace' => '${(value / 60).toStringAsFixed(1)} min/km',
        'time' => '${(value / 60000).toStringAsFixed(0)} min',
        _ => value.toStringAsFixed(1),
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
        'pending' => Colors.orange,
        'active' => Colors.green,
        'completing' => Colors.blue,
        'completed' => Colors.teal,
        'cancelled' => Colors.red,
        'expired' => Colors.grey,
        _ => Colors.grey,
      };
}

class _ChallengeData {
  final String id, creatorUserId, status, type, metric, startMode;
  final String? title;
  final double? target;
  final int windowMs, entryFeeCoins;
  final int? fixedStartMs;
  final double minSessionDistanceM;
  final String? teamAGroupName, teamBGroupName;
  final String? teamAGroupId, teamBGroupId;

  const _ChallengeData({
    required this.id,
    required this.creatorUserId,
    required this.status,
    required this.type,
    required this.title,
    required this.metric,
    required this.target,
    required this.windowMs,
    required this.startMode,
    required this.fixedStartMs,
    required this.entryFeeCoins,
    required this.minSessionDistanceM,
    this.teamAGroupName,
    this.teamBGroupName,
    this.teamAGroupId,
    this.teamBGroupId,
  });

  bool get isTeamVsTeam => type == 'team_vs_team';
}

class _ParticipantData {
  final String userId, displayName, status;
  const _ParticipantData({
    required this.userId,
    required this.displayName,
    required this.status,
  });
}
