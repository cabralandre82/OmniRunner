import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_state.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/l10n/l10n.dart';

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
      appBar: AppBar(title: Text(context.l10n.myAssessoria)),
      body: BlocConsumer<MyAssessoriaBloc, MyAssessoriaState>(
        listener: (context, state) {
          if (state is MyAssessoriaSwitched) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Assessoria alterada com sucesso.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            context.pop();
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
          MyAssessoriaInitial() || MyAssessoriaLoading() =>
            const ShimmerListLoader(itemCount: 4),
          MyAssessoriaSwitching() => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: DesignTokens.spacingMd),
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
          MyAssessoriaError(:final message) => ErrorState(
              message: message,
              onRetry: () {
                final uid = sl<UserIdentityProvider>().userId;
                context.read<MyAssessoriaBloc>().add(LoadMyAssessoria(uid));
              },
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
      return _NoAssessoriaBody(theme: theme);
    }

    final roleLabel = switch (membership!.role) {
      CoachingRole.adminMaster => 'Admin Master',
      CoachingRole.coach => 'Coach',
      CoachingRole.assistant => 'Assistente',
      CoachingRole.athlete => 'Atleta',
    };

    return ListView(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      children: [
        _CurrentGroupCard(group: currentGroup!, roleLabel: roleLabel),
        const SizedBox(height: DesignTokens.spacingLg),
        _QuickAccessSection(groupId: currentGroup!.id),
        const SizedBox(height: DesignTokens.spacingLg),
        if (availableGroups.isNotEmpty) ...[
          Text('Trocar para outra assessoria',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: DesignTokens.spacingSm),
          ...availableGroups.map((g) => _AvailableGroupTile(
                group: g,
                onTap: () => _showBurnWarning(context, g),
              )),
        ] else
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.outline),
                  const SizedBox(width: DesignTokens.spacingMd),
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
        icon: const Icon(Icons.warning_amber_rounded,
            color: DesignTokens.warning, size: 48),
        title: Text(context.l10n.switchAssessoria),
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
            const SizedBox(height: DesignTokens.spacingMd),
            const _ImpactRow(
              icon: Icons.check_circle,
              color: DesignTokens.success,
              text: 'Seus treinos e histórico permanecem',
            ),
            const _ImpactRow(
              icon: Icons.check_circle,
              color: DesignTokens.success,
              text: 'Desafios em andamento continuam normalmente',
            ),
            const _ImpactRow(
              icon: Icons.check_circle,
              color: DesignTokens.success,
              text: 'Seu status de verificação não muda',
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            const _ImpactRow(
              icon: Icons.cancel,
              color: DesignTokens.error,
              text: 'Você será removido do grupo atual',
            ),
            const _ImpactRow(
              icon: Icons.cancel,
              color: DesignTokens.error,
              text: 'OmniCoins pendentes entre assessorias serão perdidos',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Container(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              decoration: BoxDecoration(
                color: DesignTokens.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: DesignTokens.error.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.local_fire_department,
                      color: DesignTokens.error, size: 20),
                  SizedBox(width: DesignTokens.spacingSm),
                  Expanded(
                    child: Text(
                      'Esta ação não pode ser desfeita.',
                      style: TextStyle(
                        color: DesignTokens.error,
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
            onPressed: () => ctx.pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DesignTokens.error,
            ),
            onPressed: () {
              ctx.pop(true);
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
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: group.logoUrl != null
                      ? CachedNetworkImageProvider(group.logoUrl!)
                      : null,
                  child: group.logoUrl == null
                      ? Icon(Icons.sports,
                          color: theme.colorScheme.primary, size: 28)
                      : null,
                ),
                const SizedBox(width: DesignTokens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: DesignTokens.spacingXs),
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
              const SizedBox(height: DesignTokens.spacingMd),
              Text(group.description, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: DesignTokens.spacingMd),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
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
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          backgroundImage:
              group.logoUrl != null ? CachedNetworkImageProvider(group.logoUrl!) : null,
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
        const SizedBox(height: DesignTokens.spacingSm),
        _QuickTile(
          icon: Icons.forum_rounded,
          iconColor: DesignTokens.success,
          title: 'Feed da assessoria',
          subtitle: 'Atividades recentes do grupo',
          onTap: () {
            context.push(AppRoutes.assessoriaFeed, extra: groupId);
          },
        ),
        _QuickTile(
          icon: Icons.emoji_events_rounded,
          iconColor: DesignTokens.warning,
          title: 'Campeonatos',
          subtitle: 'Competições abertas e em andamento',
          onTap: () {
            context.push(AppRoutes.championships);
          },
        ),
        _QuickTile(
          icon: Icons.shield_rounded,
          iconColor: DesignTokens.info,
          title: 'Liga de Assessorias',
          subtitle: 'Ranking entre assessorias da plataforma',
          onTap: () {
            context.push(AppRoutes.league);
          },
        ),
        _QuickTile(
          icon: Icons.sports_kabaddi_rounded,
          iconColor: DesignTokens.primary,
          title: 'Desafios',
          subtitle: 'Desafios disponíveis e aceitos',
          onTap: () {
            context.push(AppRoutes.challenges);
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
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
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
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// No assessoria body — checks for pending requests
// ---------------------------------------------------------------------------

class _NoAssessoriaBody extends StatefulWidget {
  final ThemeData theme;
  const _NoAssessoriaBody({required this.theme});

  @override
  State<_NoAssessoriaBody> createState() => _NoAssessoriaBodyState();
}

class _NoAssessoriaBodyState extends State<_NoAssessoriaBody> {
  String? _pendingGroupName;
  String? _pendingStatus;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkPendingRequest();
  }

  Future<void> _checkPendingRequest() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final rows = await Supabase.instance.client
          .from('coaching_join_requests')
          .select('group_id, status')
          .eq('user_id', uid)
          .order('requested_at', ascending: false)
          .limit(1);

      if ((rows as List).isNotEmpty) {
        final status = rows.first['status'] as String?;
        final groupId = rows.first['group_id'] as String;

        final groupRows = await Supabase.instance.client
            .from('coaching_groups')
            .select('name')
            .eq('id', groupId)
            .limit(1);

        if (mounted) {
          setState(() {
            _pendingGroupName =
                (groupRows as List).isNotEmpty
                    ? (groupRows.first['name'] as String?) ?? 'Assessoria'
                    : 'Assessoria';
            _pendingStatus = status;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'MyAssessoriaScreen', error: e);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    if (_loading) {
      return const ShimmerListLoader(itemCount: 3);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingStatus == 'pending') ...[
              const Icon(Icons.hourglass_top_rounded,
                  size: 72, color: DesignTokens.warning),
              const SizedBox(height: DesignTokens.spacingLg),
              Text('Solicitação pendente',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: DesignTokens.spacingSm),
              Text(
                'Sua solicitação para entrar na assessoria '
                '"$_pendingGroupName" está aguardando aprovação.\n\n'
                'O responsável pela assessoria irá analisar e aprovar '
                'sua entrada. Você será notificado.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingSm,
                ),
                decoration: BoxDecoration(
                  color: DesignTokens.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(color: DesignTokens.warning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: DesignTokens.warning),
                    SizedBox(width: DesignTokens.spacingSm),
                    Text(
                      'Enquanto isso, explore o app normalmente.',
                      style: TextStyle(
                        fontSize: 13,
                        color: DesignTokens.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_pendingStatus == 'rejected') ...[
              Icon(Icons.cancel_outlined,
                  size: 72, color: theme.colorScheme.error),
              const SizedBox(height: DesignTokens.spacingLg),
              Text('Solicitação não aprovada',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: DesignTokens.spacingSm),
              Text(
                'Sua solicitação para "$_pendingGroupName" não foi aprovada. '
                'Você pode tentar outra assessoria.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              FilledButton.icon(
                onPressed: () {
                  context.push(AppRoutes.joinAssessoria);
                },
                icon: const Icon(Icons.search_rounded),
                label: const Text('Buscar outra assessoria'),
              ),
            ] else ...[
              Icon(Icons.groups_outlined,
                  size: 72, color: theme.colorScheme.outline),
              const SizedBox(height: DesignTokens.spacingLg),
              Text('Sem assessoria',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: DesignTokens.spacingSm),
              Text(
                'Você ainda não está em nenhuma assessoria.\n'
                'Busque pelo nome, QR ou aceite um convite.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              FilledButton.icon(
                onPressed: () {
                  context.push(AppRoutes.joinAssessoria);
                },
                icon: const Icon(Icons.search_rounded),
                label: const Text('Entrar em uma assessoria'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
