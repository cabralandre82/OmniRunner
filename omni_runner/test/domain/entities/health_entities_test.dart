import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/health_step_sample.dart';

void main() {
  group('HealthHrSample', () {
    test('equality by value', () {
      const a = HealthHrSample(bpm: 72, startMs: 1000, endMs: 2000);
      const b = HealthHrSample(bpm: 72, startMs: 1000, endMs: 2000);
      expect(a, equals(b));
    });

    test('inequality when bpm differs', () {
      const a = HealthHrSample(bpm: 72, startMs: 1000, endMs: 2000);
      const b = HealthHrSample(bpm: 80, startMs: 1000, endMs: 2000);
      expect(a, isNot(equals(b)));
    });

    test('inequality when startMs differs', () {
      const a = HealthHrSample(bpm: 72, startMs: 1000, endMs: 2000);
      const b = HealthHrSample(bpm: 72, startMs: 1500, endMs: 2000);
      expect(a, isNot(equals(b)));
    });

    test('inequality when endMs differs', () {
      const a = HealthHrSample(bpm: 72, startMs: 1000, endMs: 2000);
      const b = HealthHrSample(bpm: 72, startMs: 1000, endMs: 3000);
      expect(a, isNot(equals(b)));
    });

    test('props contains all fields', () {
      const s = HealthHrSample(bpm: 120, startMs: 5000, endMs: 6000);
      expect(s.props, [120, 5000, 6000]);
    });
  });

  group('HealthStepSample', () {
    test('equality by value', () {
      const a = HealthStepSample(steps: 150, startMs: 1000, endMs: 2000);
      const b = HealthStepSample(steps: 150, startMs: 1000, endMs: 2000);
      expect(a, equals(b));
    });

    test('inequality when steps differ', () {
      const a = HealthStepSample(steps: 150, startMs: 1000, endMs: 2000);
      const b = HealthStepSample(steps: 200, startMs: 1000, endMs: 2000);
      expect(a, isNot(equals(b)));
    });

    test('inequality when startMs differs', () {
      const a = HealthStepSample(steps: 150, startMs: 1000, endMs: 2000);
      const b = HealthStepSample(steps: 150, startMs: 1500, endMs: 2000);
      expect(a, isNot(equals(b)));
    });

    test('inequality when endMs differs', () {
      const a = HealthStepSample(steps: 150, startMs: 1000, endMs: 2000);
      const b = HealthStepSample(steps: 150, startMs: 1000, endMs: 3000);
      expect(a, isNot(equals(b)));
    });

    test('props contains all fields', () {
      const s = HealthStepSample(steps: 500, startMs: 3000, endMs: 4000);
      expect(s.props, [500, 3000, 4000]);
    });
  });
}
