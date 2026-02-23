import 'dart:typed_data';

import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// Parse a raw BLE Heart Rate Measurement characteristic value (UUID 0x2A37).
///
/// Pure function — no side effects, no I/O, deterministic output.
/// Returns `null` if [data] is malformed or too short.
///
/// ## Bluetooth SIG Heart Rate Measurement Spec
///
/// ```
/// Byte 0: Flags
///   Bit 0     HR Value Format    0 = UINT8   1 = UINT16 (little-endian)
///   Bit 1     Sensor Contact     0 = no/not detected   1 = detected
///   Bit 2     Sensor Contact     0 = not supported      1 = supported
///   Bit 3     Energy Expended    0 = not present        1 = present (UINT16 LE)
///   Bit 4     RR-Interval        0 = not present        1 = present (UINT16 LE each)
///   Bit 5-7   Reserved
///
/// Byte 1(+2): Heart Rate value
///   If bit 0 = 0 → 1 byte  UINT8  (0–255 BPM)
///   If bit 0 = 1 → 2 bytes UINT16 little-endian (0–65535 BPM)
///
/// Then (if bit 3 = 1): Energy Expended
///   2 bytes UINT16 little-endian, in kilojoules, cumulative since reset
///
/// Then (if bit 4 = 1): RR-Intervals
///   N × 2 bytes UINT16 little-endian, resolution = 1/1024 second
///   Multiple RR values may be packed into a single notification
/// ```
///
/// ## Sensor Contact Bits (1–2) Truth Table
///
/// | Bit 2 | Bit 1 | Meaning                           |
/// |-------|-------|-----------------------------------|
/// |   0   |   0   | Contact not supported             |
/// |   0   |   1   | Contact not supported             |
/// |   1   |   0   | Supported — no contact detected   |
/// |   1   |   1   | Supported — contact detected      |
///
/// ## Parameters
///
/// - [data]: Raw bytes from the BLE characteristic notification.
/// - [timestampMs]: Timestamp to attach to the sample. Defaults to current
///   time if not provided. Injecting this makes the function fully pure
///   and deterministic in tests.
HeartRateSample? parseHeartRateMeasurement(
  Uint8List data, {
  int? timestampMs,
}) {
  // Minimum: 1 flags byte + 1 BPM byte
  if (data.length < 2) return null;

  final int flags = data[0];
  int offset = 1;

  // ── BPM ──────────────────────────────────────────────────────────────────
  final bool isUint16 = (flags & 0x01) != 0;
  final int bpm;

  if (isUint16) {
    if (data.length < 3) return null;
    bpm = data[1] | (data[2] << 8); // little-endian
    offset = 3;
  } else {
    bpm = data[1];
    offset = 2;
  }

  // BPM = 0 means the sensor has no valid reading
  if (bpm == 0) return null;

  // ── Sensor Contact ───────────────────────────────────────────────────────
  // Bit 2 = contact feature supported
  // Bit 1 = contact detected (only meaningful if bit 2 is set)
  final bool contactSupported = (flags & 0x04) != 0;
  final bool? sensorContact =
      contactSupported ? (flags & 0x02) != 0 : null;

  // ── Energy Expended ──────────────────────────────────────────────────────
  final bool hasEnergy = (flags & 0x08) != 0;
  int? energyExpendedKj;
  if (hasEnergy) {
    if (offset + 2 > data.length) return null; // truncated
    energyExpendedKj = data[offset] | (data[offset + 1] << 8);
    offset += 2;
  }

  // ── RR Intervals ─────────────────────────────────────────────────────────
  // Each RR value is UINT16 LE in units of 1/1024 second.
  // Multiple values can appear if HR is fast and notification rate is slow.
  final bool hasRr = (flags & 0x10) != 0;
  final rrIntervals = <int>[];
  if (hasRr) {
    while (offset + 1 < data.length) {
      final int rawRr = data[offset] | (data[offset + 1] << 8);
      // Convert 1/1024s → milliseconds: (raw * 1000) ~/ 1024
      rrIntervals.add((rawRr * 1000) ~/ 1024);
      offset += 2;
    }
    // A trailing single byte (incomplete pair) is silently ignored per spec.
  }

  return HeartRateSample(
    bpm: bpm,
    sensorContact: sensorContact,
    rrIntervalsMs: rrIntervals,
    energyExpendedKj: energyExpendedKj,
    timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}
