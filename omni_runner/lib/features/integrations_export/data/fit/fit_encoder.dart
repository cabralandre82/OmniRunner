import 'dart:math' as math;
import 'dart:typed_data';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// Generates a Garmin FIT (Flexible and Interoperable Data Transfer) file.
///
/// FIT is a binary protocol used by Garmin, Strava, TrainingPeaks, and most
/// serious training platforms. It supports GPS, HR, pace, distance, laps,
/// sessions, and device metadata.
///
/// Binary layout:
///   [14-byte header] [definition + data messages...] [2-byte CRC]
///
/// Key conversions:
///   - Coordinates: semicircles = degrees × (2³¹ / 180)
///   - Timestamps: seconds since 1989-12-31T00:00:00Z (Garmin epoch)
///   - Altitude: (meters + 500) × 5  (uint16, scale 5, offset 500)
///   - Distance: meters × 100        (uint32, scale 100)
///   - Speed: m/s × 1000             (uint16, scale 1000)
final class FitEncoder {
  const FitEncoder();

  static const _garminEpochMs = 631065600000;
  static const _semicirclesPerDegree = 2147483648.0 / 180.0;

  /// Encode a workout session into FIT binary format.
  ///
  /// Returns a valid FIT binary even for edge cases (empty route,
  /// zero timestamps, extreme coordinates).
  Uint8List encode({
    required WorkoutSessionEntity session,
    required List<LocationPointEntity> route,
    List<HeartRateSample> hrSamples = const [],
    String activityName = 'Omni Runner',
  }) {
    final w = _FitWriter();
    final safeStartMs = session.startTimeMs > _garminEpochMs
        ? session.startTimeMs
        : DateTime.now().millisecondsSinceEpoch;
    final startTs = _garminTs(safeStartMs);
    final endMs = (session.endTimeMs ?? safeStartMs).clamp(safeStartMs, safeStartMs + 86400000);
    final endTs = _garminTs(endMs);
    final elapsedMs = endMs - safeStartMs;
    final distM = (session.totalDistanceM ?? 0.0).clamp(0.0, 1000000.0);

    // ── file_id (global mesg 0, local 0) ──
    w.defineMessage(0, 0, const [
      (0, 1, 0x00),  // type: enum
      (1, 2, 0x84),  // manufacturer: uint16
      (2, 2, 0x84),  // product: uint16
      (3, 4, 0x8C),  // serial_number: uint32z
      (4, 4, 0x86),  // time_created: uint32
    ]);
    w.dataHeader(0);
    w.u8(4);        // type = activity
    w.u16(255);     // manufacturer = development
    w.u16(0);       // product
    w.u32(0);       // serial_number
    w.u32(startTs);

    // ── event definition (global mesg 21, local 1) ──
    w.defineMessage(1, 21, const [
      (253, 4, 0x86), // timestamp: uint32
      (0, 1, 0x00),   // event: enum
      (1, 1, 0x00),   // event_type: enum
    ]);

    // event: timer start
    w.dataHeader(1);
    w.u32(startTs);
    w.u8(0); // event = timer
    w.u8(0); // event_type = start

    // ── record definition (global mesg 20, local 2) ──
    w.defineMessage(2, 20, const [
      (253, 4, 0x86), // timestamp: uint32
      (0, 4, 0x85),   // position_lat: sint32
      (1, 4, 0x85),   // position_lng: sint32
      (2, 2, 0x84),   // altitude: uint16 (scale 5, offset 500)
      (3, 1, 0x02),   // heart_rate: uint8
      (5, 4, 0x86),   // distance: uint32 (scale 100)
      (6, 2, 0x84),   // speed: uint16 (scale 1000)
    ]);

    // ── trackpoint records ──
    var accDist = 0.0;
    LocationPointEntity? prev;
    final safeRoute = route.where((pt) =>
        pt.lat.isFinite && pt.lng.isFinite &&
        pt.lat.abs() <= 90 && pt.lng.abs() <= 180).toList();
    for (final pt in safeRoute) {
      if (prev != null) {
        final seg = _haversine(prev.lat, prev.lng, pt.lat, pt.lng);
        if (seg.isFinite && seg < 100000) accDist += seg;
      }
      prev = pt;

      final hr = _nearestHr(pt.timestampMs, hrSamples);
      final altScaled = pt.alt != null && pt.alt!.isFinite
          ? ((pt.alt!.clamp(-500, 9000) + 500) * 5).round()
          : 0xFFFF;
      final speedScaled = pt.speed != null && pt.speed!.isFinite
          ? (pt.speed!.clamp(0, 100) * 1000).round()
          : 0xFFFF;

      w.dataHeader(2);
      w.u32(_garminTs(pt.timestampMs.clamp(_garminEpochMs, safeStartMs + 86400000)));
      w.s32(_toSemicircles(pt.lat));
      w.s32(_toSemicircles(pt.lng));
      w.u16(altScaled);
      w.u8(hr ?? 0xFF);
      w.u32((accDist * 100).round().clamp(0, 0xFFFFFFFF));
      w.u16(speedScaled);
    }

    // event: timer stop
    w.dataHeader(1);
    w.u32(endTs);
    w.u8(0); // event = timer
    w.u8(4); // event_type = stop_all

    // ── lap (global mesg 19, local 3) ──
    w.defineMessage(3, 19, const [
      (253, 4, 0x86), // timestamp
      (0, 1, 0x00),   // event: enum
      (1, 1, 0x00),   // event_type: enum
      (2, 4, 0x86),   // start_time: uint32
      (7, 4, 0x86),   // total_elapsed_time: uint32 (scale 1000)
      (8, 4, 0x86),   // total_timer_time: uint32 (scale 1000)
      (9, 4, 0x86),   // total_distance: uint32 (scale 100)
      (15, 1, 0x02),  // avg_heart_rate: uint8
      (16, 1, 0x02),  // max_heart_rate: uint8
      (25, 1, 0x00),  // sport: enum
    ]);
    w.dataHeader(3);
    w.u32(endTs);
    w.u8(9);  // event = lap
    w.u8(1);  // event_type = stop
    w.u32(startTs);
    w.u32(elapsedMs);
    w.u32(elapsedMs);
    w.u32((distM * 100).round());
    w.u8(session.avgBpm ?? 0xFF);
    w.u8(session.maxBpm ?? 0xFF);
    w.u8(1);  // sport = running

    // ── session (global mesg 18, local 4) ──
    w.defineMessage(4, 18, const [
      (253, 4, 0x86), // timestamp
      (0, 1, 0x00),   // event: enum
      (1, 1, 0x00),   // event_type: enum
      (2, 4, 0x86),   // start_time: uint32
      (5, 1, 0x00),   // sport: enum
      (6, 1, 0x00),   // sub_sport: enum
      (7, 4, 0x86),   // total_elapsed_time: uint32 (scale 1000)
      (8, 4, 0x86),   // total_timer_time: uint32 (scale 1000)
      (9, 4, 0x86),   // total_distance: uint32 (scale 100)
      (16, 1, 0x02),  // avg_heart_rate: uint8
      (17, 1, 0x02),  // max_heart_rate: uint8
      (25, 2, 0x84),  // first_lap_index: uint16
      (26, 2, 0x84),  // num_laps: uint16
    ]);
    w.dataHeader(4);
    w.u32(endTs);
    w.u8(8);  // event = session
    w.u8(1);  // event_type = stop
    w.u32(startTs);
    w.u8(1);  // sport = running
    w.u8(0);  // sub_sport = generic
    w.u32(elapsedMs);
    w.u32(elapsedMs);
    w.u32((distM * 100).round());
    w.u8(session.avgBpm ?? 0xFF);
    w.u8(session.maxBpm ?? 0xFF);
    w.u16(0); // first_lap_index
    w.u16(1); // num_laps

    // ── activity (global mesg 34, local 5) ──
    w.defineMessage(5, 34, const [
      (253, 4, 0x86), // timestamp
      (0, 4, 0x86),   // total_timer_time: uint32 (scale 1000)
      (1, 2, 0x84),   // num_sessions: uint16
      (2, 1, 0x00),   // type: enum
      (3, 1, 0x00),   // event: enum
      (4, 1, 0x00),   // event_type: enum
    ]);
    w.dataHeader(5);
    w.u32(endTs);
    w.u32(elapsedMs);
    w.u16(1); // num_sessions
    w.u8(0);  // type = manual
    w.u8(26); // event = activity
    w.u8(1);  // event_type = stop

    return w.finish();
  }

