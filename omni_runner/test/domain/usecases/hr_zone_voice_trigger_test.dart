import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/hr_zone.dart';
import 'package:omni_runner/domain/usecases/hr_zone_voice_trigger.dart';

void main() {
  late HrZoneVoiceTrigger sut;

  // maxHr = 200 → zone boundaries at 100, 120, 140, 160, 180
  const calc = HrZoneCalculator(maxHr: 200);

  setUp(() {
    sut = HrZoneVoiceTrigger(
      calculator: calc,
      cooldownMs: 30000,
      confirmCount: 3,
    );
  });

  group('basic zone change', () {
    test('no alert until confirmCount consecutive readings', () {
      // 2 readings in zone 3 (not enough for confirmCount=3)
      expect(sut.evaluate(bpm: 150, timestampMs: 1000), isNull);
      expect(sut.evaluate(bpm: 150, timestampMs: 2000), isNull);
      expect(sut.currentZone, HrZone.belowZones);
    });

    test('alert after confirmCount consecutive readings in new zone', () {
      // 3 consecutive readings in zone 3
      expect(sut.evaluate(bpm: 150, timestampMs: 1000), isNull);
      expect(sut.evaluate(bpm: 150, timestampMs: 2000), isNull);
      final event = sut.evaluate(bpm: 150, timestampMs: 3000);
      expect(event, isNotNull);
      expect(event!.type, AudioEventType.heartRateAlert);
      expect(event.payload['zone'], 3);
      expect(event.payload['direction'], 'up');
      expect(event.payload['bpm'], 150);
      expect(sut.currentZone, HrZone.zone3);
    });

    test('no alert when staying in same zone', () {
      // Establish zone 3
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      sut.evaluate(bpm: 150, timestampMs: 3000);

      // More readings in zone 3 — no new alert
      expect(sut.evaluate(bpm: 145, timestampMs: 34000), isNull);
      expect(sut.evaluate(bpm: 155, timestampMs: 35000), isNull);
    });
  });

  group('cooldown', () {
    test('suppresses alert within cooldown window', () {
      // Establish zone 3 at t=3000
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      expect(sut.evaluate(bpm: 150, timestampMs: 3000), isNotNull);

      // Move to zone 4 within cooldown (3000 + 30000 = 33000)
      sut.evaluate(bpm: 170, timestampMs: 10000);
      sut.evaluate(bpm: 170, timestampMs: 11000);
      final suppressed = sut.evaluate(bpm: 170, timestampMs: 12000);
      expect(suppressed, isNull, reason: 'cooldown should suppress');
      // Zone should still have changed internally
      expect(sut.currentZone, HrZone.zone4);
    });

    test('allows alert after cooldown expires', () {
      // Establish zone 3 at t=3000
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      expect(sut.evaluate(bpm: 150, timestampMs: 3000), isNotNull);

      // Move to zone 4 after cooldown (3000 + 31000 = 34000)
      sut.evaluate(bpm: 170, timestampMs: 34000);
      sut.evaluate(bpm: 170, timestampMs: 35000);
      final event = sut.evaluate(bpm: 170, timestampMs: 36000);
      expect(event, isNotNull);
      expect(event!.payload['zone'], 4);
    });
  });

  group('hysteresis / confirmCount', () {
    test('single spike does not trigger zone change', () {
      // Establish zone 3
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      sut.evaluate(bpm: 150, timestampMs: 3000);

      // 1 spike into zone 4, then back to zone 3 — after cooldown
      sut.evaluate(bpm: 170, timestampMs: 40000);
      sut.evaluate(bpm: 150, timestampMs: 41000); // back to zone 3
      expect(sut.currentZone, HrZone.zone3, reason: 'spike should not change zone');
    });

    test('oscillation between zones does not trigger', () {
      // Establish zone 3
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      sut.evaluate(bpm: 150, timestampMs: 3000);

      // Oscillate zone3 ↔ zone4 (never 3 consecutive in zone 4) after cooldown
      sut.evaluate(bpm: 170, timestampMs: 40000);
      sut.evaluate(bpm: 170, timestampMs: 41000);
      sut.evaluate(bpm: 150, timestampMs: 42000); // resets pending
      sut.evaluate(bpm: 170, timestampMs: 43000);
      sut.evaluate(bpm: 150, timestampMs: 44000);

      expect(sut.currentZone, HrZone.zone3);
    });

    test('confirmCount=1 triggers immediately', () {
      final instant = HrZoneVoiceTrigger(
        calculator: calc,
        cooldownMs: 0,
        confirmCount: 1,
      );
      final event = instant.evaluate(bpm: 150, timestampMs: 1000);
      expect(event, isNotNull);
      expect(event!.payload['zone'], 3);
    });
  });

  group('direction', () {
    test('going up from zone 2 to zone 4 reports up', () {
      // Establish zone 2
      sut.evaluate(bpm: 130, timestampMs: 1000);
      sut.evaluate(bpm: 130, timestampMs: 2000);
      sut.evaluate(bpm: 130, timestampMs: 3000);

      // Move to zone 4 after cooldown
      sut.evaluate(bpm: 170, timestampMs: 40000);
      sut.evaluate(bpm: 170, timestampMs: 41000);
      final event = sut.evaluate(bpm: 170, timestampMs: 42000);
      expect(event, isNotNull);
      expect(event!.payload['direction'], 'up');
    });

    test('going down from zone 4 to zone 2 reports down', () {
      // Establish zone 4
      sut.evaluate(bpm: 170, timestampMs: 1000);
      sut.evaluate(bpm: 170, timestampMs: 2000);
      sut.evaluate(bpm: 170, timestampMs: 3000);

      // Move to zone 2 after cooldown
      sut.evaluate(bpm: 130, timestampMs: 40000);
      sut.evaluate(bpm: 130, timestampMs: 41000);
      final event = sut.evaluate(bpm: 130, timestampMs: 42000);
      expect(event, isNotNull);
      expect(event!.payload['direction'], 'down');
    });
  });

  group('belowZones transitions', () {
    test('entering belowZones does not produce alert', () {
      // Establish zone 1
      sut.evaluate(bpm: 110, timestampMs: 1000);
      sut.evaluate(bpm: 110, timestampMs: 2000);
      sut.evaluate(bpm: 110, timestampMs: 3000);

      // Drop below zones after cooldown
      sut.evaluate(bpm: 80, timestampMs: 40000);
      sut.evaluate(bpm: 80, timestampMs: 41000);
      final event = sut.evaluate(bpm: 80, timestampMs: 42000);
      expect(event, isNull, reason: 'belowZones should not produce alert');
      expect(sut.currentZone, HrZone.belowZones);
    });

    test('going from belowZones to zone3 produces alert', () {
      // Already starts at belowZones
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      final event = sut.evaluate(bpm: 150, timestampMs: 3000);
      expect(event, isNotNull);
      expect(event!.payload['zone'], 3);
    });
  });

  group('reset', () {
    test('reset clears zone and cooldown state', () {
      // Establish zone 3
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      sut.evaluate(bpm: 150, timestampMs: 3000);
      expect(sut.currentZone, HrZone.zone3);

      sut.reset();
      expect(sut.currentZone, HrZone.belowZones);

      // After reset, first zone entry triggers alert again
      sut.evaluate(bpm: 150, timestampMs: 4000);
      sut.evaluate(bpm: 150, timestampMs: 5000);
      final event = sut.evaluate(bpm: 150, timestampMs: 6000);
      expect(event, isNotNull);
      expect(event!.payload['zone'], 3);
    });
  });

  group('payload completeness', () {
    test('payload contains all required fields', () {
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      final event = sut.evaluate(bpm: 155, timestampMs: 3000);
      expect(event, isNotNull);
      expect(event!.payload['zone'], 3);
      expect(event.payload['zoneName'], isA<String>());
      expect(event.payload['bpm'], 155);
      expect(event.payload['direction'], isIn(['up', 'down']));
      expect(event.payload['maxHr'], 200);
    });

    test('priority is 7 (higher than distance/time, lower than interrupt)', () {
      sut.evaluate(bpm: 150, timestampMs: 1000);
      sut.evaluate(bpm: 150, timestampMs: 2000);
      final event = sut.evaluate(bpm: 150, timestampMs: 3000);
      expect(event!.priority, 7);
    });
  });

  group('edge cases', () {
    test('zero cooldown allows back-to-back alerts', () {
      final noCooldown = HrZoneVoiceTrigger(
        calculator: calc,
        cooldownMs: 0,
        confirmCount: 3,
      );

      // Zone 3
      noCooldown.evaluate(bpm: 150, timestampMs: 1000);
      noCooldown.evaluate(bpm: 150, timestampMs: 2000);
      expect(noCooldown.evaluate(bpm: 150, timestampMs: 3000), isNotNull);

      // Immediately zone 4
      noCooldown.evaluate(bpm: 170, timestampMs: 4000);
      noCooldown.evaluate(bpm: 170, timestampMs: 5000);
      expect(noCooldown.evaluate(bpm: 170, timestampMs: 6000), isNotNull);
    });

    test('calculator accessor returns injected calculator', () {
      expect(sut.calculator.maxHr, 200);
    });
  });
}
