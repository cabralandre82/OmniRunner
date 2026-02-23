import 'package:omni_runner/domain/entities/coach_settings_entity.dart';
import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences implementation of [ICoachSettingsRepo].
class CoachSettingsRepo implements ICoachSettingsRepo {
  static const _kmKey = 'coach_km_enabled';
  static const _ghostKey = 'coach_ghost_enabled';
  static const _periodicKey = 'coach_periodic_enabled';
  static const _hrZoneKey = 'coach_hr_zone_enabled';
  static const _maxHrKey = 'coach_max_hr';

  @override
  Future<CoachSettingsEntity> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CoachSettingsEntity(
      kmEnabled: prefs.getBool(_kmKey) ?? true,
      ghostEnabled: prefs.getBool(_ghostKey) ?? true,
      periodicEnabled: prefs.getBool(_periodicKey) ?? true,
      hrZoneEnabled: prefs.getBool(_hrZoneKey) ?? true,
      maxHr: prefs.getInt(_maxHrKey) ?? 190,
    );
  }

  @override
  Future<void> save(CoachSettingsEntity settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kmKey, settings.kmEnabled);
    await prefs.setBool(_ghostKey, settings.ghostEnabled);
    await prefs.setBool(_periodicKey, settings.periodicEnabled);
    await prefs.setBool(_hrZoneKey, settings.hrZoneEnabled);
    await prefs.setInt(_maxHrKey, settings.maxHr);
  }
}
