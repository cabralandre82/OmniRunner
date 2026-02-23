import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/utils/calculate_moving_ms.dart';
import 'package:omni_runner/core/utils/generate_uuid_v4.dart';
import 'package:omni_runner/data/datasources/foreground_task_config.dart';
import 'package:omni_runner/domain/entities/ghost_session_entity.dart';
import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/failures/location_failure.dart';
import 'package:omni_runner/domain/entities/coach_settings_entity.dart';
import 'package:omni_runner/domain/repositories/i_audio_coach.dart';
import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';
import 'package:omni_runner/domain/repositories/i_location_stream.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/domain/usecases/accumulate_distance.dart';
import 'package:omni_runner/domain/usecases/auto_pause_detector.dart';
import 'package:omni_runner/domain/usecases/calculate_ghost_delta.dart';
import 'package:omni_runner/domain/usecases/calculate_pace.dart';
import 'package:omni_runner/domain/usecases/ensure_location_ready.dart';
import 'package:omni_runner/domain/usecases/export_workout_to_health.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';
import 'package:omni_runner/domain/usecases/finish_session.dart';
import 'package:omni_runner/domain/usecases/ghost_position_at.dart';
import 'package:omni_runner/domain/usecases/ghost_voice_trigger.dart';
import 'package:omni_runner/domain/entities/hr_zone.dart';
import 'package:omni_runner/domain/usecases/hr_zone_voice_trigger.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_speed.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_teleport.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_vehicle.dart';
import 'package:omni_runner/domain/usecases/time_voice_trigger.dart';
import 'package:omni_runner/domain/usecases/gamification/post_session_challenge_dispatcher.dart';
import 'package:omni_runner/domain/usecases/gamification/reward_session_coins.dart';
import 'package:omni_runner/domain/usecases/progression/post_session_progression.dart';
import 'package:omni_runner/domain/usecases/voice_triggers.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';
import 'package:omni_runner/features/wearables_ble/i_heart_rate_source.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_event.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_state.dart';

class TrackingBloc extends Bloc<TrackingEvent, TrackingState> {
  static const _tag = 'TrackingBloc';
  final EnsureLocationReady _ensureLocationReady; final ILocationStream _locationStream;
  final FilterLocationPoints _filterPoints;
  final AccumulateDistance _accumulateDistance;
  final CalculatePace _calculatePace;
  final AutoPauseDetector _autoPause;
  final FinishSession _finishSession;
  final GhostPositionAt _ghostPosAt;
  final CalculateGhostDelta _calcGhostDelta;
  final IntegrityDetectSpeed _detectSpeed;
  final IntegrityDetectTeleport _detectTeleport;
  final IAudioCoach _audioCoach;
  final IPointsRepo _pointsRepo; final ISessionRepo _sessionRepo;
  final ISyncRepo _syncRepo; final ICoachSettingsRepo _coachSettings;
  final IHeartRateSource? _hrSource;
  final ExportWorkoutToHealth? _exportWorkout;
  final IStepsSource? _stepsSource;
  final PostSessionProgression? _progression;
  final PostSessionChallengeDispatcher? _challengeDispatcher;
  final RewardSessionCoins? _rewardCoins;
  StreamSubscription<LocationPointEntity>? _sub;
  StreamSubscription<HeartRateSample>? _hrSub;
  StreamSubscription<BleHrConnectionState>? _hrConnSub;
  final _points = <LocationPointEntity>[]; List<LocationPointEntity> _buffer = [];
  List<LocationPointEntity> _filteredCache = [];
  int _filteredUpTo = 0;
  String _sessionId = ''; GhostSessionEntity? _ghost; double _ghostTotalDistM = 0.0;
  String? _challengeId; String? _challengeOpponentUserId; String? _challengeOpponentName; double? _challengeTargetM;
  static const _bufSize = 10; static const _cooldownMs = 30000;
  static const _emitMs = 1000; static const _maxPts = 300;
  static const _gpsReconnectIntervalMs = 5000;
  static const _gpsReconnectTimeoutMs = 60000;
  Timer? _gpsReconnectTimer;
  int _gpsLostAtMs = 0;
  bool _gpsLost = false;
  final _intBuf = <LocationPointEntity>[]; final _intFlags = <String>{};
  final _vehicleDetector = VehicleSlidingDetector();
  int _lastStepFetchMs = 0; static const _stepFetchIntervalMs = 15000;
  bool _isVerified = true; int _lastIntCheckMs = 0; int _lastEmitMs = 0;
  double _accumDistM = 0.0; int _startMs = 0; LocationPointEntity? _prevPt; int _totalPts = 0;
  final _voiceKm = VoiceTriggers(); final _voiceTime = TimeVoiceTrigger();
  final _voiceGhost = GhostVoiceTrigger(); HrZoneVoiceTrigger? _voiceHrZone;
  int _lastSpeakMs = 0; var _cs = const CoachSettingsEntity();

