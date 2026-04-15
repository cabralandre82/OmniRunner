import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/utils/error_messages.dart';

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
      final db = sl<SupabaseClient>();

      final templateRes = await db
          .from('championship_templates')
          .select('id, name, description, metric, duration_days, requires_badge, max_participants')
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
    } on Object catch (e) {
      AppLogger.warn('Caught error', tag: 'StaffChampionshipTemplates', error: e);
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
      context.push(AppRoutes.staffChampionshipManage, extra: StaffChampionshipManageExtra(
        championshipId: champId,
        hostGroupId: widget.groupId,
      ));
    }
  }

  void _openChampionship(_ChampItem c) {
    context.push(AppRoutes.staffChampionshipManage, extra: StaffChampionshipManageExtra(
      championshipId: c.id,
      hostGroupId: widget.groupId,
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
              ? _ErrorBody(message: _error ?? '', onRetry: _load)
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
        padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingMd, 80),
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
        padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingMd, 80),
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
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
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
        'draft' => DesignTokens.textMuted,
        'open' => DesignTokens.success,
        'active' => DesignTokens.primary,
        'completed' => DesignTokens.success,
        'cancelled' => DesignTokens.error,
        _ => DesignTokens.textMuted,
      };

  static String _metricLabel(String m) => switch (m) {
        'distance' => 'Distância',
        'time' => 'Tempo',
        'pace' => 'Pace',
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
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    size: 22, color: DesignTokens.warning),
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
                    _durationLabel(template.durationDays)),
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
        'elevation' => 'Elevação',
        _ => m,
      };

  static String _durationLabel(int days) => switch (days) {
        1 => 'Corrida única',
        7 => '1 semana',
        14 => '2 semanas',
        30 => '1 mês',
        _ => '$days dias',
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
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
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
  final _customDaysCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _refDistCtrl = TextEditingController();

  String _metric = 'distance';
  bool _isSingleRace = true;
  int _durationDays = 7;
  bool _customDuration = false;
  bool _requiresBadge = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _maxCtrl.dispose();
    _customDaysCtrl.dispose();
    _locationCtrl.dispose();
    _refDistCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    int days;
    if (_isSingleRace) {
      days = 1;
    } else if (_customDuration) {
      days = int.tryParse(_customDaysCtrl.text.trim()) ?? 7;
    } else {
      days = _durationDays;
    }

    setState(() => _saving = true);

    try {
      final db = sl<SupabaseClient>();
      final uid = sl<UserIdentityProvider>().userId;

      final desc = StringBuffer();
      if (_descCtrl.text.trim().isNotEmpty) {
        desc.write(_descCtrl.text.trim());
      }
      if (_locationCtrl.text.trim().isNotEmpty) {
        if (desc.isNotEmpty) desc.write('\n');
        desc.write('Local: ${_locationCtrl.text.trim()}');
      }
      if (_refDistCtrl.text.trim().isNotEmpty &&
          (_metric == 'pace' || _metric == 'elevation')) {
        if (desc.isNotEmpty) desc.write('\n');
        desc.write('Distância de referência: ${_refDistCtrl.text.trim()} km');
      }

      final payload = <String, dynamic>{
        'owner_group_id': widget.groupId,
        'name': _nameCtrl.text.trim(),
        'description': desc.toString(),
        'metric': _metric,
        'duration_days': days,
        'requires_badge': _requiresBadge,
        'created_by': uid,
      };

      final maxText = _maxCtrl.text.trim();
      if (maxText.isNotEmpty) {
        payload['max_participants'] = int.tryParse(maxText) ?? 0;
      }

      await db.from('championship_templates').insert(payload);

      if (mounted) context.pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.humanize(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Novo campeonato')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── STEP 1: Name ──
            _SectionHeader(
              number: '1',
              title: 'Identifique o campeonato',
              theme: theme,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome do campeonato *',
                hintText: 'Ex: Corrida de 5K no Parque',
                prefixIcon: Icon(Icons.emoji_events_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrição e regras (opcional)',
                hintText: 'Detalhes, observações, regras especiais...',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
              maxLines: 3,
              minLines: 1,
            ),

            const SizedBox(height: 28),

            // ── STEP 2: Format ──
            _SectionHeader(
              number: '2',
              title: 'Formato do campeonato',
              theme: theme,
            ),
            const SizedBox(height: 8),
            Text(
              'O campeonato é um evento único ou acontece durante um período?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FormatCard(
                    icon: Icons.flag_rounded,
                    label: 'Corrida única',
                    subtitle: 'Um evento, data e hora definidos',
                    selected: _isSingleRace,
                    onTap: () => setState(() => _isSingleRace = true),
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FormatCard(
                    icon: Icons.date_range_rounded,
                    label: 'Período',
                    subtitle: 'Corridas acumulam durante dias/semanas',
                    selected: !_isSingleRace,
                    onTap: () => setState(() => _isSingleRace = false),
                    theme: theme,
                  ),
                ),
              ],
            ),

            if (!_isSingleRace) ...[
              const SizedBox(height: 16),
              Text('Duração do período',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...[
                    (7, '1 semana'),
                    (14, '2 semanas'),
                    (30, '1 mês'),
                    (60, '2 meses'),
                  ].map((d) {
                    final selected =
                        !_customDuration && _durationDays == d.$1;
                    return ChoiceChip(
                      label: Text(d.$2),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _durationDays = d.$1;
                        _customDuration = false;
                      }),
                    );
                  }),
                  ChoiceChip(
                    label: const Text('Personalizado'),
                    selected: _customDuration,
                    onSelected: (_) =>
                        setState(() => _customDuration = true),
                  ),
                ],
              ),
              if (_customDuration) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customDaysCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de dias',
                    hintText: 'Ex: 45',
                    suffixText: 'dias',
                    prefixIcon: Icon(Icons.timelapse_rounded),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (!_customDuration || _isSingleRace) return null;
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n < 2) return 'Mínimo 2 dias';
                    return null;
                  },
                ),
              ],
            ],

            const SizedBox(height: 28),

            // ── STEP 3: Metric ──
            _SectionHeader(
              number: '3',
              title: 'Como classificar os atletas?',
              theme: theme,
            ),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _metric,
              onChanged: (v) { if (v != null) setState(() => _metric = v); },
              child: Column(
                children: [
                  (
                    'distance',
                    Icons.straighten_rounded,
                    'Distância',
                    _isSingleRace
                        ? 'Quem correr mais km na corrida'
                        : 'Quem acumular mais km no período',
                  ),
                  (
                    'time',
                    Icons.timer_rounded,
                    'Tempo de corrida',
                    _isSingleRace
                        ? 'Quem correr mais tempo na corrida'
                        : 'Quem acumular mais tempo correndo',
                  ),
                  (
                    'pace',
                    Icons.speed_rounded,
                    'Pace médio',
                    'Quem tiver o melhor pace médio (min/km)',
                  ),
                  (
                    'elevation',
                    Icons.terrain_rounded,
                    'Elevação',
                    _isSingleRace
                        ? 'Quem subir mais metros na corrida'
                        : 'Quem acumular mais metros de subida',
                  ),
                ].map((e) => RadioListTile<String>(
                      value: e.$1,
                      secondary: Icon(e.$2, size: 22),
                      title: Text(e.$3),
                      subtitle: Text(e.$4,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    )).toList(),
              ),
            ),

            if (_metric == 'pace') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _refDistCtrl,
                decoration: const InputDecoration(
                  labelText: 'Distância mínima da corrida (opcional)',
                  hintText: 'Ex: 5 (km)',
                  suffixText: 'km',
                  prefixIcon: Icon(Icons.straighten_rounded),
                  helperText:
                      'Corridas menores que essa distância não contam para o ranking de pace',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],

            const SizedBox(height: 28),

            // ── STEP 4: Where ──
            _SectionHeader(
              number: '4',
              title: 'Local (opcional)',
              theme: theme,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Local ou percurso',
                hintText: 'Ex: Parque da Cidade, Brasília',
                prefixIcon: Icon(Icons.location_on_outlined),
                helperText:
                    'Deixe em branco se os atletas podem correr em qualquer lugar',
              ),
            ),

            const SizedBox(height: 28),

            // ── STEP 5: Extras ──
            _SectionHeader(
              number: '5',
              title: 'Configurações extras',
              theme: theme,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _maxCtrl,
              decoration: const InputDecoration(
                labelText: 'Máximo de participantes (opcional)',
                hintText: 'Sem limite se vazio',
                prefixIcon: Icon(Icons.group_rounded),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                if (n == null || n < 2) return 'Mínimo 2 participantes';
                return null;
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _requiresBadge,
              onChanged: (v) => setState(() => _requiresBadge = v),
              title: const Text('Requer badge de participação'),
              subtitle: const Text(
                  'Atletas precisam de badge ativo para participar'),
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 32),

            // ── Summary ──
            _buildSummary(theme),

            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Salvar modelo'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final metricLabel = switch (_metric) {
      'distance' => 'Distância',
      'time' => 'Tempo',
      'pace' => 'Pace',
      'elevation' => 'Elevação',
      _ => _metric,
    };
    final formatLabel = _isSingleRace
        ? 'Corrida única'
        : _customDuration
            ? '${_customDaysCtrl.text.trim().isEmpty ? '?' : _customDaysCtrl.text.trim()} dias'
            : _TemplateTile._durationLabel(_durationDays);

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resumo',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _SummaryRow(Icons.emoji_events_rounded, 'Ranking',
              metricLabel),
          _SummaryRow(Icons.calendar_today_rounded, 'Formato',
              formatLabel),
          if (_locationCtrl.text.trim().isNotEmpty)
            _SummaryRow(Icons.location_on_outlined, 'Local',
                _locationCtrl.text.trim()),
          if (_maxCtrl.text.trim().isNotEmpty)
            _SummaryRow(Icons.group_rounded, 'Máx. participantes',
                _maxCtrl.text.trim()),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String number;
  final String title;
  final ThemeData theme;

  const _SectionHeader({
    required this.number,
    required this.title,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary,
          child: Text(number,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _FormatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _FormatCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 28,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text('$label: ',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value, style: theme.textTheme.bodySmall),
          ),
        ],
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
  TimeOfDay? _startTime;

  bool get _isSingleRace => widget.template.durationDays == 1;

  @override
  void initState() {
    super.initState();
    if (_isSingleRace) {
      _startDate = DateTime.now().add(const Duration(days: 1));
      _startTime = const TimeOfDay(hour: 7, minute: 0);
    } else {
      final now = DateTime.now();
      final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
      _startDate = now.add(
          Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
    }
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 7, minute: 0),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _launch() async {
    if (_startDate == null) return;
    setState(() => _launching = true);

    try {
      final t = widget.template;
      DateTime startAt;
      if (_isSingleRace && _startTime != null) {
        startAt = DateTime(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
          _startTime!.hour,
          _startTime!.minute,
        ).toUtc();
      } else {
        startAt = DateTime(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
        ).toUtc();
      }
      final endAt = startAt.add(Duration(days: t.durationDays));

      final db = sl<SupabaseClient>();
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
          (res.data as Map<String, dynamic>?)?['championship_id']
              as String?;

      sl<ProductEventTracker>().trackOnce(
        ProductEvents.firstChampionshipLaunched,
        {'metric': t.metric, 'template_id': t.id},
      );

      if (champId != null) {
        sl<NotificationRulesService>().notifyChampionshipStarting(
          championshipId: champId,
        );
      }
      if (mounted) context.pop(champId ?? '');
    } on Object catch (e) {
      AppLogger.warn('Caught error', tag: 'StaffChampionshipTemplates', error: e);
      if (mounted) {
        setState(() => _launching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao criar campeonato.')),
        );
      }
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_isSingleRace ? 'Agendar corrida' : 'Criar campeonato'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${_TemplateTile._metricLabel(t.metric)} · '
                '${_TemplateTile._durationLabel(t.durationDays)}'),
            if (t.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(t.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
            const Divider(height: 24),

            Text(_isSingleRace ? 'Data da corrida:' : 'Data de início:'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: Text(
                  _startDate != null ? _fmtDate(_startDate!) : '—'),
            ),

            if (_isSingleRace) ...[
              const SizedBox(height: 12),
              const Text('Horário:'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time_rounded, size: 16),
                label: Text(
                    _startTime != null ? _fmtTime(_startTime!) : '—'),
              ),
            ],

            if (!_isSingleRace && _startDate != null) ...[
              const SizedBox(height: 12),
              Text(
                'Encerramento: ${_fmtDate(_startDate!.add(Duration(days: t.durationDays)))}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _launching
              ? null
              : () => context.pop(),
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
