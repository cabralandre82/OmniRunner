import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/utils/calculate_moving_ms.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/presentation/map/map_style.dart';
import 'package:omni_runner/presentation/map/polyline_builder.dart';
import 'package:omni_runner/features/integrations_export/presentation/export_screen.dart';
import 'package:omni_runner/presentation/widgets/invalidated_run_card.dart';
import 'package:omni_runner/presentation/widgets/summary_metrics_panel.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

const _srcId = 'details-route-src';
const _layerId = 'details-route-layer';

/// Detail screen for a past workout session from history.
///
/// Loads GPS points asynchronously from [IPointsRepo], then displays
/// the full polyline on a map with session metrics.
class RunDetailsScreen extends StatefulWidget {
  final WorkoutSessionEntity session;
  const RunDetailsScreen({super.key, required this.session});

  @override
  State<RunDetailsScreen> createState() => _RunDetailsScreenState();
}

class _RunDetailsScreenState extends State<RunDetailsScreen> {
  MapLibreMapController? _mapCtrl;
  bool _mapReady = false;
  bool _mapTimedOut = false;
  bool _layerAdded = false;

  List<LocationPointEntity>? _points;
  List<LatLng> _coords = const []; int _movingMs = 0;
  bool _loading = true;
  Timer? _mapTimeout;

