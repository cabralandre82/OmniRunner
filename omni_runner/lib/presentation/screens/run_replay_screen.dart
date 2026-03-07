import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:omni_runner/core/utils/format_pace.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/replay_analyzer.dart';
import 'package:omni_runner/presentation/map/map_style.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

const _routeSrcId = 'replay-route-src';
const _routeLayerId = 'replay-route-layer';
const _sprintSrcId = 'replay-sprint-src';
const _sprintLayerId = 'replay-sprint-layer';
const _headSrcId = 'replay-head-src';
const _headLayerId = 'replay-head-layer';

/// Lightweight replay screen: animated polyline, km splits, sprint highlight.
class RunReplayScreen extends StatefulWidget {
  final List<LocationPointEntity> points;
  final double totalDistanceM;
  final int elapsedMs;

  const RunReplayScreen({
    super.key,
    required this.points,
    required this.totalDistanceM,
    required this.elapsedMs,
  });

  @override
  State<RunReplayScreen> createState() => _RunReplayScreenState();
}

class _RunReplayScreenState extends State<RunReplayScreen>
    with SingleTickerProviderStateMixin {
  MapLibreMapController? _mapCtrl;
  bool _mapReady = false;
  bool _mapTimedOut = false;
  bool _layersAdded = false;
  Timer? _mapTimeout;

  late final ReplayData _replay;
  late final AnimationController _animCtrl;
  late final Animation<double> _animProgress;

  bool _isPlaying = false;
  int _revealedCount = 0;

  static const _animDurationSec = 12;

  @override
  void initState() {
    super.initState();
    _replay = const ReplayAnalyzer().call(widget.points);

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _animDurationSec),
    );
    _animProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
    _animCtrl.addListener(_onAnimTick);

    _mapTimeout = Timer(const Duration(seconds: 6), () {
      if (!mounted || _mapReady) return;
      setState(() { _mapReady = true; _mapTimedOut = true; });
    });
  }

  @override
  void dispose() {
    _mapTimeout?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _onStyleLoaded() async {
    if (!mounted || _mapCtrl == null) return;
    _mapTimeout?.cancel();
    setState(() { _mapReady = true; _mapTimedOut = false; });
    await _initLayers();
    _fitBounds();
  }

  Future<void> _initLayers() async {
    if (_layersAdded) return;
    final ctrl = _mapCtrl!;

    await ctrl.addGeoJsonSource(_routeSrcId, _emptyLine());
    await ctrl.addLineLayer(_routeSrcId, _routeLayerId,
        const LineLayerProperties(
          lineColor: '#2196F3',
          lineWidth: 4.0,
          lineJoin: 'round',
          lineCap: 'round',
        ));

    await ctrl.addGeoJsonSource(_sprintSrcId, _emptyLine());
    await ctrl.addLineLayer(_sprintSrcId, _sprintLayerId,
        const LineLayerProperties(
          lineColor: '#FF5722',
          lineWidth: 6.0,
          lineJoin: 'round',
          lineCap: 'round',
        ));

    await ctrl.addGeoJsonSource(_headSrcId, _emptyPoint());
    await ctrl.addCircleLayer(_headSrcId, _headLayerId,
        const CircleLayerProperties(
          circleRadius: 8,
          circleColor: '#2196F3',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ));

    _layersAdded = true;
  }

  void _fitBounds() {
    if (widget.points.length < 2 || _mapCtrl == null) return;
    var minLat = widget.points.first.lat, maxLat = minLat;
    var minLng = widget.points.first.lng, maxLng = minLng;
    for (final p in widget.points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      left: DesignTokens.spacingXxl, top: DesignTokens.spacingXxl, right: DesignTokens.spacingXxl, bottom: 300,
    ));
  }

  void _togglePlay() {
    if (_isPlaying) {
      _animCtrl.stop();
    } else {
      if (_animCtrl.isCompleted) _animCtrl.reset();
      _animCtrl.forward();
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  void _onAnimTick() {
    if (!_layersAdded || _mapCtrl == null) return;
    final t = _animProgress.value;
    final count = (t * widget.points.length).round().clamp(1, widget.points.length);

    if (count == _revealedCount) return;
    _revealedCount = count;

    final revealed = widget.points.sublist(0, count);
    final coords = revealed.map((p) => [p.lng, p.lat]).toList();

    _mapCtrl!.setGeoJsonSource(_routeSrcId, _lineGeo(coords));

    final last = revealed.last;
    _mapCtrl!.setGeoJsonSource(_headSrcId, _pointGeo(last.lat, last.lng));

    if (_animCtrl.isCompleted && _isPlaying) {
      setState(() => _isPlaying = false);
      _showSprintHighlight();
    }
  }

  void _showSprintHighlight() {
    final sprint = _replay.sprint;
    if (sprint == null || !_layersAdded || _mapCtrl == null) return;

    final sprintPts = widget.points
        .sublist(sprint.startPointIdx, sprint.endPointIdx + 1);
    final coords = sprintPts.map((p) => [p.lng, p.lat]).toList();
    _mapCtrl!.setGeoJsonSource(_sprintSrcId, _lineGeo(coords));
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.points.isNotEmpty
        ? LatLng(
            widget.points[widget.points.length ~/ 2].lat,
            widget.points[widget.points.length ~/ 2].lng,
          )
        : const LatLng(-23.5505, -46.6333);

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            styleString: mapStyleUrl,
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            onStyleLoadedCallback: _onStyleLoaded,
            myLocationEnabled: false,
            trackCameraPosition: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
          ),
          if (!_mapReady)
            const Center(child: CircularProgressIndicator())
          else if (_mapTimedOut)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.map_outlined, size: 48, color: DesignTokens.textMuted),
              const SizedBox(height: 8),
              Text('Mapa indisponível offline', style: TextStyle(color: DesignTokens.textSecondary, fontSize: 14)),
            ])),
          _TopBar(),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomPanel(
              replay: _replay,
              isPlaying: _isPlaying,
              onToggle: _togglePlay,
              totalDistanceM: widget.totalDistanceM,
              elapsedMs: widget.elapsedMs,
            ),
          ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _emptyLine() => {
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[],
      };

  static Map<String, dynamic> _emptyPoint() => {
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[],
      };

  static Map<String, dynamic> _lineGeo(List<List<double>> coords) => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'LineString',
              'coordinates': coords,
            },
          },
        ],
      };

  static Map<String, dynamic> _pointGeo(double lat, double lng) => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [lng, lat],
            },
          },
        ],
      };
}