  // Heart rate accumulation
  int? _currentBpm;
  int _hrSum = 0;
  int _hrCount = 0;
  int _hrMax = 0;
  String? _hrConnState;
  final _hrSamples = <HealthHrSample>[];

  TrackingBloc({
    required EnsureLocationReady ensureLocationReady,
    required ILocationStream locationStream,
    required FilterLocationPoints filterPoints,
    required AccumulateDistance accumulateDistance,
    required CalculatePace calculatePace,
    required AutoPauseDetector autoPause,
    required FinishSession finishSession,
    required GhostPositionAt ghostPositionAt,
    required CalculateGhostDelta calculateGhostDelta,
    required IntegrityDetectSpeed detectSpeed,
    required IntegrityDetectTeleport detectTeleport,
    required IAudioCoach audioCoach,
    required IPointsRepo pointsRepo, required ISessionRepo sessionRepo,
    required ISyncRepo syncRepo, required ICoachSettingsRepo coachSettings,
    IHeartRateSource? hrSource,
    ExportWorkoutToHealth? exportWorkout,
    IStepsSource? stepsSource,
    PostSessionProgression? progression,
    PostSessionChallengeDispatcher? challengeDispatcher,
    RewardSessionCoins? rewardCoins,
  })  : _ensureLocationReady = ensureLocationReady,
        _locationStream = locationStream,
        _filterPoints = filterPoints,
        _accumulateDistance = accumulateDistance,
        _calculatePace = calculatePace,
        _autoPause = autoPause,
        _finishSession = finishSession,
        _ghostPosAt = ghostPositionAt,
        _calcGhostDelta = calculateGhostDelta,
        _detectSpeed = detectSpeed,
        _detectTeleport = detectTeleport,
        _audioCoach = audioCoach,
        _pointsRepo = pointsRepo, _sessionRepo = sessionRepo,
        _syncRepo = syncRepo, _coachSettings = coachSettings,
        _hrSource = hrSource,
        _exportWorkout = exportWorkout,
        _stepsSource = stepsSource,
        _progression = progression,
        _challengeDispatcher = challengeDispatcher,
        _rewardCoins = rewardCoins,
        super(const TrackingIdle()) {
    on<AppStarted>(_onPermCheck); on<RequestPermission>(_onPermCheck);
    on<StartTracking>(_onStartTracking); on<StopTracking>(_onStopTracking);
    on<AppLifecycleChanged>(_onAppLifecycleChanged);
    on<LocationPointReceived>(_onLocationPointReceived);
    on<LocationStreamError>((e, emit) { _sub = null; emit(TrackingError(message: e.message)); });
    on<GpsStreamEnded>(_onGpsStreamEnded);
    on<HeartRateReceived>(_onHeartRateReceived);
    on<SetGhostSession>(_onSetGhost);
    on<SetChallengeContext>(_onSetChallengeContext);
  }

  Future<void> _onPermCheck(TrackingEvent _, Emitter<TrackingState> emit) async {
    final f = await _ensureLocationReady();
    f != null ? emit(_mapFailure(f)) : emit(const TrackingIdle());
  }

  void _onSetGhost(SetGhostSession e, Emitter<TrackingState> emit) {
    _ghost = e.ghost; _ghostTotalDistM = _ghost != null ? _accumulateDistance(_ghost!.route) : 0.0;
  }

  void _onSetChallengeContext(SetChallengeContext e, Emitter<TrackingState> emit) {
    _challengeId = e.challengeId;
    _challengeOpponentUserId = e.opponentUserId;
    _challengeOpponentName = e.opponentName;
    _challengeTargetM = e.targetDistanceM;
  }

