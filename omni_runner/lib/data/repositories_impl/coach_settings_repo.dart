import 'package:omni_runner/core/storage/preferences_keys.dart';
import 'package:omni_runner/domain/entities/coach_settings_entity.dart';
import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences implementation of [ICoachSettingsRepo].
class CoachSettingsRepo implements ICoachSettingsRepo {
  @override
  Future<CoachSettingsEntity> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CoachSettingsEntity(
      kmEnabled: prefs.getBool(PreferencesKeys.coachKmEnabled) ?? true,
      ghostEnabled: prefs.getBool(PreferencesKeys.coachGhostEnabled) ?? true,
      periodicEnabled: prefs.getBool(PreferencesKeys.coachPeriodicEnabled) ?? true,
      hrZoneEnabled: prefs.getBool(PreferencesKeys.coachHrZoneEnabled) ?? true,
      maxHr: prefs.getInt(PreferencesKeys.coachMaxHr) ?? 190,
      useImperial: prefs.getBool(PreferencesKeys.coachUseImperial) ?? false,
      profileVisibleInRanking:
          prefs.getBool(PreferencesKeys.coachProfileVisibleRanking) ?? true,
      shareActivityInFeed:
          prefs.getBool(PreferencesKeys.coachShareActivityFeed) ?? true,
    );
  }

  @override
  Future<void> save(CoachSettingsEntity settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PreferencesKeys.coachKmEnabled, settings.kmEnabled);
    await prefs.setBool(PreferencesKeys.coachGhostEnabled, settings.ghostEnabled);
    await prefs.setBool(
        PreferencesKeys.coachPeriodicEnabled, settings.periodicEnabled);
    await prefs.setBool(
        PreferencesKeys.coachHrZoneEnabled, settings.hrZoneEnabled);
    await prefs.setInt(PreferencesKeys.coachMaxHr, settings.maxHr);
    await prefs.setBool(PreferencesKeys.coachUseImperial, settings.useImperial);
    await prefs.setBool(PreferencesKeys.coachProfileVisibleRanking,
        settings.profileVisibleInRanking);
    await prefs.setBool(
        PreferencesKeys.coachShareActivityFeed, settings.shareActivityInFeed);
  }
}
