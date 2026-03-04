import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_event.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_state.dart';
import 'package:omni_runner/presentation/screens/staff_training_scan_screen.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

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

  Future<void> _openScan(BuildContext context) async {
    final refreshed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StaffTrainingScanScreen(sessionId: sessionId),
      ),
    );
    if (refreshed == true && context.mounted) {
      context.read<TrainingDetailBloc>().add(const RefreshTrainingDetail());
    }
  }

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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Presença ($attendanceCount)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (session.isScheduled)
                              FilledButton.icon(
                                onPressed: () => _openScan(context),
                                icon: const Icon(Icons.qr_code_scanner),
                                label: const Text('Escanear QR'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (attendance.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(DesignTokens.spacingXl),
                          child: Center(
                            child: Text(
                              'Nenhuma presença registrada',
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
      floatingActionButton: BlocBuilder<TrainingDetailBloc, TrainingDetailState>(
        builder: (context, state) {
          return switch (state) {
            TrainingDetailLoaded(:final session) => session.isScheduled
                ? FloatingActionButton.extended(
                    onPressed: () => _openScan(context),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear QR'),
                  )
                : const SizedBox.shrink(),
            _ => const SizedBox.shrink(),
          };
        },
      ),
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
}

class _AttendanceTile extends StatelessWidget {
  final TrainingAttendanceEntity attendance;

  const _AttendanceTile({required this.attendance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final timeFormat = DateFormat('HH:mm');

    final methodLabel = switch (attendance.method) {
      CheckinMethod.qr => 'QR',
      CheckinMethod.manual => 'Manual',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.person, color: cs.onPrimaryContainer),
        ),
        title: Text(
          attendance.athleteDisplayName ?? attendance.athleteUserId,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          timeFormat.format(attendance.checkedAt.toLocal()),
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Text(
            methodLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
