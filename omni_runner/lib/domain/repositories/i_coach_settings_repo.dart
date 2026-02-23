import 'package:omni_runner/domain/entities/coach_settings_entity.dart';

/// Contract for persisting audio coach user preferences.
///
/// Domain interface — implementation uses SharedPreferences (or similar).
abstract interface class ICoachSettingsRepo {
  /// Load saved settings, or defaults if none saved.
  Future<CoachSettingsEntity> load();

  /// Persist [settings] to storage.
  Future<void> save(CoachSettingsEntity settings);
}
