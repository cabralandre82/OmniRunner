import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/presentation/blocs/groups/groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/groups/groups_event.dart';
import 'package:omni_runner/presentation/blocs/groups/groups_state.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.groups),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<GroupsBloc>().add(const RefreshGroups()),
          ),
        ],
      ),
      body: BlocBuilder<GroupsBloc, GroupsState>(
        builder: (context, state) => switch (state) {
          GroupsInitial() =>
            const Center(child: Text('Carregue seus grupos.')),
          GroupsLoading() =>
            const Center(child: CircularProgressIndicator()),
          GroupsLoaded(:final groups) => groups.isEmpty
              ? _empty(context)
              : _body(context, groups),
          GroupsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
                child: Text(message,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
        },
      ),
    );
  }

  static Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Nenhum grupo', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Crie ou entre em um grupo\npara correr com amigos!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  static Widget _body(BuildContext context, List<GroupEntity> groups) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
      itemCount: groups.length,
      itemBuilder: (context, index) => _GroupCard(group: groups[index]),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final GroupEntity group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final privacyIcon = switch (group.privacy) {
      GroupPrivacy.open => Icons.public,
      GroupPrivacy.closed => Icons.lock_open,
      GroupPrivacy.secret => Icons.lock,
    };
    final privacyLabel = switch (group.privacy) {
      GroupPrivacy.open => 'Aberto',
      GroupPrivacy.closed => 'Fechado',
      GroupPrivacy.secret => 'Secreto',
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.group,
                    color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (group.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(group.description,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(privacyIcon,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(privacyLabel,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(width: 12),
                        Icon(Icons.people,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                            '${group.memberCount}/${group.maxMembers}',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
