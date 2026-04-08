import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/presentation/blocs/training_feed/training_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_feed/training_feed_event.dart';
import 'package:omni_runner/presentation/blocs/training_feed/training_feed_state.dart';

/// Feed principal do atleta — agenda de treinos liberados pelo treinador.
/// Organiza por data, permite navegar entre dias e acessa o detalhe.
class AthleteTrainingFeedScreen extends StatefulWidget {
  const AthleteTrainingFeedScreen({super.key});

  @override
  State<AthleteTrainingFeedScreen> createState() =>
      _AthleteTrainingFeedScreenState();
}

class _AthleteTrainingFeedScreenState
    extends State<AthleteTrainingFeedScreen> {
  late final PageController _pageController;
  late DateTime _today;
  // Janela de dias exibidos na barra de scroll
  static const int _daysWindow = 28;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _pageController = PageController(initialPage: 7, viewportFraction: 0.16);
    context.read<TrainingFeedBloc>().add(LoadTrainingFeed(focusDate: _today));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<DateTime> _buildDays(DateTime anchor) {
    final start = anchor.subtract(const Duration(days: 7));
    return List.generate(_daysWindow, (i) => start.add(Duration(days: i)));
  }

  void _selectDay(DateTime day, TrainingFeedLoaded state) {
    HapticFeedback.selectionClick();
    context.read<TrainingFeedBloc>().add(SelectFeedDate(day));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TrainingFeedBloc, TrainingFeedState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Meus Treinos'),
            actions: [
              if (state is TrainingFeedLoaded && state.isSyncing)
                const Padding(
                  padding: EdgeInsets.only(right: DesignTokens.spacingMd),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () =>
                      context.read<TrainingFeedBloc>().add(const RefreshTrainingFeed()),
                  tooltip: 'Sincronizar',
                ),
            ],
          ),
          body: _buildBody(state),
        );
      },
    );
  }

  Widget _buildBody(TrainingFeedState state) {
    if (state is TrainingFeedLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is TrainingFeedError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: DesignTokens.spacingMd),
              Text(state.message, textAlign: TextAlign.center),
              const SizedBox(height: DesignTokens.spacingLg),
              FilledButton.icon(
                onPressed: () =>
                    context.read<TrainingFeedBloc>().add(LoadTrainingFeed(focusDate: _today)),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is TrainingFeedLoaded) {
      final days = _buildDays(state.selectedDate);
      final workouts = state.workoutsForSelectedDate
          .where((w) => w.status.isVisibleToAthlete)
          .toList();

      return Column(
        children: [
          // ── Horizontal date strip ──────────────────────────────────────
          _DateStrip(
            days: days,
            selectedDate: state.selectedDate,
            workoutsByDate: state.workoutsByDate,
            onDaySelected: (d) => _selectDay(d, state),
          ),

          const Divider(height: 1),

          // ── Workout list for selected day ──────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                context.read<TrainingFeedBloc>().add(const RefreshTrainingFeed());
              },
              child: workouts.isEmpty
                  ? _EmptyDay(date: state.selectedDate, today: _today)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spacingMd,
                        horizontal: DesignTokens.spacingMd,
                      ),
                      itemCount: workouts.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: DesignTokens.spacingSm),
                      itemBuilder: (ctx, i) => _WorkoutCard(
                        workout: workouts[i],
                        onTap: () => ctx.push(
                          '/athlete/plan-workout/${workouts[i].id}',
                          extra: workouts[i],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

// ─── Date Strip ───────────────────────────────────────────────────────────────

class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.days,
    required this.selectedDate,
    required this.workoutsByDate,
    required this.onDaySelected,
  });

  final List<DateTime> days;
  final DateTime selectedDate;
  final Map<String, List<PlanWorkoutEntity>> workoutsByDate;
  final ValueChanged<DateTime> onDaySelected;

  static final _weekdayFmt = DateFormat('E', 'pt_BR');
  static final _dayFmt     = DateFormat('d');

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}-'
      '${d.month.toString().padLeft(2,'0')}-'
      '${d.day.toString().padLeft(2,'0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final today  = DateTime.now();

    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingSm,
          vertical: DesignTokens.spacingSm,
        ),
        itemCount: days.length,
        itemBuilder: (ctx, i) {
          final day      = days[i];
          final isToday  = _isSameDay(day, today);
          final isSelected = _isSameDay(day, selectedDate);
          final key      = _key(day);
          final dayWorkouts = workoutsByDate[key] ?? [];
          final hasReleased = dayWorkouts.any((w) =>
              w.status == PlanWorkoutStatus.released ||
              w.status == PlanWorkoutStatus.inProgress);
          final allDone = dayWorkouts.isNotEmpty &&
              dayWorkouts.every((w) => w.status == PlanWorkoutStatus.completed);

          return GestureDetector(
            onTap: () => onDaySelected(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 52,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isSelected
                    ? DesignTokens.brand
                    : isToday
                        ? DesignTokens.brand.withValues(alpha: 0.12)
                        : isDark
                            ? DesignTokens.surface
                            : Colors.transparent,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(
                  color: isSelected
                      ? DesignTokens.brand
                      : isToday
                          ? DesignTokens.brand.withValues(alpha: 0.4)
                          : DesignTokens.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _weekdayFmt.format(day).substring(0, 3),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? Colors.white
                          : DesignTokens.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dayFmt.format(day),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isSelected ? Colors.white : DesignTokens.textPrimary,
                      fontWeight: isSelected || isToday
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Dot indicator
                  if (dayWorkouts.isNotEmpty)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: allDone
                            ? DesignTokens.success
                            : hasReleased
                                ? (isSelected ? Colors.white : DesignTokens.brand)
                                : DesignTokens.textMuted,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 5),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Workout Card ─────────────────────────────────────────────────────────────

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout, required this.onTap});

  final PlanWorkoutEntity workout;
  final VoidCallback onTap;

  Color _statusColor(BuildContext context) => switch (workout.status) {
        PlanWorkoutStatus.released    => DesignTokens.info,
        PlanWorkoutStatus.inProgress  => DesignTokens.brand,
        PlanWorkoutStatus.completed   => DesignTokens.success,
        PlanWorkoutStatus.cancelled   => DesignTokens.error,
        PlanWorkoutStatus.replaced    => DesignTokens.textMuted,
        _                             => DesignTokens.textMuted,
      };

  IconData _typeIcon() => switch (workout.workoutType) {
        'interval'    => Icons.bolt,
        'regenerative'=> Icons.spa,
        'long_run'    => Icons.directions_run,
        'strength'    => Icons.fitness_center,
        'test'        => Icons.timer,
        'race'        => Icons.emoji_events,
        _             => Icons.directions_run,
      };

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color  = _statusColor(context);
    final snap   = workout.contentSnapshot;
    final completed = workout.completedWorkout;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? DesignTokens.surface : Colors.white,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          border: Border.all(
            color: DesignTokens.border,
            width: 1,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Row(
          children: [
            // Left accent strip
            Container(
              width: 4,
              height: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(DesignTokens.radiusMd),
                  bottomLeft: Radius.circular(DesignTokens.radiusMd),
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_typeIcon(), size: 16, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            workout.displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: workout.status == PlanWorkoutStatus.cancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Updated badge
                        if (workout.isUpdatedAfterSync)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: DesignTokens.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                            ),
                            child: Text(
                              'Atualizado',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: DesignTokens.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: DesignTokens.spacingXs),

                    // Status + distance
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                          ),
                          child: Text(
                            workout.status.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (snap != null && snap.totalDistanceM > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${(snap.totalDistanceM / 1000).toStringAsFixed(1)} km',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: DesignTokens.textSecondary,
                            ),
                          ),
                        ],
                        if (snap != null && snap.blocks.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${snap.blocks.length} bloco${snap.blocks.length == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: DesignTokens.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Completed metrics
                    if (completed != null && workout.status == PlanWorkoutStatus.completed) ...[
                      const SizedBox(height: DesignTokens.spacingXs),
                      Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 13, color: DesignTokens.success),
                          const SizedBox(width: 4),
                          if (completed.actualDistanceM != null)
                            Text(
                              '${(completed.actualDistanceM! / 1000).toStringAsFixed(1)} km realizado',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: DesignTokens.success,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (workout.feedback?.rating != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '★' * (workout.feedback!.rating ?? 0),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: DesignTokens.warning,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],

                    // Coach notes
                    if (workout.coachNotes != null &&
                        workout.coachNotes!.isNotEmpty) ...[
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text(
                        workout.coachNotes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: DesignTokens.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.only(right: DesignTokens.spacingMd),
              child: Icon(Icons.chevron_right, color: DesignTokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty Day ────────────────────────────────────────────────────────────────

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.date, required this.today});

  final DateTime date;
  final DateTime today;

  bool get _isPast =>
      date.isBefore(DateTime(today.year, today.month, today.day));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            children: [
              const SizedBox(height: DesignTokens.spacingXl),
              Icon(
                _isPast ? Icons.event_available : Icons.free_breakfast,
                size: 56,
                color: DesignTokens.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: DesignTokens.spacingMd),
              Text(
                _isPast
                    ? 'Sem treino registrado neste dia'
                    : 'Nenhum treino liberado para este dia',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: DesignTokens.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              if (!_isPast) ...[
                const SizedBox(height: DesignTokens.spacingSm),
                Text(
                  'Seu treinador irá liberar os treinos aqui.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DesignTokens.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
