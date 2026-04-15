import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/presentation/widgets/state_widgets.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';

/// Screen for staff of an assessoria to view and respond to
/// incoming team challenge invitations from other assessorias.
class StaffChallengeInvitesScreen extends StatefulWidget {
  final String groupId;

  const StaffChallengeInvitesScreen({super.key, required this.groupId});

  @override
  State<StaffChallengeInvitesScreen> createState() =>
      _StaffChallengeInvitesScreenState();
}

class _StaffChallengeInvitesScreenState
    extends State<StaffChallengeInvitesScreen> {
  static const _tag = 'StaffChallengeInvites';

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<_InviteData> _invites = [];

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    if (!AppConfig.isSupabaseReady) {
      setState(() {
        _loading = false;
        _error = 'Backend indisponível';
      });
      return;
    }

    try {
      final db = sl<SupabaseClient>();

      final res = await db
          .from('challenge_team_invites')
          .select('id, challenge_id, to_group_id, status, created_at')
          .eq('to_group_id', widget.groupId)
          .order('created_at', ascending: false)
          .limit(50);

      final rows = (res as List).cast<Map<String, dynamic>>();

      if (rows.isEmpty) {
        setState(() {
          _invites = [];
          _loading = false;
        });
        return;
      }

      final challengeIds =
          rows.map((r) => r['challenge_id'] as String).toSet().toList();

      // Fetch challenges to get team_a_group_id (the from-group)
      final challengeRes = await db
          .from('challenges')
          .select('id, title, type, metric, entry_fee_coins, window_ms, team_a_group_id')
          .inFilter('id', challengeIds);

      final challengeMap = <String, Map<String, dynamic>>{};
      for (final c in (challengeRes as List).cast<Map<String, dynamic>>()) {
        challengeMap[c['id'] as String] = c;
      }

      // Collect team_a_group_ids to resolve names
      final fromGroupIds = challengeMap.values
          .map((c) => c['team_a_group_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final groupNameMap = <String, String>{};
      if (fromGroupIds.isNotEmpty) {
        final groupRes = await db
            .from('coaching_groups')
            .select('id, name')
            .inFilter('id', fromGroupIds);

        for (final g in (groupRes as List).cast<Map<String, dynamic>>()) {
          groupNameMap[g['id'] as String] = g['name'] as String;
        }
      }

      final invites = rows.map((r) {
        final ch = challengeMap[r['challenge_id']];
        final windowMs = (ch?['window_ms'] as num?)?.toInt() ?? 0;
        final days = (windowMs / 86400000).round();
        final fromGroupId = ch?['team_a_group_id'] as String?;

        return _InviteData(
          inviteId: r['id'] as String,
          challengeId: r['challenge_id'] as String,
          status: r['status'] as String,
          fromGroupName: fromGroupId != null
              ? (groupNameMap[fromGroupId] ?? 'Assessoria desconhecida')
              : 'Assessoria desconhecida',
          challengeTitle: ch?['title'] as String? ?? 'Desafio de Equipe',
          metric: ch?['metric'] as String? ?? 'distance',
          entryFeeCoins: (ch?['entry_fee_coins'] as num?)?.toInt() ?? 0,
          windowDays: days,
        );
      }).toList();

      setState(() {
        _invites = invites;
        _loading = false;
      });
    } on Object catch (e) {
      AppLogger.warn('Failed to load challenge invites: $e', tag: _tag);
      setState(() {
        _error = 'Erro ao carregar convites';
        _loading = false;
      });
    }
  }

  Future<void> _respond(String inviteId, bool accept) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _loading = true;
    });
    try {
      await sl<SupabaseClient>().functions.invoke(
        'challenge-accept-group-invite',
        body: {'invite_id': inviteId, 'accept': accept},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accept ? 'Convite aceito!' : 'Convite recusado.'),
        ));
        await _loadInvites();
      }
    } on Object catch (e) {
      AppLogger.warn('Failed to respond to invite: $e', tag: _tag);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao responder convite. Tente novamente.'),
        ));
        setState(() => _loading = false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desafios Recebidos'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(
                  message: _error ?? '',
                  onRetry: () {
                    setState(() {
                      _error = null;
                      _loading = true;
                    });
                    _loadInvites();
                  },
                )
              : _invites.isEmpty
                  ? const AppEmptyState(
                      message: 'Nenhum convite de desafio',
                      icon: Icons.shield_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: _loadInvites,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(DesignTokens.spacingMd),
                        itemCount: _invites.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            _InviteCard(invite: _invites[i], onRespond: _respond),
                      ),
                    ),
    );
  }
}

class _InviteData {
  final String inviteId;
  final String challengeId;
  final String status;
  final String fromGroupName;
  final String challengeTitle;
  final String metric;
  final int entryFeeCoins;
  final int windowDays;

  const _InviteData({
    required this.inviteId,
    required this.challengeId,
    required this.status,
    required this.fromGroupName,
    required this.challengeTitle,
    required this.metric,
    required this.entryFeeCoins,
    required this.windowDays,
  });

  bool get isPending => status == 'pending';
}

class _InviteCard extends StatelessWidget {
  final _InviteData invite;
  final Future<void> Function(String inviteId, bool accept) onRespond;

  const _InviteCard({required this.invite, required this.onRespond});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final metricLabel = switch (invite.metric) {
      'pace' => 'Pace',
      'time' => 'Tempo',
      _ => 'Distância',
    };

    final statusColor = switch (invite.status) {
      'accepted' => DesignTokens.success,
      'declined' => DesignTokens.error,
      _ => DesignTokens.warning,
    };
    final statusLabel = switch (invite.status) {
      'accepted' => 'Aceito',
      'declined' => 'Recusado',
      _ => 'Pendente',
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: DesignTokens.spacingXs),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.shield_rounded,
                    size: 20, color: cs.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              invite.challengeTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Desafiante: ${invite.fromGroupName}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _InfoChip(
                    icon: Icons.straighten, label: metricLabel),
                _InfoChip(
                    icon: Icons.calendar_today,
                    label: '${invite.windowDays} dia${invite.windowDays != 1 ? "s" : ""}'),
                if (invite.entryFeeCoins > 0)
                  _InfoChip(
                      icon: Icons.toll,
                      label: '${invite.entryFeeCoins} OmniCoins/atleta'),
              ],
            ),
            if (invite.isPending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onRespond(invite.inviteId, false),
                      child: const Text('Recusar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => onRespond(invite.inviteId, true),
                      child: const Text('Aceitar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
