import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_plan_repo.dart';

/// Gerencia o sync incremental de treinos usando cursor de timestamp.
///
/// Fluxo:
///  1. Lê o cursor salvo localmente (último updated_at recebido).
///  2. Chama fn_get_training_sync_delta(device_id, since=cursor).
///  3. Salva os workouts no cache local (Drift).
///  4. Persiste o novo cursor.
///
/// O app pode chamar syncDelta() a qualquer momento (app start, pull-to-refresh).
/// Funciona sem rede — usa cache. Quando volta online, o delta é aplicado incrementalmente.
class TrainingSyncService {
  TrainingSyncService({
    required ITrainingPlanRepo repo,
    required String deviceId,
  })  : _repo = repo,
        _deviceId = deviceId;

  final ITrainingPlanRepo _repo;
  final String _deviceId;

  static const _cursorKey = 'training_sync_cursor';
  static const _tag = 'TrainingSyncService';

  bool _syncing = false;

  /// Executa sync incremental.
  /// Retorna a lista de workouts atualizados (delta apenas).
  Future<List<PlanWorkoutEntity>> syncDelta() async {
    if (_syncing) {
      AppLogger.debug('Sync already in progress, skipping', tag: _tag);
      return [];
    }
    _syncing = true;
    try {
      final cursor = await _loadCursor();
      AppLogger.debug('Syncing training feed since $cursor', tag: _tag);

      final result = await _repo.getSyncDelta(
        deviceId: _deviceId,
        since:    cursor,
      );

      if (result.count > 0) {
        await _saveCursor(result.cursor);
        AppLogger.info(
          'Synced ${result.count} workouts, new cursor=${result.cursor}',
          tag: _tag,
        );
      }

      return result.workouts;
    } catch (e, stack) {
      AppLogger.error('syncDelta failed', tag: _tag, error: e, stack: stack);
      return [];
    } finally {
      _syncing = false;
    }
  }

  /// Força full sync (ignora cursor — útil após logout/login ou primeiro uso).
  Future<List<PlanWorkoutEntity>> fullSync() async {
    await _clearCursor();
    return syncDelta();
  }

  Future<DateTime?> _loadCursor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_cursorKey);
      if (stored == null) return null;
      return DateTime.tryParse(stored);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCursor(DateTime cursor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cursorKey, cursor.toUtc().toIso8601String());
    } catch (e) {
      AppLogger.debug('Failed to save cursor', tag: _tag, error: e);
    }
  }

  Future<void> _clearCursor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cursorKey);
    } catch (_) {}
  }
}
