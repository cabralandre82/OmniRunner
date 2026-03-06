import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class PartnerAssessoriasScreen extends StatefulWidget {
  final String groupId;
  const PartnerAssessoriasScreen({super.key, required this.groupId});

  @override
  State<PartnerAssessoriasScreen> createState() =>
      _PartnerAssessoriasScreenState();
}

class _PartnerAssessoriasScreenState extends State<PartnerAssessoriasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assessorias Parceiras'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.handshake), text: 'Parceiras'),
            Tab(icon: Icon(Icons.emoji_events), text: 'Campeonatos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _PartnersTab(groupId: widget.groupId),
          _ChampionshipsTab(groupId: widget.groupId),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 1: Lista de parceiras + convidar
// ═══════════════════════════════════════════════════════════════════════════════

class _PartnersTab extends StatefulWidget {
  final String groupId;
  const _PartnersTab({required this.groupId});

  @override
  State<_PartnersTab> createState() => _PartnersTabState();
}

class _PartnersTabState extends State<_PartnersTab> {
  List<_PartnerItem> _partners = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await Supabase.instance.client
          .rpc('fn_list_partnerships', params: {'p_group_id': widget.groupId});
      final items = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(_PartnerItem.fromJson)
          .toList();
      if (!mounted) return;
      setState(() { _partners = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _respond(String partnershipId, bool accept) async {
    try {
      await Supabase.instance.client.rpc('fn_respond_partnership', params: {
        'p_partnership_id': partnershipId,
        'p_accept': accept,
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => _showSearchDialog(context),
            icon: const Icon(Icons.person_add),
            label: const Text('Convidar Assessoria'),
          ),
        ),
        Expanded(
          child: _partners.isEmpty
              ? _emptyState(theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
                    itemCount: _partners.length,
                    itemBuilder: (_, i) => _partnerTile(_partners[i], theme),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.handshake_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Nenhuma assessoria parceira',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Convide assessorias para criar uma rede de parceiros.\nVocês poderão se inscrever em campeonatos umas das outras.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _partnerTile(_PartnerItem p, ThemeData theme) {
    final cs = theme.colorScheme;
    final isPending = p.status == 'pending';
    final isIncoming = isPending && !p.isRequester;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isPending ? DesignTokens.warning : cs.primaryContainer,
              child: Text(
                p.partnerName.isNotEmpty ? p.partnerName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPending ? DesignTokens.warning : cs.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.partnerName,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${p.athleteCount} atletas',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
                  if (isPending && p.isRequester)
                    Text('Convite enviado — aguardando resposta',
                        style: theme.textTheme.bodySmall?.copyWith(color: DesignTokens.warning)),
                ],
              ),
            ),
            if (isIncoming) ...[
              IconButton(
                onPressed: () => _respond(p.partnershipId, true),
                icon: const Icon(Icons.check_circle),
                color: DesignTokens.success,
                tooltip: 'Aceitar',
              ),
              IconButton(
                onPressed: () => _respond(p.partnershipId, false),
                icon: const Icon(Icons.cancel),
                color: cs.error,
                tooltip: 'Recusar',
              ),
            ] else if (!isPending) ...[
              Icon(Icons.check_circle, color: DesignTokens.success, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showSearchDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _SearchAssessoriaDialog(myGroupId: widget.groupId),
    );
    if (result == true) _load();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 2: Campeonatos das parceiras
// ═══════════════════════════════════════════════════════════════════════════════

class _ChampionshipsTab extends StatefulWidget {
  final String groupId;
  const _ChampionshipsTab({required this.groupId});

  @override
  State<_ChampionshipsTab> createState() => _ChampionshipsTabState();
}

class _ChampionshipsTabState extends State<_ChampionshipsTab> {
  List<_ChampItem> _champs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await Supabase.instance.client
          .rpc('fn_partner_championships', params: {'p_group_id': widget.groupId});
      final items = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(_ChampItem.fromJson)
          .toList();
      if (!mounted) return;
      setState(() { _champs = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _requestJoin(_ChampItem champ) async {
    try {
      final result = await Supabase.instance.client.rpc('fn_request_champ_join', params: {
        'p_championship_id': champ.championshipId,
        'p_group_id': widget.groupId,
      });
      if (!mounted) return;
      final msg = switch (result as String) {
        'requested' => 'Solicitação enviada!',
        'already_pending' => 'Solicitação já pendente.',
        'already_accepted' => 'Já inscrito neste campeonato.',
        _ => 'Resultado: $result',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }

    if (_champs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_outlined, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              Text('Nenhum campeonato disponível',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Quando suas assessorias parceiras criarem campeonatos abertos, eles aparecerão aqui.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
        itemCount: _champs.length,
        itemBuilder: (_, i) => _champTile(_champs[i], theme),
      ),
    );
  }

  Widget _champTile(_ChampItem c, ThemeData theme) {
    final cs = theme.colorScheme;
    final metricLabel = {
      'distance': 'Distância',
      'time': 'Tempo',
      'pace': 'Pace',
      'sessions': 'Sessões',
      'elevation': 'Elevação',
    }[c.metric] ?? c.metric;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: DesignTokens.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.name,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.status == 'open' ? DesignTokens.success : DesignTokens.primary,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                  child: Text(
                    c.status == 'open' ? 'Aberto' : 'Ativo',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.status == 'open' ? DesignTokens.success : DesignTokens.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Organizado por: ${c.hostGroupName}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
            const SizedBox(height: 8),
            Row(
              children: [
                _InfoChip(Icons.straighten, metricLabel),
                const SizedBox(width: 8),
                _InfoChip(Icons.people, '${c.participantCount} inscritos'),
                const SizedBox(width: 8),
                _InfoChip(Icons.calendar_today, _formatDate(c.startAt)),
              ],
            ),
            const SizedBox(height: 10),
            if (c.alreadyInvited)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
                decoration: BoxDecoration(
                  color: DesignTokens.success,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: const Text(
                  'Já inscrito / solicitação enviada',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: DesignTokens.success, fontWeight: FontWeight.w600),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _requestJoin(c),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Solicitar Participação'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Dialog: Buscar assessoria para convidar
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchAssessoriaDialog extends StatefulWidget {
  final String myGroupId;
  const _SearchAssessoriaDialog({required this.myGroupId});

  @override
  State<_SearchAssessoriaDialog> createState() => _SearchAssessoriaDialogState();
}

class _SearchAssessoriaDialogState extends State<_SearchAssessoriaDialog> {
  final _ctrl = TextEditingController();
  List<_SearchResult> _results = [];
  bool _searching = false;

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) return;
    setState(() => _searching = true);
    try {
      final rows = await Supabase.instance.client.rpc('fn_search_assessorias', params: {
        'p_query': q,
        'p_exclude_group_id': widget.myGroupId,
      });
      if (!mounted) return;
      setState(() {
        _results = (rows as List)
            .cast<Map<String, dynamic>>()
            .map((j) => _SearchResult(
                  groupId: j['group_id'] as String,
                  groupName: j['group_name'] as String,
                  athleteCount: (j['athlete_count'] as num).toInt(),
                ))
            .toList();
        _searching = false;
      });
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'PartnerAssessoriasScreen', error: e);
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _invite(String targetGroupId) async {
    try {
      final result = await Supabase.instance.client.rpc('fn_request_partnership', params: {
        'p_my_group_id': widget.myGroupId,
        'p_target_group_id': targetGroupId,
      });
      if (!mounted) return;
      final msg = switch (result as String) {
        'requested' => 'Convite enviado!',
        'already_partners' => 'Já são parceiras.',
        'already_pending' => 'Convite já pendente.',
        _ => 'Resultado: $result',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (result == 'requested') {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buscar Assessoria'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: 'Nome da assessoria...',
                suffixIcon: IconButton(
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(DesignTokens.spacingMd),
                child: CircularProgressIndicator(),
              ),
            if (!_searching && _results.isNotEmpty)
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(r.groupName.isNotEmpty ? r.groupName[0].toUpperCase() : '?'),
                      ),
                      title: Text(r.groupName),
                      subtitle: Text('${r.athleteCount} atletas'),
                      trailing: FilledButton(
                        onPressed: () => _invite(r.groupId),
                        child: const Text('Convidar'),
                      ),
                    );
                  },
                ),
              ),
            if (!_searching && _results.isEmpty && _ctrl.text.length >= 2)
              const Padding(
                padding: EdgeInsets.all(DesignTokens.spacingMd),
                child: Text('Nenhuma assessoria encontrada.'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Data models
// ═══════════════════════════════════════════════════════════════════════════════

class _PartnerItem {
  final String partnershipId;
  final String partnerGroupId;
  final String partnerName;
  final int athleteCount;
  final String status;
  final bool isRequester;

  const _PartnerItem({
    required this.partnershipId,
    required this.partnerGroupId,
    required this.partnerName,
    required this.athleteCount,
    required this.status,
    required this.isRequester,
  });

  factory _PartnerItem.fromJson(Map<String, dynamic> j) => _PartnerItem(
        partnershipId: j['partnership_id'] as String,
        partnerGroupId: j['partner_group_id'] as String,
        partnerName: (j['partner_name'] as String?) ?? 'Assessoria',
        athleteCount: (j['partner_athlete_count'] as num?)?.toInt() ?? 0,
        status: j['status'] as String,
        isRequester: (j['is_requester'] as bool?) ?? false,
      );
}

class _ChampItem {
  final String championshipId;
  final String name;
  final String hostGroupId;
  final String hostGroupName;
  final String metric;
  final DateTime? startAt;
  final DateTime? endAt;
  final String status;
  final int? maxParticipants;
  final int participantCount;
  final bool alreadyInvited;

  const _ChampItem({
    required this.championshipId,
    required this.name,
    required this.hostGroupId,
    required this.hostGroupName,
    required this.metric,
    this.startAt,
    this.endAt,
    required this.status,
    this.maxParticipants,
    required this.participantCount,
    required this.alreadyInvited,
  });

  factory _ChampItem.fromJson(Map<String, dynamic> j) => _ChampItem(
        championshipId: j['championship_id'] as String,
        name: (j['championship_name'] as String?) ?? '',
        hostGroupId: j['host_group_id'] as String,
        hostGroupName: (j['host_group_name'] as String?) ?? 'Assessoria',
        metric: j['metric'] as String,
        startAt: j['start_at'] != null ? DateTime.tryParse(j['start_at'] as String) : null,
        endAt: j['end_at'] != null ? DateTime.tryParse(j['end_at'] as String) : null,
        status: j['status'] as String,
        maxParticipants: (j['max_participants'] as num?)?.toInt(),
        participantCount: (j['participant_count'] as num?)?.toInt() ?? 0,
        alreadyInvited: (j['already_invited'] as bool?) ?? false,
      );
}

class _SearchResult {
  final String groupId;
  final String groupName;
  final int athleteCount;
  const _SearchResult({required this.groupId, required this.groupName, required this.athleteCount});
}
