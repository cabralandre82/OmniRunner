import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/deep_links/deep_link_handler.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/presentation/screens/challenge_join_screen.dart';
import 'package:omni_runner/presentation/screens/home_screen.dart';
import 'package:omni_runner/presentation/screens/join_assessoria_screen.dart';
import 'package:omni_runner/presentation/screens/login_screen.dart';
import 'package:omni_runner/presentation/screens/onboarding_role_screen.dart';
import 'package:omni_runner/presentation/screens/onboarding_tour_screen.dart';
import 'package:omni_runner/presentation/screens/staff_setup_screen.dart';
import 'package:omni_runner/presentation/screens/welcome_screen.dart';

/// Single entry-point guard that routes users based on auth + onboarding state.
///
/// Flow:
///   No session / anonymous → [WelcomeScreen] → [LoginScreen]
///   Session + NEW → [OnboardingRoleScreen]
///   Session + ROLE_SELECTED + ATLETA → [JoinAssessoriaScreen]
///   Session + ROLE_SELECTED + STAFF → [StaffSetupScreen]
///   Session + READY → [HomeScreen]
///   Mock mode → [HomeScreen] (skip all gates)
///
/// Invite link handling:
///   - Not logged in → persists code, applies after login
///   - Onboarding ATLETA → passed as initialCode to [JoinAssessoriaScreen]
///   - READY user → auto-join with confirmation dialog
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _GateDestination {
  loading,
  welcome,
  login,
  onboarding,
  joinAssessoria,
  staffSetup,
  tour,
  home,
}

class _AuthGateState extends State<AuthGate> {
  static const _tag = 'AuthGate';

  _GateDestination _dest = _GateDestination.loading;
  OnboardingState _onboardingState = OnboardingState.newUser;
  String? _userRole;
  String? _pendingInviteCode;
  StreamSubscription<DeepLinkAction>? _linkSub;