  static const _mapLoadTimeout = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _loadPoints();
    _mapTimeout = Timer(_mapLoadTimeout, () {
      if (!mounted || _mapReady) return;
      setState(() { _mapReady = true; _mapTimedOut = true; });
    });
  }

  @override
  void dispose() { _mapTimeout?.cancel(); super.dispose(); }

  Future<void> _loadPoints() async {
    final pointsRepo = sl<IPointsRepo>();
    var points = await pointsRepo.getBySessionId(widget.session.id);

    if (points.isEmpty && widget.session.isSynced) {
      points = await _downloadPointsFromStorage(pointsRepo);
    }

    if (!mounted) return;

    List<LatLng> coords;
    if (points.isNotEmpty) {
      coords = PolylineBuilder.fromPoints(points, simplifyThresholdMeters: 2.0);
    } else {
      coords = await _loadPolylineFallback();
    }

    final filt = const FilterLocationPoints()(points);
    setState(() {
      _points = points;
      _coords = coords;
      _movingMs = calculateMovingMs(filt); _loading = false;
    });
    if (_mapReady) await _drawRoute();
  }

  Future<List<LatLng>> _loadPolylineFallback() async {
    if (!AppConfig.isSupabaseReady) return const [];
    try {
      final uid = widget.session.userId ??
          Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return const [];
      final db = Supabase.instance.client;

      // 1) Try direct lookup via strava_activity_id on the session row
      try {
        final sessionRow = await db
            .from('sessions')
            .select('strava_activity_id')
            .eq('id', widget.session.id)
            .maybeSingle();
        final stravaId = sessionRow?['strava_activity_id'];
        if (stravaId != null) {
          final hist = await db
              .from('strava_activity_history')
              .select('summary_polyline')
              .eq('user_id', uid)
              .eq('strava_activity_id', stravaId)
              .maybeSingle();
          final poly = hist?['summary_polyline'] as String?;
          if (poly != null && poly.isNotEmpty) {
            return PolylineBuilder.decodeGooglePolyline(poly);
          }
        }
      } catch (_) {}

      // 2) Fallback: match by date window (±2 hours around session start)
      final startMs = widget.session.startTimeMs;
      final windowStart = DateTime.fromMillisecondsSinceEpoch(
          startMs - 7200000, isUtc: true);
      final windowEnd = DateTime.fromMillisecondsSinceEpoch(
          startMs + 7200000, isUtc: true);

      final rows = await db
          .from('strava_activity_history')
          .select('summary_polyline')
          .eq('user_id', uid)
          .gte('start_date', windowStart.toIso8601String())
          .lt('start_date', windowEnd.toIso8601String())
          .limit(1);

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return const [];

      final polyline = list.first['summary_polyline'] as String?;
      if (polyline == null || polyline.isEmpty) return const [];

      return PolylineBuilder.decodeGooglePolyline(polyline);
    } catch (e) {
      AppLogger.debug('Polyline fallback failed: $e', tag: 'RunDetails');
      return const [];
    }
  }

  Future<List<LocationPointEntity>> _downloadPointsFromStorage(
    IPointsRepo pointsRepo,
  ) async {
    if (!AppConfig.isSupabaseReady) return const [];
    final uid = widget.session.userId ??
        Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return const [];

    final storage = Supabase.instance.client.storage.from('session-points');
    final primaryPath = '$uid/${widget.session.id}.json';
    // Legacy path: strava-webhook used to prefix the bucket name in the path
    final legacyPath = 'session-points/$uid/${widget.session.id}.json';

    for (final path in [primaryPath, legacyPath]) {
      try {
        final bytes = await storage.download(path);
        final jsonStr = utf8.decode(bytes);
        final list = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();

        final points = list.map((m) => LocationPointEntity(
          lat: (m['lat'] as num).toDouble(),
          lng: (m['lng'] as num).toDouble(),
          alt: (m['alt'] as num?)?.toDouble(),
          accuracy: (m['accuracy'] as num?)?.toDouble(),
          speed: (m['speed'] as num? ?? m['spd'] as num?)?.toDouble(),
          bearing: (m['bearing'] as num?)?.toDouble(),
          timestampMs: (m['timestampMs'] as num? ?? m['ts'] as num?)?.toInt() ?? 0,
        )).toList();

        if (points.isNotEmpty) {
          await pointsRepo.savePoints(widget.session.id, points);
          AppLogger.info(
            'Downloaded ${points.length} points from Storage ($path)',
            tag: 'RunDetails',
          );
          return points;
        }
      } on Exception catch (_) {
        continue;
      }
    }

    AppLogger.warn('No points found in Storage for ${widget.session.id}',
        tag: 'RunDetails');
    return const [];
  }

  Future<void> _onStyleLoaded() async {
    if (!mounted || _mapCtrl == null) return;
    _mapTimeout?.cancel();
    setState(() { _mapReady = true; _mapTimedOut = false; });
    if (!_loading) await _drawRoute();
  }

  Future<void> _drawRoute() async {
    if (_layerAdded || _mapCtrl == null) return;
    await _mapCtrl!.addGeoJsonSource(_srcId, _buildGeoJson());
    await _mapCtrl!.addLineLayer(
      _srcId,
      _layerId,
      const LineLayerProperties(
        lineColor: '#2196F3',
        lineWidth: 5.0,
        lineJoin: 'round',
        lineCap: 'round',
      ),
    );
    _layerAdded = true;
    _fitBounds();
  }

  void _fitBounds() {
    if (_coords.length < 2) return;
    var sLat = _coords.first.latitude, nLat = sLat;
    var sLng = _coords.first.longitude, nLng = sLng;
    for (final c in _coords) {
      sLat = math.min(sLat, c.latitude);
      nLat = math.max(nLat, c.latitude);
      sLng = math.min(sLng, c.longitude);
      nLng = math.max(nLng, c.longitude);
    }
    _mapCtrl?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(sLat, sLng), northeast: LatLng(nLat, nLng)),
      left: DesignTokens.spacingXxl, top: DesignTokens.spacingXxl, right: DesignTokens.spacingXxl, bottom: 200,
    ),);
  }

  Map<String, dynamic> _buildGeoJson() => {'type': 'FeatureCollection', 'features': [
    {'type': 'Feature', 'properties': <String, dynamic>{}, 'geometry': {
      'type': 'LineString',
      'coordinates': [for (final c in _coords) [c.longitude, c.latitude],],
    },},
  ],};

  LatLng get _center => _coords.isNotEmpty
      ? _coords[_coords.length ~/ 2] : const LatLng(-15.7975, -47.8919);

  int get _elapsedMs {
    final e = widget.session.endTimeMs;
    return (e != null && e > widget.session.startTimeMs)
        ? e - widget.session.startTimeMs : 0;
  }

  double? get _avgPace {
    final d = widget.session.totalDistanceM;
    return (d != null && d > 0 && _movingMs > 0)
        ? (_movingMs / 1000.0) / (d / 1000.0) : null;
  }

  Widget _buildExtra() {
    final s = widget.session;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!s.isVerified || s.integrityFlags.isNotEmpty)
        InvalidatedRunCard(integrityFlags: s.integrityFlags),
      Padding(padding: const EdgeInsets.only(top: DesignTokens.spacingSm), child: Wrap(spacing: 6, runSpacing: 4, children: [
        Chip(label: Text(s.isSynced ? 'Sincronizada' : 'Pendente', style: const TextStyle(fontSize: 10)), backgroundColor: s.isSynced ? DesignTokens.success : DesignTokens.warning, visualDensity: VisualDensity.compact, side: BorderSide.none,),
        if (s.ghostSessionId != null) const Chip(avatar: Icon(Icons.directions_run, size: 14), label: Text('vs Fantasma', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, side: BorderSide.none,),
      ],),),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 14),
            styleString: mapStyleUrl,
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            onStyleLoadedCallback: _onStyleLoaded,
            myLocationEnabled: false,
            trackCameraPosition: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
          ),
          if (!_mapReady || _loading)
            const Center(child: CircularProgressIndicator())
          else if (_mapTimedOut)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.map_outlined, size: 48, color: DesignTokens.textMuted),
              const SizedBox(height: 8),
              Text('Mapa indisponível offline', style: TextStyle(color: DesignTokens.textSecondary, fontSize: 14)),
            ]))
          else if (_coords.isEmpty)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.route_outlined, size: 48, color: DesignTokens.textMuted),
              const SizedBox(height: 8),
              Text('Percurso não disponível', style: TextStyle(color: DesignTokens.textSecondary, fontSize: 14)),
            ])),
          Positioned(
            top: 0, left: 0, right: 0,
            child: _TopBar(session: widget.session),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SummaryMetricsPanel(
              totalDistanceM: widget.session.totalDistanceM ?? 0,
              elapsedMs: _elapsedMs,
              avgPaceSecPerKm: _avgPace,
              pointsCount: _points?.length ?? 0,
              extraSection: _buildExtra(),
              replayPoints: _points,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final WorkoutSessionEntity session;
  const _TopBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final date = DateTime.fromMillisecondsSinceEpoch(session.startTimeMs);
    final label = '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Container(
      padding: EdgeInsets.only(top: top, left: DesignTokens.spacingSm, right: DesignTokens.spacingSm, bottom: DesignTokens.spacingSm),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.black.withAlpha(0)],
        ),
      ),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Spacer(),
        Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold,
        ),),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.file_upload_outlined, color: Colors.white),
          tooltip: 'Exportar corrida',
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ExportScreen(session: session),
            ));
          },
        ),
      ],),
    );
  }
}
