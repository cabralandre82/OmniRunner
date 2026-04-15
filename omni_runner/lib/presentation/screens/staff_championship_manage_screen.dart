import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';

/// Staff screen for managing a single championship: open it, invite groups,
/// view invites, and see participants.
///
/// Calls Edge Functions: champ-open, champ-invite, champ-accept-invite,
/// champ-participant-list.
class StaffChampionshipManageScreen extends StatefulWidget {
  final String championshipId;
  final String hostGroupId;

  const StaffChampionshipManageScreen({
    super.key,
    required this.championshipId,
    required this.hostGroupId,
  });

  @override
  State<StaffChampionshipManageScreen> createState() =>
      _StaffChampionshipManageScreenState();
}

class _StaffChampionshipManageScreenState
    extends State<StaffChampionshipManageScreen> {
  static const _tag = 'ChampManage';

  bool _loading = true;
  bool _busy = false;
  String? _error;
  _ChampData? _champ;
  List<_InviteData> _invites = [];
  List<_ParticipantData> _participants = [];

  SupabaseClient get _db => sl<SupabaseClient>();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Load championship details
      final champRes = await _db
          .from('championships')
          .select('id, name, description, metric, status, requires_badge, max_participants, start_at, end_at')
          .eq('id', widget.championshipId)
          .maybeSingle();

      if (champRes == null) {
        if (mounted) setState(() { _error = 'Campeonato não encontrado.'; _loading = false; });
        return;
      }

      _champ = _ChampData(
        id: champRes['id'] as String,
        name: (champRes['name'] as String?) ?? '',
        description: (champRes['description'] as String?) ?? '',
        metric: (champRes['metric'] as String?) ?? 'distance',
        status: (champRes['status'] as String?) ?? 'draft',
        requiresBadge: (champRes['requires_badge'] as bool?) ?? false,
        maxParticipants: champRes['max_participants'] as int?,
        startAt: DateTime.tryParse((champRes['start_at'] as String?) ?? ''),
        endAt: DateTime.tryParse((champRes['end_at'] as String?) ?? ''),
      );

      // Load invites
      final inviteRes = await _db
          .from('championship_invites')
          .select('id, to_group_id, status, created_at')
          .eq('championship_id', widget.championshipId)
          .order('created_at', ascending: false);

      final inviteRows = (inviteRes as List).cast<Map<String, dynamic>>();

      // Fetch group names for invites
      final groupIds = inviteRows.map((r) => r['to_group_id'] as String).toSet().toList();
      final Map<String, String> groupNames = {};
      if (groupIds.isNotEmpty) {
        final groupsRes = await _db
            .from('coaching_groups')
            .select('id, name')
            .inFilter('id', groupIds);
        for (final g in (groupsRes as List).cast<Map<String, dynamic>>()) {
          groupNames[g['id'] as String] = (g['name'] as String?) ?? '';
        }
      }

      _invites = inviteRows.map((r) => _InviteData(
        id: r['id'] as String,
        toGroupId: r['to_group_id'] as String,
        groupName: groupNames[r['to_group_id'] as String] ?? r['to_group_id'] as String,
        status: (r['status'] as String?) ?? 'pending',
      )).toList();

      // Load participants via EF (skip for draft — no participants yet)
      if (_champ!.status != 'draft') {
        try {
          final partRes = await _db.functions.invoke('champ-participant-list', body: {
            'championship_id': widget.championshipId,
          });
          final partData = partRes.data as Map<String, dynamic>? ?? {};
          final partList = (partData['participants'] as List<dynamic>?) ?? [];

          _participants = partList.map((p) {
            final m = p as Map<String, dynamic>;
            return _ParticipantData(
              userId: (m['user_id'] as String?) ?? '',
              displayName: (m['display_name'] as String?) ?? 'Atleta',
              groupId: (m['group_id'] as String?) ?? '',
              status: (m['status'] as String?) ?? 'enrolled',
              progressValue: ((m['progress_value'] as num?) ?? 0).toDouble(),
              finalRank: m['final_rank'] as int?,
            );
          }).toList();
        } on Object catch (e) {
          AppLogger.warn('Load participants failed (non-fatal): $e', tag: _tag);
          _participants = [];
        }
      } else {
        _participants = [];
      }

      if (mounted) setState(() => _loading = false);
    } on Object catch (e) {
      AppLogger.error('Load championship failed: $e', tag: _tag, error: e);
      if (mounted) {
        setState(() { _error = 'Erro ao carregar campeonato.'; _loading = false; });
      }
    }
  }

  Future<void> _openChampionship() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir campeonato?'),
        content: const Text(
          'Ao abrir, atletas poderão se inscrever. '
          'Você pode convidar assessorias antes ou depois.',
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Abrir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await _db.functions.invoke('champ-open', body: {
        'championship_id': widget.championshipId,
      });
      final data = res.data as Map<String, dynamic>? ?? {};
      if (data['ok'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Campeonato aberto para inscrições!')),
          );
        }
        _loadAll();
      } else {
        final err = data['error'] as Map<String, dynamic>?;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err?['message'] as String? ?? 'Erro ao abrir campeonato.')),
          );
        }
      }
    } on Object catch (e) {
      AppLogger.error('Open championship failed: $e', tag: _tag, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao abrir campeonato.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _generateBadgeQr() {
    context.push(AppRoutes.staffGenerateQr, extra: StaffGenerateQrExtra(
      type: TokenIntentType.champBadgeActivate,
      groupId: widget.hostGroupId,
      championshipId: widget.championshipId,
    ));
  }

  Future<void> _cancelChampionship() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar campeonato?'),
        content: const Text(
          'Essa ação é irreversível. Todos os participantes inscritos '
          'serão retirados e convites pendentes serão revogados.',
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            style: FilledButton.styleFrom(backgroundColor: DesignTokens.error),
            child: const Text('Cancelar campeonato'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await _db.functions.invoke('champ-cancel', body: {
        'championship_id': widget.championshipId,
      });
      final data = res.data as Map<String, dynamic>? ?? {};
      if (data['ok'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Campeonato cancelado.')),
          );
        }
        _loadAll();
      } else {
        final err = data['error'] as Map<String, dynamic>?;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err?['message'] as String? ?? 'Erro ao cancelar.')),
          );
        }
      }
    } on Exception catch (e) {
      AppLogger.error('Cancel championship failed: $e', tag: _tag, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao cancelar campeonato.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteGroup() async {
    if (_busy) return;
    final List<Map<String, String>> availableGroups = [];
    try {
      final rows = await _db
          .rpc('fn_list_partnerships', params: {'p_group_id': widget.hostGroupId});
      final invitedIds = _invites.map((i) => i.toGroupId).toSet();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        if (r['status'] != 'accepted') continue;
        final gid = r['partner_group_id'] as String;
        if (!invitedIds.contains(gid)) {
          availableGroups.add({
            'id': gid,
            'name': (r['partner_name'] as String?) ?? gid,
          });
        }
      }
    } on Exception catch (e) {
      AppLogger.warn('Partner fetch failed', tag: 'StaffChampionshipManage', error: e);
    }

    if (!mounted) return;

    if (availableGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma assessoria parceira disponível. '
            'Adicione parceiras em Painel → Parceiras.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convidar assessoria parceira'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Apenas assessorias da sua lista de parceiras podem ser convidadas.',
                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  )),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: availableGroups.length > 5 ? 250 : null,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableGroups.length,
                  itemBuilder: (_, i) {
                    final g = availableGroups[i];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        child: Text(
                          g['name']!.isNotEmpty ? g['name']![0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(g['name'] ?? ''),
                      onTap: () => ctx.pop(g['id']),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selected == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await _db.functions.invoke('champ-invite', body: {
        'championship_id': widget.championshipId,
        'to_group_id': selected,
      });
      final data = res.data as Map<String, dynamic>? ?? {};
      if (data['ok'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Convite enviado!')),
          );
        }
        _loadAll();
      } else {
        final err = data['error'] as Map<String, dynamic>?;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err?['message'] as String? ?? 'Erro ao convidar.')),
          );
        }
      }
    } on Object catch (e) {
      AppLogger.error('Invite failed: $e', tag: _tag, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao enviar convite.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gerenciar Campeonato')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gerenciar Campeonato')),
        body: ErrorState(
          message: _error ?? '',
          onRetry: _loadAll,
        ),
      );
    }

    final c = _champ;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gerenciar Campeonato')),
        body: const Center(child: Text('Campeonato não encontrado')),
      );
    }
    final isDraft = c.status == 'draft';
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            // ── Status header ──
            Card(
              elevation: 0,
              color: _statusColor(c.status).withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: DesignTokens.warning),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor(c.status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                          ),
                          child: Text(_statusLabel(c.status), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(c.status))),
                        ),
                      ],
                    ),
                    if (c.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(c.description, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _chip(Icons.speed_rounded, _metricLabel(c.metric), cs),
                      if (c.startAt != null) _chip(Icons.calendar_today_rounded, 'Início: ${_fmtDate(c.startAt!)}', cs),
                      if (c.endAt != null) _chip(Icons.event_rounded, 'Fim: ${_fmtDate(c.endAt!)}', cs),
                      if (c.requiresBadge) _chip(Icons.verified_rounded, 'Requer badge', cs),
                      if (c.maxParticipants != null) _chip(Icons.group_rounded, 'Máx ${c.maxParticipants}', cs),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Open action ──
            if (isDraft) ...[
              FilledButton.icon(
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Abrir para inscrições'),
                onPressed: _busy ? null : _openChampionship,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 8),
              Text(
                'O campeonato está em rascunho. Abra para que atletas possam se inscrever.',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],

            // ── Cancel action ──
            if (c.status == 'draft' || c.status == 'open' || c.status == 'active') ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancelar campeonato'),
                onPressed: _busy ? null : _cancelChampionship,
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesignTokens.error,
                  side: const BorderSide(color: DesignTokens.error),
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Badge QR generation (for requires_badge championships) ──
            if (c.requiresBadge && (c.status == 'open' || c.status == 'active')) ...[
              Card(
                elevation: 0,
                color: DesignTokens.primary.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: DesignTokens.primary.withValues(alpha: 0.15)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.military_tech_rounded, size: 22, color: DesignTokens.primary),
                          const SizedBox(width: 8),
                          Text('Badges de participação', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Este campeonato requer badge. Gere QR codes para que '
                        'cada atleta escaneie e ative seu badge de participação.',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.qr_code_rounded, size: 18),
                        label: const Text('Gerar QR de Badge'),
                        style: FilledButton.styleFrom(
                          backgroundColor: DesignTokens.primary,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => _generateBadgeQr(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Invite section ──
            Row(
              children: [
                Icon(Icons.group_add_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Convites para assessorias', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isDraft || c.status == 'open')
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Convidar'),
                    onPressed: _busy ? null : _inviteGroup,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (c.startAt != null && (isDraft || c.status == 'open'))
              Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: cs.outline),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'As assessorias precisam aceitar o convite antes do início '
                    '(${_fmtDate(c.startAt!)}), caso contrário seus atletas não poderão se inscrever.',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline, fontSize: 11),
                  )),
                ]),
              ),
            if (_invites.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
                child: Text('Nenhum convite enviado ainda.', style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
              )
            else
              ..._invites.map((inv) => _inviteTile(theme, inv)),
            const SizedBox(height: 20),

            // ── Participants section ──
            Row(
              children: [
                Icon(Icons.people_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Participantes (${_participants.length})', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (_participants.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
                child: Text(
                  isDraft
                      ? 'Abra o campeonato para receber inscrições.'
                      : 'Nenhum atleta inscrito ainda.',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              )
            else
              ..._participants.asMap().entries.map((e) => _participantTile(theme, e.value, e.key + 1, c.metric)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  Widget _inviteTile(ThemeData theme, _InviteData inv) {
    final (icon, color) = switch (inv.status) {
      'accepted' => (Icons.check_circle, DesignTokens.success),
      'declined' => (Icons.cancel, DesignTokens.error),
      'revoked' => (Icons.block, DesignTokens.textMuted),
      _ => (Icons.hourglass_empty, DesignTokens.warning),
    };

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 20),
      title: Text(inv.groupName),
      trailing: Text(
        _inviteStatusLabel(inv.status),
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _participantTile(ThemeData theme, _ParticipantData p, int rank, String metric) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text('$rank', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
      ),
      title: Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_participantStatusLabel(p.status), style: theme.textTheme.bodySmall),
      trailing: p.progressValue > 0
          ? Text(_fmtProgress(p.progressValue, metric), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))
          : null,
    );
  }

  static String _statusLabel(String s) => switch (s) { 'draft' => 'Rascunho', 'open' => 'Aberto', 'active' => 'Em andamento', 'completed' => 'Encerrado', 'cancelled' => 'Cancelado', _ => s };
  static Color _statusColor(String s) => switch (s) { 'draft' => DesignTokens.textMuted, 'open' => DesignTokens.success, 'active' => DesignTokens.primary, 'completed' => DesignTokens.success, 'cancelled' => DesignTokens.error, _ => DesignTokens.textMuted };
  static String _metricLabel(String m) => switch (m) { 'distance' => 'Distância', 'time' => 'Tempo', 'pace' => 'Pace', 'sessions' => 'Sessões', 'elevation' => 'Elevação', _ => m };
  static String _inviteStatusLabel(String s) => switch (s) { 'pending' => 'Pendente', 'accepted' => 'Aceito', 'declined' => 'Recusado', 'revoked' => 'Revogado', _ => s };
  static String _participantStatusLabel(String s) => switch (s) { 'enrolled' => 'Inscrito', 'active' => 'Ativo', 'completed' => 'Completou', 'withdrawn' => 'Desistiu', 'disqualified' => 'Não elegível', _ => s };
  static String _fmtDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  static String _fmtProgress(double v, String metric) => switch (metric) {
    'distance' => '${(v / 1000).toStringAsFixed(1)} km',
    'time' => '${(v / 60).toStringAsFixed(0)} min',
    'pace' => '${(v / 60).toStringAsFixed(1)} min/km',
    'sessions' => '${v.toInt()} corridas',
    'elevation' => '${v.toInt()} m',
    _ => v.toStringAsFixed(1),
  };
}

class _ChampData {
  final String id, name, description, metric, status;
  final bool requiresBadge;
  final int? maxParticipants;
  final DateTime? startAt, endAt;
  const _ChampData({required this.id, required this.name, required this.description, required this.metric, required this.status, required this.requiresBadge, this.maxParticipants, this.startAt, this.endAt});
}

class _InviteData {
  final String id, toGroupId, groupName, status;
  const _InviteData({required this.id, required this.toGroupId, required this.groupName, required this.status});
}

class _ParticipantData {
  final String userId, displayName, groupId, status;
  final double progressValue;
  final int? finalRank;
  const _ParticipantData({required this.userId, required this.displayName, required this.groupId, required this.status, required this.progressValue, this.finalRank});
}
