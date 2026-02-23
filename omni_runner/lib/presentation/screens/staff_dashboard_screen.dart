import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_event.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/presentation/screens/coaching_group_details_screen.dart';
import 'package:omni_runner/presentation/screens/staff_championship_templates_screen.dart';
import 'package:omni_runner/presentation/screens/staff_championship_invites_screen.dart';
import 'package:omni_runner/presentation/screens/staff_credits_screen.dart';
import 'package:omni_runner/presentation/screens/staff_challenge_invites_screen.dart';
import 'package:omni_runner/presentation/screens/staff_disputes_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final uid = sl<UserIdentityProvider>().userId;
      final memberships = await sl<ICoachingMemberRepo>().getByUserId(uid);
      final staffMembership = memberships.where((m) => m.isStaff).firstOrNull;

      if (staffMembership != null) {
        final group =
            await sl<ICoachingGroupRepo>().getById(staffMembership.groupId);

        try {
          final wallet = await sl<IWalletRepo>().getByUserId(uid);
          _hasPendingPrizes = wallet.hasPending;
        } catch (_) {}

        try {
          final gid = staffMembership.groupId;
          final res = await Supabase.instance.client
              .from('clearing_cases')
              .select('id')
              .or('from_group_id.eq.$gid,to_group_id.eq.$gid')
              .inFilter('status', ['OPEN', 'SENT_CONFIRMED', 'DISPUTED']);
          _openDisputesCount = (res as List).length;
        } catch (_) {}

        if (mounted) {
          setState(() {
            _groupName = group?.name ?? 'Assessoria';
            _groupId = staffMembership.groupId;
            _membership = staffMembership;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _openAtletas() {
    if (_groupId.isEmpty) return;
    final uid = sl<UserIdentityProvider>().userId;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider<CoachingGroupDetailsBloc>(
        create: (_) => sl<CoachingGroupDetailsBloc>()
          ..add(LoadCoachingGroupDetails(
            groupId: _groupId,
            callerUserId: uid,
          )),
        child: const CoachingGroupDetailsScreen(),
      ),
    ));
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

  void _openDesafiosRecebidos() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffChallengeInvitesScreen(groupId: _groupId),
    ));
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
    final uri = Uri.parse(AppConfig.portalUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _loading ? 'Carregando...' : _groupName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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
                    title: 'Atletas',
                    subtitle: 'Ver e gerenciar atletas',
                    bgColor: cs.primaryContainer,
                    iconColor: cs.onPrimaryContainer,
                    onTap: _loading ? null : _openAtletas,
                  ),
                  _StaffCard(
                    icon: Icons.handshake_rounded,
                    title: 'Confirmações',
                    subtitle: 'Desafios entre assessorias',
                    bgColor: Colors.indigo.shade50,
                    iconColor: Colors.indigo.shade700,
                    alert: _openDisputesCount > 0
                        ? '$_openDisputesCount ${_openDisputesCount == 1 ? "caso pendente" : "casos pendentes"}'
                        : null,
                    onTap: _loading ? null : _openConfirmacoes,
                  ),
                  _StaffCard(
                    icon: Icons.bar_chart_rounded,
                    title: 'Performance',
                    subtitle: 'Visão geral da assessoria',
                    bgColor: Colors.teal.shade50,
                    iconColor: Colors.teal.shade700,
                    onTap: _loading ? null : _openPerformance,
                  ),
                  _StaffCard(
                    icon: Icons.emoji_events_rounded,
                    title: 'Campeonatos',
                    subtitle: 'Gerenciar e criar',
                    bgColor: Colors.orange.shade50,
                    iconColor: Colors.orange.shade800,
                    onTap: _loading ? null : _openCampeonatos,
                  ),
                  _StaffCard(
                    icon: Icons.mail_rounded,
                    title: 'Convites',
                    subtitle: 'Campeonatos recebidos',
                    bgColor: Colors.purple.shade50,
                    iconColor: Colors.purple.shade700,
                    onTap: _loading ? null : _openConvites,
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
                  _StaffCard(
                    icon: Icons.shield_rounded,
                    title: 'Desafios',
                    subtitle: 'Convites de equipe',
                    bgColor: Colors.red.shade50,
                    iconColor: Colors.red.shade700,
                    onTap: _loading ? null : _openDesafiosRecebidos,
                  ),
                  _StaffCard(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Administração',
                    subtitle: 'Operações e equipe',
                    bgColor: cs.tertiaryContainer,
                    iconColor: cs.onTertiaryContainer,
                    onTap: _loading ? null : _openAdmin,
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
