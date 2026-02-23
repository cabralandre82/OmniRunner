import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Per-kilometer split data.
final class KmSplit {
  final int kmIndex;
  final double paceSecPerKm;
  final int startPointIdx;
  final int endPointIdx;
  final int elapsedMs;

  const KmSplit({
    required this.kmIndex,
    required this.paceSecPerKm,
    required this.startPointIdx,
    required this.endPointIdx,
    required this.elapsedMs,
  });
}

/// The fastest sustained segment in the run ("sprint final").
final class SprintHighlight {
  final int startPointIdx;
  final int endPointIdx;
  final double distanceM;
  final int durationMs;
  final double paceSecPerKm;

  const SprintHighlight({
    required this.startPointIdx,
    required this.endPointIdx,
    required this.distanceM,
    required this.durationMs,
    required this.paceSecPerKm,
  });
}

/// Complete replay analysis of a run.
final class ReplayData {
  final List<KmSplit> splits;
  final SprintHighlight? sprint;
  final int bestSplitIdx;
  final double totalDistanceM;
  final int totalElapsedMs;

  const ReplayData({
    required this.splits,
    this.sprint,
    required this.bestSplitIdx,
    required this.totalDistanceM,
    required this.totalElapsedMs,
  });
}

/// Analyzes a completed run to produce km splits and detect sprint moments.
///
/// Pure function, no side effects. Operates on raw GPS points.
final class ReplayAnalyzer {
  static const _minSprintDistM = 200.0;
  static const _slidingWindowPoints = 30;

  const ReplayAnalyzer();

  ReplayData call(List<LocationPointEntity> points) {
    if (points.length < 2) {
      return const ReplayData(
        splits: [],
        bestSplitIdx: -1,
        totalDistanceM: 0,
        totalElapsedMs: 0,
      );
    }

    final splits = _computeSplits(points);
    final sprint = _detectSprint(points);

    var bestIdx = -1;
    var bestPace = double.infinity;
    for (var i = 0; i < splits.length; i++) {
      if (splits[i].paceSecPerKm < bestPace) {
        bestPace = splits[i].paceSecPerKm;
        bestIdx = i;
      }
    }

    final totalMs =
        points.last.timestampMs - points.first.timestampMs;

    double totalDist = 0;
    for (var i = 1; i < points.length; i++) {
      totalDist += haversineMeters(
        lat1: points[i - 1].lat,
        lng1: points[i - 1].lng,
        lat2: points[i].lat,
        lng2: points[i].lng,
      );
    }

    return ReplayData(
      splits: splits,
      sprint: sprint,
      bestSplitIdx: bestIdx,
      totalDistanceM: totalDist,
      totalElapsedMs: totalMs,
    );
  }

  List<KmSplit> _computeSplits(List<LocationPointEntity> points) {
    final splits = <KmSplit>[];
    double accumM = 0;
    int splitStartIdx = 0;
    int kmCount = 0;

    for (var i = 1; i < points.length; i++) {
      final seg = haversineMeters(
        lat1: points[i - 1].lat,
        lng1: points[i - 1].lng,
        lat2: points[i].lat,
        lng2: points[i].lng,
      );
      accumM += seg;

      if (accumM >= 1000) {
        kmCount++;
        final elapsedMs =
            points[i].timestampMs - points[splitStartIdx].timestampMs;
        final pace =
            elapsedMs > 0 ? (elapsedMs / 1000.0) / (accumM / 1000.0) : 0.0;

        splits.add(KmSplit(
          kmIndex: kmCount,
          paceSecPerKm: pace,
          startPointIdx: splitStartIdx,
          endPointIdx: i,
          elapsedMs: elapsedMs,
        ));

        accumM = 0;
        splitStartIdx = i;
      }
    }

    // Partial last km (only if > 100m)
    if (accumM > 100 && splitStartIdx < points.length - 1) {
      kmCount++;
      final elapsedMs = points.last.timestampMs -
          points[splitStartIdx].timestampMs;
      final pace =
          elapsedMs > 0 ? (elapsedMs / 1000.0) / (accumM / 1000.0) : 0.0;

      splits.add(KmSplit(
        kmIndex: kmCount,
        paceSecPerKm: pace,
        startPointIdx: splitStartIdx,
        endPointIdx: points.length - 1,
        elapsedMs: elapsedMs,
      ));
    }

    return splits;
  }

  /// Sliding-window sprint detection.
  ///
  /// Scans through the final 40% of the run with a window of
  /// [_slidingWindowPoints] points. Finds the window with the
  /// lowest pace (fastest speed) over at least [_minSprintDistM].
  SprintHighlight? _detectSprint(List<LocationPointEntity> points) {
    if (points.length < _slidingWindowPoints + 5) return null;

    final scanStart = (points.length * 0.6).round();

    double bestPace = double.infinity;
    int bestStart = 0;
    int bestEnd = 0;
    double bestDist = 0;
    int bestDurMs = 0;

    for (var i = scanStart;
        i <= points.length - _slidingWindowPoints;
        i++) {
      final end = i + _slidingWindowPoints - 1;
      double dist = 0;
      for (var j = i; j < end; j++) {
        dist += haversineMeters(
          lat1: points[j].lat,
          lng1: points[j].lng,
          lat2: points[j + 1].lat,
          lng2: points[j + 1].lng,
        );
      }

      if (dist < _minSprintDistM) continue;

      final durMs = points[end].timestampMs - points[i].timestampMs;
      if (durMs <= 0) continue;

      final pace = (durMs / 1000.0) / (dist / 1000.0);
      if (pace < bestPace) {
        bestPace = pace;
        bestStart = i;
        bestEnd = end;
        bestDist = dist;
        bestDurMs = durMs;
      }
    }

    if (bestPace == double.infinity) return null;

    return SprintHighlight(
      startPointIdx: bestStart,
      endPointIdx: bestEnd,
      distanceM: bestDist,
      durationMs: bestDurMs,
      paceSecPerKm: bestPace,
    );
  }
}
