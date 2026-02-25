import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_state.dart';
import 'package:omni_runner/presentation/screens/assessoria_feed_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_championships_screen.dart';
import 'package:omni_runner/presentation/screens/challenges_list_screen.dart';
import 'package:omni_runner/presentation/screens/join_assessoria_screen.dart';

/// "Minha Assessoria" screen for athletes.
///
/// Shows current assessoria, membership role, and a button to switch.
/// Before switching, displays a burn-warning modal explaining that
/// tokens from the current assessoria will be invalidated.
class MyAssessoriaScreen extends StatelessWidget {
  const MyAssessoriaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minha Assessoria')),
      body: BlocConsumer<MyAssessoriaBloc, MyAssessoriaState>(
        listener: (context, state) {
          if (state is MyAssessoriaSwitched) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Assessoria alterada com sucesso.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            Navigator.of(context).pop();
          }
          if (state is MyAssessoriaError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) => switch (state) {
          MyAssessoriaInitial() =>
            const Center(child: Text('Carregando...')),
          MyAssessoriaLoading() =>
            const Center(child: CircularProgressIndicator()),
          MyAssessoriaSwitching() => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Trocando assessoria...'),
                ],
              ),
            ),
          MyAssessoriaLoaded(
            :final currentGroup,
            :final membership,
            :final availableGroups,
          ) =>
            _LoadedBody(
              currentGroup: currentGroup,
              membership: membership,
              availableGroups: availableGroups,
            ),
          MyAssessoriaSwitched() =>
            const Center(child: Icon(Icons.check_circle, size: 64)),
          MyAssessoriaError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
        },
      ),
    );
  }
}

class _LoadedBody extends StatelessWidget {
  final CoachingGroupEntity? currentGroup;
  final CoachingMemberEntity? membership;
  final List<CoachingGroupEntity> availableGroups;

  const _LoadedBody({
    this.currentGroup,
    this.membership,
    this.availableGroups = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (currentGroup == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined,
                  size: 72, color: theme.colorScheme.outline),
              const SizedBox(height: 20),
              Text('Sem assessoria',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 8),
              Text(
                'Você ainda não está em nenhuma assessoria.\n'
                'Busque pelo nome, QR ou aceite um convite.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => JoinAssessoriaScreen(
                      onComplete: () => Navigator.of(context).pop(),
                    ),
                  ));
                },
                icon: const Icon(Icons.search_rounded),
                label: const Text('Entrar em uma assessoria'),
              ),
            ],
          ),
        ),
      );
    }

    final roleLabel = switch (membership!.role) {
      CoachingRole.adminMaster => 'Admin Master',
      CoachingRole.professor => 'Professor',
      CoachingRole.assistente => 'Assistente',
      CoachingRole.atleta => 'Atleta',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CurrentGroupCard(group: currentGroup!, roleLabel: roleLabel),
        const SizedBox(height: 20),
        _QuickAccessSection(groupId: currentGroup!.id),
        const SizedBox(height: 24),
        if (availableGroups.isNotEmpty) ...[
          Text('Trocar para outra assessoria',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...availableGroups.map((g) => _AvailableGroupTile(
                group: g,
                onTap: () => _showBurnWarning(context, g),
              )),
        ] else
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Para trocar de assessoria, solicite um convite '
                      'da nova assessoria.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showBurnWarning(BuildContext context, CoachingGroupEntity target) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Colors.orange.shade700, size: 48),
        title: const Text('Trocar de Assessoria'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ao trocar para "${target.name}":',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            _ImpactRow(
              icon: Icons.check_circle,
              color: Colors.green,
              text: 'Seus treinos e histórico permanecem',
            ),
            _ImpactRow(
              icon: Icons.check_circle,
              color: Colors.green,
              text: 'Desafios em andamento continuam normalmente',
            ),
            _ImpactRow(
              icon: Icons.check_circle,
              color: Colors.green,
              text: 'Seu status de verificação não muda',
            ),
            const SizedBox(height: 8),
            _ImpactRow(
              icon: Icons.cancel,
              color: Colors.red,
              text: 'Você será removido do grupo atual',
            ),
            _ImpactRow(
              icon: Icons.cancel,
              color: Colors.red,
              text: 'OmniCoins pendentes entre assessorias serão perdidos',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department,
                      color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta ação não pode ser desfeita.',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            onPressed: () {
              Navigator.of(ctx).pop(true);
              context.read<MyAssessoriaBloc>().add(
                    ConfirmSwitchAssessoria(target.id),
                  );
            },
            child: const Text('Confirmar Troca'),
          ),
        ],
      ),
    );
  }
}

class _CurrentGroupCard extends StatelessWidget {
  final CoachingGroupEntity group;
  final String roleLabel;

  const _CurrentGroupCard({
    required this.group,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: group.logoUrl != null
                      ? NetworkImage(group.logoUrl!)
                      : null,
                  child: group.logoUrl == null
                      ? Icon(Icons.sports,
                          color: theme.colorScheme.primary, size: 28)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      if (group.city.isNotEmpty)
                        Text(group.city,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              ],
            ),
            if (group.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(group.description, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                roleLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailableGroupTile extends StatelessWidget {
  final CoachingGroupEntity group;
  final VoidCallback onTap;

  const _AvailableGroupTile({
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          backgroundImage:
              group.logoUrl != null ? NetworkImage(group.logoUrl!) : null,
          child: group.logoUrl == null
              ? Icon(Icons.sports, color: theme.colorScheme.outline, size: 20)
              : null,
        ),
        title: Text(group.name,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w500)),
        subtitle: group.city.isNotEmpty ? Text(group.city) : null,
        trailing:
            Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
        onTap: onTap,
      ),
    );
  }
}

/// Quick-access navigation tiles shown below the group card so the athlete
/// can reach group-related features without going back to the dashboard.
class _QuickAccessSection extends StatelessWidget {
  final String groupId;
  const _QuickAccessSection({required this.groupId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Explorar a assessoria',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _QuickTile(
          icon: Icons.forum_rounded,
          iconColor: Colors.teal,
          title: 'Feed da assessoria',
          subtitle: 'Atividades recentes do grupo',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => BlocProvider<AssessoriaFeedBloc>(
                create: (_) => AssessoriaFeedBloc()..add(LoadFeed(groupId)),
                child: const AssessoriaFeedScreen(),
              ),
            ));
          },
        ),
        _QuickTile(
          icon: Icons.emoji_events_rounded,
          iconColor: Colors.orange.shade800,
          title: 'Campeonatos',
          subtitle: 'Competições abertas e em andamento',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const AthleteChampionshipsScreen(),
            ));
          },
        ),
        _QuickTile(
          icon: Icons.sports_kabaddi_rounded,
          iconColor: Colors.deepPurple,
          title: 'Desafios',
          subtitle: 'Desafios disponíveis e aceitos',
          onTap: () {
            final uid = sl<UserIdentityProvider>().userId;
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => BlocProvider<ChallengesBloc>(
                create: (_) => sl<ChallengesBloc>()..add(LoadChallenges(uid)),
                child: const ChallengesListScreen(),
              ),
            ));
          },
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: iconColor.withValues(alpha: 0.12),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        title: Text(title,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        onTap: onTap,
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _ImpactRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
