import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_bloc.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_event.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_state.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Tabbed profile view for a specific athlete (staff perspective).
class StaffAthleteProfileScreen extends StatefulWidget {
  final String groupId;
  final String athleteUserId;
  final String athleteDisplayName;

  const StaffAthleteProfileScreen({
    super.key,
    required this.groupId,
    required this.athleteUserId,
    required this.athleteDisplayName,
  });

  @override
  State<StaffAthleteProfileScreen> createState() =>
      _StaffAthleteProfileScreenState();
}

class _StaffAthleteProfileScreenState extends State<StaffAthleteProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AthleteProfileBloc>()
        ..add(LoadAthleteProfile(
          groupId: widget.groupId,
          athleteUserId: widget.athleteUserId,
        )),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.athleteDisplayName,
            overflow: TextOverflow.ellipsis,
          ),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Visão geral'),
              Tab(text: 'Notas'),
              Tab(text: 'Tags'),
              Tab(text: 'Presença'),
              Tab(text: 'Alertas'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _OverviewTab(
              groupId: widget.groupId,
              athleteUserId: widget.athleteUserId,
            ),
            _NotesTab(
              groupId: widget.groupId,
              athleteUserId: widget.athleteUserId,
            ),
            const _TagsTab(),
            _PresencaTab(
              groupId: widget.groupId,
              athleteUserId: widget.athleteUserId,
            ),
            const _AlertasTab(),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final String groupId;
  final String athleteUserId;

  const _OverviewTab({
    required this.groupId,
    required this.athleteUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<AthleteProfileBloc, AthleteProfileState>(
      builder: (context, state) {
        return switch (state) {
          AthleteProfileInitial() || AthleteProfileLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          AthleteProfileError(:final message) => Center(
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
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        context
                            .read<AthleteProfileBloc>()
                            .add(const RefreshAthleteProfile());
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          AthleteProfileLoaded(
            :final status,
            :final tags,
            :final notes,
          ) => SingleChildScrollView(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusCard(
                    status: status,
                    groupId: groupId,
                    athleteUserId: athleteUserId,
                  ),
                  const SizedBox(height: 24),
                  FutureBuilder<int>(
                    future: sl<ITrainingAttendanceRepo>().listByAthlete(
                      groupId: groupId,
                      athleteUserId: athleteUserId,
                    ).then((l) => l.length),
                    builder: (context, snap) {
                      final attendanceCount = snap.data ?? 0;
                      final lastNote = notes.isNotEmpty
                          ? notes.reduce(
                              (a, b) =>
                                  a.createdAt.isAfter(b.createdAt) ? a : b,
                            )
                          : null;
                      return _QuickStatsRow(
                        attendanceCount: attendanceCount,
                        tagCount: tags.length,
                        lastNoteDate: lastNote?.createdAt,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  if (notes.isNotEmpty) ...[
                    Text(
                      'Últimas notas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...notes.take(3).map(
                          (n) => _NotePreviewCard(note: n),
                        ),
                  ],
                ],
              ),
            ),
        };
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  final MemberStatusEntity? status;
  final String groupId;
  final String athleteUserId;

  const _StatusCard({
    required this.status,
    required this.groupId,
    required this.athleteUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = status?.status ?? MemberStatusValue.active;
    final info = _statusInfo(theme, current);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: DesignTokens.spacingSm,
                  ),
                  decoration: BoxDecoration(
                    color: info.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Text(
                    info.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: info.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<MemberStatusValue>(
                  onSelected: (v) {
                    context.read<AthleteProfileBloc>().add(UpdateStatus(v));
                  },
                  itemBuilder: (ctx) => MemberStatusValue.values
                      .map(
                        (v) => PopupMenuItem(
                          value: v,
                          child: Text(_statusLabel(v)),
                        ),
                      )
                      .toList(),
                  child: const Text('Alterar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(MemberStatusValue v) => switch (v) {
        MemberStatusValue.active => 'Ativo',
        MemberStatusValue.paused => 'Pausado',
        MemberStatusValue.injured => 'Lesionado',
        MemberStatusValue.inactive => 'Inativo',
        MemberStatusValue.trial => 'Trial',
      };

  ({String label, Color color}) _statusInfo(
      ThemeData theme, MemberStatusValue v) {
    return switch (v) {
      MemberStatusValue.active =>
        (label: 'Ativo', color: DesignTokens.success),
      MemberStatusValue.paused =>
        (label: 'Pausado', color: DesignTokens.warning),
      MemberStatusValue.injured =>
        (label: 'Lesionado', color: DesignTokens.error),
      MemberStatusValue.inactive =>
        (label: 'Inativo', color: DesignTokens.textSecondary),
      MemberStatusValue.trial => (label: 'Trial', color: DesignTokens.primary),
    };
  }
}

class _QuickStatsRow extends StatelessWidget {
  final int attendanceCount;
  final int tagCount;
  final DateTime? lastNoteDate;

  const _QuickStatsRow({
    required this.attendanceCount,
    required this.tagCount,
    this.lastNoteDate,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'pt_BR');

    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: Icons.event_available,
            label: '$attendanceCount presença${attendanceCount != 1 ? 's' : ''}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatChip(
            icon: Icons.label_outline,
            label: '$tagCount tag${tagCount != 1 ? 's' : ''}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatChip(
            icon: Icons.note_outlined,
            label: lastNoteDate != null ? fmt.format(lastNoteDate!) : 'Sem notas',
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _NotePreviewCard extends StatelessWidget {
  final AthleteNoteEntity note;

  const _NotePreviewCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM HH:mm', 'pt_BR');

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  note.authorDisplayName ?? 'Equipe',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  fmt.format(note.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              note.note,
              style: theme.textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesTab extends StatefulWidget {
  final String groupId;
  final String athleteUserId;

  const _NotesTab({
    required this.groupId,
    required this.athleteUserId,
  });

  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab> {
  final _noteController = TextEditingController();

  Future<void> _confirmDeleteNote(
      BuildContext context, AthleteNoteEntity note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
        title: const Text('Confirmar exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta nota? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AthleteProfileBloc>().add(DeleteNote(note.id));
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<AthleteProfileBloc, AthleteProfileState>(
      listenWhen: (_, curr) => curr is AthleteProfileError,
      listener: (context, state) {
        if (state is AthleteProfileError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      buildWhen: (_, curr) => curr is! AthleteProfileError,
      builder: (context, state) {
        if (state is! AthleteProfileLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final notes = state.notes;

        return Column(
          children: [
            Expanded(
              child: notes.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhuma nota registrada',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(DesignTokens.spacingMd),
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return _NoteCard(
                          note: note,
                          onDelete: () => _confirmDeleteNote(context, note),
                        );
                      },
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteController,
                        decoration: const InputDecoration(
                          hintText: 'Digite uma nota...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (text) {
                          if (text.trim().isEmpty) return;
                          context
                              .read<AthleteProfileBloc>()
                              .add(AddNote(text.trim()));
                          _noteController.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        final text = _noteController.text.trim();
                        if (text.isEmpty) return;
                        context.read<AthleteProfileBloc>().add(AddNote(text));
                        _noteController.clear();
                      },
                      child: const Text('Enviar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  final AthleteNoteEntity note;
  final VoidCallback onDelete;

  const _NoteCard({
    required this.note,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM yyyy, HH:mm', 'pt_BR');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  note.authorDisplayName ?? 'Equipe',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  fmt.format(note.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                  tooltip: 'Excluir nota',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(note.note, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

Color _tagColorFromHex(String? hex) {
  if (hex == null || hex.isEmpty) return DesignTokens.primary;
  final c = hex.replaceFirst('#', '');
  if (c.length == 6) {
    final v = int.tryParse('FF$c', radix: 16);
    if (v != null) return Color(v);
  }
  return DesignTokens.primary;
}

class _TagsTab extends StatelessWidget {
  const _TagsTab();

  static Future<void> _confirmRemoveTag(
      BuildContext context, CoachingTagEntity tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
        title: const Text('Confirmar remoção'),
        content: Text(
          'Tem certeza que deseja remover a tag "${tag.name}" do atleta? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AthleteProfileBloc>().add(RemoveTag(tag.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<AthleteProfileBloc, AthleteProfileState>(
      builder: (context, state) {
        if (state is! AthleteProfileLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final currentTags = state.tags;
        final availableToAdd = state.allGroupTags
            .where(
              (t) => !currentTags.any((c) => c.id == t.id),
            )
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: currentTags
                    .map(
                      (t) => Chip(
                        label: Text(t.name),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => _confirmRemoveTag(context, t),
                        backgroundColor: _tagColorFromHex(t.color)
                            .withValues(alpha: 0.2),
                        side: BorderSide(
                          color: _tagColorFromHex(t.color),
                          width: 1,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: availableToAdd.isEmpty
                    ? null
                    : () => _showAddTagSheet(context, availableToAdd),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar tag'),
              ),
              if (availableToAdd.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Todas as tags do grupo já estão atribuídas.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAddTagSheet(BuildContext context, List<CoachingTagEntity> tags) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Selecionar tag',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ...tags.map(
                (t) => ListTile(
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _tagColorFromHex(t.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(t.name),
                  onTap: () {
                    context.read<AthleteProfileBloc>().add(AssignTag(t.id));
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresencaTab extends StatelessWidget {
  final String groupId;
  final String athleteUserId;

  const _PresencaTab({
    required this.groupId,
    required this.athleteUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<TrainingAttendanceEntity>>(
      future: sl<ITrainingAttendanceRepo>().listByAthlete(
        groupId: groupId,
        athleteUserId: athleteUserId,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Erro: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ),
            ),
          );
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              'Nenhuma presença registrada',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          itemCount: list.length,
          itemBuilder: (context, index) =>
              _AttendanceCard(attendance: list[index]),
        );
      },
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final TrainingAttendanceEntity attendance;

  const _AttendanceCard({required this.attendance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM yyyy, HH:mm', 'pt_BR');
    final statusInfo = _statusInfo(theme);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              attendance.sessionTitle ?? 'Treino',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  fmt.format(attendance.checkedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
              decoration: BoxDecoration(
                color: statusInfo.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: Text(
                statusInfo.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusInfo.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, Color color}) _statusInfo(ThemeData theme) {
    return switch (attendance.status) {
      AttendanceStatus.present => (
          label: 'Presente',
          color: DesignTokens.success,
        ),
      AttendanceStatus.late_ => (
          label: 'Atrasado',
          color: DesignTokens.warning,
        ),
      AttendanceStatus.excused => (
          label: 'Justificado',
          color: DesignTokens.primary,
        ),
      AttendanceStatus.absent => (
          label: 'Ausente',
          color: theme.colorScheme.error,
        ),
      AttendanceStatus.completed => (
          label: 'Concluído',
          color: DesignTokens.success,
        ),
      AttendanceStatus.partial => (
          label: 'Parcial',
          color: DesignTokens.warning,
        ),
    };
  }
}

class _AlertasTab extends StatelessWidget {
  const _AlertasTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum alerta registrado',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Quando houver alertas para este atleta, eles aparecerão aqui.',
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
