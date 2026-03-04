import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_event.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_state.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class MissionsScreen extends StatelessWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.missions),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<MissionsBloc>().add(const RefreshMissions()),
          ),
        ],
      ),
      body: BlocBuilder<MissionsBloc, MissionsState>(
        builder: (context, state) => switch (state) {
          MissionsInitial() => const Center(
              child: Text('Carregue suas missões.'),
            ),
          MissionsLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          MissionsLoaded(:final active, :final completed, :final missionDefs) =>
            active.isEmpty && completed.isEmpty
                ? _empty(context)
                : _body(context, active, completed, missionDefs),
          MissionsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        },
      ),
    );
  }

  static Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.flag_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma missão ativa',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Novas missões aparecem diariamente.\nCorra para completar!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  static Widget _body(
    BuildContext context,
    List<MissionProgressEntity> active,
    List<MissionProgressEntity> completed,
    Map<String, MissionEntity> defs,
  ) {
    return ListView(
      children: [
        if (active.isNotEmpty) ...[
          _SectionHeader(
            title: 'Ativas',
            count: active.length,
            icon: Icons.flag,
            color: DesignTokens.success,
          ),
          ...active.map((m) => _MissionTile(progress: m, isActive: true, def: defs[m.missionId])),
        ],
        if (completed.isNotEmpty) ...[
          _SectionHeader(
            title: 'Completadas',
            count: completed.length,
            icon: Icons.check_circle,
            color: DesignTokens.success,
          ),
          ...completed.map((m) => _MissionTile(progress: m, isActive: false, def: defs[m.missionId])),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Section Header ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingSm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mission Tile ────────────────────────────────────────────

class _MissionTile extends StatelessWidget {
  final MissionProgressEntity progress;
  final bool isActive;
  final MissionEntity? def;

  const _MissionTile({required this.progress, required this.isActive, this.def});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = progress.progressFraction;
    final percent = (fraction * 100).toStringAsFixed(0);
    final isDone = progress.status == MissionProgressStatus.completed;

    final displayTitle = def?.title ?? 'Missão ${progress.missionId.length > 8 ? progress.missionId.substring(0, 8) : progress.missionId}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDone
                        ? DesignTokens.success.withValues(alpha: 0.15)
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isDone ? Icons.check : Icons.flag,
                    color: isDone
                        ? DesignTokens.success
                        : theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (def?.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          def!.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      Text(
                        _statusLabel(progress.status),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _statusColor(progress.status),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$percent%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDone ? DesignTokens.success : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDone ? DesignTokens.success : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatProgress(progress.currentValue, progress.targetValue),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (progress.completedAtMs != null)
                  Text(
                    'Concluída ${_formatDate(progress.completedAtMs!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(MissionProgressStatus s) => switch (s) {
        MissionProgressStatus.active => 'Em progresso',
        MissionProgressStatus.completed => 'Completada',
        MissionProgressStatus.expired => 'Expirada',
      };

  static Color _statusColor(MissionProgressStatus s) => switch (s) {
        MissionProgressStatus.active => DesignTokens.primary,
        MissionProgressStatus.completed => DesignTokens.success,
        MissionProgressStatus.expired => DesignTokens.textMuted,
      };

  static String _formatProgress(double current, double target) {
    if (target == 1.0) {
      return current >= 1.0 ? 'Concluído' : 'Pendente';
    }
    if (target >= 1000) {
      return '${(current / 1000).toStringAsFixed(1)} / ${(target / 1000).toStringAsFixed(1)} km';
    }
    return '${current.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}';
  }

  static String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}';
  }
}