  int _garminTs(int unixMs) => (unixMs - _garminEpochMs) ~/ 1000;

  int _toSemicircles(double degrees) =>
      (degrees * _semicirclesPerDegree).round();

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

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
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

  double _toRad(double deg) => deg * math.pi / 180.0;
}

// ── Binary writer for FIT protocol ──────────────────────────────

/// Low-level writer that handles FIT message framing, byte ordering,
/// and CRC computation.
class _FitWriter {
  final _buf = BytesBuilder();

  /// Write a definition message.
  ///
  /// Each tuple is (fieldDefNumber, sizeBytes, baseType).
  void defineMessage(
    int localType,
    int globalMesgNum,
    List<(int, int, int)> fields,
  ) {
    _buf.addByte(0x40 | (localType & 0x0F)); // definition header
    _buf.addByte(0);                           // reserved
    _buf.addByte(0);                           // architecture: little-endian
    _buf.add([globalMesgNum & 0xFF, (globalMesgNum >> 8) & 0xFF]);
    _buf.addByte(fields.length);
    for (final (fd, sz, bt) in fields) {
      _buf.addByte(fd);
      _buf.addByte(sz);
      _buf.addByte(bt);
    }
  }

  /// Write a data record header for the given local message type.
  void dataHeader(int localType) {
    _buf.addByte(localType & 0x0F);
  }

