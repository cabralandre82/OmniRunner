import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/services/time_trial_scheduler.dart';
import 'package:omni_runner/domain/value_objects/time_trial_protocol.dart';

void main() {
  const scheduler = TimeTrialScheduler();

  group('TimeTrialScheduler.schedule', () {
    test('emits cycle_type=test for all protocols', () {
      for (final p in TimeTrialProtocol.values) {
        final workout = scheduler.schedule(
          protocol: p,
          scheduledOn: DateTime.utc(2026, 5, 10),
          planId: 'plan-abc',
        );
        expect(workout.cycleType, 'test');
      }
    });

    test('quantises scheduledOn to UTC calendar day', () {
      final workout = scheduler.schedule(
        protocol: TimeTrialProtocol.fiveKm,
        scheduledOn: DateTime.utc(2026, 5, 10, 14, 37, 22),
        planId: 'plan-abc',
      );
      expect(workout.scheduledOn, DateTime.utc(2026, 5, 10));
    });

    test('accepts non-UTC scheduledOn and normalises', () {
      final local = DateTime(2026, 5, 10, 23, 30);
      final workout = scheduler.schedule(
        protocol: TimeTrialProtocol.threeKm,
        scheduledOn: local,
        planId: 'plan-abc',
      );
      expect(workout.scheduledOn.isUtc, isTrue);
    });

    test('carries the protocol kind in time_trial_kind field', () {
      for (final p in TimeTrialProtocol.values) {
        final workout = scheduler.schedule(
          protocol: p,
          scheduledOn: DateTime.utc(2026, 5, 10),
          planId: 'plan-abc',
        );
        final payload = workout.toPlanWorkoutPayload();
        expect(payload['time_trial_kind'], p.kind);
        expect(payload['cycle_type'], 'test');
      }
    });

    test('distance-based protocol sets target_distance_m, not duration', () {
      final workout = scheduler.schedule(
        protocol: TimeTrialProtocol.fiveKm,
        scheduledOn: DateTime.utc(2026, 5, 10),
        planId: 'plan-abc',
      );
      expect(workout.targetDistanceM, 5000);
      expect(workout.targetDurationS, isNull);
    });

    test('duration-based protocol sets target_duration_s, not distance', () {
      final workout = scheduler.schedule(
        protocol: TimeTrialProtocol.thirtyMinute,
        scheduledOn: DateTime.utc(2026, 5, 10),
        planId: 'plan-abc',
      );
      expect(workout.targetDurationS, 1800);
      expect(workout.targetDistanceM, isNull);
    });

    test('title is locale-appropriate per protocol', () {
      expect(
        scheduler
            .schedule(
              protocol: TimeTrialProtocol.threeKm,
              scheduledOn: DateTime.utc(2026, 5, 10),
              planId: 'plan-abc',
            )
            .title,
        'Time trial 3 km',
      );
      expect(
        scheduler
            .schedule(
              protocol: TimeTrialProtocol.thirtyMinute,
              scheduledOn: DateTime.utc(2026, 5, 10),
              planId: 'plan-abc',
            )
            .title,
        'Tempo trial 30 min',
      );
    });

    test('description mentions warmup + cooldown', () {
      for (final p in TimeTrialProtocol.values) {
        final workout = scheduler.schedule(
          protocol: p,
          scheduledOn: DateTime.utc(2026, 5, 10),
          planId: 'plan-abc',
        );
        expect(workout.description.toLowerCase(), contains('aquecimento'));
        expect(workout.description.toLowerCase(), contains('volta à calma'));
      }
    });

    test('coach note is included when provided, absent otherwise', () {
      final withNote = scheduler.schedule(
        protocol: TimeTrialProtocol.fiveKm,
        scheduledOn: DateTime.utc(2026, 5, 10),
        planId: 'plan-abc',
        coachNote: 'Buscar negative split',
      );
      expect(withNote.coachNote, 'Buscar negative split');
      expect(withNote.toPlanWorkoutPayload()['coach_note'],
          'Buscar negative split');

      final noNote = scheduler.schedule(
        protocol: TimeTrialProtocol.fiveKm,
        scheduledOn: DateTime.utc(2026, 5, 10),
        planId: 'plan-abc',
      );
      expect(noNote.coachNote, isNull);
      expect(noNote.toPlanWorkoutPayload().containsKey('coach_note'), isFalse);
    });

    test('rejects empty planId', () {
      expect(
        () => scheduler.schedule(
          protocol: TimeTrialProtocol.fiveKm,
          scheduledOn: DateTime.utc(2026, 5, 10),
          planId: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('payload contains plan_id + scheduled_on as ISO8601', () {
      final workout = scheduler.schedule(
        protocol: TimeTrialProtocol.fiveKm,
        scheduledOn: DateTime.utc(2026, 5, 10),
        planId: 'plan-abc',
      );
      final payload = workout.toPlanWorkoutPayload();
      expect(payload['plan_id'], 'plan-abc');
      expect(payload['scheduled_on'], '2026-05-10T00:00:00.000Z');
    });
  });
}