// ═════════════════════════════════════════════════════════════════════════════
// Top bar
// ═════════════════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(top: top, left: DesignTokens.spacingSm, right: DesignTokens.spacingSm, bottom: DesignTokens.spacingSm),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.black.withAlpha(0)],
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 48),
            const Spacer(),
            const Text(
              'Replay da Corrida',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Bottom panel: play button + splits + sprint highlight
// ═════════════════════════════════════════════════════════════════════════════

class _BottomPanel extends StatelessWidget {
  final ReplayData replay;
  final bool isPlaying;
  final VoidCallback onToggle;
  final double totalDistanceM;
  final int elapsedMs;

  const _BottomPanel({
    required this.replay,
    required this.isPlaying,
    required this.onToggle,
    required this.totalDistanceM,
    required this.elapsedMs,
  });

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(bottom: pad + 12, top: 12, left: DesignTokens.spacingMd, right: DesignTokens.spacingMd),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              FilledButton.icon(
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 20),
                label: Text(isPlaying ? 'Pausar' : 'Reproduzir'),
                onPressed: onToggle,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtDist(totalDistanceM),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _fmtTime(elapsedMs),
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (replay.sprint != null) ...[
            const SizedBox(height: 10),
            _SprintCard(sprint: replay.sprint!),
          ],
          if (replay.splits.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SplitsTable(
              splits: replay.splits,
              bestIdx: replay.bestSplitIdx,
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtDist(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.toStringAsFixed(0)} m';
  }

  static String _fmtTime(int ms) {
    final t = ms ~/ 1000;
    final h = t ~/ 3600;
    final min = (t % 3600) ~/ 60;
    final sec = t % 60;
    if (h > 0) return '${h}h ${min.toString().padLeft(2, '0')}m';
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Sprint highlight card
// ═════════════════════════════════════════════════════════════════════════════

class _SprintCard extends StatelessWidget {
  final SprintHighlight sprint;
  const _SprintCard({required this.sprint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DesignTokens.warning,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: DesignTokens.warning),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt, color: DesignTokens.warning, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sprint final',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: DesignTokens.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmtDist(sprint.distanceM)} a '
                  '${formatPace(sprint.paceSecPerKm)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
            decoration: BoxDecoration(
              color: DesignTokens.warning,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Text(
              formatPace(sprint.paceSecPerKm),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: DesignTokens.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDist(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.toStringAsFixed(0)} m';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Splits table
// ═════════════════════════════════════════════════════════════════════════════

class _SplitsTable extends StatelessWidget {
  final List<KmSplit> splits;
  final int bestIdx;

  const _SplitsTable({required this.splits, required this.bestIdx});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Pace por km',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...List.generate(splits.length, (i) {
              final s = splits[i];
              final isBest = i == bestIdx;
              return _SplitRow(split: s, isBest: isBest);
            }),
          ],
        ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  final KmSplit split;
  final bool isBest;

  const _SplitRow({required this.split, required this.isBest});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 5),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isBest ? DesignTokens.success.withAlpha(20) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              'km ${split.kmIndex}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isBest ? DesignTokens.success : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: _PaceBar(
              pace: split.paceSecPerKm,
              isBest: isBest,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 65,
            child: Text(
              formatPace(split.paceSecPerKm),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBest ? FontWeight.bold : FontWeight.w500,
                color: isBest ? DesignTokens.success : Colors.black87,
              ),
            ),
          ),
          if (isBest) ...[
            const SizedBox(width: 4),
            Icon(Icons.star, size: 14, color: DesignTokens.success),
          ],
        ],
      ),
    );
  }
}

class _PaceBar extends StatelessWidget {
  final double pace;
  final bool isBest;

  const _PaceBar({required this.pace, required this.isBest});

  @override
  Widget build(BuildContext context) {
    // Normalize pace bar: faster (lower pace) = longer bar.
    // Assume 3:00/km is max speed, 10:00/km is min.
    final normalized = 1.0 - ((pace - 180) / (600 - 180)).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: math.max(normalized, 0.05),
        minHeight: 10,
        backgroundColor: DesignTokens.textMuted.withAlpha(30),
        valueColor: AlwaysStoppedAnimation(
          isBest ? DesignTokens.success : DesignTokens.primary,
        ),
      ),
    );
  }
}
