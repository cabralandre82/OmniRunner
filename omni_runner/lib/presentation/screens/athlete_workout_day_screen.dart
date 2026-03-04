import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/data/services/workout_delivery_service.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/presentation/screens/athlete_delivery_screen.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/presentation/widgets/state_widgets.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';

// TODO: This screen appears to be unused. Consider removing or integrating it.
/// Shows the athlete's workout for today (or selected date).
/// Allows marking the workout as completed.
class AthleteWorkoutDayScreen extends StatefulWidget {
  final String groupId;

  const AthleteWorkoutDayScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<AthleteWorkoutDayScreen> createState() =>
      _AthleteWorkoutDayScreenState();
}

class _AthleteWorkoutDayScreenState extends State<AthleteWorkoutDayScreen> {
  bool _loading = true;
  String? _error;
  WorkoutAssignmentEntity? _assignment;
  WorkoutTemplateEntity? _template;
  bool _completing = false;
  int _pendingDeliveries = 0;

  @override
  void initState() {
    super.initState();
    _loadToday();
    _loadPendingDeliveryCount();
  }

  Future<void> _loadPendingDeliveryCount() async {
    try {
      final uid = sl<UserIdentityProvider>().userId;
      final count = await sl<WorkoutDeliveryService>().countPublishedItems(uid);
      if (mounted) {
        setState(() => _pendingDeliveries = count);
      }
    } catch (e) {
      AppLogger.warn('Failed to load delivery count', tag: 'WorkoutDayScreen', error: e);
    }
  }

  Future<void> _loadToday() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = sl<UserIdentityProvider>().userId;
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final assignments = await sl<IWorkoutRepo>().listAssignmentsByAthlete(
        groupId: widget.groupId,
        athleteUserId: uid,
        from: startOfDay,
        to: endOfDay,
        limit: 1,
      );

      WorkoutTemplateEntity? template;
      WorkoutAssignmentEntity? assignment;
      if (assignments.isNotEmpty) {
        assignment = assignments.first;
        template = await sl<IWorkoutRepo>().getTemplateById(assignment.templateId);
      }

