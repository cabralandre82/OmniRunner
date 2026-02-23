import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_vehicle.dart';

const String _tag = 'HealthStepsSource';

/// Adapts [IHealthProvider.readSteps] to the [IStepsSource] interface
/// used by [IntegrityDetectVehicle] for anti-cheat.
///
/// Converts [HealthStepSample] (steps over a time window) into
/// [StepSample] (instantaneous SPM at a point in time) by calculating
/// steps-per-minute from each window's duration and step count.
class HealthStepsSource implements IStepsSource {
  final IHealthProvider _provider;
  final ISessionRepo _sessionRepo;

  const HealthStepsSource({
    required IHealthProvider provider,
    required ISessionRepo sessionRepo,
  })  : _provider = provider,
        _sessionRepo = sessionRepo;

  @override
  Future<List<StepSample>> samplesForSession(String sessionId) async {
    try {
      final session = await _sessionRepo.getById(sessionId);
      if (session == null) return const [];

      final start =
          DateTime.fromMillisecondsSinceEpoch(session.startTimeMs, isUtc: true);
      final endMs = session.endTimeMs ?? DateTime.now().millisecondsSinceEpoch;
      final end = DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true);

      final healthSteps = await _provider.readSteps(start: start, end: end);
      if (healthSteps.isEmpty) return const [];

      final samples = <StepSample>[];
      for (final hs in healthSteps) {
        final durationMs = hs.endMs - hs.startMs;
        if (durationMs <= 0) continue;

        final durationMin = durationMs / 60000.0;
        final spm = hs.steps / durationMin;

        // Emit a single sample at the midpoint of the window.
        final midMs = hs.startMs + (durationMs ~/ 2);
        samples.add(StepSample(timestampMs: midMs, spm: spm));
      }

      samples.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      return samples;
    } on Exception catch (e) {
      AppLogger.warn('Failed to load health steps for session $sessionId: $e',
          tag: _tag);
      return const [];
    }
  }
}
