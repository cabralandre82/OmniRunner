import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// Generates a Garmin Training Center XML (TCX) file from a workout session.
///
/// Includes:
/// - `<Activity>` with sport type "Running"
/// - Single `<Lap>` with total time, distance, calories, avg/max HR
/// - `<Track>` with all trackpoints (position, altitude, HR, distance)
///
/// Reference: http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2
final class TcxEncoder {
  const TcxEncoder();

  /// Encode a workout session + route + HR into TCX XML bytes.
  Uint8List encode({
    required WorkoutSessionEntity session,
    required List<LocationPointEntity> route,
    List<HeartRateSample> hrSamples = const [],
    String activityName = 'Omni Runner',
  }) {
    final buf = StringBuffer();
    final startIso = _isoTime(session.startTimeMs);
    final endMs = session.endTimeMs ?? session.startTimeMs;
    final totalTimeSec = (endMs - session.startTimeMs) / 1000.0;
    final distance = session.totalDistanceM ?? 0.0;

    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<TrainingCenterDatabase '
      'xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xsi:schemaLocation="http://www.garmin.com/xmlschemas/'
      'TrainingCenterDatabase/v2 '
      'http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">',
    );

    buf.writeln('  <Activities>');
    buf.writeln('    <Activity Sport="Running">');
    buf.writeln('      <Id>$startIso</Id>');
    buf.writeln('      <Notes>${_escapeXml(activityName)}</Notes>');

    // Single lap
    buf.writeln('      <Lap StartTime="$startIso">');
    buf.writeln(
      '        <TotalTimeSeconds>'
      '${totalTimeSec.toStringAsFixed(1)}'
      '</TotalTimeSeconds>',
    );
    buf.writeln(
      '        <DistanceMeters>${distance.toStringAsFixed(1)}</DistanceMeters>',
    );
    buf.writeln('        <Calories>0</Calories>');
    buf.writeln('        <Intensity>Active</Intensity>');
    buf.writeln('        <TriggerMethod>Manual</TriggerMethod>');

    if (session.avgBpm != null && session.avgBpm! > 0) {
      buf.writeln('        <AverageHeartRateBpm>');
      buf.writeln('          <Value>${session.avgBpm}</Value>');
      buf.writeln('        </AverageHeartRateBpm>');
    }
    if (session.maxBpm != null && session.maxBpm! > 0) {
      buf.writeln('        <MaximumHeartRateBpm>');
      buf.writeln('          <Value>${session.maxBpm}</Value>');
      buf.writeln('        </MaximumHeartRateBpm>');
    }

    // Track
    buf.writeln('        <Track>');

    var accDistance = 0.0;
    LocationPointEntity? prevPt;

    for (final pt in route) {
      if (prevPt != null) {
        accDistance += _haversineM(
          prevPt.lat,
          prevPt.lng,
          pt.lat,
          pt.lng,
        );
      }
      prevPt = pt;

      buf.writeln('          <Trackpoint>');
      buf.writeln('            <Time>${_isoTime(pt.timestampMs)}</Time>');
      buf.writeln('            <Position>');
      buf.writeln(
        '              <LatitudeDegrees>'
        '${pt.lat.toStringAsFixed(8)}'
        '</LatitudeDegrees>',
      );
      buf.writeln(
        '              <LongitudeDegrees>'
        '${pt.lng.toStringAsFixed(8)}'
        '</LongitudeDegrees>',
      );
      buf.writeln('            </Position>');

      if (pt.alt != null) {
        buf.writeln(
          '            <AltitudeMeters>'
          '${pt.alt!.toStringAsFixed(1)}'
          '</AltitudeMeters>',
        );
      }

      buf.writeln(
        '            <DistanceMeters>'
        '${accDistance.toStringAsFixed(1)}'
        '</DistanceMeters>',
      );

      final hr = _nearestHr(pt.timestampMs, hrSamples);
      if (hr != null) {
        buf.writeln('            <HeartRateBpm>');
        buf.writeln('              <Value>$hr</Value>');
        buf.writeln('            </HeartRateBpm>');
      }

      buf.writeln('          </Trackpoint>');
    }

    buf.writeln('        </Track>');
    buf.writeln('      </Lap>');

    // Creator
    buf.writeln('      <Creator xsi:type="Device_t">');
    buf.writeln('        <Name>Omni Runner</Name>');
    buf.writeln('      </Creator>');

    buf.writeln('    </Activity>');
    buf.writeln('  </Activities>');
    buf.writeln('</TrainingCenterDatabase>');

    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  int? _nearestHr(
    int timestampMs,
    List<HeartRateSample> samples, {
    int maxDeltaMs = 5000,
  }) {
    if (samples.isEmpty) return null;

    int? bestBpm;
    int bestDelta = maxDeltaMs + 1;

    for (final s in samples) {
      final delta = (s.timestampMs - timestampMs).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestBpm = s.bpm;
      }
    }

    return bestDelta <= maxDeltaMs ? bestBpm : null;
  }

  String _isoTime(int ms) {
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
        .toIso8601String();
  }

  String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Simplified Haversine for accumulated distance in trackpoints.
  double _haversineM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _toRad(double deg) => deg * 3.14159265358979323846 / 180.0;
}
