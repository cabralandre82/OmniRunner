import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/presentation/screens/coaching_group_details_screen.dart';
import 'package:omni_runner/presentation/screens/staff_championship_templates_screen.dart';
import 'package:omni_runner/presentation/screens/staff_championship_invites_screen.dart';
import 'package:omni_runner/presentation/screens/staff_credits_screen.dart';
import 'package:omni_runner/presentation/screens/staff_disputes_screen.dart';
import 'package:omni_runner/presentation/screens/staff_join_requests_screen.dart';
import 'package:omni_runner/presentation/screens/staff_performance_screen.dart';
import 'package:omni_runner/presentation/screens/support_screen.dart';
import 'package:omni_runner/presentation/screens/staff_qr_hub_screen.dart';
import 'package:omni_runner/presentation/screens/staff_workout_assign_screen.dart';
import 'package:omni_runner/presentation/screens/league_screen.dart';
import 'package:omni_runner/presentation/widgets/ds/fade_in.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';

/// Staff home dashboard — 6 cards for assessoria management.
///
/// Cards:
///   1. Atletas          → [CoachingGroupDetailsScreen]
///   2. Confirmações     → [StaffDisputesScreen]
///   3. Performance      → [StaffPerformanceScreen]
///   4. Campeonatos      → [StaffChampionshipTemplatesScreen]
///   5. Créditos         → [StaffCreditsScreen] (inventory + acquisition info)
///   6. Administração    → [StaffQrHubScreen]
class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  String _groupName = '...';
  String _groupId = '';
  CoachingMemberEntity? _membership;
  bool _loading = true;
  String? _errorMessage;
  bool _hasPendingPrizes = false;
  int _openDisputesCount = 0;
  int _memberCount = 0;
  int _pendingJoinRequests = 0;
  String? _inviteCode;
  String? _pendingProfessorGroupName;
  String _approvalStatus = 'approved';
  String? _approvalRejectReason;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final db = Supabase.instance.client;
    try {
      final uid = sl<UserIdentityProvider>().userId;

      // Query Supabase directly (local Isar cache may not be synced)
      final memberRows = await db
          .from('coaching_members')
          .select('id, user_id, group_id, display_name, role, joined_at_ms')
          .eq('user_id', uid);

      final staffRow = (memberRows as List).cast<Map<String, dynamic>>().where(
        (r) {
          final role = r['role'] as String? ?? '';
          return role == 'admin_master' ||
              role == 'coach' ||
              role == 'assistant';
        },
      ).firstOrNull;

      if (staffRow != null) {
        final gid = staffRow['group_id'] as String;

        final groupRow = await db
            .from('coaching_groups')
            .select('id, name, logo_url, coach_user_id, description, city, invite_code, invite_enabled, created_at_ms, approval_status, approval_reject_reason')
            .eq('id', gid)
            .maybeSingle();

        final membership = CoachingMemberEntity(
          id: staffRow['id'] as String,
          userId: staffRow['user_id'] as String,
          groupId: gid,
          displayName: (staffRow['display_name'] as String?) ?? '',
          role: coachingRoleFromString(staffRow['role'] as String? ?? ''),
          joinedAtMs: (staffRow['joined_at_ms'] as num?)?.toInt() ?? 0,
        );

        // Sync to local Isar so downstream code (detail screens, blocs) works
        if (groupRow != null) {
          final groupEntity = CoachingGroupEntity(
            id: gid,
            name: (groupRow['name'] as String?) ?? 'Assessoria',
            logoUrl: groupRow['logo_url'] as String?,
            coachUserId: (groupRow['coach_user_id'] as String?) ?? uid,
            description: (groupRow['description'] as String?) ?? '',
            city: (groupRow['city'] as String?) ?? '',
            inviteCode: groupRow['invite_code'] as String?,
            inviteEnabled: (groupRow['invite_enabled'] as bool?) ?? true,
            createdAtMs: (groupRow['created_at_ms'] as num?)?.toInt() ?? 0,
          );
          try {
            await sl<ICoachingGroupRepo>().save(groupEntity);
            await sl<ICoachingMemberRepo>().save(membership);
          } catch (e) {
            AppLogger.debug('Isar cache write failed', tag: 'StaffDash', error: e);
          }
        }

        // Parallelize independent queries and Isar sync
        final membersFuture = db
            .from('coaching_members')
            .select('id, user_id, group_id, display_name, role, joined_at_ms')
            .eq('group_id', gid);
        final walletFuture = sl<IWalletRepo>().getByUserId(uid);
        final disputesFuture = db
            .from('clearing_cases')
            .select('id')
            .or('from_group_id.eq.$gid,to_group_id.eq.$gid')
            .inFilter('status', ['OPEN', 'SENT_CONFIRMED', 'DISPUTED']);
        final joinReqFuture = db
            .from('coaching_join_requests')
            .select('id')
            .eq('group_id', gid)
            .eq('status', 'pending');

        final results = await Future.wait<dynamic>([
          membersFuture.catchError((Object e) { AppLogger.debug('Members fetch failed', tag: 'StaffDash', error: e); return <Map<String, dynamic>>[]; }),
          walletFuture.then<dynamic>((v) => v).catchError((Object e) { AppLogger.debug('Wallet load failed', tag: 'StaffDash', error: e); return null; }),
          disputesFuture.catchError((Object e) { AppLogger.debug('Clearing cases load failed', tag: 'StaffDash', error: e); return <Map<String, dynamic>>[]; }),
          joinReqFuture.catchError((Object e) { AppLogger.debug('Join requests count failed', tag: 'StaffDash', error: e); return <Map<String, dynamic>>[]; }),
        ]);

        final allMembers = (results[0] as List).cast<Map<String, dynamic>>();
        final wallet = results[1];
        final disputes = results[2] as List;
        final joinReqs = results[3] as List;

        // Batch Isar sync
        try {
          for (final row in allMembers) {
            final m = CoachingMemberEntity(
              id: row['id'] as String,
              userId: row['user_id'] as String,
              groupId: row['group_id'] as String,
              displayName: (row['display_name'] as String?) ?? '',
              role: coachingRoleFromString(row['role'] as String? ?? ''),
              joinedAtMs: (row['joined_at_ms'] as num?)?.toInt() ?? 0,
            );
            await sl<ICoachingMemberRepo>().save(m);
          }
        } catch (e) {
          AppLogger.debug('Members Isar batch sync failed', tag: 'StaffDash', error: e);
        }

        if (wallet != null) {
          _hasPendingPrizes = wallet.hasPending;
        }
        _openDisputesCount = disputes.length;
        _memberCount = allMembers.length;
        _pendingJoinRequests = joinReqs.length;

        if (mounted) {
          setState(() {
            _groupName = (groupRow?['name'] as String?) ?? 'Assessoria';
            _groupId = gid;
            _membership = membership;
            _inviteCode = groupRow?['invite_code'] as String?;
            _approvalStatus =
                (groupRow?['approval_status'] as String?) ?? 'approved';
            _approvalRejectReason =
                groupRow?['approval_reject_reason'] as String?;
            _loading = false;
          });
        }
      } else {
        AppLogger.warn('No staff membership found for user', tag: 'StaffDash');
        // Check if there's a pending professor join request
        try {
          final joinRows = await db
              .from('coaching_join_requests')
              .select('group_id')
              .eq('user_id', uid)
              .eq('status', 'pending')
              .eq('requested_role', 'coach')
              .limit(1);
          if ((joinRows as List).isNotEmpty) {
            final gid = joinRows.first['group_id'] as String;
            final groupRow = await db
                .from('coaching_groups')
                .select('name')
                .eq('id', gid)
                .maybeSingle();
            if (mounted) {
              _pendingProfessorGroupName =
                  (groupRow?['name'] as String?) ?? 'Assessoria';
            }
          }
        } catch (e) {
          AppLogger.debug('Pending professor check failed', tag: 'StaffDash', error: e);
        }
        if (mounted) setState(() => _loading = false);
      }
    } on PostgrestException catch (e) {
      AppLogger.error('StaffDashboard load failed (Postgrest)', tag: 'StaffDash', error: e);
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Dados não encontrados. Verifique suas permissões.';
        });
      }
    } catch (e) {
      AppLogger.error('StaffDashboard load failed', tag: 'StaffDash', error: e);
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Erro de conexão. Verifique sua internet e tente novamente.';
        });
      }
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _openAtletas() {
    if (_groupId.isEmpty) return;
    final uid = sl<UserIdentityProvider>().userId;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CoachingGroupDetailsScreen(
        groupId: _groupId,
        callerUserId: uid,
      ),
    )).then((_) => _loadStatus());
  }

  void _openConfirmacoes() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffDisputesScreen(
        groupId: _groupId,
        groupName: _groupName,
      ),
    ));
  }

  void _openPerformance() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffPerformanceScreen(
        groupId: _groupId,
        groupName: _groupName,
      ),
    ));
  }

  void _openCampeonatos() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffChampionshipTemplatesScreen(
        groupId: _groupId,
        groupName: _groupName,
      ),
    ));
  }

  void _openConvites() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffChampionshipInvitesScreen(groupId: _groupId),
    ));
  }

  void _openSolicitacoes() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffJoinRequestsScreen(groupId: _groupId),
    )).then((_) => _loadStatus());
  }

  void _openCreditos() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffCreditsScreen(
        groupId: _groupId,
        groupName: _groupName,
      ),
    ));
  }

  void _openAdmin() {
    final m = _membership;
    if (m == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffQrHubScreen(membership: m),
    ));
  }

  Future<void> _openPortal() async {
    final uri = Uri.parse('https://omnirunner.app');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (e1) {
      AppLogger.debug('External browser failed, trying in-app', tag: 'StaffDash', error: e1);
      try {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível abrir o portal: $e')),
          );
        }
      }
    }
  }

  void _openWorkoutAssign() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffWorkoutAssignScreen(groupId: _groupId),
    ));
  }

  void _openSupport() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SupportScreen(groupId: _groupId),
    ));
  }

  void _openLiga() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const LeagueScreen(),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Omni Runner'),
        backgroundColor: cs.inversePrimary,
      ),
      body: _loading
          ? const ShimmerListLoader()
          : FadeIn(
              child: _errorMessage != null && _groupId.isEmpty
                  ? _buildErrorState(theme)
                  : _groupId.isEmpty
                      ? _buildNoGroup(theme)
                      : _approvalStatus != 'approved'
                          ? _buildPlatformApprovalPending(theme)
                          : _buildDashboard(theme, cs),
            ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 64, color: theme.colorScheme.error),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(_errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: DesignTokens.spacingLg),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _errorMessage = null;
                });
                _loadStatus();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoGroup(ThemeData theme) {
    final cs = theme.colorScheme;

    if (_pendingProfessorGroupName != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_rounded,
                  size: 72, color: DesignTokens.warning),
              const SizedBox(height: DesignTokens.spacingLg),
              Text('Solicitação pendente',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: DesignTokens.spacingMd),
              Text(
                'Sua solicitação para entrar como professor na assessoria '
                '"$_pendingProfessorGroupName" está aguardando aprovação '
                'do administrador.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingMd,
                  vertical: DesignTokens.spacingSm,
                ),
                decoration: BoxDecoration(
                  color: DesignTokens.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(
                    color: DesignTokens.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: DesignTokens.warning),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Flexible(
                      child: Text(
                        'Você será notificado quando o administrador '
                        'aprovar sua entrada.',
                        style: TextStyle(
                          fontSize: 13,
                          color: DesignTokens.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _loadStatus();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Verificar status'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_rounded, size: 64,
                color: theme.colorScheme.outline),
            const SizedBox(height: DesignTokens.spacingMd),
            Text('Nenhuma assessoria encontrada',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              'Não foi possível carregar os dados da sua assessoria. '
              'Tente sair e entrar novamente.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingLg),
            FilledButton.icon(
              onPressed: () {
                setState(() => _loading = true);
                _loadStatus();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformApprovalPending(ThemeData theme) {
    final isSuspended = _approvalStatus == 'suspended';
    final isRejected = _approvalStatus == 'rejected';

    final IconData icon;
    final Color iconColor;
    final String title;
    final String message;

    if (isSuspended) {
      icon = Icons.block_rounded;
      iconColor = DesignTokens.error;
      title = 'Assessoria suspensa';
      message = 'A assessoria "$_groupName" foi suspensa pela plataforma.'
          '${_approvalRejectReason != null && _approvalRejectReason!.isNotEmpty ? '\n\nMotivo: $_approvalRejectReason' : ''}'
          '\n\nEntre em contato com o suporte para mais informações.';
    } else if (isRejected) {
      icon = Icons.cancel_outlined;
      iconColor = DesignTokens.error;
      title = 'Assessoria não aprovada';
      message = 'A solicitação de cadastro da assessoria "$_groupName" '
          'não foi aprovada pela plataforma.'
          '${_approvalRejectReason != null && _approvalRejectReason!.isNotEmpty ? '\n\nMotivo: $_approvalRejectReason' : ''}'
          '\n\nVocê pode entrar em contato com o suporte para mais informações.';
    } else {
      icon = Icons.hourglass_top_rounded;
      iconColor = DesignTokens.warning;
      title = 'Aguardando aprovação da plataforma';
      message = 'A assessoria "$_groupName" foi criada com sucesso e está '
          'aguardando aprovação da plataforma Omni Runner.\n\n'
          'Você será notificado assim que a aprovação for concluída. '
          'Enquanto isso, seus atletas ainda não poderão encontrar '
          'a assessoria na busca.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: iconColor),
            const SizedBox(height: DesignTokens.spacingLg),
            Text(title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingLg),
            if (!isRejected && !isSuspended)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingMd,
                  vertical: DesignTokens.spacingSm,
                ),
                decoration: BoxDecoration(
                  color: DesignTokens.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(
                    color: DesignTokens.info.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: DesignTokens.info),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Flexible(
                      child: Text(
                        'Código de convite: ${_inviteCode ?? "..."}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DesignTokens.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: DesignTokens.spacingMd),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _loading = true);
                _loadStatus();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Verificar status'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(ThemeData theme, ColorScheme cs) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingLg,
          DesignTokens.spacingLg,
          DesignTokens.spacingLg,
          DesignTokens.spacingMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _groupName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            Text(
              'Painel da assessoria',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            const TipBanner(
              tipKey: TipKey.staffWelcome,
              icon: Icons.lightbulb_outline_rounded,
              text: 'Bem-vindo ao painel! Comece adicionando atletas '
                  'e compartilhando o link de convite da sua assessoria.',
            ),
            const TipBanner(
              tipKey: TipKey.campeonatosHowTo,
              icon: Icons.emoji_events_outlined,
              text: 'Crie modelos de campeonatos para repetir '
                  'configurações e lançar campeonatos recorrentes.',
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async { await _loadStatus(); },
                child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: DesignTokens.spacingMd,
                crossAxisSpacing: DesignTokens.spacingMd,
                childAspectRatio: 0.95,
                children: [
                  _StaffCard(
                    icon: Icons.directions_run_rounded,
                    title: 'Atletas e Staff',
                    subtitle: '$_memberCount ${_memberCount == 1 ? 'membro' : 'membros'}',
                    bgColor: cs.primaryContainer,
                    iconColor: cs.onPrimaryContainer,
                    onTap: _openAtletas,
                  ),
                  _StaffCard(
                    icon: Icons.person_add_rounded,
                    title: 'Solicitações',
                    subtitle: 'Entrada de atletas',
                    bgColor: DesignTokens.success.withValues(alpha: 0.1),
                    iconColor: DesignTokens.success,
                    alert: _pendingJoinRequests > 0
                        ? '$_pendingJoinRequests ${_pendingJoinRequests == 1 ? "pendente" : "pendentes"}'
                        : null,
                    onTap: _openSolicitacoes,
                  ),
                  _StaffCard(
                    icon: Icons.handshake_rounded,
                    title: 'Confirmações',
                    subtitle: 'Entre assessorias',
                    bgColor: DesignTokens.info.withValues(alpha: 0.1),
                    iconColor: DesignTokens.info,
                    alert: _openDisputesCount > 0
                        ? '$_openDisputesCount ${_openDisputesCount == 1 ? "caso pendente" : "casos pendentes"}'
                        : null,
                    onTap: _openConfirmacoes,
                  ),
                  _StaffCard(
                    icon: Icons.bar_chart_rounded,
                    title: 'Performance',
                    subtitle: 'Visão geral da assessoria',
                    bgColor: DesignTokens.success.withValues(alpha: 0.1),
                    iconColor: DesignTokens.success,
                    onTap: _openPerformance,
                  ),
                  _StaffCard(
                    icon: Icons.emoji_events_rounded,
                    title: 'Campeonatos',
                    subtitle: 'Gerenciar e criar',
                    bgColor: DesignTokens.warning.withValues(alpha: 0.1),
                    iconColor: DesignTokens.warning,
                    onTap: _openCampeonatos,
                  ),
                  _StaffCard(
                    icon: Icons.mail_rounded,
                    title: 'Convites',
                    subtitle: 'Campeonatos recebidos',
                    bgColor: DesignTokens.primary.withValues(alpha: 0.1),
                    iconColor: DesignTokens.primary,
                    onTap: _openConvites,
                  ),
                  _StaffCard(
                    icon: Icons.toll_rounded,
                    title: 'Créditos',
                    subtitle: 'Seus OmniCoins',
                    bgColor: DesignTokens.warning.withValues(alpha: 0.15),
                    iconColor: DesignTokens.warning,
                    alert: _hasPendingPrizes
                        ? 'Prêmios pendentes de liberação'
                        : null,
                    onTap: _openCreditos,
                  ),
                  // Desafios são feitos entre atletas — sem card no dashboard staff
                  _StaffCard(
                    icon: Icons.fitness_center_rounded,
                    title: 'Treinos',
                    subtitle: 'Atribuir a atletas',
                    bgColor: DesignTokens.primary.withValues(alpha: 0.1),
                    iconColor: DesignTokens.primary,
                    onTap: _openWorkoutAssign,
                  ),
                  _StaffCard(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Administração',
                    subtitle: 'Operações e equipe',
                    bgColor: cs.tertiaryContainer,
                    iconColor: cs.onTertiaryContainer,
                    onTap: _openAdmin,
                  ),
                  _StaffCard(
                    icon: Icons.shield_rounded,
                    title: 'Liga',
                    subtitle: 'Ranking entre assessorias',
                    bgColor: DesignTokens.info.withValues(alpha: 0.1),
                    iconColor: DesignTokens.info,
                    onTap: _openLiga,
                  ),
                  _StaffCard(
                    icon: Icons.open_in_browser_rounded,
                    title: 'Portal',
                    subtitle: 'CRM de atletas, treinos, analytics, '
                        'relatórios financeiros e CSV',
                    bgColor: DesignTokens.info.withValues(alpha: 0.1),
                    iconColor: DesignTokens.info,
                    onTap: _openPortal,
                  ),
                  _StaffCard(
                    icon: Icons.support_agent,
                    title: 'Suporte',
                    subtitle: 'Falar com a equipe',
                    bgColor: DesignTokens.success.withValues(alpha: 0.1),
                    iconColor: DesignTokens.success,
                    onTap: _openSupport,
                  ),
                ],
              ),
              ),
            ),
          ],
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff dashboard card
// ---------------------------------------------------------------------------

class _StaffCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color bgColor;
  final Color iconColor;
  final bool dimmed;
  final String? alert;
  final VoidCallback? onTap;

  const _StaffCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.iconColor,
    this.dimmed = false,
    this.alert,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? DesignTokens.surface : bgColor;
    final titleColor = dimmed
        ? cs.onSurface.withValues(alpha: 0.6)
        : cs.onSurface;
    final subtitleColor = dimmed
        ? cs.onSurface.withValues(alpha: 0.6)
        : cs.onSurfaceVariant;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
      color: cardBg,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: isDark ? 0.25 : 0.15),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const Spacer(),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingXs),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: subtitleColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (alert != null) ...[
                const SizedBox(height: DesignTokens.spacingSm),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: DesignTokens.warning),
                    const SizedBox(width: DesignTokens.spacingXs),
                    Flexible(
                      child: Text(
                        alert!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: DesignTokens.warning,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
