import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/hr_zone.dart';

void main() {
  group('HrZone enum', () {
    test('has 6 values', () {
      expect(HrZone.values.length, 6);
    });

    test('number returns correct int', () {
      expect(HrZone.belowZones.number, 0);
      expect(HrZone.zone1.number, 1);
      expect(HrZone.zone2.number, 2);
      expect(HrZone.zone3.number, 3);
      expect(HrZone.zone4.number, 4);
      expect(HrZone.zone5.number, 5);
    });

    test('label returns non-empty Portuguese string', () {
      for (final z in HrZone.values) {
        expect(z.label, isNotEmpty);
      }
    });

    test('zone labels are distinct', () {
      final labels = HrZone.values.map((z) => z.label).toSet();
      expect(labels.length, HrZone.values.length);
    });
  });

  group('HrZoneCalculator', () {
    // maxHr = 200 for easy math:
    // Zone 1: 50–60% → 100–120
    // Zone 2: 60–70% → 120–140
    // Zone 3: 70–80% → 140–160
    // Zone 4: 80–90% → 160–180
    // Zone 5: 90–100% → 180–200
    const calc = HrZoneCalculator(maxHr: 200);

    test('belowZones when bpm < 50% maxHr', () {
      expect(calc.zoneFor(99), HrZone.belowZones);
      expect(calc.zoneFor(50), HrZone.belowZones);
    });

    test('zone1 at exactly 50% maxHr', () {
      expect(calc.zoneFor(100), HrZone.zone1);
    });

    test('zone1 just below 60%', () {
      expect(calc.zoneFor(119), HrZone.zone1);
    });

    test('zone2 at exactly 60%', () {
      expect(calc.zoneFor(120), HrZone.zone2);
    });

    test('zone2 just below 70%', () {
      expect(calc.zoneFor(139), HrZone.zone2);
    });

    test('zone3 at exactly 70%', () {
      expect(calc.zoneFor(140), HrZone.zone3);
    });

    test('zone3 just below 80%', () {
      expect(calc.zoneFor(159), HrZone.zone3);
    });

    test('zone4 at exactly 80%', () {
      expect(calc.zoneFor(160), HrZone.zone4);
    });

    test('zone4 just below 90%', () {
      expect(calc.zoneFor(179), HrZone.zone4);
    });

    test('zone5 at exactly 90%', () {
      expect(calc.zoneFor(180), HrZone.zone5);
    });

    test('zone5 at 100%', () {
      expect(calc.zoneFor(200), HrZone.zone5);
    });

    test('zone5 above maxHr (clamped)', () {
      expect(calc.zoneFor(210), HrZone.zone5);
    });

    test('belowZones when bpm is 0', () {
      expect(calc.zoneFor(0), HrZone.belowZones);
    });

    test('belowZones when bpm is negative', () {
      expect(calc.zoneFor(-10), HrZone.belowZones);
    });

    test('belowZones when maxHr is 0', () {
      const badCalc = HrZoneCalculator(maxHr: 0);
      expect(badCalc.zoneFor(150), HrZone.belowZones);
    });

    test('belowZones when maxHr is negative', () {
      const badCalc = HrZoneCalculator(maxHr: -100);
      expect(badCalc.zoneFor(150), HrZone.belowZones);
    });

    test('fromAge factory creates correct maxHr', () {
      final c30 = HrZoneCalculator.fromAge(30);
      expect(c30.maxHr, 190);

      final c20 = HrZoneCalculator.fromAge(20);
      expect(c20.maxHr, 200);
    });

    test('bpmRangeFor returns correct ranges', () {
      final r1 = calc.bpmRangeFor(HrZone.zone1);
      expect(r1, isNotNull);
      expect(r1!.low, 100);
      expect(r1.high, 120);

      final r5 = calc.bpmRangeFor(HrZone.zone5);
      expect(r5, isNotNull);
      expect(r5!.low, 180);
      expect(r5.high, 200);
    });

    test('bpmRangeFor returns null for belowZones', () {
      expect(calc.bpmRangeFor(HrZone.belowZones), isNull);
    });

    test('bpmRangeFor returns null when maxHr is 0', () {
      const badCalc = HrZoneCalculator(maxHr: 0);
      expect(badCalc.bpmRangeFor(HrZone.zone3), isNull);
    });

    test('realistic maxHr 190 (age 30)', () {
      const c = HrZoneCalculator(maxHr: 190);
      // 50% = 95, 60% = 114, 70% = 133, 80% = 152, 90% = 171
      expect(c.zoneFor(94), HrZone.belowZones);
      expect(c.zoneFor(95), HrZone.zone1);
      expect(c.zoneFor(114), HrZone.zone2);
      expect(c.zoneFor(133), HrZone.zone3);
      expect(c.zoneFor(152), HrZone.zone4);
      expect(c.zoneFor(171), HrZone.zone5);
    });
  });
}
