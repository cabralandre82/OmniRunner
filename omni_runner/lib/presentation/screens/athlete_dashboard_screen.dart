import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_event.dart';
import 'package:omni_runner/presentation/screens/assessoria_feed_screen.dart';
import 'package:omni_runner/features/parks/presentation/my_parks_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_championships_screen.dart';
import 'package:omni_runner/presentation/screens/athlete_verification_screen.dart';
import 'package:omni_runner/presentation/screens/challenges_list_screen.dart';
import 'package:omni_runner/presentation/screens/join_assessoria_screen.dart';
import 'package:omni_runner/presentation/screens/my_assessoria_screen.dart';
import 'package:omni_runner/presentation/screens/progress_hub_screen.dart';
import 'package:omni_runner/presentation/screens/wallet_screen.dart';
import 'package:omni_runner/presentation/widgets/assessoria_required_sheet.dart';
import 'package:omni_runner/presentation/widgets/login_required_sheet.dart';
import 'package:flutter/services.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/presentation/widgets/tip_banner.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';

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

class _AthleteDashboardScreenState extends State<AthleteDashboardScreen>
    with SingleTickerProviderStateMixin {
  String? _assessoriaName;
  String? _assessoriaGroupId;
  String? _pendingRequestGroupName;
  String? _displayName;
  bool _loading = true;
  bool _stravaConnected = true;
  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadAssessoriaStatus();
    _checkStrava();
    _loadDisplayName();
    sl<UserIdentityProvider>().profileNameNotifier.addListener(_onProfileNameChanged);
  }

  @override
  void dispose() {
    sl<UserIdentityProvider>().profileNameNotifier.removeListener(_onProfileNameChanged);
    _staggerCtrl.dispose();
    super.dispose();
  }

  void _onProfileNameChanged() {
    final name = sl<UserIdentityProvider>().profileNameNotifier.value;
    if (name != null && mounted) {
      setState(() => _displayName = name);
    }
  }

  Future<void> _loadDisplayName() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('display_name')
          .eq('id', uid)
          .maybeSingle();
      if (mounted && row != null) {
        var name = row['display_name'] as String?;
        if (name != null && name.contains('@')) {
          name = name.split('@').first;
          if (name.isNotEmpty) {
            name = name[0].toUpperCase() + name.substring(1);
          }
        }
        setState(() => _displayName = name);
      }
    } catch (e) {
      AppLogger.debug('Failed to load display name', tag: 'Dashboard', error: e);
    }
  }

  Future<void> _checkStrava() async {
    try {
      final connected = await sl<StravaConnectController>().isConnected;
      if (mounted) setState(() => _stravaConnected = connected);
    } catch (e) {
      AppLogger.debug('Strava status check failed', tag: 'Dashboard', error: e);
    }
  }

  Future<void> _loadAssessoriaStatus() async {
    try {
      final uid = sl<UserIdentityProvider>().userId;

      // Try Supabase first (authoritative), fallback to local Isar
      String? groupId;
      String? groupName;
      try {
        final db = Supabase.instance.client;
        final row = await db
            .from('coaching_members')
            .select('group_id, coaching_groups(name)')
            .eq('user_id', uid)
            .eq('role', 'atleta')
            .maybeSingle();
        if (row != null) {
          groupId = row['group_id'] as String?;
          groupName =
              (row['coaching_groups'] as Map?)?['name'] as String?;
        }
      } catch (e) {
        AppLogger.debug('Supabase offline, falling back to Isar', tag: 'Dashboard', error: e);
        final memberships =
            await sl<ICoachingMemberRepo>().getByUserId(uid);
        final membership =
            memberships.where((m) => m.isAtleta).firstOrNull;
        if (membership != null) {
          groupId = membership.groupId;
          final group =
              await sl<ICoachingGroupRepo>().getById(membership.groupId);
          groupName = group?.name;
        }
      }

      if (groupId != null) {
        if (mounted) {
          setState(() {
            _assessoriaName = groupName;
            _assessoriaGroupId = groupId;
            _loading = false;
          });
          _staggerCtrl.forward();
        }
      } else {
        await _checkPendingRequest(uid);
        if (mounted) {
          setState(() => _loading = false);
          _staggerCtrl.forward();
        }
      }
    } catch (e) {
      AppLogger.warn('Failed to load assessoria status', tag: 'Dashboard', error: e);
      if (mounted) {
        setState(() => _loading = false);
        _staggerCtrl.forward();
      }
    }
  }

  Future<void> _checkPendingRequest(String uid) async {
    try {
      final rows = await Supabase.instance.client
          .from('coaching_join_requests')
          .select('group_id')
          .eq('user_id', uid)
          .eq('status', 'pending')
          .limit(1);
      if ((rows as List).isNotEmpty) {
        final groupId = rows.first['group_id'] as String;
        final groupRows = await Supabase.instance.client
            .from('coaching_groups')
            .select('name')
            .eq('id', groupId)
            .limit(1);
        if (mounted && (groupRows as List).isNotEmpty) {
          setState(() {
            _pendingRequestGroupName =
                (groupRows.first['name'] as String?) ?? 'Assessoria';
          });
        }
      }
    } catch (e) {
      AppLogger.debug('Pending request check failed', tag: 'Dashboard', error: e);
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _openChallenges() {
    if (LoginRequiredSheet.guard(context, feature: 'Desafios')) return;
    if (AssessoriaRequiredSheet.guard(context, hasAssessoria: _assessoriaGroupId != null)) return;
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

  void _openVerification() {
    if (LoginRequiredSheet.guard(context, feature: 'Verificação')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AthleteVerificationScreen(),
    ));
  }

  void _openJoinAssessoria() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => JoinAssessoriaScreen(
            onComplete: () => Navigator.of(context).pop(),
          ),
        ))
        .then((_) => _loadAssessoriaStatus());
  }

  void _openChampionships() {
    if (LoginRequiredSheet.guard(context, feature: 'Campeonatos')) return;
    if (AssessoriaRequiredSheet.guard(context, hasAssessoria: _assessoriaGroupId != null)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AthleteChampionshipsScreen(),
    ));
  }

  // Invite friends is accessible via More screen

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
              _displayName != null ? 'Olá, $_displayName!' : 'Olá, atleta!',
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
              icon: Icons.rocket_launch_rounded,
              text: 'Primeiros passos:\n'
                  '1. Conecte seu Strava e faça sua primeira corrida\n'
                  '2. Entre em uma assessoria (peça o código ao professor)\n'
                  '3. Crie ou encontre um desafio para competir\n'
                  '4. Complete corridas para se tornar Atleta Verificado',
            ),
            if (_pendingRequestGroupName != null && !hasAssessoria) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.orange.shade50,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.orange.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded,
                          color: Colors.orange.shade700, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Solicitação pendente',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Aguardando aprovação da assessoria '
                              '"$_pendingRequestGroupName". Você será '
                              'notificado quando a assessoria aprovar.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (hasAssessoria && _assessoriaGroupId != null) ...[
              const SizedBox(height: 8),
              Card(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                margin: EdgeInsets.zero,
                child: ListTile(
                  dense: true,
                  leading:
                      Icon(Icons.forum_rounded, color: cs.primary, size: 22),
                  title: Text(
                    'Feed da $_assessoriaName',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  trailing: Icon(Icons.chevron_right, color: cs.primary),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => BlocProvider<AssessoriaFeedBloc>(
                        create: (_) => sl<AssessoriaFeedBloc>()
                          ..add(LoadFeed(_assessoriaGroupId!)),
                        child: const AssessoriaFeedScreen(),
                      ),
                    ));
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _loading
                ? ShimmerLoading(
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.95,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(6, (_) => const SkeletonCard()),
                    ),
                  )
                : FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _staggerCtrl,
                      curve: Curves.easeOut,
                    ),
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
                    icon: hasAssessoria
                        ? Icons.groups_rounded
                        : Icons.group_add_rounded,
                    title: hasAssessoria
                        ? 'Minha assessoria'
                        : 'Entrar em assessoria',
                    subtitle: _loading
                        ? '...'
                        : _assessoriaName ?? 'Toque para se juntar',
                    bgColor: hasAssessoria
                        ? cs.secondaryContainer
                        : Colors.blue.shade50,
                    iconColor: hasAssessoria
                        ? cs.onSecondaryContainer
                        : Colors.blue.shade700,
                    isEmpty: !hasAssessoria && !_loading,
                    onTap: hasAssessoria
                        ? _openAssessoria
                        : _openJoinAssessoria,
                  ),
                  _DashCard(
                    icon: Icons.trending_up_rounded,
                    title: 'Meu progresso',
                    subtitle: 'XP, badges e missões',
                    bgColor: cs.tertiaryContainer,
                    iconColor: cs.onTertiaryContainer,
                    badge: _stravaConnected ? null : 'Conecte Strava',
                    onTap: _openProgress,
                  ),
                  _DashCard(
                    icon: Icons.verified_user_rounded,
                    title: 'Verificação',
                    subtitle: 'Status de atleta verificado',
                    bgColor: Colors.blue.shade50,
                    iconColor: Colors.blue.shade700,
                    onTap: _openVerification,
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
                    icon: Icons.park_rounded,
                    title: 'Parques',
                    subtitle: 'Rankings e comunidade',
                    bgColor: Colors.green.shade50,
                    iconColor: Colors.green.shade700,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const MyParksScreen(),
                      ));
                    },
                  ),
                  _DashCard(
                    icon: Icons.toll_rounded,
                    title: 'Meus créditos',
                    subtitle: 'Seus OmniCoins',
                    bgColor: Colors.amber.shade100,
                    iconColor: Colors.amber.shade800,
                    onTap: _openWallet,
                  ),
                      ],
                    ),
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
  final String? badge;
  final VoidCallback onTap;

  const _DashCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.iconColor,
    this.isEmpty = false,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : bgColor;
    final titleColor = isEmpty
        ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
        : theme.colorScheme.onSurface;
    final subtitleColor = isEmpty
        ? (isDark ? Colors.grey.shade500 : Colors.grey.shade500)
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: cardBg,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: isDark ? 0.25 : 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 26, color: iconColor),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.orange.shade900.withValues(alpha: 0.4)
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.orange.shade300
                                : Colors.orange.shade800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: subtitleColor,
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
