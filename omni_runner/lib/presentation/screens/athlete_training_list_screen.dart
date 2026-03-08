import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_event.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_state.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

/// Lista de treinos do grupo do atleta (próximos e anteriores).
class AthleteTrainingListScreen extends StatelessWidget {
  final String groupId;

  const AthleteTrainingListScreen({
    super.key,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<TrainingListBloc>()
        ..add(LoadTrainingSessions(groupId: groupId)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meus Treinos'),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  context.read<TrainingListBloc>().add(const RefreshTrainingSessions()),
            ),
          ],
        ),
        body: BlocBuilder<TrainingListBloc, TrainingListState>(
          builder: (context, state) => switch (state) {
            TrainingListInitial() => _buildLoading(),
            TrainingListLoading() => _buildLoading(),
            TrainingListLoaded(:final sessions) => sessions.isEmpty
                ? _buildEmpty(context)
                : _buildLoaded(context, sessions),
            TrainingListError(:final message) => _buildError(context, message),
          },
        ),
      ),
    );
  }

  Widget _buildLoading() => const ShimmerListLoader();

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Nenhum treino agendado',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Não há treinos agendados para este grupo.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.read<TrainingListBloc>().add(LoadTrainingSessions(groupId: groupId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, List<TrainingSessionEntity> sessions) {
    final upcoming = sessions
        .where((s) => s.isUpcoming)
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = sessions
        .where((s) => s.isPast || s.isCancelled)
        .toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));

    return RefreshIndicator(
      onRefresh: () async {
        context.read<TrainingListBloc>().add(const RefreshTrainingSessions());
        await context.read<TrainingListBloc>().stream.first;
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm, horizontal: DesignTokens.spacingMd),
        children: [
          if (upcoming.isNotEmpty) ...[
            const _SectionHeader(title: 'Próximos'),
            ...upcoming.map((s) => _TrainingCard(
                  session: s,
                  onTap: () => _showSessionInfo(context, s),
                )),
            const SizedBox(height: 24),
          ],
          if (past.isNotEmpty) ...[
            const _SectionHeader(title: 'Anteriores'),
            ...past.map((s) => _TrainingCard(
                  session: s,
                  onTap: () => _showSessionInfo(context, s),
                )),
          ],
        ],
      ),
    );
  }

  void _showSessionInfo(BuildContext context, TrainingSessionEntity session) {
    final theme = Theme.of(context);
    final uid = sl<SupabaseClient>().auth.currentUser?.id;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(session.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              DateFormat('d MMM yyyy, HH:mm', 'pt_BR').format(session.startsAt),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
            if (session.locationName != null && session.locationName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(session.locationName!,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ),
                  ],
                ),
              ),
            if (session.distanceTargetM != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.straighten, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text('Distância: ${(session.distanceTargetM! / 1000).toStringAsFixed(1)} km',
                    style: theme.textTheme.bodyMedium),
              ]),
            ],
            if (session.paceMinSecKm != null && session.paceMaxSecKm != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.speed, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  'Pace: ${_fmtPace(session.paceMinSecKm!)} ~ ${_fmtPace(session.paceMaxSecKm!)} /km',
                  style: theme.textTheme.bodyMedium,
                ),
              ]),
            ],
            if (session.description != null && session.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(session.description!),
            ],
            if (uid != null) ...[
              const SizedBox(height: 16),
              _AthleteStatusBadge(sessionId: session.id, athleteId: uid),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _fmtPace(double secPerKm) {
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).round();
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

class _AthleteStatusBadge extends StatelessWidget {
  final String sessionId;
  final String athleteId;

  const _AthleteStatusBadge({required this.sessionId, required this.athleteId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>?>(
      future: sl<SupabaseClient>()
          .from('coaching_training_attendance')
          .select('status, method')
          .eq('session_id', sessionId)
          .eq('athlete_user_id', athleteId)
          .maybeSingle(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 24, child: Center(child: LinearProgressIndicator()));
        }
        final data = snap.data;
        if (data == null) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Row(children: [
              Icon(Icons.hourglass_empty, size: 18, color: theme.colorScheme.outline),
              const SizedBox(width: 8),
              Text('Aguardando avaliação', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
            ]),
          );
        }
        final status = attendanceStatusFromString(data['status'] as String? ?? 'present');
        final label = attendanceStatusLabel(status);
        final color = switch (status) {
          AttendanceStatus.completed || AttendanceStatus.present => DesignTokens.success,
          AttendanceStatus.partial || AttendanceStatus.late_ => DesignTokens.warning,
          AttendanceStatus.absent => DesignTokens.error,
          AttendanceStatus.excused => DesignTokens.primary,
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            Icon(
              switch (status) {
                AttendanceStatus.completed || AttendanceStatus.present => Icons.check_circle,
                AttendanceStatus.partial || AttendanceStatus.late_ => Icons.timelapse,
                AttendanceStatus.absent => Icons.cancel,
                AttendanceStatus.excused => Icons.info_outline,
              },
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ]),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm, top: DesignTokens.spacingSm),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  final TrainingSessionEntity session;
  final VoidCallback onTap;

  const _TrainingCard({
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = switch (session.status) {
      TrainingSessionStatus.scheduled => session.isUpcoming ? 'Agendado' : 'Concluído',
      TrainingSessionStatus.cancelled => 'Cancelado',
      TrainingSessionStatus.done => 'Concluído',
    };
    final statusColor = switch (session.status) {
      TrainingSessionStatus.scheduled =>
          session.isUpcoming ? DesignTokens.success : theme.colorScheme.outline,
      TrainingSessionStatus.cancelled => theme.colorScheme.error,
      TrainingSessionStatus.done => theme.colorScheme.outline,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('d MMM yyyy, HH:mm', 'pt_BR').format(session.startsAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              if (session.locationName != null && session.locationName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        session.locationName!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (session.distanceTargetM != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.straighten, size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 6),
                    Text(
                      '${(session.distanceTargetM! / 1000).toStringAsFixed(1)} km',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