  Future<void> _onStartTracking(StartTracking event, Emitter<TrackingState> emit) async {
    try {
      await _cancelSub();
      final f = await _ensureLocationReady(); if (f != null) { emit(_mapFailure(f)); return; }
      _points.clear(); _buffer = []; _filteredCache = []; _filteredUpTo = 0;
      _accumDistM = 0.0; _prevPt = null; _lastEmitMs = 0; _totalPts = 0;
      _intBuf.clear(); _intFlags.clear(); _vehicleDetector.reset(); _isVerified = true; _lastIntCheckMs = 0; _lastStepFetchMs = 0;
      // Challenge context is preserved — set before StartTracking via SetChallengeContext.
      _voiceKm.reset(); _voiceTime.reset(); _voiceGhost.reset(); _lastSpeakMs = 0;
      _gpsLost = false; _gpsLostAtMs = 0; _cancelGpsReconnectTimer();
      _cs = await _coachSettings.load();
      _voiceHrZone = _cs.hrZoneEnabled
          ? HrZoneVoiceTrigger(calculator: HrZoneCalculator(maxHr: _cs.maxHr))
          : null;
      _resetHrAccumulation();
      unawaited(_audioCoach.init());
      final now = DateTime.now().millisecondsSinceEpoch; _sessionId = generateUuidV4(); _startMs = now;
      AppLogger.info('Start session $_sessionId', tag: _tag);
      await _sessionRepo.save(WorkoutSessionEntity(id: _sessionId, status: WorkoutStatus.running, startTimeMs: now, route: const []),);
      try { await ForegroundTaskConfig.start(); } on Exception catch (e) {
        AppLogger.warn('Foreground service start failed (non-blocking): $e', tag: _tag);
      }
      emit(const TrackingActive(points: []));
      _sub = _locationStream.watch().listen((pt) => add(LocationPointReceived(pt)),
        onError: (Object e) => add(LocationStreamError(e.toString())),
        onDone: () { _sub = null; if (state is TrackingActive) add(const GpsStreamEnded()); },);
      _startHrListening();
    } on Exception catch (e, st) {
      AppLogger.error('Failed to start tracking', tag: _tag, error: e, stack: st);
      emit(const TrackingError(message: 'Não foi possível iniciar a corrida. Verifique GPS e permissões.'));
    }
  }

  Future<void> _onLocationPointReceived(LocationPointReceived event, Emitter<TrackingState> emit) async {
    if (state is! TrackingActive) return;
    if (_gpsLost) {
      AppLogger.info('GPS signal restored', tag: _tag);
      _gpsLost = false;
      _cancelGpsReconnectTimer();
    }
    final pt = event.point;
    _points.add(pt); _buffer.add(pt); _intBuf.add(pt); _vehicleDetector.addPoint(pt); _totalPts++;
    if (_buffer.length >= _bufSize) await _flushBuffer();
    _checkIntegrity(); _accumDist(pt);
    if (_points.length > _maxPts) _points.removeRange(0, _points.length - _maxPts);
    if (pt.timestampMs - _lastEmitMs < _emitMs) return;
    _lastEmitMs = pt.timestampMs;
    _emitActiveState(emit);
  }

  void _onHeartRateReceived(HeartRateReceived event, Emitter<TrackingState> emit) {
    if (state is! TrackingActive) return;
    final bpm = event.sample.bpm;
    _currentBpm = bpm;
    _hrSum += bpm;
    _hrCount++;
    if (bpm > _hrMax) _hrMax = bpm;
    _hrSamples.add(HealthHrSample(
      bpm: bpm,
      startMs: event.sample.timestampMs,
      endMs: event.sample.timestampMs,
    ));
    _evaluateHrZone(bpm, event.sample.timestampMs);
    _emitActiveState(emit);
  }
  void _evaluateHrZone(int bpm, int timestampMs) {
    if (_voiceHrZone == null) return;
    final hrEvent = _voiceHrZone!.evaluate(bpm: bpm, timestampMs: timestampMs);
    if (hrEvent != null) {
      unawaited(_audioCoach.speak(hrEvent));
    }
  }

