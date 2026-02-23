import 'package:flutter/material.dart';

import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';

/// Card displaying live workout metrics during debug tracking.
///
/// Shows distance, elapsed time, moving time, current pace, and avg pace.
/// If [metrics] is null, renders nothing.
///
/// Temporary debug widget. Will be replaced by real UI in Phase 04+.
class DebugMetricsCard extends StatelessWidget {
  /// The current workout metrics. Null means no data yet.
  final WorkoutMetricsEntity? metrics;

  const DebugMetricsCard({super.key, this.metrics});

  @override
  Widget build(BuildContext context) {
    if (metrics == null) return const SizedBox.shrink();

    final m = metrics!;
    return Card(
      color: Colors.blue.withAlpha(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live Metrics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _row('Distance', _fmtDistance(m.totalDistanceM)),
            _row('Elapsed', _fmtTime(m.elapsedMs)),
            _row('Moving', _fmtTime(m.movingMs)),
            _row('Pace (now)', _fmtPace(m.currentPaceSecPerKm)),
            _row('Pace (avg)', _fmtPace(m.avgPaceSecPerKm)),
            _row('Points', '${m.pointsCount}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }

  static String _fmtDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  static String _fmtTime(int ms) {
    final total = ms ~/ 1000;
    final min = total ~/ 60;
    final sec = total % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  static String _fmtPace(double? secPerKm) {
    if (secPerKm == null) return '--:--';
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).round();
    return "$min'${sec.toString().padLeft(2, '0')}\"/km";
  }
}
