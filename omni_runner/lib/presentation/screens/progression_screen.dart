import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/weekly_goal_entity.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_bloc.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_event.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_state.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';

class ProgressionScreen extends StatelessWidget {
  const ProgressionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Progresso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<ProgressionBloc>()
                .add(const RefreshProgression()),
          ),
        ],
      ),
      body: BlocBuilder<ProgressionBloc, ProgressionState>(
        builder: (context, state) => switch (state) {
          ProgressionInitial() => const _EmptyState(),
          ProgressionLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          ProgressionLoaded(
            :final profile,
            :final recentXp,
            :final weeklyGoal,
          ) =>
            profile.lifetimeSessionCount == 0
                ? const _EmptyState()
                : _LoadedBody(
                    profile: profile,
                    recentXp: recentXp,
                    weeklyGoal: weeklyGoal,
                  ),
          ProgressionError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ),
              ),
            ),
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Empty state
// ═════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up_rounded,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Seu progresso aparece aqui',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Corra para ganhar XP, subir de nível e '
              'acompanhar sua evolução semana a semana.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.directions_run),
              label: const Text('Ir correr'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Loaded body
// ═════════════════════════════════════════════════════════════════════════════

class _LoadedBody extends StatelessWidget {
  final ProfileProgressEntity profile;
  final List<XpTransactionEntity> recentXp;
  final WeeklyGoalEntity? weeklyGoal;

  const _LoadedBody({
    required this.profile,
    required this.recentXp,
    this.weeklyGoal,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TipBanner(
            tipKey: TipKey.progressionHowTo,
            icon: Icons.lightbulb_outline_rounded,
            text: 'Cada corrida rende XP! Quanto mais longe e '
                'por mais tempo, mais XP você ganha. Mantenha '
                'a sequência diária para bônus extras.',
          ),
        ),

        // ── Block 1: Level + XP ──────────────────────────────────────
        _LevelCard(profile: profile),
        const SizedBox(height: 12),

        // ── Block 2: Streak ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _StreakCard(profile: profile),
        ),
        const SizedBox(height: 12),

        // ── Block 3: Weekly Goal ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: weeklyGoal != null
              ? _WeeklyGoalCard(goal: weeklyGoal!)
              : const _NoGoalCard(),
        ),
        const SizedBox(height: 12),

        // ── Stats summary ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _LifetimeStatsCard(profile: profile),
        ),

        // ── XP History ───────────────────────────────────────────────
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Histórico de XP',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        if (recentXp.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Nenhum XP registrado ainda.\nCorra para ganhar XP!',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...recentXp.take(50).map(_XpTile.new),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Block 1 — Level + XP bar
// ═════════════════════════════════════════════════════════════════════════════