  @override
  void initState() {
    super.initState();
    _linkSub = sl<DeepLinkHandler>().actions.listen(_onDeepLink);
    _resolve();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  // ── Deep link handling ──────────────────────────────────────────────────

  void _onDeepLink(DeepLinkAction action) {
    if (action is ChallengeAction) {
      _navigateToChallenge(action.challengeId);
      return;
    }

    if (action is StravaCallbackAction) {
      // Strava OAuth is now handled by FlutterWebAuth2 in the settings screen.
      // Deep link may still fire as a duplicate — ignore silently.
      AppLogger.info('Strava deep-link ignored (handled by FlutterWebAuth2)', tag: _tag);
      return;
    }

    if (action is! InviteAction) return;

    final code = action.code;
    _pendingInviteCode = code;

    if (_dest == _GateDestination.home) {
      _autoJoinFromHome(code);
    } else if (_dest == _GateDestination.welcome) {
      _go(_GateDestination.login);
    }
  }

  void _navigateToChallenge(String challengeId) {
    if (!mounted) return;
    if (_dest != _GateDestination.home) return;

    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChallengeJoinScreen(challengeId: challengeId),
    ));
  }

  /// Deep-link join flow: looks up the group, shows confirmation, then
  /// sends a join **request** (requires staff approval — no instant entry).
  Future<void> _autoJoinFromHome(String code) async {
    if (!mounted) return;

    _pendingInviteCode = null;
    sl<DeepLinkHandler>().consumePendingInvite();

    final client = Supabase.instance.client;

    try {
      final res = await client.rpc(
        'fn_lookup_group_by_invite_code',
        params: {'p_code': code},
      );
      final list = res as List<dynamic>;

      if (list.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Código de convite inválido ou assessoria não encontrada.',
            ),
          ),
        );
        return;
      }

      final data = list.first as Map<String, dynamic>;
      final groupId = data['id'] as String;
      final groupName = data['name'] as String? ?? 'Assessoria';

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Solicitar entrada?'),
          content: Text(
            'Sua solicitação será enviada para a assessoria '
            '"$groupName". Você será adicionado quando a assessoria aprovar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Solicitar'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      final joinRes = await client.rpc(
        'fn_request_join',
        params: {'p_group_id': groupId},
      );
      final status = (joinRes as Map<String, dynamic>?)?['status'] as String?;

      if (!mounted) return;

      if (status == 'already_member') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Você já é membro da assessoria $groupName.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (status == 'already_requested') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Você já tem uma solicitação pendente para "$groupName". '
              'Aguarde a aprovação.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Solicitação enviada para "$groupName"! '
              'Aguarde a aprovação da assessoria.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      AppLogger.info(
        'Join request sent for group $groupId via invite link (status: $status)',
        tag: _tag,
      );
    } catch (e) {
      AppLogger.error('Auto-join request failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível enviar a solicitação.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ── State resolution ────────────────────────────────────────────────────

  Future<void> _resolve() async {
    if (!AppConfig.isSupabaseReady) {
      _go(_GateDestination.welcome);
      return;
    }

    final identity = sl<UserIdentityProvider>();
    final authRepo = identity.authRepository;

    // No authenticated user at all → show welcome screen.
    if (!authRepo.isSignedIn) {
      _go(_GateDestination.welcome);
      return;
    }

    // Anonymous users must go through login to access the full app.
    if (identity.isAnonymous) {
      _go(_GateDestination.welcome);
      return;
    }

    // Check for a persisted pending invite code (survives OAuth redirects).
    final handler = sl<DeepLinkHandler>();
    final persistedCode = await handler.consumePendingInvite();
    if (persistedCode != null) {
      _pendingInviteCode ??= persistedCode;
    }

    // Authenticated non-anonymous user: check onboarding state.
    try {
      final profile = await sl<IProfileRepo>().getMyProfile();
      if (profile == null) {
        AppLogger.warn('Profile not found for ${identity.userId}', tag: _tag);
        _onboardingState = OnboardingState.newUser;
        _go(_GateDestination.onboarding);
        return;
      }

      _onboardingState = profile.onboardingState;
      _userRole = profile.userRole;

      if (profile.isOnboardingComplete) {
        if (_pendingInviteCode != null) {
          final code = _pendingInviteCode!;
          _pendingInviteCode = null;
          _go(_GateDestination.home);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _autoJoinFromHome(code);
          });
        } else {
          await _goHomeOrTour();
        }
      } else if (profile.onboardingState == OnboardingState.roleSelected &&
          profile.userRole == 'ATLETA') {
        _go(_GateDestination.joinAssessoria);
      } else if (profile.onboardingState == OnboardingState.roleSelected &&
          profile.userRole == 'ASSESSORIA_STAFF') {
        _go(_GateDestination.staffSetup);
      } else {
        _go(_GateDestination.onboarding);
      }
    } catch (e) {
      AppLogger.error('AuthGate profile fetch failed: $e', tag: _tag, error: e);
      await _retryResolve();
    }
  }

  int _retryCount = 0;

  Future<void> _retryResolve() async {
    if (_retryCount >= 2) {
      AppLogger.warn('AuthGate retries exhausted, falling back to home', tag: _tag);
      _go(_GateDestination.home);
      return;
    }
    _retryCount++;
    await Future<void>.delayed(Duration(seconds: _retryCount * 2));
    if (!mounted) return;
    try {
      final profile = await sl<IProfileRepo>().getMyProfile();
      if (profile == null) {
        _go(_GateDestination.onboarding);
        return;
      }
      _onboardingState = profile.onboardingState;
      _userRole = profile.userRole;
      if (profile.isOnboardingComplete) {
        await _goHomeOrTour();
      } else {
        _go(_GateDestination.onboarding);
      }
    } catch (e) {
      AppLogger.error('AuthGate retry #$_retryCount failed: $e', tag: _tag, error: e);
      await _retryResolve();
    }
  }

  Future<void> _goHomeOrTour() async {
    final shouldTour = await FirstUseTips.shouldShow(TipKey.onboardingTour);
    if (shouldTour && _userRole != 'ASSESSORIA_STAFF') {
      _go(_GateDestination.tour);
    } else {
      _go(_GateDestination.home);
    }
  }

  void _onTourComplete() {
    _go(_GateDestination.home);
  }

  void _go(_GateDestination d) {
    if (!mounted) return;
    setState(() => _dest = d);
  }

  void _onLoginSuccess() {
    sl<UserIdentityProvider>().refresh();
    setState(() => _dest = _GateDestination.loading);
    _resolve();
  }

  void _onOnboardingComplete() {
    setState(() => _dest = _GateDestination.loading);
    _resolve();
  }

  Future<void> _onBackToLogin() async {
    await sl<UserIdentityProvider>().authRepository.signOut();
    _go(_GateDestination.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _dest == _GateDestination.onboarding ||
        _dest == _GateDestination.joinAssessoria ||
        _dest == _GateDestination.staffSetup;

    final child = switch (_dest) {
      _GateDestination.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      _GateDestination.welcome => WelcomeScreen(
          onStart: () => _go(_GateDestination.login),
        ),
      _GateDestination.login => LoginScreen(
          onSuccess: _onLoginSuccess,
          hasPendingInvite: _pendingInviteCode != null,
        ),
      _GateDestination.onboarding => OnboardingRoleScreen(
          initialState: _onboardingState,
          onComplete: _onOnboardingComplete,
          onBack: _onBackToLogin,
        ),
      _GateDestination.joinAssessoria => JoinAssessoriaScreen(
          initialCode: _pendingInviteCode,
          onComplete: _onOnboardingComplete,
          onBack: _onBackToLogin,
        ),
      _GateDestination.staffSetup => StaffSetupScreen(
          onComplete: _onOnboardingComplete,
          onBack: _onBackToLogin,
        ),
      _GateDestination.tour => OnboardingTourScreen(
          onComplete: _onTourComplete,
        ),
      _GateDestination.home => HomeScreen(userRole: _userRole),
    };

    if (canGoBack) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBackToLogin();
        },
        child: child,
      );
    }
    return child;
  }
}
