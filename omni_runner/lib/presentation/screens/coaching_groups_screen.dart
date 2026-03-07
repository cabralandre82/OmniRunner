import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_state.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:omni_runner/l10n/l10n.dart';

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
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
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
          const SizedBox(height: DesignTokens.spacingMd),
          Text('Nenhuma assessoria', style: theme.textTheme.titleMedium),
          const SizedBox(height: DesignTokens.spacingSm),
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
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
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
      CoachingRole.adminMaster => DesignTokens.warning,
      CoachingRole.coach => DesignTokens.primary,
      CoachingRole.assistant => DesignTokens.info,
      CoachingRole.athlete => theme.colorScheme.primary,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingXs),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        onTap: () {
          final uid = sl<UserIdentityProvider>().userId;
          context.push(AppRoutes.coachingGroupDetailsPath(group.id));
        },
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
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
              const SizedBox(width: DesignTokens.spacingMd),
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
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text(
                        group.city,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: DesignTokens.spacingSm),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                          ),
                          child: Text(
                            roleLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: roleColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spacingMd),
                        Icon(Icons.people,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: DesignTokens.spacingXs),
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
