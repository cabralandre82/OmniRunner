import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/utils/error_messages.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_event.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_state.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Detail screen for a training session with attendance list and scan button.
/// Requires [sessionId]. Wraps with [TrainingDetailBloc] at navigation.
class StaffTrainingDetailScreen extends StatelessWidget {
  final String sessionId;

  const StaffTrainingDetailScreen({
    super.key,
    required this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<TrainingDetailBloc>()
        ..add(LoadTrainingDetail(sessionId: sessionId)),
      child: _StaffTrainingDetailView(sessionId: sessionId),
    );
  }
}

class _StaffTrainingDetailView extends StatelessWidget {
  final String sessionId;

  const _StaffTrainingDetailView({required this.sessionId});

  Future<void> _overrideStatus(
    BuildContext context,
    TrainingAttendanceEntity att,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Alterar status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            for (final s in ['completed', 'partial', 'absent', 'present', 'excused'])
              ListTile(
                leading: Icon(_statusIcon(attendanceStatusFromString(s)),
                    color: _statusColor(attendanceStatusFromString(s))),
                title: Text(attendanceStatusLabel(attendanceStatusFromString(s))),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    try {
      await sl<SupabaseClient>()
          .from('coaching_training_attendance')
          .update({'status': selected, 'method': 'manual'})
          .eq('id', att.id);
      if (context.mounted) {
        context.read<TrainingDetailBloc>().add(const RefreshTrainingDetail());
      }
    } on Object catch (e) {
      AppLogger.error('Override attendance failed', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.humanize(e))),
        );
      }
    }
  }

  static IconData _statusIcon(AttendanceStatus s) => switch (s) {
        AttendanceStatus.completed => Icons.check_circle,
        AttendanceStatus.partial => Icons.timelapse,
        AttendanceStatus.absent => Icons.cancel,
        AttendanceStatus.present => Icons.check,
        AttendanceStatus.late_ => Icons.schedule,
        AttendanceStatus.excused => Icons.info_outline,
      };

  static Color _statusColor(AttendanceStatus s) => switch (s) {
        AttendanceStatus.completed => DesignTokens.success,
        AttendanceStatus.partial => DesignTokens.warning,
        AttendanceStatus.absent => DesignTokens.error,
        AttendanceStatus.present => DesignTokens.success,
        AttendanceStatus.late_ => DesignTokens.warning,
        AttendanceStatus.excused => DesignTokens.primary,
      };

  void _showCancelDialog(BuildContext context, TrainingDetailBloc bloc) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar treino'),
        content: const Text(
          'Tem certeza que deseja cancelar este treino? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: DesignTokens.error,
            ),
            child: const Text('Cancelar treino'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        bloc.add(const CancelTraining());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateFormat = DateFormat('EEE, dd MMM • HH:mm', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<TrainingDetailBloc, TrainingDetailState>(
          builder: (context, state) {
            return Text(
              switch (state) {
                TrainingDetailLoaded(:final session) => session.title,
                _ => 'Detalhe do Treino',
              },
            );
          },
        ),
        actions: [
          BlocBuilder<TrainingDetailBloc, TrainingDetailState>(
            builder: (context, state) {
              return switch (state) {
                TrainingDetailLoaded(:final session) =>
                  session.isScheduled
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'cancel') {
                              _showCancelDialog(
                                context,
                                context.read<TrainingDetailBloc>(),
                              );
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'cancel',
                              child: Row(
                                children: [
                                  Icon(Icons.cancel_outlined),
                                  SizedBox(width: 8),
                                  Text('Cancelar Treino'),
                                ],
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                _ => const SizedBox.shrink(),
              };
            },
          ),
        ],
      ),
      body: BlocConsumer<TrainingDetailBloc, TrainingDetailState>(
        listener: (context, state) {
          switch (state) {
            case TrainingDetailError(:final message):
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: cs.error,
                ),
              );
            default:
              break;
          }
        },
        builder: (context, state) {
          return switch (state) {
            TrainingDetailInitial() || TrainingDetailLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            TrainingDetailError(:final message) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: cs.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: cs.error,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          context
                              .read<TrainingDetailBloc>()
                              .add(const RefreshTrainingDetail());
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            TrainingDetailLoaded(
              :final session,
              :final attendance,
              :final attendanceCount,
            ) =>
              RefreshIndicator(
                onRefresh: () async {
                  context
                      .read<TrainingDetailBloc>()
                      .add(const RefreshTrainingDetail());
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _SessionInfoCard(
                        session: session,
                        dateFormat: dateFormat,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingLg, DesignTokens.spacingMd, DesignTokens.spacingSm),
                        child: Text(
                          'Cumprimento do Treino ($attendanceCount)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (attendance.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(DesignTokens.spacingXl),
                          child: Center(
                            child: Text(
                              'Nenhum resultado registrado para este treino',
                              style: TextStyle(
                                color: DesignTokens.textMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _AttendanceTile(
                              attendance: attendance[index],
                              onOverride: (att) => _overrideStatus(context, att),
                            ),
                            childCount: attendance.length,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 80),
                    ),
                  ],
                ),
              ),
          };
        },
      ),
      floatingActionButton: const SizedBox.shrink(),
    );
  }
}

class _SessionInfoCard extends StatelessWidget {
  final TrainingSessionEntity session;
  final DateFormat dateFormat;

  const _SessionInfoCard({
    required this.session,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = switch (session.status) {
      TrainingSessionStatus.scheduled => DesignTokens.primary,
      TrainingSessionStatus.done => DesignTokens.success,
      TrainingSessionStatus.cancelled => DesignTokens.error,
    };

    final statusLabel = switch (session.status) {
      TrainingSessionStatus.scheduled => 'Agendado',
      TrainingSessionStatus.done => 'Realizado',
      TrainingSessionStatus.cancelled => 'Cancelado',
    };

    return Card(
      margin: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (session.description != null &&
                session.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                session.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  dateFormat.format(session.startsAt.toLocal()),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (session.endsAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Até ${dateFormat.format(session.endsAt!.toLocal())}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            if (session.locationName != null &&
                session.locationName!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      session.locationName!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (session.distanceTargetM != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.straighten, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Distância: ${(session.distanceTargetM! / 1000).toStringAsFixed(1)} km',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            if (session.paceMinSecKm != null && session.paceMaxSecKm != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.speed, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Pace: ${_fmtPace(session.paceMinSecKm!)} ~ ${_fmtPace(session.paceMaxSecKm!)} /km',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: DesignTokens.spacingXs),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: Text(
                statusLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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

class _AttendanceTile extends StatelessWidget {
  final TrainingAttendanceEntity attendance;
  final void Function(TrainingAttendanceEntity) onOverride;

  const _AttendanceTile({
    required this.attendance,
    required this.onOverride,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = _StaffTrainingDetailView._statusColor(attendance.status);
    final statusLabel = attendanceStatusLabel(attendance.status);
    final methodLabel = switch (attendance.method) {
      CheckinMethod.qr => 'QR',
      CheckinMethod.manual => 'Manual',
      CheckinMethod.auto => 'Auto',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: ListTile(
        onTap: () => onOverride(attendance),
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(
            _StaffTrainingDetailView._statusIcon(attendance.status),
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          attendance.athleteDisplayName ?? attendance.athleteUserId,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '$statusLabel • $methodLabel',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.edit_outlined,
          size: 18,
          color: cs.outline,
        ),
      ),
    );
  }
}
