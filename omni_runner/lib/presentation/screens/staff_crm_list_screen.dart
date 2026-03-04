import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/usecases/crm/manage_tags.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_bloc.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_event.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_state.dart';
import 'package:omni_runner/presentation/screens/staff_athlete_profile_screen.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/utils/error_messages.dart';

/// Filterable list of athletes in the group with tags, status, and risk indicators.
class StaffCrmListScreen extends StatelessWidget {
  final String groupId;

  const StaffCrmListScreen({
    super.key,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<CrmListBloc>()..add(LoadCrmAthletes(groupId: groupId)),
      child: _StaffCrmListView(groupId: groupId),
    );
  }
}

class _StaffCrmListView extends StatefulWidget {
  final String groupId;

  const _StaffCrmListView({required this.groupId});

  @override
  State<_StaffCrmListView> createState() => _StaffCrmListViewState();
}

class _StaffCrmListViewState extends State<_StaffCrmListView> {
  final _scrollController = ScrollController();

  String get groupId => widget.groupId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<CrmListBloc>().add(const LoadMoreCrmAthletes());
    }
  }

  void _openManageTags(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ManageTagsSheet(
        groupId: groupId,
        onTagsChanged: () {
          if (context.mounted) {
            context.read<CrmListBloc>().add(const RefreshCrmAthletes());
          }
        },
      ),
    );
  }

  void _openProfile(
    BuildContext context, {
    required String athleteUserId,
    required String athleteDisplayName,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StaffAthleteProfileScreen(
          groupId: groupId,
          athleteUserId: athleteUserId,
          athleteDisplayName: athleteDisplayName,
        ),
      ),
    ).then((_) {
      if (context.mounted) {
        context.read<CrmListBloc>().add(const RefreshCrmAthletes());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Tela de CRM de Atletas',
      child: Scaffold(
      appBar: AppBar(
        title: const Text('CRM Atletas'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlocBuilder<CrmListBloc, CrmListState>(
            buildWhen: (prev, curr) {
              if (curr is! CrmListLoaded) return false;
              if (prev is! CrmListLoaded) return true;
              return prev.activeTagFilters != curr.activeTagFilters ||
                  prev.activeStatusFilter != curr.activeStatusFilter;
            },
            builder: (context, state) {
              if (state is! CrmListLoaded) return const SizedBox.shrink();
              return _FilterSection(
                tags: state.tags,
                activeTagFilters: state.activeTagFilters,
                activeStatusFilter: state.activeStatusFilter,
                onTagToggled: (tagId) {
                  final next = state.activeTagFilters.contains(tagId)
                      ? state.activeTagFilters
                          .where((id) => id != tagId)
                          .toList()
                      : [...state.activeTagFilters, tagId];
                  context.read<CrmListBloc>().add(LoadCrmAthletes(
                        groupId: groupId,
                        tagIds: next.isEmpty ? null : next,
                        status: state.activeStatusFilter,
                      ));
                },
                onStatusChanged: (status) {
                  context.read<CrmListBloc>().add(LoadCrmAthletes(
                        groupId: groupId,
                        tagIds: state.activeTagFilters.isEmpty
                            ? null
                            : state.activeTagFilters,
                        status: status,
                      ));
                },
              );
            },
          ),
          Expanded(
            child: BlocBuilder<CrmListBloc, CrmListState>(
              builder: (context, state) {
                return switch (state) {
                  CrmListInitial() || CrmListLoading() =>
                    const ShimmerListLoader(),
                  CrmListError(:final message) => Center(
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
                                    .read<CrmListBloc>()
                                    .add(const RefreshCrmAthletes());
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  CrmListLoaded(:final athletes, :final hasMore, :final loadingMore) =>
                      athletes.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_outline, size: 64, color: DesignTokens.textMuted),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Nenhum atleta encontrado',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Convide atletas para sua assessoria',
                                    style: TextStyle(color: DesignTokens.textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                context
                                    .read<CrmListBloc>()
                                    .add(const RefreshCrmAthletes());
                              },
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                                itemCount: athletes.length + (loadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= athletes.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }
                                  final a = athletes[index];
                                  return _CrmAthleteCard(
                                    athlete: a,
                                    onTap: () => _openProfile(
                                      context,
                                      athleteUserId: a.userId,
                                      athleteDisplayName: a.displayName,
                                    ),
                                  );
                                },
                              ),
                            ),
                };
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openManageTags(context),
        icon: const Icon(Icons.label_outline),
        label: const Text('Gerenciar Tags'),
      ),
    ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final List<CoachingTagEntity> tags;
  final List<String> activeTagFilters;
  final MemberStatusValue? activeStatusFilter;
  final void Function(String tagId) onTagToggled;
  final void Function(MemberStatusValue? status) onStatusChanged;

  const _FilterSection({
    required this.tags,
    required this.activeTagFilters,
    required this.activeStatusFilter,
    required this.onTagToggled,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'Status',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatusDropdown(
                      value: activeStatusFilter,
                      onChanged: onStatusChanged,
                    ),
                  ),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Tags',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: tags
                      .map(
                        (t) => FilterChip(
                          selected: activeTagFilters.contains(t.id),
                          label: Text(t.name),
                          onSelected: (_) => onTagToggled(t.id),
                          selectedColor: _tagColor(t.color).withValues(alpha: 0.3),
                          checkmarkColor: _tagColor(t.color),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _tagColor(String? hex) {
    if (hex == null || hex.isEmpty) return DesignTokens.primary;
    final c = hex.replaceFirst('#', '');
    if (c.length == 6) {
      final v = int.tryParse('FF$c', radix: 16);
      if (v != null) return Color(v);
    }
    return DesignTokens.primary;
  }
}

class _StatusDropdown extends StatelessWidget {
  final MemberStatusValue? value;
  final void Function(MemberStatusValue? status) onChanged;

  const _StatusDropdown({
    required this.value,
    required this.onChanged,
  });

  static const _options = [
    (v: null, label: 'Todos'),
    (v: MemberStatusValue.active, label: 'Ativo'),
    (v: MemberStatusValue.paused, label: 'Pausado'),
    (v: MemberStatusValue.injured, label: 'Lesionado'),
    (v: MemberStatusValue.inactive, label: 'Inativo'),
    (v: MemberStatusValue.trial, label: 'Trial'),
  ];

  @override
  Widget build(BuildContext context) {
    return                     DropdownButtonFormField<MemberStatusValue?>(
      value: value,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: DesignTokens.spacingSm),
      ),
      items: _options
          .map(
            (o) => DropdownMenuItem(
              value: o.v,
              child: Text(o.label),
            ),
          )
          .toList(),
      onChanged: (v) => onChanged(v),
    );
  }
}

class _CrmAthleteCard extends StatelessWidget {
  final CrmAthleteView athlete;
  final VoidCallback onTap;

  const _CrmAthleteCard({
    required this.athlete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusInfo = _statusInfo(theme);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cs.surfaceContainerHighest,
                backgroundImage: athlete.avatarUrl != null &&
                        athlete.avatarUrl!.isNotEmpty
                    ? CachedNetworkImageProvider(athlete.avatarUrl!)
                    : null,
                child: athlete.avatarUrl == null || athlete.avatarUrl!.isEmpty
                    ? Text(
                        _initials(athlete.displayName),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      athlete.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (athlete.status != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spacingSm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusInfo.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusInfo.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusInfo.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ...athlete.tags.take(3).map(
                              (t) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _tagColor(t.color)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  t.name,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _tagColor(t.color),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (athlete.hasActiveAlerts)
                    Icon(
                      Icons.warning_amber_rounded,
                      color: DesignTokens.warning,
                      size: 22,
                    ),
                  if (athlete.attendanceCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingSm,
                        vertical: DesignTokens.spacingXs,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      ),
                      child: Text(
                        '${athlete.attendanceCount}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  ({String label, Color color}) _statusInfo(ThemeData theme) {
    return switch (athlete.status) {
      MemberStatusValue.active => (
          label: 'Ativo',
          color: DesignTokens.success,
        ),
      MemberStatusValue.paused => (
          label: 'Pausado',
          color: DesignTokens.warning,
        ),
      MemberStatusValue.injured => (
          label: 'Lesionado',
          color: DesignTokens.error,
        ),
      MemberStatusValue.inactive => (
          label: 'Inativo',
          color: DesignTokens.textSecondary,
        ),
      MemberStatusValue.trial => (
          label: 'Trial',
          color: DesignTokens.primary,
        ),
      null => (label: '-', color: theme.colorScheme.outline),
    };
  }

  Color _tagColor(String? hex) {
    if (hex == null || hex.isEmpty) return DesignTokens.primary;
    final c = hex.replaceFirst('#', '');
    if (c.length == 6) {
      final v = int.tryParse('FF$c', radix: 16);
      if (v != null) return Color(v);
    }
    return DesignTokens.primary;
  }
}

class _ManageTagsSheet extends StatefulWidget {
  final String groupId;
  final VoidCallback onTagsChanged;

  const _ManageTagsSheet({
    required this.groupId,
    required this.onTagsChanged,
  });

  @override
  State<_ManageTagsSheet> createState() => _ManageTagsSheetState();
}

class _ManageTagsSheetState extends State<_ManageTagsSheet> {
  late List<CoachingTagEntity> _tags;
  bool _loading = true;
  String? _error;
  final _nameController = TextEditingController();
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tags = await sl<ManageTags>().list(widget.groupId);
      if (mounted) {
        setState(() {
          _tags = tags;
          _loading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorMessages.humanize(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _createTag() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    try {
      await sl<ManageTags>().create(groupId: widget.groupId, name: name);
      _nameController.clear();
      await _load();
      widget.onTagsChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag criada')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.humanize(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteTag(CoachingTagEntity tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
        title: const Text('Confirmar exclusão'),
        content: Text(
          'Tem certeza que deseja excluir a tag "${tag.name}"? '
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
    if (confirmed != true) return;
    try {
      await sl<ManageTags>().delete(tag.id);
      await _load();
      widget.onTagsChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag excluída')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.humanize(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Gerenciar Tags',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nova tag',
                        hintText: 'Nome da tag',
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _createTag(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _creating || _nameController.text.trim().isEmpty
                        ? null
                        : _createTag,
                    child: const Text('Criar'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          )
                        : _tags.isEmpty
                            ? Center(
                                child: Text(
                                  'Nenhuma tag. Crie uma acima.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: _tags.length,
                                itemBuilder: (context, index) {
                                  final tag = _tags[index];
                                  return ListTile(
                                    leading: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: _tagColor(tag.color),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    title: Text(tag.name),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _deleteTag(tag),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _tagColor(String? hex) {
    if (hex == null || hex.isEmpty) return DesignTokens.primary;
    final c = hex.replaceFirst('#', '');
    if (c.length == 6) {
      final v = int.tryParse('FF$c', radix: 16);
      if (v != null) return Color(v);
    }
    return DesignTokens.primary;
  }
}
