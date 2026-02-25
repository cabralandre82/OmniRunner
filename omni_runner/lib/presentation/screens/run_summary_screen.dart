import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/presentation/map/map_style.dart';
import 'package:omni_runner/presentation/map/polyline_builder.dart';
import 'package:omni_runner/presentation/widgets/ghost_comparison_card.dart';
import 'package:omni_runner/presentation/widgets/challenge_session_banner.dart';
import 'package:omni_runner/presentation/widgets/invalidated_run_card.dart';
import 'package:omni_runner/presentation/widgets/summary_metrics_panel.dart';

const _srcId = 'summary-route-src';
const _layerId = 'summary-route-layer';

/// Post-run summary screen with full polyline and final metrics.
class RunSummaryScreen extends StatefulWidget {
  final List<LocationPointEntity> points;
  final double totalDistanceM;
  final int elapsedMs;
  final double? avgPaceSecPerKm;
  final double? ghostFinalDeltaM;
  final int? ghostDurationMs;
  final double? ghostDistanceM;
  final bool isVerified;
  final List<String> integrityFlags;
  final int? avgBpm;
  final int? maxBpm;
  final String? challengeId;

  const RunSummaryScreen({
    super.key,
    required this.points,
    required this.totalDistanceM,
    required this.elapsedMs,
    this.avgPaceSecPerKm,
    this.ghostFinalDeltaM,
    this.ghostDurationMs,
    this.ghostDistanceM,
    this.isVerified = true,
    this.integrityFlags = const [],
    this.avgBpm,
    this.maxBpm,
    this.challengeId,
  });

  @override
  State<RunSummaryScreen> createState() => _RunSummaryScreenState();
}

class _RunSummaryScreenState extends State<RunSummaryScreen> {
  MapLibreMapController? _mapCtrl;
  bool _mapReady = false;
  bool _mapTimedOut = false;
  late final List<LatLng> _coords;
  late final LatLng _center;
  Timer? _mapTimeout;

  static const _mapLoadTimeout = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _coords = PolylineBuilder.fromPoints(widget.points, simplifyThresholdMeters: 2.0);
    _center = _coords.isNotEmpty ? _coords[_coords.length ~/ 2] : const LatLng(-23.5505, -46.6333);
    _mapTimeout = Timer(_mapLoadTimeout, () {
      if (!mounted || _mapReady) return;
      setState(() { _mapReady = true; _mapTimedOut = true; });
    });
  }

  @override
  void dispose() { _mapTimeout?.cancel(); super.dispose(); }

  Future<void> _onStyleLoaded() async {
    if (!mounted || _mapCtrl == null) return;
    _mapTimeout?.cancel();
    setState(() { _mapReady = true; _mapTimedOut = false; });
    await _addRouteLayer();
    _fitBounds();
  }

  Future<void> _addRouteLayer() async {
    await _mapCtrl!.addGeoJsonSource(_srcId, _buildGeoJson());
    await _mapCtrl!.addLineLayer(_srcId, _layerId, const LineLayerProperties(
      lineColor: '#2196F3', lineWidth: 5.0, lineJoin: 'round', lineCap: 'round',
    ),);
  }

  void _fitBounds() {
    if (_coords.length < 2) return;
    var minLat = _coords.first.latitude, maxLat = minLat;
    var minLng = _coords.first.longitude, maxLng = minLng;
    for (final c in _coords) {
      minLat = math.min(minLat, c.latitude); maxLat = math.max(maxLat, c.latitude);
      minLng = math.min(minLng, c.longitude); maxLng = math.max(maxLng, c.longitude);
    }
    _mapCtrl?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      left: 48, top: 48, right: 48, bottom: 200,
    ),);
  }

  Widget? _buildExtra() {
    final ghost = _buildGhostCard();
    final integrity = _buildIntegrityCard();
    final challengeBanner = widget.challengeId != null
        ? ChallengeSessionBanner(challengeId: widget.challengeId!)
        : null;
    if (ghost == null && integrity == null && challengeBanner == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              'Verificação final pelo servidor ao sincronizar',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (challengeBanner != null) challengeBanner,
      if (ghost != null) ghost,
      if (integrity != null) integrity,
      if (integrity == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                'Verificação final pelo servidor ao sincronizar',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget? _buildGhostCard() {
    final delta = widget.ghostFinalDeltaM;
    final dur = widget.ghostDurationMs;
    final dist = widget.ghostDistanceM;
    if (delta == null || dur == null || dist == null) return null;
    return GhostComparisonCard(
      finalDeltaM: delta, runnerElapsedMs: widget.elapsedMs,
      ghostDurationMs: dur, ghostDistanceM: dist,
    );
  }

  Widget? _buildIntegrityCard() {
    if (widget.isVerified && widget.integrityFlags.isEmpty) return null;
    return InvalidatedRunCard(
      integrityFlags: widget.integrityFlags,
      onRetry: () {
        Navigator.of(context).pop();
      },
    );
  }

  Map<String, dynamic> _buildGeoJson() => {'type': 'FeatureCollection', 'features': [
    {'type': 'Feature', 'properties': <String, dynamic>{}, 'geometry': {
      'type': 'LineString', 'coordinates': [for (final c in _coords) [c.longitude, c.latitude]],
    },},
  ],};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        MapLibreMap(
          initialCameraPosition: CameraPosition(target: _center, zoom: 14),
          styleString: mapStyleUrl,
          onMapCreated: (ctrl) => _mapCtrl = ctrl,
          onStyleLoadedCallback: _onStyleLoaded,
          myLocationEnabled: false, trackCameraPosition: false,
          attributionButtonPosition: AttributionButtonPosition.bottomLeft,
        ),
        if (!_mapReady)
          const Center(child: CircularProgressIndicator())
        else if (_mapTimedOut)
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Mapa indisponível offline', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          ])),
        Positioned(top: 0, left: 0, right: 0, child: _TopBar()),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: SummaryMetricsPanel(
            totalDistanceM: widget.totalDistanceM, elapsedMs: widget.elapsedMs,
            avgPaceSecPerKm: widget.avgPaceSecPerKm, pointsCount: widget.points.length,
            avgBpm: widget.avgBpm, maxBpm: widget.maxBpm,
            extraSection: _buildExtra(),
            replayPoints: widget.points,
          ),
        ),
      ],),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: top, left: 8, right: 8, bottom: 8),
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.black54, Colors.black.withAlpha(0)],
      ),),
      child: Row(children: [
        const SizedBox(width: 48), const Spacer(),
        const Text('Resumo da Corrida', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
      ],),
    );
  }
}
