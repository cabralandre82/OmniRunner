import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';
import 'package:omni_runner/features/wearables_ble/parse_heart_rate_measurement.dart';

// Fixed timestamp for deterministic tests.
const int _ts = 1700000000000;

/// Helper: call parser with a fixed timestamp so assertions are deterministic.
HeartRateSample? _parse(List<int> bytes) =>
    parseHeartRateMeasurement(Uint8List.fromList(bytes), timestampMs: _ts);

/// ============================================================================
/// Tests for [parseHeartRateMeasurement]
///
/// Follows the Bluetooth SIG Heart Rate Measurement characteristic spec:
///
///   Byte 0: Flags
///     Bit 0:   HR format     — 0 = UINT8, 1 = UINT16 (LE)
///     Bit 1:   Contact status — (only when bit 2 = 1)
///     Bit 2:   Contact supported
///     Bit 3:   Energy Expended present
///     Bit 4:   RR-Interval present
///     Bit 5-7: Reserved
///
///   Then: BPM (1 or 2 bytes)
///   Then: optional Energy (2 bytes LE)
///   Then: optional RR intervals (2 bytes each, LE, 1/1024s resolution)
/// ============================================================================
void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // 1. GUARD CLAUSES — malformed / insufficient data
  // ──────────────────────────────────────────────────────────────────────────

  group('guard clauses — malformed data', () {
    test('empty data returns null', () {
      expect(_parse([]), isNull);
    });

    test('single byte (flags only, no BPM) returns null', () {
      expect(_parse([0x00]), isNull);
    });

    test('BPM = 0 returns null (sensor reports no valid reading)', () {
      expect(_parse([0x00, 0x00]), isNull);
    });

    test('UINT16 flag set but only 2 bytes total returns null', () {
      // flags=0x01 (UINT16) + only one BPM byte
      expect(_parse([0x01, 72]), isNull);
    });

    test('energy flag set but data truncated before energy bytes', () {
      // flags=0x08 (energy present), BPM=75, no energy bytes
      expect(_parse([0x08, 75]), isNull);
    });

    test('energy flag set but only 1 energy byte present', () {
      // flags=0x08, BPM=75, one byte of energy
      expect(_parse([0x08, 75, 0x64]), isNull);
    });

    test('UINT16 + energy flag set but only BPM present', () {
      // flags=0x09 (UINT16 + energy), BPM=150 LE, no energy bytes
      expect(_parse([0x09, 0x96, 0x00]), isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. BPM FORMAT — Bit 0
  // ──────────────────────────────────────────────────────────────────────────

  group('BPM format — bit 0', () {
    test('bit 0 = 0 → UINT8 BPM', () {
      final r = _parse([0x00, 72]);
      expect(r, isNotNull);
      expect(r!.bpm, 72);
    });

    test('bit 0 = 1 → UINT16 little-endian BPM', () {
      // 0x012C = 300 → LE bytes: [0x2C, 0x01]
      final r = _parse([0x01, 0x2C, 0x01]);
      expect(r!.bpm, 300);
    });

    test('UINT8 BPM = 1 (minimum valid)', () {
      expect(_parse([0x00, 1])!.bpm, 1);
    });

    test('UINT8 BPM = 255 (maximum)', () {
      expect(_parse([0x00, 255])!.bpm, 255);
    });

    test('UINT16 BPM = 256 (just above UINT8 range)', () {
      // 256 LE: [0x00, 0x01]
      expect(_parse([0x01, 0x00, 0x01])!.bpm, 256);
    });

    test('UINT16 BPM = 65535 (maximum)', () {
      expect(_parse([0x01, 0xFF, 0xFF])!.bpm, 65535);
    });

    test('UINT16 BPM = 1 (LE: [0x01, 0x00])', () {
      expect(_parse([0x01, 0x01, 0x00])!.bpm, 1);
    });

    test('UINT16 BPM = 0 returns null', () {
      expect(_parse([0x01, 0x00, 0x00]), isNull);
    });

    test('UINT8 typical resting HR (60)', () {
      expect(_parse([0x00, 60])!.bpm, 60);
    });

    test('UINT8 typical max HR (195)', () {
      expect(_parse([0x00, 195])!.bpm, 195);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. SENSOR CONTACT — Bits 1–2
  // ──────────────────────────────────────────────────────────────────────────

  group('sensor contact — bits 1-2', () {
    test('bits 1-2 = 00 → contact not supported, returns null', () {
      // flags = 0x00
      expect(_parse([0x00, 80])!.sensorContact, isNull);
    });

    test('bits 1-2 = 01 → contact not supported (bit 2 = 0), returns null', () {
      // flags = 0x02 (bit 1 set, bit 2 clear — spec says not supported)
      expect(_parse([0x02, 80])!.sensorContact, isNull);
    });

    test('bits 1-2 = 10 → supported, NOT detected', () {
      // flags = 0x04 (bit 2 set, bit 1 clear)
      expect(_parse([0x04, 80])!.sensorContact, false);
    });

    test('bits 1-2 = 11 → supported, detected', () {
      // flags = 0x06 (bit 2 + bit 1 set)
      expect(_parse([0x06, 80])!.sensorContact, true);
    });

    test('contact bits are independent of BPM format', () {
      // UINT16 + contact supported + detected: flags = 0x07
      final r = _parse([0x07, 80, 0x00]);
      expect(r!.bpm, 80);
      expect(r.sensorContact, true);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. ENERGY EXPENDED — Bit 3
  // ──────────────────────────────────────────────────────────────────────────

  group('energy expended — bit 3', () {
    test('bit 3 = 0 → energy not present', () {
      expect(_parse([0x00, 80])!.energyExpendedKj, isNull);
    });

    test('bit 3 = 1 → UINT16 LE energy present', () {
      // flags=0x08, BPM=75, energy=500 (0x01F4 LE: [0xF4, 0x01])
      final r = _parse([0x08, 75, 0xF4, 0x01]);
      expect(r!.bpm, 75);
      expect(r.energyExpendedKj, 500);
    });

    test('energy = 0 is valid', () {
      final r = _parse([0x08, 75, 0x00, 0x00]);
      expect(r!.energyExpendedKj, 0);
    });

    test('energy = 65535 (max)', () {
      final r = _parse([0x08, 75, 0xFF, 0xFF]);
      expect(r!.energyExpendedKj, 65535);
    });

    test('energy with UINT16 BPM: offsets shift correctly', () {
      // flags=0x09 (UINT16 + energy), BPM=150, energy=100
      final r = _parse([0x09, 0x96, 0x00, 0x64, 0x00]);
      expect(r!.bpm, 150);
      expect(r.energyExpendedKj, 100);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5. RR INTERVALS — Bit 4
  // ──────────────────────────────────────────────────────────────────────────

  group('RR intervals — bit 4', () {
    test('bit 4 = 0 → no RR intervals', () {
      expect(_parse([0x00, 80])!.rrIntervalsMs, isEmpty);
    });

    test('single RR interval parsed correctly', () {
      // flags=0x10 (RR), BPM=70, RR raw=800 (0x0320 LE) → (800*1000)~/1024 = 781 ms
      final r = _parse([0x10, 70, 0x20, 0x03]);
      expect(r!.rrIntervalsMs, [781]);
    });

    test('two RR intervals packed in one notification', () {
      // RR1 raw=1024 (0x0400 LE) → 1000 ms
      // RR2 raw=900  (0x0384 LE) → (900*1000)~/1024 = 878 ms
      final r = _parse([0x10, 65, 0x00, 0x04, 0x84, 0x03]);
      expect(r!.rrIntervalsMs, [1000, 878]);
    });

    test('three RR intervals packed in one notification', () {
      // RR1=1024 → 1000ms,  RR2=512 → 500ms,  RR3=768 → 750ms
      // 1024 LE: [0x00,0x04], 512 LE: [0x00,0x02], 768 LE: [0x00,0x03]
      final r = _parse([0x10, 60, 0x00, 0x04, 0x00, 0x02, 0x00, 0x03]);
      expect(r!.rrIntervalsMs, [1000, 500, 750]);
    });

    test('trailing incomplete RR byte is silently ignored', () {
      // flags=0x10, BPM=80, only 1 byte of RR data
      final r = _parse([0x10, 80, 0x20]);
      expect(r!.bpm, 80);
      expect(r.rrIntervalsMs, isEmpty);
    });

    test('RR = 0 raw → 0 ms (edge case)', () {
      final r = _parse([0x10, 80, 0x00, 0x00]);
      expect(r!.rrIntervalsMs, [0]);
    });

    test('RR = 65535 raw → max interval', () {
      // (65535 * 1000) ~/ 1024 = 63999 ms
      final r = _parse([0x10, 80, 0xFF, 0xFF]);
      expect(r!.rrIntervalsMs, [63999]);
    });

    test('RR resolution: 1024 raw → exactly 1000 ms', () {
      final r = _parse([0x10, 80, 0x00, 0x04]);
      expect(r!.rrIntervalsMs, [1000]);
    });

    test('RR with UINT16 BPM: offset correct', () {
      // flags=0x11 (UINT16 + RR), BPM=200 [0xC8,0x00], RR=512 raw → 500ms
      final r = _parse([0x11, 0xC8, 0x00, 0x00, 0x02]);
      expect(r!.bpm, 200);
      expect(r.rrIntervalsMs, [500]);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 6. COMBINED FIELDS — all optional fields together
  // ──────────────────────────────────────────────────────────────────────────

  group('combined fields', () {
    test('all flags set: UINT16 + contact + energy + RR', () {
      // flags = 0x1F = 0b00011111
      // BPM = 150 (LE: [0x96, 0x00])
      // Energy = 200 (LE: [0xC8, 0x00])
      // RR = 410 raw (LE: [0x9A, 0x01]) → (410*1000)~/1024 = 400 ms
      final r = _parse([0x1F, 0x96, 0x00, 0xC8, 0x00, 0x9A, 0x01]);
      expect(r!.bpm, 150);
      expect(r.sensorContact, true);
      expect(r.energyExpendedKj, 200);
      expect(r.rrIntervalsMs, [400]);
      expect(r.timestampMs, _ts);
    });

    test('UINT8 + contact (no) + energy + multiple RR', () {
      // flags = 0x1C = 0b00011100 (contact supported-no, energy, RR)
      // BPM = 90
      // Energy = 50 (LE: [0x32, 0x00])
      // RR1 = 1024 → 1000ms, RR2 = 900 → 878ms
      final r = _parse([0x1C, 90, 0x32, 0x00, 0x00, 0x04, 0x84, 0x03]);
      expect(r!.bpm, 90);
      expect(r.sensorContact, false);
      expect(r.energyExpendedKj, 50);
      expect(r.rrIntervalsMs, [1000, 878]);
    });

    test('UINT8 + energy + no RR', () {
      final r = _parse([0x08, 90, 0x64, 0x00]);
      expect(r!.bpm, 90);
      expect(r.energyExpendedKj, 100);
      expect(r.rrIntervalsMs, isEmpty);
    });

    test('contact + RR, no energy', () {
      // flags = 0x16 (contact supported+detected, RR)
      final r = _parse([0x16, 72, 0x00, 0x04]);
      expect(r!.bpm, 72);
      expect(r.sensorContact, true);
      expect(r.energyExpendedKj, isNull);
      expect(r.rrIntervalsMs, [1000]);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 7. REALISTIC DEVICE PACKETS
  // ──────────────────────────────────────────────────────────────────────────

  group('realistic device packets', () {
    test('Polar H10 — UINT8, contact detected, single RR', () {
      // flags=0x16 (bit1+2=contact, bit4=RR), BPM=68
      // RR raw=880 (0x0370 LE) → (880*1000)~/1024 = 859 ms
      final r = _parse([0x16, 68, 0x70, 0x03]);
      expect(r!.bpm, 68);
      expect(r.sensorContact, true);
      expect(r.rrIntervalsMs, [859]);
      expect(r.energyExpendedKj, isNull);
    });

    test('Garmin HRM-Pro — UINT8, no contact info, two RR', () {
      // flags=0x10 (RR only), BPM=142
      // RR1=430 raw (0x01AE LE) → (430*1000)~/1024 = 419 ms
      // RR2=425 raw (0x01A9 LE) → (425*1000)~/1024 = 415 ms
      final r = _parse([0x10, 142, 0xAE, 0x01, 0xA9, 0x01]);
      expect(r!.bpm, 142);
      expect(r.sensorContact, isNull);
      expect(r.rrIntervalsMs, [419, 415]);
    });

    test('Wahoo TICKR — UINT8, contact, energy, RR', () {
      // flags=0x1E (contact supported+detected, energy, RR)
      // BPM=155, Energy=350 (0x015E LE), RR=390 raw → (390*1000)~/1024 = 380
      final r = _parse([0x1E, 155, 0x5E, 0x01, 0x86, 0x01]);
      expect(r!.bpm, 155);
      expect(r.sensorContact, true);
      expect(r.energyExpendedKj, 350);
      expect(r.rrIntervalsMs, [380]);
    });

    test('generic optical — UINT8, no extras, minimal packet', () {
      // flags=0x00, BPM=92
      final r = _parse([0x00, 92]);
      expect(r!.bpm, 92);
      expect(r.sensorContact, isNull);
      expect(r.energyExpendedKj, isNull);
      expect(r.rrIntervalsMs, isEmpty);
    });

    test('Apple Watch bridge — UINT16, no extras', () {
      // flags=0x01, BPM=78 (LE: [0x4E, 0x00])
      final r = _parse([0x01, 0x4E, 0x00]);
      expect(r!.bpm, 78);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 8. TIMESTAMP INJECTION
  // ──────────────────────────────────────────────────────────────────────────

  group('timestamp', () {
    test('injected timestampMs is used when provided', () {
      final r = parseHeartRateMeasurement(
        Uint8List.fromList([0x00, 80]),
        timestampMs: 42,
      );
      expect(r!.timestampMs, 42);
    });

    test('timestampMs defaults to now when not provided', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final r = parseHeartRateMeasurement(Uint8List.fromList([0x00, 80]));
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(r!.timestampMs, greaterThanOrEqualTo(before));
      expect(r.timestampMs, lessThanOrEqualTo(after));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 9. RESERVED BITS — should be ignored
  // ──────────────────────────────────────────────────────────────────────────

  group('reserved bits 5-7', () {
    test('reserved bits set to 1 are ignored', () {
      // flags = 0xE0 (bits 5,6,7 set, rest 0) → UINT8, no extras
      final r = _parse([0xE0, 85]);
      expect(r!.bpm, 85);
      expect(r.sensorContact, isNull);
      expect(r.energyExpendedKj, isNull);
      expect(r.rrIntervalsMs, isEmpty);
    });

    test('all 8 bits set → parses UINT16 + contact + energy + RR', () {
      // flags = 0xFF
      // BPM = 100 (LE: [0x64, 0x00])
      // Energy = 10 (LE: [0x0A, 0x00])
      // RR = 1024 raw → 1000ms
      final r = _parse([0xFF, 0x64, 0x00, 0x0A, 0x00, 0x00, 0x04]);
      expect(r!.bpm, 100);
      expect(r.sensorContact, true);
      expect(r.energyExpendedKj, 10);
      expect(r.rrIntervalsMs, [1000]);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 10. EXTRA TRAILING BYTES — should be harmlessly ignored
  // ──────────────────────────────────────────────────────────────────────────

  group('extra trailing bytes', () {
    test('extra bytes after UINT8 BPM without RR flag are ignored', () {
      // flags=0x00, BPM=80, extra garbage bytes
      final r = _parse([0x00, 80, 0xDE, 0xAD, 0xBE, 0xEF]);
      expect(r!.bpm, 80);
      expect(r.rrIntervalsMs, isEmpty);
    });

    test('extra single byte after RR data is ignored (incomplete pair)', () {
      // flags=0x10, BPM=70, RR1=[0x20,0x03], trailing 0xFF
      final r = _parse([0x10, 70, 0x20, 0x03, 0xFF]);
      expect(r!.rrIntervalsMs, [781]);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 11. RR INTERVAL ARITHMETIC — conversion precision
  // ──────────────────────────────────────────────────────────────────────────

  group('RR interval conversion precision', () {
    test('raw=1 → (1*1000)~/1024 = 0 ms', () {
      final r = _parse([0x10, 80, 0x01, 0x00]);
      expect(r!.rrIntervalsMs, [0]);
    });

    test('raw=2 → (2*1000)~/1024 = 1 ms', () {
      final r = _parse([0x10, 80, 0x02, 0x00]);
      expect(r!.rrIntervalsMs, [1]);
    });

    test('raw=512 → (512*1000)~/1024 = 500 ms', () {
      final r = _parse([0x10, 80, 0x00, 0x02]);
      expect(r!.rrIntervalsMs, [500]);
    });

    test('raw=1024 → exactly 1000 ms', () {
      final r = _parse([0x10, 80, 0x00, 0x04]);
      expect(r!.rrIntervalsMs, [1000]);
    });

    test('raw=800 → (800*1000)~/1024 = 781 ms', () {
      final r = _parse([0x10, 80, 0x20, 0x03]);
      expect(r!.rrIntervalsMs, [781]);
    });

    test('raw=900 → (900*1000)~/1024 = 878 ms', () {
      final r = _parse([0x10, 80, 0x84, 0x03]);
      expect(r!.rrIntervalsMs, [878]);
    });

    test('raw=425 → (425*1000)~/1024 = 415 ms', () {
      final r = _parse([0x10, 80, 0xA9, 0x01]);
      expect(r!.rrIntervalsMs, [415]);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 12. EQUATABLE — HeartRateSample value equality
  // ──────────────────────────────────────────────────────────────────────────

  group('HeartRateSample — Equatable', () {
    test('identical samples are equal', () {
      const a = HeartRateSample(bpm: 80, timestampMs: 1000);
      const b = HeartRateSample(bpm: 80, timestampMs: 1000);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different BPM → not equal', () {
      const a = HeartRateSample(bpm: 80, timestampMs: 1000);
      const b = HeartRateSample(bpm: 81, timestampMs: 1000);
      expect(a, isNot(equals(b)));
    });

    test('different timestamp → not equal', () {
      const a = HeartRateSample(bpm: 80, timestampMs: 1000);
      const b = HeartRateSample(bpm: 80, timestampMs: 1001);
      expect(a, isNot(equals(b)));
    });

    test('different sensorContact → not equal', () {
      const a = HeartRateSample(bpm: 80, sensorContact: true, timestampMs: 1000);
      const b = HeartRateSample(bpm: 80, sensorContact: false, timestampMs: 1000);
      expect(a, isNot(equals(b)));
    });

    test('null vs true sensorContact → not equal', () {
      const a = HeartRateSample(bpm: 80, timestampMs: 1000);
      const b = HeartRateSample(bpm: 80, sensorContact: true, timestampMs: 1000);
      expect(a, isNot(equals(b)));
    });

    test('different RR intervals → not equal', () {
      const a = HeartRateSample(bpm: 80, rrIntervalsMs: [800], timestampMs: 1000);
      const b = HeartRateSample(bpm: 80, rrIntervalsMs: [801], timestampMs: 1000);
      expect(a, isNot(equals(b)));
    });

    test('empty vs non-empty RR intervals → not equal', () {
      const a = HeartRateSample(bpm: 80, timestampMs: 1000);
      const b = HeartRateSample(bpm: 80, rrIntervalsMs: [800], timestampMs: 1000);
      expect(a, isNot(equals(b)));
    });

    test('different energyExpendedKj → not equal', () {
      const a = HeartRateSample(bpm: 80, energyExpendedKj: 100, timestampMs: 1000);
      const b = HeartRateSample(bpm: 80, energyExpendedKj: 101, timestampMs: 1000);
      expect(a, isNot(equals(b)));
    });

    test('null vs 0 energyExpendedKj → not equal', () {
      const a = HeartRateSample(bpm: 80, timestampMs: 1000);
      const b = HeartRateSample(bpm: 80, energyExpendedKj: 0, timestampMs: 1000);
      expect(a, isNot(equals(b)));
    });

    test('fully populated identical samples are equal', () {
      const a = HeartRateSample(
        bpm: 150,
        sensorContact: true,
        rrIntervalsMs: [800, 810],
        energyExpendedKj: 500,
        timestampMs: 99999,
      );
      const b = HeartRateSample(
        bpm: 150,
        sensorContact: true,
        rrIntervalsMs: [800, 810],
        energyExpendedKj: 500,
        timestampMs: 99999,
      );
      expect(a, equals(b));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 13. INTEGRATION — full round-trip byte → HeartRateSample verification
  // ──────────────────────────────────────────────────────────────────────────

  group('round-trip verification', () {
    test('every field of returned HeartRateSample matches parsed bytes', () {
      // flags=0x1E: UINT8, contact supported+detected, energy, RR
      // BPM=120, Energy=42 LE:[0x2A,0x00], RR=600 raw LE:[0x58,0x02]
      final r = _parse([0x1E, 120, 0x2A, 0x00, 0x58, 0x02]);

      expect(r, isNotNull);
      expect(r!.bpm, 120);
      expect(r.sensorContact, true);
      expect(r.energyExpendedKj, 42);
      expect(r.rrIntervalsMs.length, 1);
      expect(r.rrIntervalsMs[0], (600 * 1000) ~/ 1024); // 585 ms
      expect(r.timestampMs, _ts);
    });

    test('minimal valid packet produces correct defaults', () {
      final r = _parse([0x00, 80]);

      expect(r!.bpm, 80);
      expect(r.sensorContact, isNull);
      expect(r.energyExpendedKj, isNull);
      expect(r.rrIntervalsMs, isEmpty);
      expect(r.timestampMs, _ts);
    });
  });
}