  void u8(int v) => _buf.addByte(v & 0xFF);

  void u16(int v) => _buf.add([v & 0xFF, (v >> 8) & 0xFF]);

  void u32(int v) => _buf.add([
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ]);

  /// Write a signed 32-bit integer (same byte layout, different semantics).
  void s32(int v) => u32(v);

  /// Assemble the final FIT file: header + data + CRC.
  Uint8List finish() {
    final dataBytes = _buf.toBytes();

    final hdr = ByteData(14);
    hdr.setUint8(0, 14);                                   // header size
    hdr.setUint8(1, 0x20);                                 // protocol 2.0
    hdr.setUint16(2, 2132, Endian.little);                 // profile 21.32
    hdr.setUint32(4, dataBytes.length, Endian.little);
    hdr.setUint8(8, 0x2E);  // '.'
    hdr.setUint8(9, 0x46);  // 'F'
    hdr.setUint8(10, 0x49); // 'I'
    hdr.setUint8(11, 0x54); // 'T'
    final headerCrc = _crc16(hdr.buffer.asUint8List().sublist(0, 12));
    hdr.setUint16(12, headerCrc, Endian.little);

    final headerBytes = hdr.buffer.asUint8List();

    // File CRC covers header + data records
    var fileCrc = _crc16(headerBytes);
    fileCrc = _crc16(dataBytes, fileCrc);

    final out = BytesBuilder();
    out.add(headerBytes);
    out.add(dataBytes);
    out.add([fileCrc & 0xFF, (fileCrc >> 8) & 0xFF]);

    return out.toBytes();
  }

  /// CRC-16 lookup table (FIT SDK nibble-processing variant).
  static const _crcTable = [
    0x0000, 0xCC01, 0xD801, 0x1400,
    0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401,
    0x5000, 0x9C01, 0x8801, 0x4400,
  ];

  static int _crc16(Uint8List data, [int crc = 0]) {
    for (final byte in data) {
      var tmp = _crcTable[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ _crcTable[byte & 0xF];

      tmp = _crcTable[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ _crcTable[(byte >> 4) & 0xF];
    }
    return crc;
  }
}
