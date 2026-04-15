import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/screens/challenge_details_screen.dart';
import 'package:omni_runner/presentation/screens/challenge_join_screen.dart';
import 'package:omni_runner/presentation/screens/friends_screen.dart';

/// Handles push notification UX:
/// 1. Shows an in-app MaterialBanner when a push arrives while app is open
/// 2. Navigates to the relevant screen when the user taps a push notification
class PushNavigationHandler {
  static const _tag = 'PushNav';

  final GlobalKey<NavigatorState> navigatorKey;
  StreamSubscription<RemoteMessage>? _openedSub;

  PushNavigationHandler({required this.navigatorKey});

  Future<void> init() async {
    // Handle tap on notification when app is in background/terminated
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // Handle cold-start tap (app was terminated)
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Small delay to let the navigator be ready
      Future.delayed(const Duration(milliseconds: 800), () {
        _handleTap(initial);
      });
    }
  }

  /// Show an in-app banner for foreground pushes.
  void showForegroundBanner(RemoteMessage message) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final data = message.data;

    ScaffoldMessenger.maybeOf(ctx)?.showMaterialBanner(
      MaterialBanner(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.notifications_active, color: Colors.deepPurple),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty)
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (body.isNotEmpty)
              Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.maybeOf(ctx)?.hideCurrentMaterialBanner();
            },
            child: const Text('FECHAR'),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.maybeOf(ctx)?.hideCurrentMaterialBanner();
              _navigateFromData(data);
            },
            child: const Text('VER'),
          ),
        ],
      ),
    );

    // Auto-dismiss after 6 seconds (re-resolve context — [ctx] is stale after the gap).
    Future.delayed(const Duration(seconds: 6), () {
      final after = navigatorKey.currentContext;
      if (after == null || !after.mounted) return;
      ScaffoldMessenger.maybeOf(after)?.hideCurrentMaterialBanner();
    });
  }

  void _handleTap(RemoteMessage message) {
    AppLogger.info('Push tapped: ${message.data}', tag: _tag);
    _navigateFromData(message.data);
  }

  void _navigateFromData(Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final type = data['type'] as String? ?? '';

    switch (type) {
      case 'challenge_received':
        final challengeId = data['challenge_id'] as String?;
        if (challengeId != null) {
          nav.push(MaterialPageRoute<void>(
            builder: (_) => ChallengeJoinScreen(challengeId: challengeId),
          ));
        }
        return;

      case 'challenge_accepted':
      case 'challenge_settled':
      case 'challenge_expiring':
      case 'challenge_team_invite_received':
        final challengeId = data['challenge_id'] as String?;
        if (challengeId != null) {
          nav.push(MaterialPageRoute<void>(
            builder: (_) => BlocProvider(
              create: (_) => sl<ChallengesBloc>()
                ..add(ViewChallengeDetails(challengeId)),
              child: ChallengeDetailsScreen(challengeId: challengeId),
            ),
          ));
        }
        return;

      case 'friend_request_received':
      case 'friend_request_accepted':
        nav.push(MaterialPageRoute<void>(
          builder: (_) => BlocProvider(
            create: (_) => sl<FriendsBloc>(),
            child: const FriendsScreen(),
          ),
        ));
        return;

      case 'badge_earned':
      case 'streak_at_risk':
      case 'inactivity_nudge':
        // Navigate to the main screen (AuthGate handles routing to TodayScreen)
        break;

      case 'championship_starting':
      case 'championship_invite_received':
        // Navigate to championships; AuthGate lands on TodayScreen
        break;

      case 'league_rank_change':
        // Navigate to league; currently accessible via ProgressHub
        break;

      case 'join_request_approved':
      case 'join_request_received':
        // Staff/athlete will see it upon opening the relevant screen
        break;

      default:
        AppLogger.debug('Unknown push type: $type', tag: _tag);
    }
  }

  void dispose() {
    _openedSub?.cancel();
  }
}