  void _emitActiveState(Emitter<TrackingState> emit) {
    final m = _computeMetrics(); final g = _ghostData(m);
    final paused = _autoPause(_points).pauseSuggested;
    emit(TrackingActive(
      points: List.unmodifiable(_points), metrics: m, pauseSuggested: paused,
      ghostDeltaM: g.delta, ghostPosition: g.pos,
      isVerified: _isVerified, integrityFlags: _intFlags.toList(),
      currentBpm: _currentBpm, hrConnectionState: _hrConnState,
      gpsLost: _gpsLost,
      ghostDurationMs: _ghost?.durationMs,
      ghostTotalDistanceM: _ghost != null ? _ghostTotalDistM : null,
      challengeId: _challengeId,
      challengeOpponentUserId: _challengeOpponentUserId,
      challengeOpponentName: _challengeOpponentName,
      challengeTargetM: _challengeTargetM,
    ),);
    _evalTriggers(m, g.delta, paused);
  }

  Future<void> _onStopTracking(StopTracking event, Emitter<TrackingState> emit) async {
    try {
      await _flushBuffer();
    } on Exception catch (e, st) {
      AppLogger.error('Failed to flush buffer on stop', tag: _tag, error: e, stack: st);
    }
    await _cancelSub();
    _stopHrListening();
    _cancelGpsReconnectTimer();
    _gpsLost = false;
    try { await ForegroundTaskConfig.stop(); } on Exception catch (e) {
      AppLogger.warn('Foreground service stop failed (non-blocking): $e', tag: _tag);
    }
    if (_sessionId.isNotEmpty) {
      AppLogger.info('Stop session $_sessionId ($_totalPts pts, verified=$_isVerified)', tag: _tag);
      try {
        final result = await _finishSession(sessionId: _sessionId, ghostSessionId: _ghost?.sessionId, isVerified: _isVerified, integrityFlags: _intFlags.toList(),);
        if (_hrCount > 0) {
          final avgBpm = (_hrSum / _hrCount).round();
          await _sessionRepo.updateHrMetrics(_sessionId, avgBpm: avgBpm, maxBpm: _hrMax);
          AppLogger.info('HR persisted: avg=$avgBpm max=$_hrMax ($_hrCount samples)', tag: _tag);
        }
        // Export workout to HealthKit / Health Connect (fire-and-forget).
        final endMs = DateTime.now().millisecondsSinceEpoch;
        _exportToHealth(endTimeMs: endMs);

        // Progression + Gamification pipeline (fire-and-forget, idempotent).
        _dispatchPostSessionPipeline(
          result: result,
          endTimeMs: endMs,
        );
      } on Exception catch (e, st) {
        AppLogger.error('Failed to finish session', tag: _tag, error: e, stack: st);
      }
      unawaited(_syncRepo.syncPending().catchError((Object e) {
        AppLogger.error('Background sync failed', tag: _tag, error: e);
        return null;
      }),);
    }
    emit(const TrackingIdle());
  }

  // ---------------------------------------------------------------------------
  // GPS Reconnection
  // ---------------------------------------------------------------------------

  Future<void> _onGpsStreamEnded(GpsStreamEnded _, Emitter<TrackingState> emit) async {
    if (state is! TrackingActive) return;
    _gpsLost = true;
    _gpsLostAtMs = DateTime.now().millisecondsSinceEpoch;
    AppLogger.warn('GPS stream ended — attempting reconnection (timeout ${_gpsReconnectTimeoutMs ~/ 1000}s)', tag: _tag);
    await _flushBuffer();

    _emitActiveState(emit);
    _scheduleGpsReconnect();
  }

  void _scheduleGpsReconnect() {
    _cancelGpsReconnectTimer();
    _gpsReconnectTimer = Timer.periodic(
      Duration(milliseconds: _gpsReconnectIntervalMs),
      (_) => _attemptGpsReconnect(),
    );
  }

  Future<void> _attemptGpsReconnect() async {
    if (isClosed || state is! TrackingActive || !_gpsLost) {
      _cancelGpsReconnectTimer();
      return;
    }

    final elapsed = DateTime.now().millisecondsSinceEpoch - _gpsLostAtMs;
    if (elapsed >= _gpsReconnectTimeoutMs) {
      AppLogger.warn('GPS reconnection timeout — stopping session', tag: _tag);
      _cancelGpsReconnectTimer();
      add(const StopTracking());
      return;
    }

    try {
      final f = await _ensureLocationReady();
      if (f != null) return;

      AppLogger.info('GPS available again — resubscribing', tag: _tag);
      _sub = _locationStream.watch().listen(
        (pt) => add(LocationPointReceived(pt)),
        onError: (Object e) => add(LocationStreamError(e.toString())),
        onDone: () { _sub = null; if (state is TrackingActive) add(const GpsStreamEnded()); },
      );
      _cancelGpsReconnectTimer();
    } on Exception catch (e) {
      AppLogger.debug('GPS reconnect attempt failed: $e', tag: _tag);
    }
  }

