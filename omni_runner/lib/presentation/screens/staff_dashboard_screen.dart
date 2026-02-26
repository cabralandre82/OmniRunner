import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
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
import 'package:omni_runner/presentation/screens/staff_qr_hub_screen.dart';
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
              role == 'professor' ||
              role == 'assistente';
        },
      ).firstOrNull;

      if (staffRow != null) {
        final gid = staffRow['group_id'] as String;

        final groupRow = await db
            .from('coaching_groups')
            .select()
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
          } catch (_) {}
        }

        // Also sync all members of this group to Isar
        try {
          final allMembers = await db
              .from('coaching_members')
              .select('id, user_id, group_id, display_name, role, joined_at_ms')
              .eq('group_id', gid);
          for (final row in (allMembers as List).cast<Map<String, dynamic>>()) {
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
        } catch (_) {}

        try {
          final wallet = await sl<IWalletRepo>().getByUserId(uid);
          _hasPendingPrizes = wallet.hasPending;
        } catch (_) {}

        try {
          final res = await db
              .from('clearing_cases')
              .select('id')
              .or('from_group_id.eq.$gid,to_group_id.eq.$gid')
              .inFilter('status', ['OPEN', 'SENT_CONFIRMED', 'DISPUTED']);
          _openDisputesCount = (res as List).length;
        } catch (_) {}

        // Count members + pending join requests
        try {
          final countRes = await db
              .from('coaching_members')
              .select('id')
              .eq('group_id', gid);
          _memberCount = (countRes as List).length;
        } catch (_) {}

        try {
          final joinRes = await db
              .from('coaching_join_requests')
              .select('id')
              .eq('group_id', gid)
              .eq('status', 'pending');
          _pendingJoinRequests = (joinRes as List).length;
        } catch (_) {}

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
              .eq('requested_role', 'professor')
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
        } catch (_) {}
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      AppLogger.error('StaffDashboard load failed: $e', tag: 'StaffDash', error: e);
      if (mounted) setState(() => _loading = false);
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

  void _openPortal() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Portal de Assessorias em breve. '
            'Acompanhe as novidades pelo app.'),
        duration: Duration(seconds: 3),
      ),
    );
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
          ? const Center(child: CircularProgressIndicator())
          : _groupId.isEmpty
              ? _buildNoGroup(theme)
              : _approvalStatus != 'approved'
                  ? _buildPlatformApprovalPending(theme)
                  : _buildDashboard(theme, cs),
    );
  }

  Widget _buildNoGroup(ThemeData theme) {
    if (_pendingProfessorGroupName != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_rounded,
                  size: 72, color: Colors.orange.shade400),
              const SizedBox(height: 20),
              Text('Solicitação pendente',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 12),
              Text(
                'Sua solicitação para entrar como professor na assessoria '
                '"$_pendingProfessorGroupName" está aguardando aprovação '
                'do administrador.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Você será notificado quando o administrador '
                        'aprovar sua entrada.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_rounded, size: 64,
                color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Nenhuma assessoria encontrada',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Não foi possível carregar os dados da sua assessoria. '
              'Tente sair e entrar novamente.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
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
      iconColor = Colors.red.shade400;
      title = 'Assessoria suspensa';
      message = 'A assessoria "$_groupName" foi suspensa pela plataforma.'
          '${_approvalRejectReason != null && _approvalRejectReason!.isNotEmpty ? '\n\nMotivo: $_approvalRejectReason' : ''}'
          '\n\nEntre em contato com o suporte para mais informações.';
    } else if (isRejected) {
      icon = Icons.cancel_outlined;
      iconColor = Colors.red.shade400;
      title = 'Assessoria não aprovada';
      message = 'A solicitação de cadastro da assessoria "$_groupName" '
          'não foi aprovada pela plataforma.'
          '${_approvalRejectReason != null && _approvalRejectReason!.isNotEmpty ? '\n\nMotivo: $_approvalRejectReason' : ''}'
          '\n\nVocê pode entrar em contato com o suporte para mais informações.';
    } else {
      icon = Icons.hourglass_top_rounded;
      iconColor = Colors.orange.shade400;
      title = 'Aguardando aprovação da plataforma';
      message = 'A assessoria "$_groupName" foi criada com sucesso e está '
          'aguardando aprovação da plataforma Omni Runner.\n\n'
          'Você será notificado assim que a aprovação for concluída. '
          'Enquanto isso, seus atletas ainda não poderão encontrar '
          'a assessoria na busca.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: iconColor),
            const SizedBox(height: 20),
            Text(title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (!isRejected && !isSuspended)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Código de convite: ${_inviteCode ?? "..."}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
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
            const SizedBox(height: 4),
            Text(
              'Painel da assessoria',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
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
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
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
                    bgColor: Colors.green.shade50,
                    iconColor: Colors.green.shade700,
                    alert: _pendingJoinRequests > 0
                        ? '$_pendingJoinRequests ${_pendingJoinRequests == 1 ? "pendente" : "pendentes"}'
                        : null,
                    onTap: _openSolicitacoes,
                  ),
                  _StaffCard(
                    icon: Icons.handshake_rounded,
                    title: 'Confirmações',
                    subtitle: 'Entre assessorias',
                    bgColor: Colors.indigo.shade50,
                    iconColor: Colors.indigo.shade700,
                    alert: _openDisputesCount > 0
                        ? '$_openDisputesCount ${_openDisputesCount == 1 ? "caso pendente" : "casos pendentes"}'
                        : null,
                    onTap: _openConfirmacoes,
                  ),
                  _StaffCard(
                    icon: Icons.bar_chart_rounded,
                    title: 'Performance',
                    subtitle: 'Visão geral da assessoria',
                    bgColor: Colors.teal.shade50,
                    iconColor: Colors.teal.shade700,
                    onTap: _openPerformance,
                  ),
                  _StaffCard(
                    icon: Icons.emoji_events_rounded,
                    title: 'Campeonatos',
                    subtitle: 'Gerenciar e criar',
                    bgColor: Colors.orange.shade50,
                    iconColor: Colors.orange.shade800,
                    onTap: _openCampeonatos,
                  ),
                  _StaffCard(
                    icon: Icons.mail_rounded,
                    title: 'Convites',
                    subtitle: 'Campeonatos recebidos',
                    bgColor: Colors.purple.shade50,
                    iconColor: Colors.purple.shade700,
                    onTap: _openConvites,
                  ),
                  _StaffCard(
                    icon: Icons.toll_rounded,
                    title: 'Créditos',
                    subtitle: 'Seus OmniCoins',
                    bgColor: Colors.amber.shade100,
                    iconColor: Colors.amber.shade800,
                    alert: _hasPendingPrizes
                        ? 'Prêmios pendentes de liberação'
                        : null,
                    onTap: _openCreditos,
                  ),
                  // Desafios são feitos entre atletas — sem card no dashboard staff
                  _StaffCard(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Administração',
                    subtitle: 'Operações e equipe',
                    bgColor: cs.tertiaryContainer,
                    iconColor: cs.onTertiaryContainer,
                    onTap: _openAdmin,
                  ),
                  _StaffCard(
                    icon: Icons.open_in_browser_rounded,
                    title: 'Portal',
                    subtitle: 'Abrir no navegador',
                    bgColor: Colors.blue.shade50,
                    iconColor: Colors.blue.shade700,
                    onTap: _openPortal,
                  ),
                ],
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: bgColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const Spacer(),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: dimmed ? Colors.grey.shade600 : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dimmed
                      ? Colors.grey.shade500
                      : theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (alert != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        alert!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange.shade700,
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
