import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Parsed deep link action dispatched to the UI layer.
sealed class DeepLinkAction {
  const DeepLinkAction();
}

/// User tapped an invite link: `https://omnirunner.app/invite/{code}`
/// or scanned a QR containing the same URL.
class InviteAction extends DeepLinkAction {
  final String code;
  const InviteAction(this.code);
}

/// Supabase auth callback: `omnirunner://auth-callback#...`
/// Handled automatically by supabase_flutter — logged here for observability.
class AuthCallbackAction extends DeepLinkAction {
  final Uri uri;
  const AuthCallbackAction(this.uri);
}

/// User tapped a challenge link: `https://omnirunner.app/challenge/{challengeId}`
class ChallengeAction extends DeepLinkAction {
  final String challengeId;
  const ChallengeAction(this.challengeId);
}

/// User tapped a friend referral link: `https://omnirunner.app/refer/{userId}`
class ReferralAction extends DeepLinkAction {
  final String referrerId;
  const ReferralAction(this.referrerId);
}

/// Strava OAuth callback: `omnirunner://strava/callback?code=XXX`
class StravaCallbackAction extends DeepLinkAction {
  final String code;
  const StravaCallbackAction(this.code);
}

/// Unrecognized link — logged but ignored.
class UnknownLinkAction extends DeepLinkAction {
  final Uri uri;
  const UnknownLinkAction(this.uri);
}

/// Singleton handler that listens for App Links (Universal Links on iOS,
/// App Links on Android) and custom-scheme deep links.
///
/// Register once during app bootstrap via [init]. Consumers subscribe to
/// [actions] to react to parsed links.
///
/// Pending invite codes are persisted to [SharedPreferences] so they survive
/// the OAuth redirect / app restart cycle.
class DeepLinkHandler {
  static const _tag = 'DeepLink';

  /// Production web host(s) for universal links. Accepts `www` and case variants.
  static bool isOmniRunnerWebHost(String host) {
    final h = host.toLowerCase();
    return h == 'omnirunner.app' || h == 'www.omnirunner.app';
  }

  final _appLinks = AppLinks();
  final _controller = StreamController<DeepLinkAction>.broadcast();

  StreamSubscription<Uri>? _sub;

  Stream<DeepLinkAction> get actions => _controller.stream;

  /// Initialise: check for a cold-start link, then subscribe to live links.
  Future<void> init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handle(initial);
      }
    } on Object catch (e) {
      AppLogger.warn('getInitialLink failed: $e', tag: _tag);
    }

    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) {
        AppLogger.warn('uriLinkStream error: $e', tag: _tag);
      },
    );
  }

  void _handle(Uri uri) {
    AppLogger.info('Received link: $uri', tag: _tag);

    final action = _parse(uri);

    // Always persist invite codes so cold-start links survive even when
    // no stream listener is attached yet (AuthGate subscribes after runApp).
    if (action is InviteAction) {
      AppLogger.info('Invite code: ${action.code}', tag: _tag);
      savePendingInvite(action.code);
    }

    _controller.add(action);
  }

  /// Same parsing as cold-start / stream handling; exposed for tests.
  DeepLinkAction parseUri(Uri uri) => _parse(uri);

  DeepLinkAction _parse(Uri uri) {
    // https://omnirunner.app/invite/{code}
    // https://omnirunner.app/refer/{userId}
    if (isOmniRunnerWebHost(uri.host) && uri.pathSegments.length >= 2) {
      final segment = uri.pathSegments[0];
      final value = uri.pathSegments[1];
      if (segment == 'invite' && value.isNotEmpty) {
        return InviteAction(value);
      }
      if (segment == 'challenge' && value.isNotEmpty) {
        return ChallengeAction(value);
      }
      if (segment == 'refer' && value.isNotEmpty) {
        return ReferralAction(value);
      }
    }

    // omnirunner://auth-callback (handled by supabase_flutter internally)
    if (uri.scheme == 'omnirunner' && uri.host == 'auth-callback') {
      return AuthCallbackAction(uri);
    }

    // Strava OAuth callback:
    //   current: omnirunner://localhost/exchange_token?code=XXX
    //   legacy:  omnirunner://strava/callback?code=XXX
    if (uri.scheme == 'omnirunner') {
      final isExchangeToken =
          uri.host == 'localhost' && uri.path.contains('exchange_token');
      final isLegacy =
          uri.host == 'strava' && uri.path.contains('callback');
      if (isExchangeToken || isLegacy) {
        final code = uri.queryParameters['code'];
        if (code != null && code.isNotEmpty) {
          return StravaCallbackAction(code);
        }
      }
    }

    return UnknownLinkAction(uri);
  }

  // ── Pending invite code persistence ────────────────────────────────────

  /// Persist an invite code so it survives login/OAuth redirects.
  Future<void> savePendingInvite(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PreferencesKeys.pendingInviteCode, code);
    AppLogger.info('Saved pending invite: $code', tag: _tag);
  }

  /// Read and clear the persisted invite code (consume-once).
  Future<String?> consumePendingInvite() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(PreferencesKeys.pendingInviteCode);
    if (code != null) {
      await prefs.remove(PreferencesKeys.pendingInviteCode);
      AppLogger.info('Consumed pending invite: $code', tag: _tag);
    }
    return code;
  }

  /// Check if there's a pending invite without consuming it.
  Future<String?> peekPendingInvite() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PreferencesKeys.pendingInviteCode);
  }

  /// Parse an invite code from a URL string, QR data, or raw code.
  /// Returns the extracted code or null if not an invite.
  static String? extractInviteCode(String input) {
    final trimmed = input.trim();

    // Full URL: https://omnirunner.app/invite/{code}
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        isOmniRunnerWebHost(uri.host) &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments[0] == 'invite') {
      final code = uri.pathSegments[1];
      if (code.isNotEmpty) return code;
    }

    // Raw code (non-empty, non-URL)
    if (trimmed.isNotEmpty && !trimmed.contains('/')) return trimmed;

    return null;
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
