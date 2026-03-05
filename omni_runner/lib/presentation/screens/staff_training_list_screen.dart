import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_bloc.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_event.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_state.dart';
import 'package:omni_runner/presentation/screens/staff_training_create_screen.dart';
import 'package:omni_runner/presentation/screens/staff_training_detail_screen.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// List of training sessions for the current group (upcoming and past).
/// Requires [groupId] and wraps with [TrainingListBloc] at navigation.
class StaffTrainingListScreen extends StatelessWidget {
  final String groupId;

  const StaffTrainingListScreen({
    super.key,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<TrainingListBloc>()
        ..add(LoadTrainingSessions(groupId: groupId)),
      child: _StaffTrainingListView(groupId: groupId),
    );
  }
}

class _StaffTrainingListView extends StatelessWidget {
  final String groupId;

  const _StaffTrainingListView({required this.groupId});

  void _openCreate(BuildContext context) async {
    final uid = sl<UserIdentityProvider>().userId;
    final result = await Navigator.of(context).push<TrainingSessionEntity?>(
      MaterialPageRoute(
        builder: (_) => StaffTrainingCreateScreen(
          groupId: groupId,
          userId: uid,
        ),
      ),
    );
    if (result != null && context.mounted) {
      context.read<TrainingListBloc>().add(const RefreshTrainingSessions());
    }
  }

  void _openDetail(BuildContext context, String sessionId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StaffTrainingDetailScreen(sessionId: sessionId),
      ),
    ).then((_) {
      if (context.mounted) {
        context.read<TrainingListBloc>().add(const RefreshTrainingSessions());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('EEE, dd MMM • HH:mm', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda de Treinos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openCreate(context),
            tooltip: 'Novo treino',
          ),
        ],
      ),
      body: BlocBuilder<TrainingListBloc, TrainingListState>(
        builder: (context, state) {
          return switch (state) {
            TrainingListInitial() || TrainingListLoading() =>
              const ShimmerListLoader(),
            TrainingListError(:final message) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          context
                              .read<TrainingListBloc>()
                              .add(const RefreshTrainingSessions());
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            TrainingListLoaded(:final sessions) => sessions.isEmpty
                ? _buildEmpty(theme)
                : RefreshIndicator(
                    onRefresh: () async {
                      context
                          .read<TrainingListBloc>()
                          .add(const RefreshTrainingSessions());
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.all(DesignTokens.spacingMd),
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        return _TrainingSessionCard(
                          session: session,
                          dateFormat: dateFormat,
                          onTap: () => _openDetail(context, session.id),
                        );
                      },
                    ),
                  ),
          };
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo Treino'),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum treino agendado',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toque em "+" para criar o primeiro treino.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingSessionCard extends StatelessWidget {
  final TrainingSessionEntity session;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _TrainingSessionCard({
    required this.session,
    required this.dateFormat,
    required this.onTap,
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
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: DesignTokens.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
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
                  Icon(Icons.schedule, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    dateFormat.format(session.startsAt.toLocal()),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (session.locationName != null &&
                  session.locationName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        session.locationName!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              FutureBuilder<int>(
                future: sl<ITrainingAttendanceRepo>().countBySession(session.id),
                builder: (context, snap) {
                  final count = snap.data ?? 0;
                  return Row(
                    children: [
                      Icon(Icons.people_outline,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(
                        '$count atleta${count != 1 ? 's' : ''} concluí${count != 1 ? 'ram' : 'u'}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