  void _cancelGpsReconnectTimer() {
    _gpsReconnectTimer?.cancel();
    _gpsReconnectTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Post-Session Progression + Gamification Pipeline
  // ---------------------------------------------------------------------------

  void _dispatchPostSessionPipeline({
    required FinishSessionResult result,
    required int endTimeMs,
  }) {
    if (!result.success) return;

    final metrics = result.metrics;
    final totalDistanceM = metrics?.totalDistanceM ?? _accumDistM;
    final movingMs = metrics?.movingMs ?? 0;
    final avgPace = metrics?.avgPaceSecPerKm;
    final sessionId = _sessionId;
    final startMs = _startMs;

    // Sequential pipeline — single session load, no wallet race conditions.
    unawaited(_runPostSessionPipeline(
      sessionId: sessionId,
      totalDistanceM: totalDistanceM,
      movingMs: movingMs,
      avgPace: avgPace,
      startMs: startMs,
      endTimeMs: endTimeMs,
    ));
  }

  Future<void> _runPostSessionPipeline({
    required String sessionId,
    required double totalDistanceM,
    required int movingMs,
    required double? avgPace,
    required int startMs,
    required int endTimeMs,
  }) async {
    final session = await _sessionRepo.getById(sessionId);
    if (session == null) return;

    int pxCounter = 0;
    String pxUuid() => 'px_${endTimeMs}_${pxCounter++}';
    int rcCounter = 0;
    String rcUuid() => 'rc_${endTimeMs}_${rcCounter++}';

    // 1. Progression: XP → Badges → Missions → ClaimRewards (sequential).
    try {
      await _progression?.call(
        session: session,
        totalDistanceM: totalDistanceM,
        movingMs: movingMs,
        avgPaceSecPerKm: avgPace,
        isNewPacePr: false,
        sessionStartHourLocal:
            DateTime.fromMillisecondsSinceEpoch(startMs).hour,
        uuidGenerator: pxUuid,
        nowMs: endTimeMs,
      );
    } on Exception catch (e, st) {
      AppLogger.error('Progression pipeline failed', tag: _tag, error: e, stack: st);
    }

    // 2. Gamification: Challenge dispatch.
    try {
      await _challengeDispatcher?.call(
        session: session,
        totalDistanceM: totalDistanceM,
        avgPaceSecPerKm: avgPace,
        movingMs: movingMs,
        nowMs: endTimeMs,
      );
    } on Exception catch (e, st) {
      AppLogger.error('Challenge dispatch failed', tag: _tag, error: e, stack: st);
    }

    // 3. Gamification: Session coin reward.
    try {
      await _rewardCoins?.call(
        session: session,
        uuidGenerator: rcUuid,
        nowMs: endTimeMs,
      );
    } on Exception catch (e, st) {
      AppLogger.error('Coin reward failed', tag: _tag, error: e, stack: st);
    }
  }

  // ---------------------------------------------------------------------------
  // Health Export
  // ---------------------------------------------------------------------------

  void _exportToHealth({required int endTimeMs}) {
    final export = _exportWorkout;
    if (export == null) return;

    final avgBpm = _hrCount > 0 ? (_hrSum / _hrCount).round() : null;
    final maxBpm = _hrCount > 0 ? _hrMax : null;

    unawaited(
      export.call(
        sessionId: _sessionId,
        startMs: _startMs,
        endMs: endTimeMs,
        totalDistanceM: _accumDistM,
        avgBpm: avgBpm,
        maxBpm: maxBpm,
        hrSamples: List.unmodifiable(_hrSamples),
      ).catchError((Object e) {
        AppLogger.warn('Health export failed: $e', tag: _tag);
        return const WorkoutExportResult(workoutSaved: false, message: 'catchError');
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Heart Rate
  // ---------------------------------------------------------------------------

  void _resetHrAccumulation() {
    _currentBpm = null;
    _hrSum = 0;
    _hrCount = 0;
    _hrMax = 0;
    _hrConnState = null;
    _hrSamples.clear();
    _voiceHrZone?.reset();
  }

  void _startHrListening() {
    final source = _hrSource;
    if (source == null) return;

    if (!source.isConnected) {
      _tryAutoConnect(source);
      return;
    }

    _subscribeToHr(source);
  }

  void _tryAutoConnect(IHeartRateSource source) {
    source.lastKnownDeviceId.then((deviceId) {
      if (deviceId == null || isClosed) return;
      AppLogger.info('Auto-connecting to last known HR device: $deviceId', tag: _tag);
      _subscribeToHr(source, deviceId: deviceId);
    }).catchError((Object e) {
      AppLogger.warn('Failed to auto-connect HR: $e', tag: _tag);
    });
  }

  void _subscribeToHr(IHeartRateSource source, {String? deviceId}) {
    _hrSub?.cancel();

    if (deviceId != null) {
      _hrSub = source.connectAndListen(deviceId).listen(
        (sample) => add(HeartRateReceived(sample)),
        onError: (Object e) {
          AppLogger.warn('HR stream error: $e', tag: _tag);
        },
      );
    } else {
      AppLogger.info('No HR device ID to connect to', tag: _tag);
    }

    _hrConnSub?.cancel();
    _hrConnSub = source.connectionStateStream.listen((connState) {
      _hrConnState = switch (connState) {
        BleHrConnectionState.connected => 'connected',
        BleHrConnectionState.connecting => 'connecting',
        BleHrConnectionState.reconnecting => 'reconnecting',
        BleHrConnectionState.scanning => 'scanning',
        BleHrConnectionState.disconnected => 'disconnected',
      };
    });
  }

  void _stopHrListening() {
    _hrSub?.cancel();
    _hrSub = null;
    _hrConnSub?.cancel();
    _hrConnSub = null;
  }

  // ---------------------------------------------------------------------------
  // Existing helpers
  // ---------------------------------------------------------------------------

  Future<void> _onAppLifecycleChanged(AppLifecycleChanged event, Emitter<TrackingState> emit) async {
    if (!event.isResumed || state is TrackingActive) return;
    final f = await _ensureLocationReady(); if (f != null) { emit(_mapFailure(f)); } else if (state is TrackingNeedsPermission) { emit(const TrackingIdle()); }
  }
  Future<void> _flushBuffer() async {
    if (_buffer.isNotEmpty && _sessionId.isNotEmpty) {
      try {
        await _pointsRepo.savePoints(_sessionId, List.of(_buffer));
      } on Exception catch (e, st) {
        AppLogger.error('Failed to flush ${_buffer.length} points', tag: _tag, error: e, stack: st);
        return;
      }
    }
    _buffer = [];
  }
  void _checkIntegrity() {
    if (_intBuf.length < 2) return;
    final now = _intBuf.last.timestampMs; if (now - _lastIntCheckMs < 5000) return;
    _lastIntCheckMs = now; _intBuf.removeWhere((p) => p.timestampMs < now - 30000);
    if (_detectSpeed(_intBuf).isNotEmpty) { _intFlags.add(IntegrityDetectSpeed.flag); _isVerified = false; AppLogger.warn('Integrity: HIGH_SPEED', tag: _tag); }
    if (_detectTeleport(_intBuf).isNotEmpty) { _intFlags.add(IntegrityDetectTeleport.flag); _isVerified = false; AppLogger.warn('Integrity: TELEPORT', tag: _tag); }
    _checkVehicle(now);
  }
  void _checkVehicle(int nowMs) {
    if (_stepsSource == null) return;
    if (nowMs - _lastStepFetchMs >= _stepFetchIntervalMs) {
      _lastStepFetchMs = nowMs;
      unawaited(_fetchAndFeedSteps());
    }
    final violations = _vehicleDetector.check();
    if (violations.isNotEmpty) {
      _intFlags.add(IntegrityDetectVehicle.flag);
      _isVerified = false;
      AppLogger.warn('Integrity: VEHICLE_SUSPECT (${violations.length} windows)', tag: _tag);
    }
  }
  Future<void> _fetchAndFeedSteps() async {
    try {
      final samples = await _stepsSource!.samplesForSession(_sessionId);
      for (final s in samples) {
        _vehicleDetector.addStepSample(s);
      }
    } on Exception catch (e) {
      AppLogger.warn('Step fetch for vehicle check failed: $e', tag: _tag);
    }
  }
  void _accumDist(LocationPointEntity pt) {
    if (_prevPt == null) { _prevPt = pt; return; }
    final f = _filterPoints([_prevPt!, pt]);
    if (f.length < 2) return;
    _accumDistM += _accumulateDistance(f); _prevPt = pt;
  }
  void _evalTriggers(WorkoutMetricsEntity m, double? gd, bool paused) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in [if (_cs.ghostEnabled) _voiceGhost.evaluate(gd), if (_cs.kmEnabled) _voiceKm.evaluate(m), if (_cs.periodicEnabled) _voiceTime.evaluate(m, isPaused: paused)]) {
      if (e != null && (e.priority <= 5 || now - _lastSpeakMs >= _cooldownMs)) { _lastSpeakMs = now; unawaited(_audioCoach.speak(e)); }
    }
  }
  ({LocationPointEntity? pos, double? delta}) _ghostData(WorkoutMetricsEntity m) {
    if (_ghost == null || _points.isEmpty) return (pos: null, delta: null);
    final gPos = _ghostPosAt(_ghost!, m.elapsedMs);
    final frac = _ghost!.durationMs > 0 ? (m.elapsedMs / _ghost!.durationMs).clamp(0.0, 1.0) : 0.0;
    return (pos: gPos, delta: _calcGhostDelta(runnerPos: _points.last, ghostPos: gPos,
      runnerDistanceM: m.totalDistanceM, ghostDistanceM: _ghostTotalDistM * frac,)?.deltaM);
  }
  /// Incrementally-cached filter: only processes new points since last call.
  /// Falls back to full rebuild when _points is trimmed (every ~300 ticks).
  List<LocationPointEntity> _getFilteredPoints() {
    if (_filteredUpTo > _points.length) {
      _filteredCache = _filterPoints(_points);
      _filteredUpTo = _points.length;
      return _filteredCache;
    }
    if (_filteredUpTo == _points.length) return _filteredCache;

    final newRaw = _points.sublist(_filteredUpTo);
    if (_filteredCache.isNotEmpty) {
      final anchored = [_filteredCache.last, ...newRaw];
      final result = _filterPoints(anchored);
      if (result.isNotEmpty && result.first == _filteredCache.last) {
        _filteredCache.addAll(result.skip(1));
      } else {
        _filteredCache.addAll(result);
      }
    } else {
      _filteredCache = _filterPoints(newRaw);
    }
    _filteredUpTo = _points.length;
    return _filteredCache;
  }

  WorkoutMetricsEntity _computeMetrics() {
    final f = _getFilteredPoints();
    final el = _points.isNotEmpty ? _points.last.timestampMs - _startMs : 0;
    final movMs = calculateMovingMs(f);
    return WorkoutMetricsEntity(
      totalDistanceM: _accumDistM, elapsedMs: el, movingMs: movMs,
      currentPaceSecPerKm: _calculatePace(f),
      avgPaceSecPerKm: _accumDistM > 0 && movMs > 0 ? (movMs / 1000.0) / (_accumDistM / 1000.0) : null,
      pointsCount: _totalPts,
      currentBpm: _currentBpm,
      avgBpm: _hrCount > 0 ? (_hrSum / _hrCount).round() : null,
      maxBpm: _hrCount > 0 ? _hrMax : null,
    );
  }
  Future<void> _cancelSub() async { await _sub?.cancel(); _sub = null; }
  TrackingState _mapFailure(LocationFailure f) => switch (f) {
    LocationPermissionDenied() => const TrackingNeedsPermission(message: 'Permissão de localização necessária para rastrear sua corrida.',),
    LocationPermissionPermanentlyDenied() => const TrackingNeedsPermission(message: 'Permissão negada permanentemente. Ative nas configurações do dispositivo.', canRetry: false,),
    LocationServiceDisabled() => const TrackingNeedsPermission(message: 'GPS desativado. Ative os serviços de localização.',),
    LocationUnavailable() => const TrackingError(message: 'Não foi possível obter localização. Verifique o sinal GPS.',),
  };
  @override
  Future<void> close() async {
    _cancelGpsReconnectTimer();
    await _flushBuffer();
    await _cancelSub();
    _stopHrListening();
    try { await ForegroundTaskConfig.stop(); } on Exception catch (_) {}
    return super.close();
  }
}
