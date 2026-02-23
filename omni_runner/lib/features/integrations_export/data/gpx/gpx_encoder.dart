import 'dart:convert';
import 'dart:typed_data';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// Generates a GPX 1.1 XML file from a workout session.
///
/// Includes:
/// - `<metadata>` with name and start time
/// - `<trk>` / `<trkseg>` with all GPS trackpoints
/// - Garmin TrackPointExtension for HR data (per-point nearest-match)
///
/// Reference: https://www.topografix.com/GPX/1/1/
/// HR extension: http://www.garmin.com/xmlschemas/TrackPointExtension/v1
final class GpxEncoder {
  const GpxEncoder();

  /// Encode a workout session + route + HR into GPX 1.1 XML bytes.
  Uint8List encode({
    required WorkoutSessionEntity session,
    required List<LocationPointEntity> route,
    List<HeartRateSample> hrSamples = const [],
    String activityName = 'Omni Runner',
  }) {
    final buf = StringBuffer();

    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<gpx version="1.1" creator="Omni Runner"');
    buf.writeln('  xmlns="http://www.topografix.com/GPX/1/1"');
    buf.writeln(
      '  xmlns:gpxtpx='
      '"http://www.garmin.com/xmlschemas/TrackPointExtension/v1"',
    );
    buf.writeln(
      '  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"',
    );
    buf.writeln(
      '  xsi:schemaLocation='
      '"http://www.topografix.com/GPX/1/1 '
      'http://www.topografix.com/GPX/1/1/gpx.xsd">',
    );

    // Metadata
    buf.writeln('  <metadata>');
    buf.writeln('    <name>${_escapeXml(activityName)}</name>');
    buf.writeln('    <time>${_isoTime(session.startTimeMs)}</time>');
    buf.writeln('  </metadata>');

    // Track
    buf.writeln('  <trk>');
    buf.writeln('    <name>${_escapeXml(activityName)}</name>');
    buf.writeln('    <type>running</type>');
    buf.writeln('    <trkseg>');

    for (final pt in route) {
      buf.writeln(
        '      <trkpt lat="${pt.lat.toStringAsFixed(8)}" '
        'lon="${pt.lng.toStringAsFixed(8)}">',
      );

      if (pt.alt != null) {
        buf.writeln(
          '        <ele>${pt.alt!.toStringAsFixed(1)}</ele>',
        );
      }

      buf.writeln('        <time>${_isoTime(pt.timestampMs)}</time>');

      // HR extension: find nearest HR sample within 5 seconds
      final hr = _nearestHr(pt.timestampMs, hrSamples);
      if (hr != null) {
        buf.writeln('        <extensions>');
        buf.writeln('          <gpxtpx:TrackPointExtension>');
        buf.writeln('            <gpxtpx:hr>$hr</gpxtpx:hr>');
        buf.writeln('          </gpxtpx:TrackPointExtension>');
        buf.writeln('        </extensions>');
      }

      buf.writeln('      </trkpt>');
    }

    buf.writeln('    </trkseg>');
    buf.writeln('  </trk>');
    buf.writeln('</gpx>');

    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  /// Find the nearest HR sample within [maxDeltaMs] of a given timestamp.
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
}