      if (mounted) {
        setState(() {
          _assignment = assignment;
          _template = template;
          _loading = false;
        });
      }
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao carregar treino do dia',
        tag: 'WorkoutDayScreen',
        error: e,
        stack: stack,
      );
      if (mounted) {
        setState(() {
          _error = ErrorMessages.humanize(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _markCompleted() async {
    final assignment = _assignment;
    if (assignment == null) return;
    setState(() => _completing = true);
    try {
      await sl<IWorkoutRepo>().updateAssignmentStatus(
        assignment.id,
        WorkoutAssignmentStatus.completed,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Treino marcado como concluído!')),
      );
      _loadToday();
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao marcar treino como concluído',
        tag: 'WorkoutDayScreen',
        error: e,
        stack: stack,
      );
      if (mounted) {
        setState(() => _completing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.humanize(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Tela de Meu Treino do Dia',
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Meu Treino do Dia'),
        actions: [
          if (_pendingDeliveries > 0)
            IconButton(
              icon: Badge.count(
                count: _pendingDeliveries,
                backgroundColor: DesignTokens.error,
                child: const Icon(Icons.delivery_dining),
              ),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AthleteDeliveryScreen(),
                ));
                _loadPendingDeliveryCount();
              },
              tooltip: 'Entregas Pendentes',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadToday,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _buildBody(theme),
    ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return ListView(children: List.generate(5, (_) => const ShimmerCard()));
    }

    if (_error != null) {
      return ErrorState(
        message: _error ?? '',
        onRetry: _loadToday,
      );
    }

    if (_assignment == null) {
      return _buildEmpty(theme);
    }

    return _buildAssignment(theme);
  }

  Widget _buildEmpty(ThemeData theme) {
    return AppEmptyState(
      message: 'Sem treino agendado para hoje',
      icon: Icons.event_available_outlined,
    );
  }

  Widget _buildAssignment(ThemeData theme) {
    final assignment = _assignment;
    final template = _template;
    if (assignment == null) return _buildEmpty(theme);

    final cs = theme.colorScheme;
    final dateLabel = DateFormat('dd/MM/yyyy', 'pt_BR')
        .format(assignment.scheduledDate);
    final isCompleted =
        assignment.status == WorkoutAssignmentStatus.completed;

    final isDark = theme.brightness == Brightness.dark;
    final statusLabel = switch (assignment.status) {
      WorkoutAssignmentStatus.planned => 'Planejado',
      WorkoutAssignmentStatus.completed => 'Concluído',
      WorkoutAssignmentStatus.missed => 'Não realizado',
    };
    final statusColor = switch (assignment.status) {
      WorkoutAssignmentStatus.planned => cs.primary,
      WorkoutAssignmentStatus.completed => cs.tertiary,
      WorkoutAssignmentStatus.missed => cs.error,
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _template?.name ?? 'Treino',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: isDark ? 0.25 : 0.2),
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
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              dateLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (template != null &&
            (template.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            template.description ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
        if (assignment.notes != null &&
            (assignment.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.note_outlined, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    assignment.notes ?? '',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (template != null && template.blocks.isNotEmpty) ...[
          Text(
            'Blocos do Treino',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(template.blocks.length, (i) {
            final block = template.blocks[i];
            return _WorkoutBlockCard(block: block, index: i);
          }),
        ],
        const SizedBox(height: 24),
        if (!isCompleted)
          FilledButton.icon(
            onPressed: _completing ? null : _markCompleted,
            icon: _completing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(
                _completing ? 'Marcando...' : 'Marcar como Concluído'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
            ),
          ),
      ],
    );
  }
}

class _WorkoutBlockCard extends StatelessWidget {
  final WorkoutBlockEntity block;
  final int index;

  const _WorkoutBlockCard({required this.block, required this.index});

  static const _typeLabels = {
    WorkoutBlockType.warmup: 'Aquecimento',
    WorkoutBlockType.interval: 'Intervalo',
    WorkoutBlockType.recovery: 'Recuperação',
    WorkoutBlockType.cooldown: 'Desaquecimento',
    WorkoutBlockType.steady: 'Contínuo',
  };

  static const _typeColors = {
    WorkoutBlockType.warmup: DesignTokens.warning,
    WorkoutBlockType.interval: DesignTokens.error,
    WorkoutBlockType.recovery: DesignTokens.success,
    WorkoutBlockType.cooldown: DesignTokens.primary,
    WorkoutBlockType.steady: DesignTokens.success,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _typeColors[block.blockType] ?? theme.colorScheme.outline;
    final label = _typeLabels[block.blockType] ?? 'Bloco';
    final isDark = theme.brightness == Brightness.dark;
    final chipTextColor = isDark ? color.withValues(alpha: 0.9) : color;

    final details = <String>[];
    if (block.durationSeconds != null) {
      final min = block.durationSeconds! ~/ 60;
      final sec = block.durationSeconds! % 60;
      details.add(sec > 0 ? '${min}m${sec}s' : '${min}min');
    }
    if (block.distanceMeters != null) {
      if (block.distanceMeters! >= 1000) {
        details.add('${(block.distanceMeters! / 1000).toStringAsFixed(1)}km');
      } else {
        details.add('${block.distanceMeters}m');
      }
    }
    if (block.targetPaceSecondsPerKm != null) {
      final m = block.targetPaceSecondsPerKm! ~/ 60;
      final s = block.targetPaceSecondsPerKm! % 60;
      details.add('Pace ${m}:${s.toString().padLeft(2, '0')}/km');
    }
    if (block.targetHrZone != null) details.add('Zona FC ${block.targetHrZone}');
    if (block.rpeTarget != null) details.add('RPE ${block.rpeTarget}');

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacingSm, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isDark ? 0.25 : 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: chipTextColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '#${index + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      details.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if ((block.notes ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      block.notes ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
