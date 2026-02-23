import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';

/// Staff screen to view and respond to championship invitations
/// received by their assessoria from other groups.
class StaffChampionshipInvitesScreen extends StatefulWidget {
  final String groupId;

  const StaffChampionshipInvitesScreen({super.key, required this.groupId});

  @override
  State<StaffChampionshipInvitesScreen> createState() =>
      _StaffChampionshipInvitesScreenState();
}

class _StaffChampionshipInvitesScreenState
    extends State<StaffChampionshipInvitesScreen> {
  static const _tag = 'ChampInvites';

  bool _loading = true;
  String? _error;
  List<_InviteItem> _invites = [];

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    try {
      final res = await _db
          .from('championship_invites')
          .select('id, championship_id, status, created_at')
          .eq('to_group_id', widget.groupId)
          .order('created_at', ascending: false);

      final rows = (res as List).cast<Map<String, dynamic>>();

      // Fetch championship details
      final champIds = rows.map((r) => r['championship_id'] as String).toSet().toList();
      Map<String, Map<String, dynamic>> champMap = {};
      if (champIds.isNotEmpty) {
        final champsRes = await _db
            .from('championships')
            .select('id, name, metric, status, start_at, end_at, host_group_id')
            .inFilter('id', champIds);
        for (final c in (champsRes as List)) {
          champMap[c['id'] as String] = c as Map<String, dynamic>;
        }
      }

      // Fetch host group names
      final hostGroupIds = champMap.values.map((c) => c['host_group_id'] as String).toSet().toList();
      Map<String, String> hostNames = {};
      if (hostGroupIds.isNotEmpty) {
        final groupsRes = await _db
            .from('coaching_groups')
            .select('id, name')
            .inFilter('id', hostGroupIds);
        for (final g in (groupsRes as List)) {
          hostNames[g['id'] as String] = (g['name'] as String?) ?? '';
        }
      }

      _invites = rows.map((r) {
        final champId = r['championship_id'] as String;
        final champ = champMap[champId];
        return _InviteItem(
          id: r['id'] as String,
          championshipId: champId,
          inviteStatus: (r['status'] as String?) ?? 'pending',
          champName: (champ?['name'] as String?) ?? 'Campeonato',
          champMetric: (champ?['metric'] as String?) ?? 'distance',
          champStatus: (champ?['status'] as String?) ?? '',
          hostGroupName: hostNames[champ?['host_group_id'] as String? ?? ''] ?? '',
          startAt: DateTime.tryParse((champ?['start_at'] as String?) ?? ''),
          endAt: DateTime.tryParse((champ?['end_at'] as String?) ?? ''),
        );
      }).toList();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      AppLogger.error('Load invites failed: $e', tag: _tag, error: e);
      if (mounted) setState(() { _error = 'Erro ao carregar convites.'; _loading = false; });
    }
  }

  Future<void> _respond(_InviteItem invite, bool accept) async {
    final label = accept ? 'aceitar' : 'recusar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${accept ? 'Aceitar' : 'Recusar'} convite?'),
        content: Text('Campeonato: ${invite.champName}\n'
            'Organizado por: ${invite.hostGroupName}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: accept ? null : FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(accept ? 'Aceitar' : 'Recusar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await _db.functions.invoke('champ-accept-invite', body: {
        'invite_id': invite.id,
        'accept': accept,
      });
      final data = res.data as Map<String, dynamic>? ?? {};
      if (data['ok'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Convite ${accept ? 'aceito' : 'recusado'}!')),
          );
        }
        _load();
      } else {
        final err = data['error'] as Map<String, dynamic>?;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err?['message'] as String? ?? 'Erro ao $label.')),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Respond invite failed: $e', tag: _tag, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao $label convite.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Convites de campeonatos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Tentar novamente')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _invites.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Column(children: [
                            Icon(Icons.mail_outline_rounded, size: 56, color: theme.colorScheme.outline),
                            const SizedBox(height: 16),
                            Text('Nenhum convite recebido', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text('Quando outra assessoria convidar\nsua equipe, o convite aparecerá aqui.', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ])),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: _invites.length,
                          itemBuilder: (_, i) => _InviteCard(
                            invite: _invites[i],
                            onAccept: _invites[i].inviteStatus == 'pending'
                                ? () => _respond(_invites[i], true)
                                : null,
                            onDecline: _invites[i].inviteStatus == 'pending'
                                ? () => _respond(_invites[i], false)
                                : null,
                          ),
                        ),
                ),
    );
  }
}

class _InviteItem {
  final String id, championshipId, inviteStatus, champName, champMetric, champStatus, hostGroupName;
  final DateTime? startAt, endAt;
  const _InviteItem({required this.id, required this.championshipId, required this.inviteStatus, required this.champName, required this.champMetric, required this.champStatus, required this.hostGroupName, this.startAt, this.endAt});
}

class _InviteCard extends StatelessWidget {
  final _InviteItem invite;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const _InviteCard({required this.invite, this.onAccept, this.onDecline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPending = invite.inviteStatus == 'pending';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_rounded, size: 22, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(child: Text(invite.champName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                if (!isPending) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (invite.inviteStatus == 'accepted' ? Colors.green : Colors.red).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    invite.inviteStatus == 'accepted' ? 'Aceito' : 'Recusado',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: invite.inviteStatus == 'accepted' ? Colors.green : Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Organizado por: ${invite.hostGroupName}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _chip(Icons.speed_rounded, _metricLabel(invite.champMetric), cs),
              if (invite.startAt != null) _chip(Icons.calendar_today_rounded, _fmtDate(invite.startAt!), cs),
              if (invite.endAt != null) _chip(Icons.event_rounded, _fmtDate(invite.endAt!), cs),
            ]),
            if (isPending) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Aceitar'),
                      onPressed: onAccept,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Recusar'),
                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                      onPressed: onDecline,
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

  Widget _chip(IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  static String _metricLabel(String m) => switch (m) { 'distance' => 'Distância', 'time' => 'Tempo', 'pace' => 'Pace', 'sessions' => 'Sessões', 'elevation' => 'Elevação', _ => m };
  static String _fmtDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}
