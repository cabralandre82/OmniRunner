import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/core/utils/format_pace.dart';

void main() {
  group('formatPace', () {
    // ── Invalid inputs → '--:--/km' ──

    test('null returns placeholder', () {
      expect(formatPace(null), '--:--/km');
    });

    test('positive infinity returns placeholder', () {
      expect(formatPace(double.infinity), '--:--/km');
    });

    test('negative infinity returns placeholder', () {
      expect(formatPace(double.negativeInfinity), '--:--/km');
    });

    test('NaN returns placeholder', () {
      expect(formatPace(double.nan), '--:--/km');
    });

    test('zero returns placeholder', () {
      expect(formatPace(0.0), '--:--/km');
    });

    test('negative value returns placeholder', () {
      expect(formatPace(-300.0), '--:--/km');
    });

    // ── Exact values ──

    test('300 sec/km formats to 05:00/km', () {
      expect(formatPace(300.0), '05:00/km');
    });

    test('270 sec/km formats to 04:30/km', () {
      expect(formatPace(270.0), '04:30/km');
    });

    test('360 sec/km formats to 06:00/km', () {
      expect(formatPace(360.0), '06:00/km');
    });

    test('61 sec/km formats to 01:01/km', () {
      expect(formatPace(61.0), '01:01/km');
    });

    test('60 sec/km formats to 01:00/km', () {
      expect(formatPace(60.0), '01:00/km');
    });

    // ── Rounding ──

    test('299.8 rounds to 300 → 05:00/km', () {
      expect(formatPace(299.8), '05:00/km');
    });

    test('299.4 rounds to 299 → 04:59/km', () {
      expect(formatPace(299.4), '04:59/km');
    });

    test('359.5 rounds to 360 → 06:00/km (rollover)', () {
      expect(formatPace(359.5), '06:00/km');
    });

    test('0.6 rounds to 1 → 00:01/km', () {
      expect(formatPace(0.6), '00:01/km');
    });

    // ── Padding ──

    test('minutes are zero-padded to 2 digits', () {
      expect(formatPace(65.0), '01:05/km');
    });

    test('seconds are zero-padded to 2 digits', () {
      expect(formatPace(301.0), '05:01/km');
    });

    // ── Realistic paces ──

    test('world record marathon ~2:55/km = 175 sec/km', () {
      expect(formatPace(175.0), '02:55/km');
    });

    test('casual runner ~6:00/km = 360 sec/km', () {
      expect(formatPace(360.0), '06:00/km');
    });

    test('very slow walk ~15:00/km = 900 sec/km', () {
      expect(formatPace(900.0), '15:00/km');
    });

    test('extreme slow ~60:00/km = 3600 sec/km', () {
      expect(formatPace(3600.0), '60:00/km');
    });

    // ── Small positive ──

    test('value that rounds to zero returns placeholder', () {
      // 0.4 > 0 passes initial guard, but rounds to 0 → placeholder
      expect(formatPace(0.4), '--:--/km');
    });
  });
}
