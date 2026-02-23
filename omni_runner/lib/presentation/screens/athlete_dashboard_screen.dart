import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_event.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_bloc.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_event.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/presentation/screens/athlete_championships_screen.dart';
import 'package:omni_runner/presentation/screens/challenges_list_screen.dart';
import 'package:omni_runner/presentation/screens/invite_friends_screen.dart';
import 'package:omni_runner/presentation/screens/my_assessoria_screen.dart';
import 'package:omni_runner/presentation/screens/progress_hub_screen.dart';
import 'package:omni_runner/presentation/screens/wallet_screen.dart';
import 'package:omni_runner/presentation/widgets/login_required_sheet.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';

/// Athlete home dashboard — 6 cards providing quick access to the main features.
///
/// Cards:
///   1. Meus desafios    → [ChallengesListScreen]
///   2. Minha assessoria  → [MyAssessoriaScreen] (shows empty state if unbound)
///   3. Meu progresso     → [ProgressHubScreen]
///   4. Meus créditos     → [WalletScreen]
///   5. Campeonatos       → [AthleteChampionshipsScreen]
///   6. Convidar amigos   → [InviteFriendsScreen]
class AthleteDashboardScreen extends StatefulWidget {
  const AthleteDashboardScreen({super.key});

  @override
  State<AthleteDashboardScreen> createState() =>
      _AthleteDashboardScreenState();
}

class _AthleteDashboardScreenState extends State<AthleteDashboardScreen> {
  String? _assessoriaName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAssessoriaStatus();
  }

  Future<void> _loadAssessoriaStatus() async {
    try {
      final uid = sl<UserIdentityProvider>().userId;
      final memberships = await sl<ICoachingMemberRepo>().getByUserId(uid);
      final membership = memberships.where((m) => m.isAtleta).firstOrNull;

      if (membership != null) {
        final group =
            await sl<ICoachingGroupRepo>().getById(membership.groupId);
        if (mounted) {
          setState(() {
            _assessoriaName = group?.name;
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

  void _openChallenges() {
    if (LoginRequiredSheet.guard(context, feature: 'Desafios')) return;
    final uid = sl<UserIdentityProvider>().userId;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider<ChallengesBloc>(
        create: (_) => sl<ChallengesBloc>()..add(LoadChallenges(uid)),
        child: const ChallengesListScreen(),
      ),
    ));
  }

  void _openAssessoria() {
    if (LoginRequiredSheet.guard(context, feature: 'Assessoria')) return;
    final uid = sl<UserIdentityProvider>().userId;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider<MyAssessoriaBloc>(
        create: (_) => sl<MyAssessoriaBloc>()..add(LoadMyAssessoria(uid)),
        child: const MyAssessoriaScreen(),
      ),
    ));
  }

  void _openProgress() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ProgressHubScreen(),
    ));
  }

  void _openWallet() {
    if (LoginRequiredSheet.guard(context, feature: 'OmniCoins')) return;
    final uid = sl<UserIdentityProvider>().userId;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider<WalletBloc>(
        create: (_) => sl<WalletBloc>()..add(LoadWallet(uid)),
        child: const WalletScreen(),
      ),
    ));
  }

  void _openChampionships() {
    if (LoginRequiredSheet.guard(context, feature: 'Campeonatos')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AthleteChampionshipsScreen(),
    ));
  }

  void _openInviteFriends() {
    if (LoginRequiredSheet.guard(context, feature: 'Convites')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const InviteFriendsScreen(),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasAssessoria = _assessoriaName != null && !_loading;

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
              'Olá, atleta!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'O que deseja fazer hoje?',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const TipBanner(
              tipKey: TipKey.dashboardWelcome,
              icon: Icons.lightbulb_outline_rounded,
              text: 'Bem-vindo! Comece criando um desafio '
                  'ou entre em uma assessoria para treinar com outros atletas.',
            ),
            const TipBanner(
              tipKey: TipKey.assessoriaHowTo,
              icon: Icons.groups_outlined,
              text: 'Para entrar em uma assessoria, peça o código ou link '
                  'de convite ao professor. Você também pode buscar pelo nome.',
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.95,
                children: [
                  _DashCard(
                    icon: Icons.sports_kabaddi_rounded,
                    title: 'Meus desafios',
                    subtitle: 'Competir e acompanhar',
                    bgColor: cs.primaryContainer,
                    iconColor: cs.onPrimaryContainer,
                    onTap: _openChallenges,
                  ),
                  _DashCard(
                    icon: Icons.groups_rounded,
                    title: 'Minha assessoria',
                    subtitle: _loading
                        ? '...'
                        : _assessoriaName ?? 'Sem assessoria',
                    bgColor: hasAssessoria
                        ? cs.secondaryContainer
                        : Colors.grey.shade200,
                    iconColor: hasAssessoria
                        ? cs.onSecondaryContainer
                        : Colors.grey.shade500,
                    isEmpty: !hasAssessoria && !_loading,
                    onTap: _openAssessoria,
                  ),
                  _DashCard(
                    icon: Icons.trending_up_rounded,
                    title: 'Meu progresso',
                    subtitle: 'XP, badges e missões',
                    bgColor: cs.tertiaryContainer,
                    iconColor: cs.onTertiaryContainer,
                    onTap: _openProgress,
                  ),
                  _DashCard(
                    icon: Icons.toll_rounded,
                    title: 'Meus créditos',
                    subtitle: 'Seus OmniCoins',
                    bgColor: Colors.amber.shade100,
                    iconColor: Colors.amber.shade800,
                    onTap: _openWallet,
                  ),
                  _DashCard(
                    icon: Icons.emoji_events_rounded,
                    title: 'Campeonatos',
                    subtitle: 'Competir entre assessorias',
                    bgColor: Colors.orange.shade50,
                    iconColor: Colors.orange.shade800,
                    onTap: _openChampionships,
                  ),
                  _DashCard(
                    icon: Icons.people_alt_rounded,
                    title: 'Convidar amigos',
                    subtitle: 'Compartilhe o app',
                    bgColor: Colors.green.shade50,
                    iconColor: Colors.green.shade700,
                    onTap: _openInviteFriends,
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
// Dashboard card
// ---------------------------------------------------------------------------

class _DashCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color bgColor;
  final Color iconColor;
  final bool isEmpty;
  final VoidCallback onTap;

  const _DashCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.iconColor,
    this.isEmpty = false,
    required this.onTap,
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
                  color: isEmpty ? Colors.grey.shade600 : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isEmpty
                      ? Colors.grey.shade500
                      : theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Toque para encontrar',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
