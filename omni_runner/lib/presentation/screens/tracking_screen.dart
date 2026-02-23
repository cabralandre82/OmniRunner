import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/usecases/load_ghost_from_session.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_bloc.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_event.dart';
import 'package:omni_runner/presentation/blocs/tracking/tracking_state.dart';
import 'package:omni_runner/presentation/map/auto_bearing.dart';
import 'package:omni_runner/presentation/map/camera_controller.dart';
import 'package:omni_runner/presentation/map/ghost_marker.dart';
import 'package:omni_runner/presentation/map/map_style.dart';
import 'package:omni_runner/presentation/screens/history_screen.dart';
import 'package:omni_runner/presentation/map/polyline_builder.dart';
import 'package:omni_runner/presentation/widgets/challenge_ghost_overlay.dart';
import 'package:omni_runner/presentation/widgets/challenge_ghost_provider.dart';
import 'package:omni_runner/presentation/widgets/ghost_picker_sheet.dart';
import 'package:omni_runner/presentation/screens/run_summary_screen.dart';
import 'package:omni_runner/presentation/widgets/tracking_bottom_panel.dart';

const _srcId = 'tracking-route-src';
const _layerId = 'tracking-route-layer';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider<TrackingBloc>(
      create: (_) => sl<TrackingBloc>()..add(const AppStarted()),
      child: const _TrackingView(),
    );
  }
}

class _TrackingView extends StatefulWidget {
  const _TrackingView();
  @override
  State<_TrackingView> createState() => _TrackingViewState();
}

