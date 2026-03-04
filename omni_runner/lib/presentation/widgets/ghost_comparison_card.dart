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
        _PaceComparisonBar(
          runnerElapsedMs: runnerElapsedMs,
          ghostDurationMs: ghostDurationMs,
          ghostDistanceM: ghostDistanceM,
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

class _PaceComparisonBar extends StatelessWidget {
  final int runnerElapsedMs;
  final int ghostDurationMs;
  final double ghostDistanceM;

  const _PaceComparisonBar({
    required this.runnerElapsedMs,
    required this.ghostDurationMs,
    required this.ghostDistanceM,
  });

  @override
  Widget build(BuildContext context) {
    if (ghostDistanceM <= 0 || runnerElapsedMs <= 0 || ghostDurationMs <= 0) {
      return Text(
        'Comparação de pace indisponível',
        style: TextStyle(fontSize: 12, color: Colors.purple.shade300),
      );
    }

    final runnerPace = (runnerElapsedMs / 1000) / (ghostDistanceM / 1000);
    final ghostPace = (ghostDurationMs / 1000) / (ghostDistanceM / 1000);
    final maxPace = runnerPace > ghostPace ? runnerPace : ghostPace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pace (min/km)',
            style: TextStyle(fontSize: 11, color: Colors.purple.shade400)),
        const SizedBox(height: 6),
        _bar('Você', runnerPace, maxPace, Colors.blue),
        const SizedBox(height: 4),
        _bar('Fantasma', ghostPace, maxPace, Colors.purple),
      ],
    );
  }

  Widget _bar(String label, double pace, double maxPace, Color color) {
    final fraction = (pace / maxPace).clamp(0.0, 1.0);
    final min = pace ~/ 60;
    final sec = (pace % 60).toInt();
    final paceStr = '$min:${sec.toString().padLeft(2, '0')}/km';

    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 11))),
        Expanded(
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: color.withAlpha(30),
            valueColor: AlwaysStoppedAnimation(color.withAlpha(180)),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 6),
        Text(paceStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
