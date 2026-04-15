import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

/// Athlete-facing screen to browse and join open championships.
///
/// Uses `champ-list` Edge Function to fetch open/active championships
/// and `champ-enroll` Edge Function for self-enrollment.
class AthleteChampionshipsScreen extends StatefulWidget {
  const AthleteChampionshipsScreen({super.key});

  @override
  State<AthleteChampionshipsScreen> createState() =>
      _AthleteChampionshipsScreenState();
}

class _AthleteChampionshipsScreenState
    extends State<AthleteChampionshipsScreen> {
  static const _tag = 'AthleteChampionships';

  bool _loading = true;
  String? _error;
  List<_ChampItem> _championships = [];
  final Set<String> _enrolled = {};
  String _statusFilter = 'all'; // all | open | active | enrolled

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
      // Trigger lifecycle transitions for due championships
      try {
        await _db.functions.invoke('champ-lifecycle', body: {})
            .timeout(const Duration(seconds: 10));
      } on Object catch (e) {
        AppLogger.warn('Unexpected error', tag: 'AthleteChampionshipsScreen', error: e);
      }

      final res = await _db.functions.invoke('champ-list', body: {});
      final data = res.data as Map<String, dynamic>? ?? {};
      final list = (data['championships'] as List<dynamic>?) ?? [];

      final uid = _db.auth.currentUser?.id;

      // Check which ones the user is already enrolled in
      if (uid != null && list.isNotEmpty) {
        final champIds = list.map((c) => (c as Map)['id'] as String).toList();
        final partRes = await _db
            .from('championship_participants')
            .select('championship_id')
            .eq('user_id', uid)
            .inFilter('championship_id', champIds);
        for (final row in (partRes as List<dynamic>)) {
          final map = row as Map<String, dynamic>;
          _enrolled.add(map['championship_id'] as String);
        }
      }

      _championships = list.map((c) {
        final m = c as Map<String, dynamic>;
        return _ChampItem(
          id: m['id'] as String,
          name: (m['name'] as String?) ?? '',
          description: (m['description'] as String?) ?? '',
          metric: (m['metric'] as String?) ?? 'distance',
          status: (m['status'] as String?) ?? 'open',
          requiresBadge: (m['requires_badge'] as bool?) ?? false,
          maxParticipants: m['max_participants'] as int?,
          startAt: DateTime.tryParse((m['start_at'] as String?) ?? ''),
          endAt: DateTime.tryParse((m['end_at'] as String?) ?? ''),
          hostGroupName: (m['host_group_name'] as String?) ?? '',
        );
      }).toList();

      if (mounted) setState(() => _loading = false);
    } on Object catch (e) {
      AppLogger.error('Failed to load championships: $e',
          tag: _tag, error: e);
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar os campeonatos.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _enroll(_ChampItem champ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Participar do campeonato?'),
        content: Text(champ.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Participar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await _db.functions.invoke('champ-enroll', body: {
        'championship_id': champ.id,
      });
      final data = res.data as Map<String, dynamic>? ?? {};
      if (data['ok'] == true) {
        AppLogger.info('Enrolled in championship ${champ.id}', tag: _tag);
        if (mounted) {
          setState(() => _enrolled.add(champ.id));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Inscrito em "${champ.name}"!')),
          );
        }
      } else {
        final err = data['error'] as Map<String, dynamic>?;
        final code = err?['code'] as String? ?? '';
        final msg = _friendlyError(code);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    } on Object catch (e) {
      AppLogger.error('Enrollment failed: $e', tag: _tag, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao se inscrever. Tente novamente.')),
        );
      }
    }
  }

  void _viewParticipants(_ChampItem champ) {
    context.push(
      AppRoutes.championshipRankingPath(champ.id),
      extra: ChampionshipRankingExtra(
        championshipId: champ.id,
        championshipName: champ.name,
        metric: champ.metric,
      ),
    );
  }

  static String _friendlyError(String code) => switch (code) {
        'NOT_OPEN' => 'Este campeonato não está mais aberto para inscrições.',
        'NO_GROUP' =>
          'Você precisa estar em uma assessoria para participar.',
        'BADGE_REQUIRED' =>
          'Este campeonato requer um badge de participação.',
        'FULL' => 'Campeonato lotado — número máximo de participantes atingido.',
        'GROUP_NOT_INVITED' =>
          'Sua assessoria não foi convidada para este campeonato.',
        _ => 'Não foi possível se inscrever.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Campeonatos')),
      body: _loading
          ? const ShimmerListLoader()
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _championships.isEmpty
                      ? _empty(theme)
                      : _buildFilteredList(theme),
                ),
    );
  }

  Widget _buildFilteredList(ThemeData theme) {
    final filtered = _championships.where((c) {
      if (_statusFilter == 'enrolled') return _enrolled.contains(c.id);
      if (_statusFilter == 'all') return true;
      return c.status == _statusFilter;
    }).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 12, DesignTokens.spacingMd, 0),
          child: Row(
            children: [
              _filterChip('Todos', 'all'),
              const SizedBox(width: 8),
              _filterChip('Abertos', 'open'),
              const SizedBox(width: 8),
              _filterChip('Ativos', 'active'),
              const SizedBox(width: 8),
              _filterChip('Inscritos', 'enrolled'),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum campeonato neste filtro',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 12, DesignTokens.spacingMd, DesignTokens.spacingLg),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final isEnrolled = _enrolled.contains(c.id);
                    return _ChampCard(
                      champ: c,
                      isEnrolled: isEnrolled,
                      onEnroll: c.status == 'open' && !isEnrolled
                          ? () => _enroll(c)
                          : null,
                      onViewParticipants: isEnrolled
                          ? () => _viewParticipants(c)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    return FilterChip(
      label: Text(label),
      selected: _statusFilter == value,
      onSelected: (_) => setState(() => _statusFilter = value),
      showCheckmark: false,
    );
  }

  Widget _empty(ThemeData theme) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(Icons.emoji_events_outlined,
                  size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('Nenhum campeonato disponível',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Quando sua assessoria ou outras\n'
                'abrirem campeonatos, eles aparecerão aqui.',
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
}

class _ChampItem {
  final String id;
  final String name;
  final String description;
  final String metric;
  final String status;
  final bool requiresBadge;
  final int? maxParticipants;
  final DateTime? startAt;
  final DateTime? endAt;
  final String hostGroupName;

  const _ChampItem({
    required this.id,
    required this.name,
    required this.description,
    required this.metric,
    required this.status,
    required this.requiresBadge,
    this.maxParticipants,
    this.startAt,
    this.endAt,
    this.hostGroupName = '',
  });
}

class _ChampCard extends StatelessWidget {
  final _ChampItem champ;
  final bool isEnrolled;
  final VoidCallback? onEnroll;
  final VoidCallback? onViewParticipants;

  const _ChampCard({
    required this.champ,
    required this.isEnrolled,
    this.onEnroll,
    this.onViewParticipants,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(champ.status);

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
                  child: Text(champ.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Text(
                    _statusLabel(champ.status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (champ.hostGroupName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.groups_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      champ.hostGroupName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (champ.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(champ.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(Icons.speed_rounded, _metricLabel(champ.metric)),
                if (champ.startAt != null)
                  _InfoChip(
                      Icons.calendar_today_rounded, _fmtDate(champ.startAt!)),
                if (champ.endAt != null)
                  _InfoChip(Icons.event_rounded, _fmtDate(champ.endAt!)),
                if (champ.requiresBadge)
                  const _InfoChip(Icons.verified_rounded, 'Requer badge'),
                if (champ.maxParticipants != null)
                  _InfoChip(
                      Icons.group_rounded, 'Máx ${champ.maxParticipants}'),
              ],
            ),
            const SizedBox(height: 12),
            if (isEnrolled)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: DesignTokens.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 18, color: DesignTokens.success),
                          SizedBox(width: 6),
                          Text('Inscrito',
                              style: TextStyle(
                                  color: DesignTokens.success, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onViewParticipants,
                    icon: const Icon(Icons.people_rounded, size: 18),
                    label: const Text('Ranking'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                  ),
                ],
              )
            else if (onEnroll != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onEnroll,
                  icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                  label: const Text('Participar'),
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

  static String _statusLabel(String s) => switch (s) {
        'open' => 'Aberto',
        'active' => 'Em andamento',
        'completed' => 'Encerrado',
        _ => s,
      };

  static Color _statusColor(String s) => switch (s) {
        'open' => DesignTokens.success,
        'active' => DesignTokens.primary,
        'completed' => DesignTokens.textMuted,
        _ => DesignTokens.textMuted,
      };

  static String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
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