class _TrackingViewState extends State<_TrackingView>
    with WidgetsBindingObserver {
  MapLibreMapController? _mapCtrl;
  bool _mapReady = false;
  bool _mapTimedOut = false;
  bool _sourceAdded = false;
  String? _ghostLabel; GhostMarker? _ghostMarker; TrackingActive? _lastActive;
  Timer? _mapTimeout;
  ChallengeGhostProvider? _challengeGhostProvider;

  final _cameraFollow = CameraFollowController();
  double _bearing = 0.0;
  bool _firstFix = true;

  /// User's last known position, or Brasília as fallback.
  LatLng _initialCenter = const LatLng(-15.7975, -47.8919);

  static const _mapLoadTimeout = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapTimeout = Timer(_mapLoadTimeout, _onMapLoadTimeout);
    _resolveInitialPosition();
  }

  Future<void> _resolveInitialPosition() async {
    try {
      final pos = await geo.Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() => _initialCenter = LatLng(pos.latitude, pos.longitude));
        _mapCtrl?.animateCamera(CameraUpdate.newLatLng(_initialCenter));
      }
    } catch (_) {
      // Permission not yet granted or unavailable — keep fallback.
    }
  }

  @override
  void dispose() {
    _mapTimeout?.cancel();
    _challengeGhostProvider?.dispose();
    _cameraFollow.detach();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onMapLoadTimeout() {
    if (!mounted || _mapReady) return;
    setState(() {
      _mapReady = true;
      _mapTimedOut = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<TrackingBloc>().add(AppLifecycleChanged(isResumed: state == AppLifecycleState.resumed));
  }

  Future<void> _onStyleLoaded() async {
    if (!mounted || _mapCtrl == null) return;
    _mapTimeout?.cancel();
    setState(() { _mapReady = true; _mapTimedOut = false; });
    _cameraFollow.attach(_mapCtrl!);
    await _initRouteLayer();
    await (_ghostMarker = GhostMarker(_mapCtrl!)).init();
  }

  Future<void> _initRouteLayer() async {
    if (_sourceAdded) return;
    await _mapCtrl!.addGeoJsonSource(_srcId, _emptyGeo());
    await _mapCtrl!.addLineLayer(_srcId, _layerId, const LineLayerProperties(lineColor: '#2196F3', lineWidth: 4.0, lineJoin: 'round', lineCap: 'round'),);
    _sourceAdded = true;
  }

  Future<void> _updatePolyline(TrackingActive state) async {
    if (_mapCtrl == null || !_sourceAdded) return;
    final coords = PolylineBuilder.fromPoints(state.points, simplifyThresholdMeters: 5.0);
    await _mapCtrl!.setGeoJsonSource(_srcId, _lineGeo(coords));
  }

  void _updateCamera(TrackingActive state) {
    if (state.points.isEmpty) return;
    final pt = state.points.last;
    final target = LatLng(pt.lat, pt.lng);

    // Compute bearing: prefer GPS field, fall back to two-point calc.
    if (state.points.length >= 2) {
      final prev = state.points[state.points.length - 2];
      _bearing = AutoBearing.fromPoint(
        pt,
        fallback: AutoBearing.fromTwoPoints(prev, pt, fallback: _bearing),
      );
    } else {
      _bearing = AutoBearing.fromPoint(pt, fallback: _bearing);
    }

    if (_firstFix) {
      _firstFix = false;
      _cameraFollow.enable();
      _cameraFollow.jumpTo(target, bearing: _bearing);
    } else {
      _cameraFollow.update(target, bearing: _bearing);
    }
  }

  void _recenter() {
    _cameraFollow.enable();
    if (!mounted) return;
    setState(() {});
    final state = context.read<TrackingBloc>().state;
    if (state is TrackingActive && state.points.isNotEmpty) {
      final pt = state.points.last;
      _cameraFollow.jumpTo(LatLng(pt.lat, pt.lng), bearing: _bearing);
    }
  }

  static Map<String, dynamic> _emptyGeo() => _lineGeo(const []);
  static Map<String, dynamic> _lineGeo(List<LatLng> c) => {'type': 'FeatureCollection', 'features': [
    {'type': 'Feature', 'properties': <String, dynamic>{}, 'geometry': {
      'type': 'LineString', 'coordinates': [for (final p in c) [p.longitude, p.latitude]],
    },},
  ],};

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickGhost() async {
    final sessions = await sl<ISessionRepo>().getByStatus(WorkoutStatus.completed);
    if (!mounted || sessions.isEmpty) { if (mounted) _snack('Nenhuma corrida anterior para usar como fantasma'); return; }
    final picked = await showModalBottomSheet<WorkoutSessionEntity>(
      context: context, builder: (_) => GhostPickerSheet(sessions: sessions),
    );
    if (picked == null || !mounted) return;
    final ghost = await sl<LoadGhostFromSession>()(picked.id);
    if (!mounted) return;
    if (ghost == null) { _snack('Corrida sem pontos GPS suficientes'); return; }
    context.read<TrackingBloc>().add(SetGhostSession(ghost));
    final d = DateTime.fromMillisecondsSinceEpoch(picked.startTimeMs);
    setState(() => _ghostLabel = '${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}');
  }

  void _clearGhost() { context.read<TrackingBloc>().add(const SetGhostSession(null)); setState(() => _ghostLabel = null); }

  void _ensureChallengeGhost(TrackingActive state) {
    if (!state.inChallengeMode) {
      if (_challengeGhostProvider != null) {
        _challengeGhostProvider!.dispose();
        _challengeGhostProvider = null;
        if (mounted) setState(() {});
      }
      return;
    }
    if (_challengeGhostProvider != null) return;
    _challengeGhostProvider = ChallengeGhostProvider(
      challengeId: state.challengeId!,
      opponentUserId: state.challengeOpponentUserId!,
    )..start();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<TrackingBloc, TrackingState>(
        listener: (context, state) {
          if (state is TrackingActive) {
            _updatePolyline(state);
            _ghostMarker?.update(state.ghostPosition);
            _updateCamera(state);
            _ensureChallengeGhost(state);
            _lastActive = state;
          }
          if (state is TrackingIdle) {
            _firstFix = true;
            _challengeGhostProvider?.dispose();
            _challengeGhostProvider = null;
            if (_sourceAdded) { _mapCtrl?.setGeoJsonSource(_srcId, _emptyGeo()); _ghostMarker?.update(null); }
            final la = _lastActive; _lastActive = null; if (la?.metrics != null) { Navigator.of(context).push(MaterialPageRoute(builder: (_) => RunSummaryScreen(
              points: la!.points, totalDistanceM: la.metrics!.totalDistanceM, elapsedMs: la.metrics!.elapsedMs, avgPaceSecPerKm: la.metrics!.avgPaceSecPerKm, ghostFinalDeltaM: la.ghostDeltaM, ghostDurationMs: la.ghostDurationMs, ghostDistanceM: la.ghostTotalDistanceM, isVerified: la.isVerified, integrityFlags: la.integrityFlags, avgBpm: la.metrics!.avgBpm, maxBpm: la.metrics!.maxBpm, challengeId: la.challengeId,),),); }
          }
        },
        child: Stack(fit: StackFit.expand, children: [
          Listener(
            onPointerDown: (_) {
              if (_cameraFollow.isFollowing) {
                _cameraFollow.disable();
                if (mounted) setState(() {});
              }
            },
            child: MapLibreMap(
              initialCameraPosition: CameraPosition(target: _initialCenter, zoom: 15),
              styleString: mapStyleUrl,
              onMapCreated: (ctrl) => _mapCtrl = ctrl,
              onStyleLoadedCallback: _onStyleLoaded,
              myLocationEnabled: false, trackCameraPosition: false,
              attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            ),
          ),
          if (!_mapReady)
            const Center(child: CircularProgressIndicator())
          else if (_mapTimedOut)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('Mapa indisponível offline',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('O rastreamento funciona normalmente — o mapa aparecerá quando conectado',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ]),
              ),
            ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: _TopBar(
              mapReady: _mapReady, ghostLabel: _ghostLabel,
              onPickGhost: _pickGhost, onClearGhost: _clearGhost,
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: BlocBuilder<TrackingBloc, TrackingState>(
              builder: (_, s) => TrackingBottomPanel(state: s),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 52,
            left: 0, right: 0,
            child: BlocSelector<TrackingBloc, TrackingState, bool>(
              selector: (s) => s is TrackingActive && s.inChallengeMode,
              builder: (_, show) {
                if (!show || _challengeGhostProvider == null) return const SizedBox.shrink();
                final s = context.read<TrackingBloc>().state;
                if (s is! TrackingActive) return const SizedBox.shrink();
                return ChallengeGhostOverlay(
                  ghostProvider: _challengeGhostProvider!,
                  targetDistanceM: s.challengeTargetM ?? 0,
                  opponentName: s.challengeOpponentName ?? 'Oponente',
                );
              },
            ),
          ),
          Positioned(
            bottom: 260, right: 16,
            child: BlocBuilder<TrackingBloc, TrackingState>(
              buildWhen: (_, s) => s is TrackingActive || s is TrackingIdle,
              builder: (_, s) {
                if (s is! TrackingActive || _cameraFollow.isFollowing) {
                  return const SizedBox.shrink();
                }
                return FloatingActionButton.small(
                  heroTag: 'recenter',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue.shade700,
                  onPressed: _recenter,
                  child: const Icon(Icons.my_location),
                );
              },
            ),
          ),
          Positioned(
            bottom: 220, left: 16, right: 16,
            child: BlocSelector<TrackingBloc, TrackingState, bool>(
              selector: (s) => s is TrackingActive && s.gpsLost,
              builder: (_, show) => !show ? const SizedBox.shrink() : Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade300)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red)),
                  SizedBox(width: 8),
                  Flexible(child: Text('Sinal GPS perdido — reconectando…', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500))),
                ],),
              ),
            ),
          ),
          Positioned(
            bottom: 180, left: 16, right: 16,
            child: BlocSelector<TrackingBloc, TrackingState, bool>(
              selector: (s) => s is TrackingActive && !s.isVerified,
              builder: (_, show) => !show ? const SizedBox.shrink() : Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.deepOrange), SizedBox(width: 6),
                  Flexible(child: Text('GPS instável — a validação pode ser afetada', style: TextStyle(fontSize: 11, color: Colors.deepOrange))),
                ],),
              ),
            ),
          ),
        ],),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool mapReady;
  final String? ghostLabel;
  final VoidCallback onPickGhost;
  final VoidCallback onClearGhost;
  const _TopBar({required this.mapReady, required this.ghostLabel, required this.onPickGhost, required this.onClearGhost});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: top, left: 8, right: 8, bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.black.withAlpha(0)],
        ),
      ),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.history, color: Colors.white), tooltip: 'Histórico', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen()))),
        const Spacer(),
        if (ghostLabel != null) GestureDetector(
          onTap: onClearGhost,
          child: Chip(
            avatar: const Icon(Icons.directions_run, size: 16),
            label: Text('Fantasma: $ghostLabel', style: const TextStyle(fontSize: 11)),
            deleteIcon: const Icon(Icons.close, size: 14),
            onDeleted: onClearGhost,
            backgroundColor: Colors.purple.shade100, visualDensity: VisualDensity.compact,
          ),
        ) else IconButton(
          icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
          tooltip: 'Escolher fantasma',
          onPressed: onPickGhost,
        ),
        const SizedBox(width: 4),
        BlocBuilder<TrackingBloc, TrackingState>(builder: (_, state) {
          final (l, c) = switch (state) { TrackingIdle() => ('Pronto', Colors.grey.shade300), TrackingNeedsPermission() => ('Sem GPS', Colors.orange.shade200), TrackingActive() => ('Rastreando', Colors.green.shade300), TrackingError() => ('Erro', Colors.red.shade300), };
          return Chip(label: Text(l, style: const TextStyle(fontSize: 12)), backgroundColor: c, visualDensity: VisualDensity.compact);
        },),
      ],),
    );
  }
}
