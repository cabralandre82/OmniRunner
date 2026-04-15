import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_plan_repo.dart';

/// Detalhe de um treino prescrito pelo treinador.
///
/// Recebe o [workoutId] via rota e a entidade completa via [extra].
/// Se a entidade não for fornecida, carrega do repositório pelo ID.
class AthleteWorkoutDetailScreen extends StatefulWidget {
  const AthleteWorkoutDetailScreen({
    super.key,
    required this.workoutId,
    this.initialWorkout,
  });

  final String workoutId;
  final PlanWorkoutEntity? initialWorkout;

  @override
  State<AthleteWorkoutDetailScreen> createState() =>
      _AthleteWorkoutDetailScreenState();
}

class _AthleteWorkoutDetailScreenState
    extends State<AthleteWorkoutDetailScreen> {
  PlanWorkoutEntity? _workout;
  bool _loading = true;
  String? _error;
  bool _actionLoading = false;
  bool _sendingToWatch = false;

  static const _tag = 'WorkoutDetailScreen';

  @override
  void initState() {
    super.initState();
    if (widget.initialWorkout != null) {
      _workout = widget.initialWorkout;
      _loading = false;
    } else {
      _loadWorkout();
    }
  }

  Future<void> _loadWorkout() async {
    try {
      final repo = sl<ITrainingPlanRepo>();
      final workout = await repo.getWorkoutById(widget.workoutId);
      if (mounted) {
        setState(() {
          _workout = workout;
          _loading = false;
          _error = workout == null ? 'Treino não encontrado.' : null;
        });
      }
    } on Object catch (e) {
      AppLogger.error('loadWorkout failed', tag: _tag, error: e);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar o treino.';
        });
      }
    }
  }

  Future<void> _onStartWorkout() async {
    final workout = _workout;
    if (workout == null || _actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await sl<ITrainingPlanRepo>().startWorkout(workout.id);
      await _loadWorkout();
    } on Object catch (e) {
      AppLogger.error('startWorkout failed', tag: _tag, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao iniciar treino. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  void _onCompleteWorkout() {
    final workout = _workout;
    if (workout == null) return;
    context.push(
      '/athlete/plan-workout/${workout.id}/feedback',
      extra: workout,
    );
  }

  Future<void> _sendToWatch() async {
    final workout = _workout;
    final templateId = workout?.contentSnapshot?.templateId;
    if (templateId == null || _sendingToWatch) return;

    setState(() => _sendingToWatch = true);
    try {
      final response = await sl<SupabaseClient>().functions.invoke(
        'generate-fit-workout',
        body: {'template_id': templateId},
      );

      if (response.status != 200) {
        throw Exception('Erro ao gerar arquivo .FIT (status ${response.status})');
      }

      final rawData = response.data;
      final List<int> bytes;
      if (rawData is List<int>) {
        bytes = rawData;
      } else if (rawData is List) {
        bytes = rawData.cast<int>();
      } else {
        throw Exception('Formato de resposta inválido do servidor');
      }

      final dir = await getTemporaryDirectory();
      final safeName = workout!.contentSnapshot!.templateName
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final file = File('${dir.path}/$safeName.fit');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Treino: ${workout.contentSnapshot!.templateName}',
        ),
      );
    } on Exception catch (e, stack) {
      AppLogger.error('sendToWatch failed', tag: _tag, error: e, stack: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível gerar o arquivo: ${e.toString().split(':').last.trim()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingToWatch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Treino')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _workout == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Treino')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: DesignTokens.spacingMd),
                Text(_error ?? 'Treino não encontrado.',
                    textAlign: TextAlign.center),
                const SizedBox(height: DesignTokens.spacingLg),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _loadWorkout();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final workout = _workout!;
    return Scaffold(
      appBar: AppBar(
        title: Text(workout.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: DesignTokens.spacingMd),
            child: _StatusBadge(status: workout.status),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(
              top: DesignTokens.spacingMd,
              left: DesignTokens.spacingMd,
              right: DesignTokens.spacingMd,
              // Reserve space for the bottom action bar
              bottom: workout.status.isActionable || workout.status == PlanWorkoutStatus.completed
                  ? 96
                  : DesignTokens.spacingMd,
            ),
            children: [
              if (workout.isUpdatedAfterSync) _buildUpdatedBanner(context),
              _MetaSection(workout: workout),
              const SizedBox(height: DesignTokens.spacingMd),
              if (workout.coachNotes != null && workout.coachNotes!.isNotEmpty) ...[
                _CoachNotesCard(notes: workout.coachNotes!),
                const SizedBox(height: DesignTokens.spacingMd),
              ],
              if (workout.contentSnapshot != null) ...[
                _BlocksTimeline(snapshot: workout.contentSnapshot!),
                const SizedBox(height: DesignTokens.spacingMd),
              ],
              if (workout.completedWorkout != null) ...[
                _CompletedSection(completed: workout.completedWorkout!),
                const SizedBox(height: DesignTokens.spacingMd),
              ],
              if (workout.feedback != null) ...[
                _FeedbackSection(feedback: workout.feedback!),
              ],
            ],
          ),
          _BottomActionBar(
            workout: workout,
            loading: _actionLoading,
            sendingToWatch: _sendingToWatch,
            onStart: _onStartWorkout,
            onComplete: _onCompleteWorkout,
            onSendToWatch: workout.contentSnapshot?.templateId != null
                ? _sendToWatch
                : null,
          ),
        ],
      ),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final PlanWorkoutStatus status;

  Color get _color => switch (status) {
        PlanWorkoutStatus.released   => DesignTokens.info,
        PlanWorkoutStatus.inProgress => DesignTokens.brand,
        PlanWorkoutStatus.completed  => DesignTokens.success,
        PlanWorkoutStatus.cancelled  => DesignTokens.error,
        PlanWorkoutStatus.replaced   => DesignTokens.textMuted,
        _                            => DesignTokens.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ─── Updated Banner ───────────────────────────────────────────────────────────

Widget _buildUpdatedBanner(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingMd),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: DesignTokens.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: DesignTokens.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.update, size: 16, color: DesignTokens.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Treino atualizado pelo treinador após sincronização.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DesignTokens.warning,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );

// ─── Meta Section ─────────────────────────────────────────────────────────────

class _MetaSection extends StatelessWidget {
  const _MetaSection({required this.workout});
  final PlanWorkoutEntity workout;

  static final _dateFmt = DateFormat("EEEE, d 'de' MMMM", 'pt_BR');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = workout.contentSnapshot;
    final totalKm = snap != null ? snap.totalDistanceM / 1000 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _dateFmt.format(workout.scheduledDate),
          style: theme.textTheme.bodySmall?.copyWith(
            color: DesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingXs),
        Text(
          workout.displayName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: DesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Wrap(
          spacing: DesignTokens.spacingSm,
          runSpacing: DesignTokens.spacingXs,
          children: [
            _MetaChip(
              icon: _typeIcon(workout.workoutType),
              label: _typeLabel(workout.workoutType),
              color: DesignTokens.brand,
            ),
            if (totalKm > 0)
              _MetaChip(
                icon: Icons.straighten,
                label: '${totalKm.toStringAsFixed(1)} km',
                color: DesignTokens.info,
              ),
            if (snap != null && snap.blocks.isNotEmpty)
              _MetaChip(
                icon: Icons.layers,
                label: '${snap.blocks.length} bloco${snap.blocks.length == 1 ? '' : 's'}',
                color: DesignTokens.textSecondary,
              ),
          ],
        ),
      ],
    );
  }

  IconData _typeIcon(String type) => switch (type) {
        'interval'     => Icons.bolt,
        'regenerative' => Icons.spa,
        'long_run'     => Icons.directions_run,
        'strength'     => Icons.fitness_center,
        'test'         => Icons.timer,
        'race'         => Icons.emoji_events,
        _              => Icons.directions_run,
      };

  String _typeLabel(String type) => switch (type) {
        'interval'     => 'Intervalado',
        'regenerative' => 'Regenerativo',
        'long_run'     => 'Longão',
        'strength'     => 'Força',
        'test'         => 'Teste',
        'race'         => 'Competição',
        _              => 'Contínuo',
      };
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Coach Notes ──────────────────────────────────────────────────────────────

class _CoachNotesCard extends StatelessWidget {
  const _CoachNotesCard({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: DesignTokens.brand.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: DesignTokens.brand.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.record_voice_over_outlined,
              size: 18, color: DesignTokens.brand),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orientação do treinador',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: DesignTokens.brand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notes,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: DesignTokens.textPrimary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Blocks Timeline ──────────────────────────────────────────────────────────

class _BlocksTimeline extends StatelessWidget {
  const _BlocksTimeline({required this.snapshot});
  final WorkoutContentSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estrutura do treino',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: DesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        ...snapshot.blocks.asMap().entries.map((entry) {
          final idx = entry.key;
          final block = entry.value;
          final isLast = idx == snapshot.blocks.length - 1;
          return _BlockRow(block: block, isLast: isLast);
        }),
      ],
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({required this.block, required this.isLast});

  final PlanWorkoutBlock block;
  final bool isLast;

  Color get _blockColor => switch (block.blockType) {
        'warmup'   => DesignTokens.warning,
        'interval' => DesignTokens.error,
        'recovery' => DesignTokens.success,
        'cooldown' => DesignTokens.info,
        'steady'   => DesignTokens.brand,
        'rest'     => DesignTokens.textMuted,
        _          => DesignTokens.textMuted,
      };

  IconData get _blockIcon => switch (block.blockType) {
        'warmup'   => Icons.local_fire_department,
        'interval' => Icons.bolt,
        'recovery' => Icons.spa,
        'cooldown' => Icons.ac_unit,
        'steady'   => Icons.trending_flat,
        'rest'     => Icons.hotel,
        'repeat'   => Icons.repeat,
        _          => Icons.circle,
      };

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    if (s == 0) return '${m}min';
    return '${m}min ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _blockColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline connector
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Icon(_blockIcon, size: 14, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: DesignTokens.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          // Block content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : DesignTokens.spacingMd,
              ),
              child: Container(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? DesignTokens.surface
                      : Colors.white,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(color: DesignTokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          block.blockTypeLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (block.repeatCount != null &&
                            block.repeatCount! > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(DesignTokens.radiusFull),
                            ),
                            child: Text(
                              '× ${block.repeatCount}',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: color),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Wrap(
                      spacing: DesignTokens.spacingMd,
                      runSpacing: 2,
                      children: [
                        if (block.durationSeconds != null)
                          _BlockMetric(
                            icon: Icons.timer_outlined,
                            value: _formatDuration(block.durationSeconds!),
                          ),
                        if (block.distanceMeters != null)
                          _BlockMetric(
                            icon: Icons.straighten,
                            value: block.distanceMeters! >= 1000
                                ? '${(block.distanceMeters! / 1000).toStringAsFixed(1)} km'
                                : '${block.distanceMeters} m',
                          ),
                        if (block.targetPaceMinSecPerKm != null) ...[
                          _BlockMetric(
                            icon: Icons.speed,
                            value: block.targetPaceMaxSecPerKm != null
                                ? '${PlanWorkoutBlock.formatPace(block.targetPaceMinSecPerKm!)} – '
                                    '${PlanWorkoutBlock.formatPace(block.targetPaceMaxSecPerKm!)}'
                                : PlanWorkoutBlock.formatPace(
                                    block.targetPaceMinSecPerKm!),
                          ),
                        ],
                        if (block.targetHrZone != null)
                          _BlockMetric(
                            icon: Icons.favorite_border,
                            value: 'Zona ${block.targetHrZone}',
                          ),
                        if (block.targetHrMin != null &&
                            block.targetHrMax != null)
                          _BlockMetric(
                            icon: Icons.monitor_heart_outlined,
                            value:
                                '${block.targetHrMin}–${block.targetHrMax} bpm',
                          ),
                        if (block.rpeTarget != null)
                          _BlockMetric(
                            icon: Icons.bar_chart,
                            value: 'RPE ${block.rpeTarget}',
                          ),
                      ],
                    ),
                    if (block.notes != null && block.notes!.isNotEmpty) ...[
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text(
                        block.notes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: DesignTokens.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockMetric extends StatelessWidget {
  const _BlockMetric({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: DesignTokens.textSecondary),
        const SizedBox(width: 3),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DesignTokens.textSecondary,
              ),
        ),
      ],
    );
  }
}

// ─── Completed Section ────────────────────────────────────────────────────────

class _CompletedSection extends StatelessWidget {
  const _CompletedSection({required this.completed});
  final CompletedWorkoutSummary completed;

  String _formatDuration(int? seconds) {
    if (seconds == null) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}min';
    }
    return '${m}min ${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: DesignTokens.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: DesignTokens.success.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle,
                  size: 18, color: DesignTokens.success),
              const SizedBox(width: 6),
              Text(
                'Realizado',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: DesignTokens.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (completed.finishedAt != null) ...[
                const SizedBox(width: 8),
                Text(
                  DateFormat("d/M 'às' HH:mm", 'pt_BR')
                      .format(completed.finishedAt!.toLocal()),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DesignTokens.textMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          Row(
            children: [
              _StatCell(
                label: 'Distância',
                value: completed.actualDistanceM != null
                    ? '${(completed.actualDistanceM! / 1000).toStringAsFixed(2)} km'
                    : '—',
              ),
              _StatCell(
                label: 'Duração',
                value: _formatDuration(completed.actualDurationS),
              ),
              if (completed.actualAvgPaceSKm != null)
                _StatCell(
                  label: 'Pace médio',
                  value: PlanWorkoutBlock.formatPace(
                      completed.actualAvgPaceSKm!.toInt()),
                ),
              if (completed.perceivedEffort != null)
                _StatCell(
                  label: 'Esforço',
                  value: 'RPE ${completed.perceivedEffort}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: DesignTokens.textPrimary,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: DesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Feedback Section ─────────────────────────────────────────────────────────

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({required this.feedback});
  final WorkoutFeedbackSummary feedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: DesignTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seu feedback',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: DesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          if (feedback.rating != null)
            Row(
              children: [
                ...List.generate(
                  5,
                  (i) => Icon(
                    i < feedback.rating! ? Icons.star : Icons.star_border,
                    size: 20,
                    color: DesignTokens.warning,
                  ),
                ),
              ],
            ),
          if (feedback.howWasIt != null && feedback.howWasIt!.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spacingXs),
            Text(
              feedback.howWasIt!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DesignTokens.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Bottom Action Bar ────────────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.workout,
    required this.loading,
    required this.sendingToWatch,
    required this.onStart,
    required this.onComplete,
    this.onSendToWatch,
  });

  final PlanWorkoutEntity workout;
  final bool loading;
  final bool sendingToWatch;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback? onSendToWatch;

  @override
  Widget build(BuildContext context) {
    final status = workout.status;

    if (!status.isActionable && status != PlanWorkoutStatus.completed) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          DesignTokens.spacingSm,
          DesignTokens.spacingMd,
          DesignTokens.spacingLg,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? DesignTokens.bgSecondary
              : Colors.white,
          border: const Border(
            top: BorderSide(color: DesignTokens.border),
          ),
        ),
        child: Builder(builder: (_) {
          if (loading) {
            return const Center(
              child: SizedBox(
                height: 44,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          if (status == PlanWorkoutStatus.released) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onSendToWatch != null) ...[
                  _WatchButton(
                    loading: sendingToWatch,
                    onPressed: onSendToWatch,
                  ),
                  const SizedBox(height: DesignTokens.spacingSm),
                ],
                FilledButton.icon(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar treino'),
                ),
              ],
            );
          }

          if (status == PlanWorkoutStatus.inProgress) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onSendToWatch != null) ...[
                  _WatchButton(
                    loading: sendingToWatch,
                    onPressed: onSendToWatch,
                  ),
                  const SizedBox(height: DesignTokens.spacingSm),
                ],
                FilledButton.icon(
                  onPressed: onComplete,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: DesignTokens.success,
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text('Concluir treino'),
                ),
              ],
            );
          }

          if (status == PlanWorkoutStatus.completed) {
            return OutlinedButton.icon(
              onPressed: onComplete,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: Text(workout.feedback != null
                  ? 'Editar feedback'
                  : 'Adicionar feedback'),
            );
          }

          return const SizedBox.shrink();
        }),
      ),
    );
  }
}

class _WatchButton extends StatelessWidget {
  const _WatchButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            side: const BorderSide(color: DesignTokens.border),
          ),
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.watch_outlined, size: 20),
          label: Text(
            loading ? 'Gerando arquivo .FIT…' : 'Enviar para relógio',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Garmin, COROS e Suunto: use o arquivo .FIT gerado. '
                'Apple Watch e WearOS sincronizam automaticamente pelo celular.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
