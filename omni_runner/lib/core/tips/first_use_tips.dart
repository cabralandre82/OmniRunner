import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which first-use tips have been shown to avoid repeating them.
///
/// Each tip is identified by a [TipKey]. Once dismissed, it won't appear again
/// on subsequent app launches.
enum TipKey {
  dashboardWelcome,
  challengeHowTo,
  matchmakingHowTo,
  stravaConnect,
  assessoriaHowTo,
  campeonatosHowTo,
  staffWelcome,
  progressionHowTo,
  badgesHowTo,
  rankingsHowTo,
  onboardingTour,
}

class FirstUseTips {
  static const _prefix = 'tip_seen_';

  /// Returns true if the tip has NOT been shown yet.
  static Future<bool> shouldShow(TipKey key) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('$_prefix${key.name}') ?? false);
  }

  /// Mark a tip as seen so it won't show again.
  static Future<void> markSeen(TipKey key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix${key.name}', true);
  }

  /// Reset all tips (useful for testing / settings).
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in TipKey.values) {
      await prefs.remove('$_prefix${key.name}');
    }
  }
}