class _LevelCard extends StatelessWidget {
  final ProfileProgressEntity profile;
  const _LevelCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final level = profile.level;
    final xpInLevel = profile.xpInCurrentLevel;
    final xpNeeded =
        profile.xpForNextLevel - ProfileProgressEntity.xpForLevel(level);
    final fraction =
        xpNeeded > 0 ? (xpInLevel / xpNeeded).clamp(0.0, 1.0) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.primary.withValues(alpha: 0.15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.15),
              border: Border.all(color: cs.primary, width: 3),
            ),
            child: Center(
              child: Text(
                '$level',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nível $level',
            style: theme.textTheme.titleLarge?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${profile.totalXp} XP total',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onPrimaryContainer.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 12,
              backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Faltam ${profile.xpToNextLevel} XP para o Nível ${level + 1}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onPrimaryContainer.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Block 2 — Streak
// ═════════════════════════════════════════════════════════════════════════════

class _StreakCard extends StatelessWidget {
  final ProfileProgressEntity profile;
  const _StreakCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streak = profile.dailyStreakCount;
    final best = profile.streakBest;
    final hasFreeze = profile.hasFreezeAvailable;
    final isActive = streak > 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isActive
          ? Colors.orange.withValues(alpha: 0.08)
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.orange.withValues(alpha: 0.2)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.local_fire_department,
                    color: isActive
                        ? Colors.orange
                        : theme.colorScheme.outline,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$streak ${streak == 1 ? 'dia' : 'dias'} seguidos',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (best > 0)
                        Text(
                          'Recorde: $best ${best == 1 ? 'dia' : 'dias'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasFreeze)
                  Tooltip(
                    message: 'Você pode faltar 1 dia sem perder a sequência',
                    child: Chip(
                      avatar: Icon(Icons.ac_unit,
                          size: 16, color: Colors.blue.shade700),
                      label: const Text('Proteção'),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isActive
                  ? 'Continue correndo para manter sua sequência!'
                  : 'Corra hoje para iniciar uma sequência.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Block 3 — Weekly Goal
// ═════════════════════════════════════════════════════════════════════════════

class _WeeklyGoalCard extends StatelessWidget {
  final WeeklyGoalEntity goal;
  const _WeeklyGoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final completed = goal.isCompleted;
    final pct = goal.progressPercent;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: completed
          ? Colors.green.withValues(alpha: 0.08)
          : cs.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: completed
                        ? Colors.green.withValues(alpha: 0.2)
                        : cs.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    completed ? Icons.check_circle : Icons.flag_rounded,
                    color: completed ? Colors.green : cs.secondary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meta da semana',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        completed
                            ? 'Parabéns! Meta atingida! +${goal.xpAwarded} XP'
                            : '${goal.currentLabel} de ${goal.targetLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: completed
                              ? Colors.green.shade700
                              : theme.colorScheme.outline,
                          fontWeight:
                              completed ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: completed ? Colors.green : cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: goal.progressFraction,
                minHeight: 10,
                backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  completed ? Colors.green : cs.primary,
                ),
              ),
            ),
            if (!completed) ...[
              const SizedBox(height: 8),
              Text(
                _remainingMessage(goal),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _remainingMessage(WeeklyGoalEntity g) {
    final remaining = g.targetValue - g.currentValue;
    if (remaining <= 0) return 'Quase lá!';
    if (g.metric == GoalMetric.distance) {
      final km = remaining / 1000;
      return 'Faltam ${km.toStringAsFixed(1)} km para completar.';
    }
    final min = remaining / 60;
    return 'Faltam ${min.toStringAsFixed(0)} min para completar.';
  }
}

class _NoGoalCard extends StatelessWidget {
  const _NoGoalCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.flag_outlined,
                  size: 28, color: theme.colorScheme.outline),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meta da semana',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Corra esta semana para gerar sua meta automática.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Lifetime Stats
// ═════════════════════════════════════════════════════════════════════════════

class _LifetimeStatsCard extends StatelessWidget {
  final ProfileProgressEntity profile;
  const _LifetimeStatsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estatísticas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatTile(
                  icon: Icons.directions_run,
                  label: 'Corridas',
                  value: '${profile.lifetimeSessionCount}',
                ),
                _StatTile(
                  icon: Icons.straighten,
                  label: 'Distância',
                  value: '${profile.lifetimeDistanceKm.toStringAsFixed(1)} km',
                ),
                _StatTile(
                  icon: Icons.timer_outlined,
                  label: 'Tempo',
                  value: _formatDuration(profile.lifetimeMovingMs),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StatTile(
                  icon: Icons.calendar_today,
                  label: 'Semana',
                  value: '${profile.weeklySessionCount}',
                ),
                _StatTile(
                  icon: Icons.calendar_month,
                  label: 'Mês',
                  value: '${profile.monthlySessionCount}',
                ),
                _StatTile(
                  icon: Icons.star_outline,
                  label: 'XP da temporada',
                  value: '${profile.seasonXp}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int ms) {
    final hours = ms ~/ 3600000;
    final minutes = (ms % 3600000) ~/ 60000;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// XP Transaction Tile
// ═════════════════════════════════════════════════════════════════════════════

class _XpTile extends StatelessWidget {
  final XpTransactionEntity tx;
  const _XpTile(this.tx);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: _sourceColor(tx.source).withValues(alpha: 0.1),
        child: Icon(_sourceIcon(tx.source),
            color: _sourceColor(tx.source), size: 20),
      ),
      title: Text(_sourceLabel(tx.source)),
      subtitle: Text(_formatDate(tx.createdAtMs)),
      trailing: Text(
        '+${tx.xp}',
        style: TextStyle(
          color: Colors.green.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  static String _sourceLabel(XpSource s) => switch (s) {
        XpSource.session => 'Corrida',
        XpSource.badge => 'Conquista',
        XpSource.mission => 'Missão',
        XpSource.streak => 'Sequência',
        XpSource.challenge => 'Desafio',
      };

  static IconData _sourceIcon(XpSource s) => switch (s) {
        XpSource.session => Icons.directions_run,
        XpSource.badge => Icons.military_tech,
        XpSource.mission => Icons.flag,
        XpSource.streak => Icons.local_fire_department,
        XpSource.challenge => Icons.emoji_events,
      };

  static Color _sourceColor(XpSource s) => switch (s) {
        XpSource.session => Colors.blue,
        XpSource.badge => Colors.amber,
        XpSource.mission => Colors.green,
        XpSource.streak => Colors.orange,
        XpSource.challenge => Colors.purple,
      };

  static String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
