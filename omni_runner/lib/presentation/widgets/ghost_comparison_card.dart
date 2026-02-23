import 'package:flutter/material.dart';

/// Card showing ghost runner comparison on the run summary screen.
///
/// Displays the final delta (ahead/behind), time comparison, and a
/// placeholder area for a future pace-over-distance chart.
class GhostComparisonCard extends StatelessWidget {
  /// Signed delta in meters. Positive = runner ahead, negative = behind.
  final double finalDeltaM;

  /// Runner's elapsed time in milliseconds.
  final int runnerElapsedMs;

  /// Ghost session's total duration in milliseconds.
  final int ghostDurationMs;

  /// Ghost session's total distance in meters.
  final double ghostDistanceM;

  const GhostComparisonCard({
    super.key,
    required this.finalDeltaM,
    required this.runnerElapsedMs,
    required this.ghostDurationMs,
    required this.ghostDistanceM,
  });

  @override
  Widget build(BuildContext context) {
    final ahead = finalDeltaM >= 0;
    final absDelta = finalDeltaM.abs();
    final deltaLabel = ahead
        ? '+${_fmtDist(absDelta)} à frente'
        : '-${_fmtDist(absDelta)} atrás';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.directions_run, color: Colors.purple, size: 18),
          const SizedBox(width: 6),
          const Text(
            'Comparação com Fantasma',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const Spacer(),
          Chip(
            label: Text(
              deltaLabel,
              style: TextStyle(
                fontSize: 12,
                color: ahead ? Colors.green.shade800 : Colors.red.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: ahead ? Colors.green.shade100 : Colors.red.shade100,
            visualDensity: VisualDensity.compact,
            side: BorderSide.none,
          ),
        ],),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _col('Você', _fmtTime(runnerElapsedMs)),
          const Text('vs', style: TextStyle(color: Colors.grey, fontSize: 12)),
          _col('Fantasma', _fmtTime(ghostDurationMs)),
        ],),
        const SizedBox(height: 10),
        // Placeholder chart area
        Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.purple.shade100.withAlpha(80),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            'Gráfico de pace em breve',
            style: TextStyle(fontSize: 12, color: Colors.purple.shade300),
          ),
        ),
      ],),
    );
  }

  Widget _col(String label, String value) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
