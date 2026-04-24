import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/presentation/widgets/assessoria_required_sheet.dart';
import 'package:omni_runner/presentation/widgets/financial_alert_banner.dart';
import 'package:omni_runner/presentation/widgets/login_required_sheet.dart';
import 'package:flutter/services.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/presentation/widgets/ds/fade_in.dart';

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
  final bool isVisible;
  const AthleteDashboardScreen({super.key, this.isVisible = true});

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
  bool _hasFirstRun = false;
  bool _hasChallenge = false;
  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (AppConfig.demoMode) {
      _loading = false;
      _displayName = 'Explorador';
      _stravaConnected = true;
      _hasFirstRun = true;
      _hasChallenge = true;
      _staggerCtrl.forward();
    } else {
      _loadAssessoriaStatus();
      _checkStrava();
      _loadDisplayName();
      _checkFirstRunAndChallenges();
      sl<UserIdentityProvider>().profileNameNotifier.addListener(_onProfileNameChanged);
    }
  }

  @override
  void didUpdateWidget(covariant AthleteDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible && !AppConfig.demoMode) {
      _checkStrava();
      _checkFirstRunAndChallenges();
      _loadAssessoriaStatus();
    }
  }

  @override
  void dispose() {
    if (!AppConfig.demoMode) {
      sl<UserIdentityProvider>().profileNameNotifier.removeListener(_onProfileNameChanged);
    }
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
      final uid = sl<SupabaseClient>().auth.currentUser?.id;
      if (uid == null) return;
      final row = await sl<SupabaseClient>()
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
    } on Object catch (e) {
      AppLogger.debug('Failed to load display name', tag: 'Dashboard', error: e);
    }
  }

  bool get _allFirstStepsComplete =>
      _stravaConnected &&
      _assessoriaGroupId != null &&
      _hasFirstRun &&
      _hasChallenge;

  Future<void> _checkStrava() async {
    try {
      final connected = await sl<StravaConnectController>().isConnected;
      if (mounted) setState(() => _stravaConnected = connected);
    } on Object catch (e) {
      AppLogger.debug('Strava status check failed', tag: 'Dashboard', error: e);
    }
  }

  Future<void> _checkFirstRunAndChallenges() async {
    // Check local Isar first (works offline)
    try {
      final localSessions = await sl<ISessionRepo>().getByStatus(WorkoutStatus.completed);
      if (localSessions.isNotEmpty && mounted) {
        setState(() => _hasFirstRun = true);
      }
    } on Object catch (_) {}

    // Then verify against Supabase (authoritative)
    try {
      final uid = sl<UserIdentityProvider>().userId;
      final db = sl<SupabaseClient>();
      final sessionRows = await db
          .from('sessions')
          .select('id')
          .eq('user_id', uid)
          .limit(1);
      final challengeRows = await db
          .from('challenge_participants')
          .select('id')
          .eq('user_id', uid)
          .limit(1);
      if (mounted) {
        setState(() {
          _hasFirstRun = _hasFirstRun || (sessionRows as List).isNotEmpty;
          _hasChallenge = (challengeRows as List).isNotEmpty;
        });
      }
    } on Object catch (e) {
      AppLogger.debug('First steps check failed', tag: 'Dashboard', error: e);
    }
  }

  Future<void> _loadAssessoriaStatus() async {
    try {
      final uid = sl<UserIdentityProvider>().userId;

      // Try Supabase first (authoritative), fallback to local Isar
      String? groupId;
      String? groupName;
      try {
        final db = sl<SupabaseClient>();
        final row = await db
            .from('coaching_members')
            .select('group_id, coaching_groups(name)')
            .eq('user_id', uid)
            .inFilter('role', ['athlete', 'atleta'])
            .maybeSingle();
        if (row != null) {
          groupId = row['group_id'] as String?;
          groupName =
              (row['coaching_groups'] as Map?)?['name'] as String?;
        }
      } on Object catch (e) {
        AppLogger.debug('Supabase offline, falling back to Isar', tag: 'Dashboard', error: e);
        final memberships =
            await sl<ICoachingMemberRepo>().getByUserId(uid);
        final membership =
            memberships.where((m) => m.isAthlete).firstOrNull;
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
    } on Object catch (e) {
      AppLogger.warn('Failed to load assessoria status', tag: 'Dashboard', error: e);
      if (mounted) {
        setState(() => _loading = false);
        _staggerCtrl.forward();
      }
    }
  }

  Future<void> _checkPendingRequest(String uid) async {
    try {
      final rows = await sl<SupabaseClient>()
          .from('coaching_join_requests')
          .select('group_id')
          .eq('user_id', uid)
          .eq('status', 'pending')
          .limit(1);
      if ((rows as List).isNotEmpty) {
        final groupId = rows.first['group_id'] as String;
        final groupRows = await sl<SupabaseClient>()
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
    } on Object catch (e) {
      AppLogger.debug('Pending request check failed', tag: 'Dashboard', error: e);
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  bool _guardDemoMode(BuildContext context) {
    if (!AppConfig.demoMode) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Crie uma conta para usar esta funcionalidade'),
      ),
    );
    return true;
  }

  void _openChallenges() {
    if (_guardDemoMode(context)) return;
    if (LoginRequiredSheet.guard(context, feature: 'Desafios')) return;
    context.push(AppRoutes.challenges);
  }

  void _openAssessoria() {
    if (_guardDemoMode(context)) return;
    if (LoginRequiredSheet.guard(context, feature: 'Assessoria')) return;
    context.push(AppRoutes.myAssessoria);
  }

  void _openProgress() {
    context.push(AppRoutes.progress);
  }

  void _openWallet() {
    if (_guardDemoMode(context)) return;
    if (LoginRequiredSheet.guard(context, feature: 'OmniCoins')) return;
    context.push(AppRoutes.wallet);
  }

  void _openVerification() {
    if (_guardDemoMode(context)) return;
    if (LoginRequiredSheet.guard(context, feature: 'Verificação')) return;
    context.push(AppRoutes.athleteVerification);
  }

  void _openJoinAssessoria() {
    if (_guardDemoMode(context)) return;
    context.push(AppRoutes.joinAssessoria).then((_) => _loadAssessoriaStatus());
  }

  void _openChampionships() {
    if (_guardDemoMode(context)) return;
    if (LoginRequiredSheet.guard(context, feature: 'Campeonatos')) return;
    if (AssessoriaRequiredSheet.guard(context, hasAssessoria: _assessoriaGroupId != null)) return;
    context.push(AppRoutes.championships);
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
      ),
      body: FadeIn(
        child: Padding(
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
                _displayName != null ? 'Olá, $_displayName!' : 'Olá, atleta!',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingXs),
              Text(
                'O que deseja fazer hoje?',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: DesignTokens.spacingMd),
              const FinancialAlertBanner(),
              if (!_loading && !_allFirstStepsComplete)
                _FirstStepsCard(
                  stravaConnected: _stravaConnected,
                  hasAssessoria: _assessoriaGroupId != null,
                  hasFirstRun: _hasFirstRun,
                  hasChallenge: _hasChallenge,
                  onConnectStrava: () {
                    context.push(AppRoutes.settings).then((_) => _checkStrava());
                  },
                  onJoinAssessoria: _openJoinAssessoria,
                  onFirstRun: _openProgress,
                  onCreateChallenge: _openChallenges,
                ),
              if (_pendingRequestGroupName != null && !hasAssessoria) ...[
                const SizedBox(height: DesignTokens.spacingSm),
                Card(
                  color: DesignTokens.warning.withValues(alpha: 0.1),
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                    side: BorderSide(color: DesignTokens.warning.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(DesignTokens.spacingMd),
                    child: Row(
                      children: [
                        const Icon(Icons.hourglass_top_rounded,
                            color: DesignTokens.warning, size: 28),
                        const SizedBox(width: DesignTokens.spacingSm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Solicitação pendente',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: DesignTokens.warning,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacingXs),
                              Text(
                                'Aguardando aprovação da assessoria '
                                '"$_pendingRequestGroupName". Você será '
                                'notificado quando a assessoria aprovar.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: DesignTokens.warning,
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
                const SizedBox(height: DesignTokens.spacingSm),
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
                      context.push(AppRoutes.assessoriaFeed, extra: _assessoriaGroupId!);
                    },
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingSm),
              ],
              if (!_loading && !_hasFirstRun && _allFirstStepsComplete)
                _RunnerQuizCard(
                  onStravaConnect: () {
                    context.push(AppRoutes.settings).then((_) => _checkStrava());
                  },
                ),
              Expanded(
                child: _loading
                  ? ShimmerLoading(
                      child: GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: DesignTokens.spacingMd,
                        crossAxisSpacing: DesignTokens.spacingMd,
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
                        mainAxisSpacing: DesignTokens.spacingMd,
                        crossAxisSpacing: DesignTokens.spacingMd,
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
                          : _assessoriaName ?? 'Grupo de corrida com treinador',
                      bgColor: hasAssessoria
                          ? cs.secondaryContainer
                          : DesignTokens.info.withValues(alpha: 0.1),
                      iconColor: hasAssessoria
                          ? cs.onSecondaryContainer
                          : DesignTokens.info,
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
                      subtitle: 'Confirme suas corridas para competir',
                      bgColor: DesignTokens.info.withValues(alpha: 0.1),
                      iconColor: DesignTokens.info,
                      onTap: _openVerification,
                    ),
                    _DashCard(
                      icon: Icons.emoji_events_rounded,
                      title: 'Campeonatos',
                      subtitle: 'Competir entre assessorias',
                      bgColor: DesignTokens.warning.withValues(alpha: 0.1),
                      iconColor: DesignTokens.warning,
                      onTap: _openChampionships,
                    ),
                    _DashCard(
                      icon: Icons.park_rounded,
                      title: 'Parques',
                      subtitle: _hasFirstRun
                          ? 'Rankings e comunidade'
                          : 'Descubra corredores nos parques perto de você',
                      bgColor: DesignTokens.success.withValues(alpha: 0.1),
                      iconColor: DesignTokens.success,
                      onTap: () {
                        context.push(AppRoutes.parks);
                      },
                    ),
                    _DashCard(
                      icon: Icons.toll_rounded,
                      title: 'Meus créditos',
                      subtitle: 'Seus OmniCoins',
                      bgColor: DesignTokens.warning.withValues(alpha: 0.15),
                      iconColor: DesignTokens.warning,
                      onTap: _openWallet,
                    ),
                        ],
                      ),
                    ),
              ),
            ],
          ),
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
    final cs = theme.colorScheme;
    final cardBg = isDark ? DesignTokens.surface : bgColor;
    final titleColor = isEmpty
        ? cs.onSurface.withValues(alpha: isDark ? 0.4 : 0.6)
        : cs.onSurface;
    final subtitleColor = isEmpty
        ? cs.onSurface.withValues(alpha: 0.4)
        : cs.onSurface.withValues(alpha: 0.6);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
      color: cardBg,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: DesignTokens.spacingXxl,
                    height: DesignTokens.spacingXxl,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: isDark ? 0.25 : 0.15),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                    ),
                    child: Icon(icon, size: 26, color: iconColor),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: DesignTokens.spacingSm),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingSm,
                          vertical: DesignTokens.spacingXs,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? DesignTokens.warning.withValues(alpha: 0.4)
                              : DesignTokens.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: DesignTokens.warning,
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
              const SizedBox(height: DesignTokens.spacingXs),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: subtitleColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (isEmpty) ...[
                const SizedBox(height: DesignTokens.spacingSm),
                Icon(Icons.add_circle_outline, size: 16, color: cs.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// First-steps interactive checklist (#18 + #36)
// ---------------------------------------------------------------------------

class _FirstStepsCard extends StatefulWidget {
  final bool stravaConnected;
  final bool hasAssessoria;
  final bool hasFirstRun;
  final bool hasChallenge;
  final VoidCallback onConnectStrava;
  final VoidCallback onJoinAssessoria;
  final VoidCallback onFirstRun;
  final VoidCallback onCreateChallenge;

  const _FirstStepsCard({
    required this.stravaConnected,
    required this.hasAssessoria,
    required this.hasFirstRun,
    required this.hasChallenge,
    required this.onConnectStrava,
    required this.onJoinAssessoria,
    required this.onFirstRun,
    required this.onCreateChallenge,
  });

  @override
  State<_FirstStepsCard> createState() => _FirstStepsCardState();
}

class _FirstStepsCardState extends State<_FirstStepsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final steps = [
      (done: widget.stravaConnected, label: 'Conectar Strava', xp: '+50 XP', onTap: widget.onConnectStrava),
      (done: widget.hasAssessoria, label: 'Entrar em assessoria', xp: '+100 XP', onTap: widget.onJoinAssessoria),
      (done: widget.hasFirstRun, label: 'Completar primeira corrida', xp: '+75 XP', onTap: widget.onFirstRun),
      (done: widget.hasChallenge, label: 'Criar ou aceitar um desafio', xp: '+50 XP', onTap: widget.onCreateChallenge),
    ];
    final completed = steps.where((s) => s.done).length;

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: completed / steps.length,
                          strokeWidth: 3,
                          backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                          color: DesignTokens.success,
                        ),
                        Text(
                          '$completed/${steps.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacingSm),
                  Expanded(
                    child: Text(
                      'Primeiros passos',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '+275 XP',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: DesignTokens.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: DesignTokens.spacingSm),
                ...steps.map((s) => _StepRow(
                      done: s.done,
                      label: s.label,
                      xp: s.xp,
                      onTap: s.done ? null : s.onTap,
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final bool done;
  final String label;
  final String xp;
  final VoidCallback? onTap;

  const _StepRow({
    required this.done,
    required this.label,
    required this.xp,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: done ? DesignTokens.success : cs.outlineVariant,
            ),
            const SizedBox(width: DesignTokens.spacingSm),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done
                      ? cs.onSurface.withValues(alpha: 0.5)
                      : cs.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingSm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: done
                    ? DesignTokens.success.withValues(alpha: 0.1)
                    : DesignTokens.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: Text(
                xp,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: done ? DesignTokens.success : DesignTokens.warning,
                ),
              ),
            ),
            if (!done) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: cs.outlineVariant),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini-AHA Quiz "Qual seu tipo de corredor?" (#41)
// ---------------------------------------------------------------------------

class _RunnerQuizCard extends StatelessWidget {
  final VoidCallback onStravaConnect;

  const _RunnerQuizCard({required this.onStravaConnect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      color: cs.tertiaryContainer.withValues(alpha: 0.3),
      child: InkWell(
        onTap: () => _showQuiz(context),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Icon(Icons.quiz_outlined, color: cs.tertiary, size: 24),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Qual seu tipo de corredor?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      'Responda 3 perguntas e descubra',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  static void _showQuiz(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _RunnerQuizSheet(
        onStravaConnect: () {
          ctx.pop();
        },
      ),
    );
  }
}

class _RunnerQuizSheet extends StatefulWidget {
  final VoidCallback onStravaConnect;
  const _RunnerQuizSheet({required this.onStravaConnect});

  @override
  State<_RunnerQuizSheet> createState() => _RunnerQuizSheetState();
}

class _RunnerQuizSheetState extends State<_RunnerQuizSheet> {
  int _step = 0;
  int? _a1;
  int? _a2;
  int? _a3;

  static const _questions = [
    (
      question: 'Quantas vezes você corre por semana?',
      options: ['1-2x', '3-4x', '5+x'],
    ),
    (
      question: 'Qual distância mais corre?',
      options: ['Até 5km', '5-10km', 'Meia/Maratona'],
    ),
    (
      question: 'O que te motiva a correr?',
      options: ['Saúde', 'Competição', 'Diversão'],
    ),
  ];

  void _answer(int value) {
    setState(() {
      switch (_step) {
        case 0:
          _a1 = value;
        case 1:
          _a2 = value;
        case 2:
          _a3 = value;
      }
      _step++;
    });
  }

  ({String emoji, String title, String subtitle}) get _result {
    final score = (_a1 ?? 0) + (_a2 ?? 0) + (_a3 ?? 0);
    if (score <= 2) {
      return (
        emoji: '\u{1F3C3}\u{200D}\u{2642}\u{FE0F}',
        title: 'Corredor Social',
        subtitle: 'Você corre pela experiência e diversão',
      );
    } else if (score <= 4) {
      return (
        emoji: '\u{1F4AA}',
        title: 'Corredor Dedicado',
        subtitle: 'Consistência é sua força',
      );
    } else {
      return (
        emoji: '\u{1F525}',
        title: 'Corredor Competitivo',
        subtitle: 'Nasceu para desafios',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spacingLg,
        DesignTokens.spacingLg,
        DesignTokens.spacingLg,
        MediaQuery.of(context).viewInsets.bottom + DesignTokens.spacingLg,
      ),
      child: _step < 3 ? _buildQuestion(theme, cs) : _buildResult(theme, cs),
    );
  }

  Widget _buildQuestion(ThemeData theme, ColorScheme cs) {
    final q = _questions[_step];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.quiz_outlined, color: cs.tertiary),
            const SizedBox(width: DesignTokens.spacingSm),
            Text(
              'Pergunta ${_step + 1} de 3',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          q.question,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        ...q.options.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _answer(e.key),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: DesignTokens.spacingMd,
                    ),
                  ),
                  child: Text(e.value),
                ),
              ),
            )),
        const SizedBox(height: DesignTokens.spacingSm),
      ],
    );
  }

  Widget _buildResult(ThemeData theme, ColorScheme cs) {
    final r = _result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(r.emoji, style: const TextStyle(fontSize: 56)),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          r.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          r.subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingLg),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text(
              'Conecte o Strava para descobrir seu DNA completo \u2192',
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
