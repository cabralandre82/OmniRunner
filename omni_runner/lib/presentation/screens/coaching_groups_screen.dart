import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_state.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/screens/coaching_group_details_screen.dart';

class CoachingGroupsScreen extends StatelessWidget {
  const CoachingGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.coaching),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CoachingGroupsBloc>()
                .add(const RefreshCoachingGroups()),
          ),
        ],
      ),
      body: BlocBuilder<CoachingGroupsBloc, CoachingGroupsState>(
        builder: (context, state) => switch (state) {
          CoachingGroupsInitial() =>
            const Center(child: Text('Carregue suas assessorias.')),
          CoachingGroupsLoading() =>
            const Center(child: CircularProgressIndicator()),
          CoachingGroupsLoaded(:final groups) => groups.isEmpty
              ? _empty(context)
              : _body(context, groups),
          CoachingGroupsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
          Icon(Icons.sports, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Nenhuma assessoria', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Você ainda não participa de\nnenhum grupo de assessoria.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  static Widget _body(
    BuildContext context,
    List<CoachingGroupItem> groups,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groups.length,
      itemBuilder: (context, index) =>
          _CoachingGroupCard(item: groups[index]),
    );
  }
}

class _CoachingGroupCard extends StatelessWidget {
  final CoachingGroupItem item;
  const _CoachingGroupCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = item.group;
    final role = item.membership.role;

    final roleLabel = switch (role) {
      CoachingRole.adminMaster => 'Admin Master',
      CoachingRole.coach => 'Coach',
      CoachingRole.assistant => 'Assistente',
      CoachingRole.athlete => 'Atleta',
    };
    final roleColor = switch (role) {
      CoachingRole.adminMaster => Colors.amber.shade700,
      CoachingRole.coach => Colors.deepPurple,
      CoachingRole.assistant => Colors.blue,
      CoachingRole.athlete => theme.colorScheme.primary,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final uid = sl<UserIdentityProvider>().userId;
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CoachingGroupDetailsScreen(
              groupId: group.id,
              callerUserId: uid,
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: group.logoUrl != null
                    ? CachedNetworkImageProvider(group.logoUrl!)
                    : null,
                child: group.logoUrl == null
                    ? Icon(Icons.sports,
                        color: theme.colorScheme.primary, size: 24)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (group.city.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        group.city,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            roleLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: roleColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.people,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          '${item.memberCount}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
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

