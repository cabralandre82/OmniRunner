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
import 'package:omni_runner/presentation/widgets/run_share_card.dart';
import 'package:omni_runner/presentation/widgets/summary_metrics_panel.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

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
    final ctrl = _mapCtrl;
    if (!mounted || ctrl == null) return;
    _mapTimeout?.cancel();
    setState(() { _mapReady = true; _mapTimedOut = false; });
    await _addRouteLayer(ctrl);
    _fitBounds();
  }

  Future<void> _addRouteLayer(MapLibreMapController ctrl) async {
    await ctrl.addGeoJsonSource(_srcId, _buildGeoJson());
    await ctrl.addLineLayer(_srcId, _layerId, const LineLayerProperties(
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
      left: DesignTokens.spacingXxl, top: DesignTokens.spacingXxl, right: DesignTokens.spacingXxl, bottom: 200,
    ),);
  }

  Widget? _buildExtra() {
    final ghost = _buildGhostCard();
    final integrity = _buildIntegrityCard();
    final challengeId = widget.challengeId;
    final challengeBanner = challengeId != null
        ? ChallengeSessionBanner(challengeId: challengeId)
        : null;
    if (ghost == null && integrity == null && challengeBanner == null) {
      return const Padding(
        padding: EdgeInsets.only(top: DesignTokens.spacingSm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 14, color: DesignTokens.textMuted),
            SizedBox(width: 4),
            Text(
              'Verificação final pelo servidor ao sincronizar',
              style: TextStyle(fontSize: 11, color: DesignTokens.textMuted),
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
        const Padding(
          padding: EdgeInsets.only(top: DesignTokens.spacingSm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule, size: 14, color: DesignTokens.textMuted),
              SizedBox(width: 4),
              Text(
                'Verificação final pelo servidor ao sincronizar',
                style: TextStyle(
                  fontSize: 11,
                  color: DesignTokens.textMuted,
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
        context.pop();
      },
    );
  }

  void _shareRun() {
    final distKm = widget.totalDistanceM / 1000;
    final avgPace = widget.avgPaceSecPerKm;
    final paceStr = avgPace != null
        ? "${avgPace ~/ 60}'${(avgPace % 60).toInt().toString().padLeft(2, '0')}\""
        : '--';
    final durSec = widget.elapsedMs ~/ 1000;
    final h = durSec ~/ 3600;
    final m = (durSec % 3600) ~/ 60;
    final s = durSec % 60;
    final durStr = h > 0
        ? '${h}h${m.toString().padLeft(2, '0')}min'
        : '${m}min${s.toString().padLeft(2, '0')}s';
    final now = DateTime.fromMillisecondsSinceEpoch(
        widget.points.isNotEmpty ? widget.points.first.timestampMs : DateTime.now().millisecondsSinceEpoch);
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final userName = sl<SupabaseClient>().auth.currentUser
            ?.userMetadata?['display_name'] as String?;

    shareRunCard(
      context,
      distanceKm: distKm,
      pace: paceStr,
      duration: durStr,
      date: dateStr,
      avgBpm: widget.avgBpm,
      userName: userName,
    );
  }

  Map<String, dynamic> _buildGeoJson() => {'type': 'FeatureCollection', 'features': [
    {'type': 'Feature', 'properties': <String, dynamic>{}, 'geometry': {
      'type': 'LineString', 'coordinates': [for (final c in _coords) [c.longitude, c.latitude]],
    },},
  ],};

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tela de Resumo da Corrida',
      child: Scaffold(
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
          const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.map_outlined, size: 48, color: DesignTokens.textMuted),
            SizedBox(height: 8),
            Text('Mapa indisponível offline', style: TextStyle(color: DesignTokens.textSecondary, fontSize: 14)),
          ])),
        Positioned(top: 0, left: 0, right: 0, child: _TopBar(onShare: _shareRun)),
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
    ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback? onShare;
  const _TopBar({this.onShare});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: top, left: DesignTokens.spacingSm, right: DesignTokens.spacingSm, bottom: DesignTokens.spacingSm),
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.black54, Colors.black.withAlpha(0)],
      ),),
      child: Row(children: [
        if (onShare != null)
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            tooltip: 'Compartilhar corrida',
            onPressed: onShare,
          )
        else
          const SizedBox(width: 48),
        const Spacer(),
        const Text('Resumo da Corrida', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => context.pop()),
      ],),
    );
  }
}
