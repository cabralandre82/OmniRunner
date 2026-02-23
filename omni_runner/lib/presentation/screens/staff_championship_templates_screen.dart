import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/screens/staff_championship_manage_screen.dart';

/// Staff screen for managing recurring championship templates.
///
/// Features:
///   1. List saved templates for the assessoria
///   2. Create a new template (name, metric, duration, badge, max)
///   3. Use a template to launch a championship (calls champ-create Edge Function)
///
/// Data: championship_templates (RLS: admin_master/professor of owner group).
/// No monetary values. No prohibited terms. Complies with GAMIFICATION_POLICY §5.
class StaffChampionshipTemplatesScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const StaffChampionshipTemplatesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<StaffChampionshipTemplatesScreen> createState() =>
      _StaffChampionshipTemplatesScreenState();
}

class _StaffChampionshipTemplatesScreenState
    extends State<StaffChampionshipTemplatesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _loading = true;
  String? _error;
  List<_TemplateItem> _templates = [];
  List<_ChampItem> _championships = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = Supabase.instance.client;

      final templateRes = await db
          .from('championship_templates')
          .select()
          .eq('owner_group_id', widget.groupId)
          .order('created_at', ascending: false);

      final rows = (templateRes as List).cast<Map<String, dynamic>>();

      _templates = rows.map((r) => _TemplateItem(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? '',
            description: (r['description'] as String?) ?? '',
            metric: (r['metric'] as String?) ?? 'distance',
            durationDays: (r['duration_days'] as int?) ?? 7,
            requiresBadge: (r['requires_badge'] as bool?) ?? false,
            maxParticipants: r['max_participants'] as int?,
          )).toList();

      final champRes = await db.functions.invoke('champ-list', body: {
        'host_group_id': widget.groupId,
        'status': null,
      });
      final champData = champRes.data as Map<String, dynamic>? ?? {};
      final champList = (champData['championships'] as List<dynamic>?) ?? [];

      _championships = champList.map((c) {
        final m = c as Map<String, dynamic>;
        return _ChampItem(
          id: (m['id'] as String?) ?? '',
          name: (m['name'] as String?) ?? '',
          status: (m['status'] as String?) ?? 'draft',
          metric: (m['metric'] as String?) ?? 'distance',
          startAt: DateTime.tryParse((m['start_at'] as String?) ?? ''),
          endAt: DateTime.tryParse((m['end_at'] as String?) ?? ''),
        );
      }).toList();

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar os dados.';
          _loading = false;
        });
      }
    }
  }

  void _createTemplate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _CreateTemplateScreen(groupId: widget.groupId),
      ),
    );
    if (created == true) _load();
  }

  void _useTemplate(_TemplateItem t) async {
    final champId = await showDialog<String>(
      context: context,
      builder: (ctx) => _LaunchFromTemplateDialog(
        template: t,
        groupId: widget.groupId,
      ),
    );
    if (champId != null && champId.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campeonato criado com sucesso!')),
      );
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StaffChampionshipManageScreen(
          championshipId: champId,
          hostGroupId: widget.groupId,
        ),
      ));
    }
  }

  void _openChampionship(_ChampItem c) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffChampionshipManageScreen(
        championshipId: c.id,
        hostGroupId: widget.groupId,
      ),
    )).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campeonatos'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(
              icon: const Icon(Icons.emoji_events_rounded, size: 20),
              text: 'Meus (${_championships.length})',
            ),
            Tab(
              icon: const Icon(Icons.copy_rounded, size: 20),
              text: 'Modelos (${_templates.length})',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTemplate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo modelo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildChampionshipsTab(theme),
                    _buildTemplatesTab(theme),
                  ],
                ),
    );
  }

  Widget _buildChampionshipsTab(ThemeData theme) {
    if (_championships.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(Icons.emoji_events_outlined,
                    size: 56, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('Nenhum campeonato criado',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  'Use um modelo para criar seu\nprimeiro campeonato.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _championships.length,
        itemBuilder: (_, i) {
          final c = _championships[i];
          return _ChampListTile(champ: c, onTap: () => _openChampionship(c));
        },
      ),
    );
  }

  Widget _buildTemplatesTab(ThemeData theme) {
    if (_templates.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(Icons.copy_outlined,
                    size: 56, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('Nenhum modelo salvo',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  'Crie um modelo para reutilizar\nconfigurações de campeonatos.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _templates.length,
        itemBuilder: (_, i) => _TemplateTile(
          template: _templates[i],
          onUse: () => _useTemplate(_templates[i]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data model
// ═══════════════════════════════════════════════════════════════════════════

class _TemplateItem {
  final String id;
  final String name;
  final String description;
  final String metric;
  final int durationDays;
  final bool requiresBadge;
  final int? maxParticipants;

  const _TemplateItem({
    required this.id,
    required this.name,
    required this.description,
    required this.metric,
    required this.durationDays,
    required this.requiresBadge,
    this.maxParticipants,
  });
}

class _ChampItem {
  final String id;
  final String name;
  final String status;
  final String metric;
  final DateTime? startAt;
  final DateTime? endAt;

  const _ChampItem({
    required this.id,
    required this.name,
    required this.status,
    required this.metric,
    this.startAt,
    this.endAt,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Championship list tile
// ═══════════════════════════════════════════════════════════════════════════

class _ChampListTile extends StatelessWidget {
  final _ChampItem champ;
  final VoidCallback onTap;

  const _ChampListTile({required this.champ, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(champ.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.15),
                child: Icon(Icons.emoji_events_rounded,
                    color: statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(champ.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      _statusBadge(champ.status, statusColor, theme),
                      Text(
                        _metricLabel(champ.metric),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (champ.startAt != null)
                        Text(
                          _fmtDate(champ.startAt!),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ]),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'draft' => 'Rascunho',
        'open' => 'Aberto',
        'active' => 'Em andamento',
        'completed' => 'Encerrado',
        'cancelled' => 'Cancelado',
        _ => s,
      };

  static Color _statusColor(String s) => switch (s) {
        'draft' => Colors.grey,
        'open' => Colors.green,
        'active' => Colors.blue,
        'completed' => Colors.teal,
        'cancelled' => Colors.red,
        _ => Colors.grey,
      };

  static String _metricLabel(String m) => switch (m) {
        'distance' => 'Distância',
        'time' => 'Tempo',
        'pace' => 'Pace',
        'sessions' => 'Sessões',
        'elevation' => 'Elevação',
        _ => m,
      };

  static String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ═══════════════════════════════════════════════════════════════════════════
// Template tile
// ═══════════════════════════════════════════════════════════════════════════

class _TemplateTile extends StatelessWidget {
  final _TemplateItem template;
  final VoidCallback onUse;

  const _TemplateTile({required this.template, required this.onUse});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                Icon(Icons.emoji_events_rounded,
                    size: 22, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(template.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (template.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(template.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(
                    Icons.speed_rounded, _metricLabel(template.metric)),
                _InfoChip(Icons.calendar_today_rounded,
                    '${template.durationDays} dias'),
                if (template.requiresBadge)
                  const _InfoChip(
                      Icons.verified_rounded, 'Requer badge'),
                if (template.maxParticipants != null)
                  _InfoChip(Icons.group_rounded,
                      'Máx ${template.maxParticipants}'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onUse,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Usar modelo'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _metricLabel(String m) => switch (m) {
        'distance' => 'Distância',
        'time' => 'Tempo',
        'pace' => 'Pace',
        'sessions' => 'Sessões',
        'elevation' => 'Elevação',
        _ => m,
      };
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Create template screen
// ═══════════════════════════════════════════════════════════════════════════

class _CreateTemplateScreen extends StatefulWidget {
  final String groupId;
  const _CreateTemplateScreen({required this.groupId});

  @override
  State<_CreateTemplateScreen> createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<_CreateTemplateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  String _metric = 'distance';
  int _durationDays = 7;
  bool _requiresBadge = false;
  bool _saving = false;

  static const _metrics = [
    ('distance', 'Distância'),
    ('time', 'Tempo'),
    ('pace', 'Pace'),
    ('sessions', 'Sessões'),
    ('elevation', 'Elevação'),
  ];

  static const _durations = [7, 14, 30, 60, 90];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final db = Supabase.instance.client;
      final uid = sl<UserIdentityProvider>().userId;

      final payload = <String, dynamic>{
        'owner_group_id': widget.groupId,
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'metric': _metric,
        'duration_days': _durationDays,
        'requires_badge': _requiresBadge,
        'created_by': uid,
      };

      final maxText = _maxCtrl.text.trim();
      if (maxText.isNotEmpty) {
        payload['max_participants'] = int.parse(maxText);
      }

      await db.from('championship_templates').insert(payload);

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao salvar modelo.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Novo modelo')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome do modelo',
                hintText: 'Ex: Desafio semanal de distância',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                hintText: 'Detalhes sobre o campeonato',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            Text('Métrica',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _metrics.map((e) {
                final selected = _metric == e.$1;
                return ChoiceChip(
                  label: Text(e.$2),
                  selected: selected,
                  onSelected: (_) => setState(() => _metric = e.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            Text('Duração',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _durations.map((d) {
                final selected = _durationDays == d;
                return ChoiceChip(
                  label: Text('$d dias'),
                  selected: selected,
                  onSelected: (_) => setState(() => _durationDays = d),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            SwitchListTile(
              value: _requiresBadge,
              onChanged: (v) => setState(() => _requiresBadge = v),
              title: const Text('Requer badge de participação'),
              subtitle: const Text(
                  'Atletas precisam de badge ativo para participar'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _maxCtrl,
              decoration: const InputDecoration(
                labelText: 'Máximo de participantes (opcional)',
                hintText: 'Sem limite se vazio',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                if (n == null || n < 2) return 'Mínimo 2 participantes';
                return null;
              },
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Salvar modelo'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Launch from template dialog
// ═══════════════════════════════════════════════════════════════════════════

class _LaunchFromTemplateDialog extends StatefulWidget {
  final _TemplateItem template;
  final String groupId;

  const _LaunchFromTemplateDialog({
    required this.template,
    required this.groupId,
  });

  @override
  State<_LaunchFromTemplateDialog> createState() => _LaunchFromTemplateDialogState();
}

class _LaunchFromTemplateDialogState
    extends State<_LaunchFromTemplateDialog> {
  bool _launching = false;
  DateTime? _startDate;

  @override
  void initState() {
    super.initState();
    // Default: next Monday
    final now = DateTime.now();
    final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
    _startDate = now.add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate!,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _launch() async {
    if (_startDate == null) return;
    setState(() => _launching = true);

    try {
      final t = widget.template;
      final startAt = _startDate!.toUtc();
      final endAt = startAt.add(Duration(days: t.durationDays));

      final db = Supabase.instance.client;
      final res = await db.functions.invoke('champ-create', body: {
        'host_group_id': widget.groupId,
        'name': t.name,
        'description': t.description,
        'metric': t.metric,
        'requires_badge': t.requiresBadge,
        'start_at_iso': startAt.toIso8601String(),
        'end_at_iso': endAt.toIso8601String(),
        'template_id': t.id,
        if (t.maxParticipants != null)
          'max_participants': t.maxParticipants,
      });

      final champId =
          (res.data as Map<String, dynamic>?)?['championship_id'] as String?;

      sl<ProductEventTracker>().trackOnce(
        ProductEvents.firstChampionshipLaunched,
        {'metric': t.metric, 'template_id': t.id},
      );

      if (champId != null) {
        sl<NotificationRulesService>().notifyChampionshipStarting(
          championshipId: champId,
        );
      }
      if (mounted) Navigator.of(context).pop(champId ?? '');
    } catch (_) {
      if (mounted) {
        setState(() => _launching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao criar campeonato.')),
        );
      }
    }
  }

  String get _dateLabel {
    if (_startDate == null) return '—';
    final d = _startDate!;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final endLabel = _startDate != null
        ? () {
            final e = _startDate!.add(Duration(days: t.durationDays));
            return '${e.day.toString().padLeft(2, '0')}/'
                '${e.month.toString().padLeft(2, '0')}/'
                '${e.year}';
          }()
        : '—';

    return AlertDialog(
      title: const Text('Criar campeonato'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modelo: ${t.name}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${_TemplateTile._metricLabel(t.metric)} · '
                '${t.durationDays} dias'),
            const Divider(height: 24),
            const Text('Data de início:'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: Text(_dateLabel),
            ),
            const SizedBox(height: 8),
            Text('Encerramento: $endLabel',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _launching ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _launching ? null : _launch,
          child: _launching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Criar'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Error body
// ═══════════════════════════════════════════════════════════════════════════

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
