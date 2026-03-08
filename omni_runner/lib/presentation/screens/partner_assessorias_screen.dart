import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/utils/error_messages.dart';

class PartnerAssessoriasScreen extends StatefulWidget {
  final String groupId;
  const PartnerAssessoriasScreen({super.key, required this.groupId});

  @override
  State<PartnerAssessoriasScreen> createState() =>
      _PartnerAssessoriasScreenState();
}

class _PartnerAssessoriasScreenState extends State<PartnerAssessoriasScreen> {
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
      final rows = await sl<SupabaseClient>()
          .rpc('fn_list_partnerships', params: {'p_group_id': widget.groupId});
      final items = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(_PartnerItem.fromJson)
          .toList();
      if (!mounted) return;
      setState(() { _partners = items; _loading = false; });
    } on PostgrestException catch (e) {
      AppLogger.warn('Partnership load failed: ${e.code} ${e.message}', tag: 'Partners');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == '42883'
            ? 'Recurso em preparação. Tente novamente em breve.'
            : 'Não foi possível carregar parcerias.';
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = ErrorMessages.humanize(e); });
    }
  }

  Future<void> _respond(String partnershipId, bool accept) async {
    try {
      await sl<SupabaseClient>().rpc('fn_respond_partnership', params: {
        'p_partnership_id': partnershipId,
        'p_accept': accept,
      });
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMessages.humanize(e))),
      );
    }
  }

  Future<void> _removePartner(_PartnerItem p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover parceira?'),
        content: Text(
          'Tem certeza que deseja remover "${p.partnerName}" da sua lista de parceiras?\n\n'
          'Essa assessoria não poderá mais participar dos seus campeonatos '
          'e vocês não aparecerão mais como parceiras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DesignTokens.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await sl<SupabaseClient>()
          .from('assessoria_partnerships')
          .delete()
          .eq('id', p.partnershipId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${p.partnerName} removida da lista.')),
        );
      }
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMessages.humanize(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Assessorias Parceiras')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSearchDialog(context),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Convidar'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _partners.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildList(theme),
                ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(DesignTokens.spacingXl),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.handshake_outlined, size: 80, color: cs.outline),
        const SizedBox(height: 24),
        Text(
          'Nenhuma assessoria parceira',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _TutorialCard(
          icon: Icons.lightbulb_outline_rounded,
          title: 'O que são assessorias parceiras?',
          body: 'São assessorias amigas da sua — assessorias da mesma cidade, '
              'que compartilham valores, que treinam juntas ou que simplesmente '
              'querem fazer eventos juntas.',
        ),
        const SizedBox(height: 12),
        _TutorialCard(
          icon: Icons.emoji_events_outlined,
          title: 'Por que ter parceiras?',
          body: 'Apenas assessorias parceiras podem ser convidadas para '
              'participar dos seus campeonatos. Ao criar um campeonato, '
              'você poderá convidar apenas assessorias da sua lista de parceiras.',
        ),
        const SizedBox(height: 12),
        _TutorialCard(
          icon: Icons.send_rounded,
          title: 'Como funciona?',
          body: 'Toque no botão "Convidar" abaixo para buscar uma assessoria '
              'pelo nome. Ao enviar o convite, a outra assessoria pode aceitar '
              'ou recusar. Se aceitar, ela entra na sua lista de parceiras.\n\n'
              'Vocês podem se remover da lista a qualquer momento.',
        ),
      ],
    );
  }

  Widget _buildList(ThemeData theme) {
    final accepted = _partners.where((p) => p.status == 'accepted').toList();
    final pendingIncoming = _partners.where((p) => p.status == 'pending' && !p.isRequester).toList();
    final pendingSent = _partners.where((p) => p.status == 'pending' && p.isRequester).toList();

    final items = <Widget>[
      _InfoBanner(
        text: 'Assessorias parceiras podem participar dos seus campeonatos. '
            'Convide assessorias amigas para criar eventos juntos!',
      ),
    ];

    if (pendingIncoming.isNotEmpty) {
      items.add(const SizedBox(height: DesignTokens.spacingMd));
      items.add(_SectionHeader(title: 'Convites recebidos', count: pendingIncoming.length, color: DesignTokens.warning));
      for (final p in pendingIncoming) {
        items.add(_PendingIncomingTile(
          partner: p,
          onAccept: () => _respond(p.partnershipId, true),
          onDecline: () => _respond(p.partnershipId, false),
        ));
      }
    }

    if (pendingSent.isNotEmpty) {
      items.add(const SizedBox(height: DesignTokens.spacingMd));
      items.add(_SectionHeader(title: 'Convites enviados', count: pendingSent.length, color: DesignTokens.info));
      for (final p in pendingSent) {
        items.add(_SentTile(partner: p));
      }
    }

    if (accepted.isNotEmpty) {
      items.add(const SizedBox(height: DesignTokens.spacingMd));
      items.add(_SectionHeader(title: 'Parceiras ativas', count: accepted.length, color: DesignTokens.success));
      for (final p in accepted) {
        items.add(_AcceptedTile(partner: p, onRemove: () => _removePartner(p)));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd, DesignTokens.spacingSm,
        DesignTokens.spacingMd, 80,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
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
// UI Components
// ═══════════════════════════════════════════════════════════════════════════════

class _TutorialCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _TutorialCard({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: DesignTokens.info),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(body, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant, height: 1.4,
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DesignTokens.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: DesignTokens.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: DesignTokens.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: cs.onSurface, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader({required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }
}

class _PendingIncomingTile extends StatelessWidget {
  final _PartnerItem partner;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _PendingIncomingTile({required this.partner, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        side: BorderSide(color: DesignTokens.warning.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: DesignTokens.warning.withValues(alpha: 0.15),
                child: Text(
                  partner.partnerName.isNotEmpty ? partner.partnerName[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: DesignTokens.warning),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(partner.partnerName, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${partner.athleteCount} atletas', style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
                ],
              )),
            ]),
            const SizedBox(height: 10),
            Text(
              'Esta assessoria quer ser sua parceira. Aceitar significa que vocês '
              'poderão participar dos campeonatos uma da outra.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: FilledButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Aceitar'),
                onPressed: onAccept,
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Recusar'),
                style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                onPressed: onDecline,
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SentTile extends StatelessWidget {
  final _PartnerItem partner;
  const _SentTile({required this.partner});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: DesignTokens.info.withValues(alpha: 0.15),
          child: Text(
            partner.partnerName.isNotEmpty ? partner.partnerName[0].toUpperCase() : '?',
            style: const TextStyle(fontWeight: FontWeight.bold, color: DesignTokens.info),
          ),
        ),
        title: Text(partner.partnerName, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text('Aguardando resposta...', style: theme.textTheme.bodySmall?.copyWith(color: DesignTokens.info)),
        trailing: Icon(Icons.hourglass_top_rounded, size: 18, color: cs.outline),
      ),
    );
  }
}

class _AcceptedTile extends StatelessWidget {
  final _PartnerItem partner;
  final VoidCallback onRemove;
  const _AcceptedTile({required this.partner, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: DesignTokens.success.withValues(alpha: 0.15),
          child: Text(
            partner.partnerName.isNotEmpty ? partner.partnerName[0].toUpperCase() : '?',
            style: const TextStyle(fontWeight: FontWeight.bold, color: DesignTokens.success),
          ),
        ),
        title: Text(partner.partnerName, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text('${partner.athleteCount} atletas', style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
        trailing: PopupMenuButton<String>(
          onSelected: (v) { if (v == 'remove') onRemove(); },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'remove',
              child: Row(children: [
                Icon(Icons.person_remove_rounded, size: 18, color: DesignTokens.error),
                SizedBox(width: 8),
                Text('Remover parceira', style: TextStyle(color: DesignTokens.error)),
              ]),
            ),
          ],
        ),
      ),
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
      final rows = await sl<SupabaseClient>().rpc('fn_search_assessorias', params: {
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
    } on Exception catch (e) {
      AppLogger.warn('Search failed', tag: 'PartnerAssessoriasScreen', error: e);
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _invite(String targetGroupId, String name) async {
    try {
      final result = await sl<SupabaseClient>().rpc('fn_request_partnership', params: {
        'p_my_group_id': widget.myGroupId,
        'p_target_group_id': targetGroupId,
      });
      if (!mounted) return;
      final msg = switch (result as String) {
        'requested' => 'Convite de parceria enviado para "$name"!',
        'already_partners' => 'Vocês já são parceiras.',
        'already_pending' => 'Convite já enviado. Aguardando resposta.',
        _ => 'Resultado: $result',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (result == 'requested') {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorMessages.humanize(e))));
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Buscar assessoria'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Busque pelo nome da assessoria que deseja convidar para ser sua parceira.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
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
                        onPressed: () => _invite(r.groupId, r.groupName),
                        child: const Text('Convidar'),
                      ),
                    );
                  },
                ),
              ),
            if (!_searching && _results.isEmpty && _ctrl.text.length >= 2)
              Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Column(
                  children: [
                    Icon(Icons.search_off_rounded, size: 32, color: cs.outline),
                    const SizedBox(height: 8),
                    const Text('Nenhuma assessoria encontrada.'),
                  ],
                ),
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

class _SearchResult {
  final String groupId;
  final String groupName;
  final int athleteCount;
  const _SearchResult({required this.groupId, required this.groupName, required this.athleteCount});
}
