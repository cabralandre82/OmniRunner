import 'package:flutter/material.dart';

import 'package:omni_runner/core/utils/format_pace.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/presentation/screens/run_replay_screen.dart';

/// Bottom panel showing final metrics on the RunSummaryScreen.
class SummaryMetricsPanel extends StatelessWidget {
  final double totalDistanceM;
  final int elapsedMs;
  final double? avgPaceSecPerKm;
  final int pointsCount;

  /// Average heart rate in BPM. Null if no HR data was collected.
  final int? avgBpm;

  /// Maximum heart rate in BPM. Null if no HR data was collected.
  final int? maxBpm;

  /// Optional widget rendered between GPS-points label and Done button.
  final Widget? extraSection;

  /// GPS points for replay. When provided, a "Replay" button appears.
  final List<LocationPointEntity>? replayPoints;

  const SummaryMetricsPanel({
    super.key,
    required this.totalDistanceM,
    required this.elapsedMs,
    this.avgPaceSecPerKm,
    required this.pointsCount,
    this.avgBpm,
    this.maxBpm,
    this.extraSection,
    this.replayPoints,
  });

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    final hasHr = avgBpm != null;
    return Container(
      padding: EdgeInsets.only(bottom: pad + 16, top: 16, left: 16, right: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _col(_fmtDist(totalDistanceM), 'Distância'),
          _col(_fmtTime(elapsedMs), 'Duração'),
          _col(formatPace(avgPaceSecPerKm), 'Pace médio'),
        ],),
        if (hasHr) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _hrCol('${avgBpm!}', 'FC média'),
            _hrCol('${maxBpm ?? '--'}', 'FC máx'),
          ],),
        ],
        const SizedBox(height: 8),
        Text(
          '$pointsCount pontos GPS registrados',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (extraSection != null) extraSection!,
        const SizedBox(height: 12),
        if (replayPoints != null && replayPoints!.length >= 10) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Replay da corrida'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RunReplayScreen(
                    points: replayPoints!,
                    totalDistanceM: totalDistanceM,
                    elapsedMs: elapsedMs,
                  ),
                ));
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Fechar'),
          ),
        ),
      ],),
    );
  }

  Widget _hrCol(String value, String label) => Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.favorite, size: 14, color: Colors.red.shade400),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],);

  Widget _col(String value, String label) => Column(children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],);

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
