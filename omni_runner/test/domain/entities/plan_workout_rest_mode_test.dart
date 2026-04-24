import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';

/// L05-28 — PlanWorkoutBlock.restMode sanitization and blockTypeLabel suffix.
///
/// Mirrors the sanitization rules in the portal (TypeScript) and the DB
/// CHECK constraints. Keeps the Flutter client forgiving when a rogue
/// snapshot shows up (legacy, server bug, manual edit) instead of blowing
/// up on the parse.
void main() {
  group('PlanWorkoutBlock.fromJson rest_mode sanitization', () {
    test('valid rest + walk is preserved', () {
      final b = PlanWorkoutBlock.fromJson({
        'order_index': 0,
        'block_type': 'rest',
        'duration_seconds': 120,
        'rest_mode': 'walk',
      });
      expect(b.restMode, 'walk');
    });

    test('valid rest + stand_still is preserved', () {
      final b = PlanWorkoutBlock.fromJson({
        'order_index': 0,
        'block_type': 'rest',
        'duration_seconds': 120,
        'rest_mode': 'stand_still',
      });
      expect(b.restMode, 'stand_still');
    });

    test('valid recovery + jog is preserved', () {
      final b = PlanWorkoutBlock.fromJson({
        'order_index': 0,
        'block_type': 'recovery',
        'duration_seconds': 120,
        'rest_mode': 'jog',
      });
      expect(b.restMode, 'jog');
    });

    test('rest + jog is coerced to null (jog requires recovery)', () {
      final b = PlanWorkoutBlock.fromJson({
        'order_index': 0,
        'block_type': 'rest',
        'duration_seconds': 120,
        'rest_mode': 'jog',
      });
      expect(b.restMode, isNull);
    });

    test('interval + walk is coerced to null (scope violation)', () {
      final b = PlanWorkoutBlock.fromJson({
        'order_index': 0,
        'block_type': 'interval',
        'distance_meters': 400,
        'rest_mode': 'walk',
      });
      expect(b.restMode, isNull);
    });

    test('unknown rest_mode value is coerced to null', () {
      final b = PlanWorkoutBlock.fromJson({
        'order_index': 0,
        'block_type': 'rest',
        'duration_seconds': 120,
        'rest_mode': 'sprinting',
      });
      expect(b.restMode, isNull);
    });

    test('missing rest_mode field stays null (legacy snapshot)', () {
      final b = PlanWorkoutBlock.fromJson({
        'order_index': 0,
        'block_type': 'rest',
        'duration_seconds': 120,
      });
      expect(b.restMode, isNull);
    });
  });

  group('PlanWorkoutBlock.blockTypeLabel suffix', () {
    test('rest + walk renders "Descanso (caminhando)"', () {
      const b = PlanWorkoutBlock(
        orderIndex: 0,
        blockType: 'rest',
        durationSeconds: 120,
        restMode: 'walk',
      );
      expect(b.blockTypeLabel, 'Descanso (caminhando)');
    });

    test('rest + stand_still renders "Descanso (parado)"', () {
      const b = PlanWorkoutBlock(
        orderIndex: 0,
        blockType: 'rest',
        durationSeconds: 120,
        restMode: 'stand_still',
      );
      expect(b.blockTypeLabel, 'Descanso (parado)');
    });

    test('recovery + jog renders "Recuperação (trote)"', () {
      const b = PlanWorkoutBlock(
        orderIndex: 0,
        blockType: 'recovery',
        durationSeconds: 120,
        restMode: 'jog',
      );
      expect(b.blockTypeLabel, 'Recuperação (trote)');
    });

    test('recovery without restMode falls back to plain label', () {
      const b = PlanWorkoutBlock(
        orderIndex: 0,
        blockType: 'recovery',
        durationSeconds: 120,
      );
      expect(b.blockTypeLabel, 'Recuperação');
    });

    test('interval is never suffixed (rest_mode would be sanitized)', () {
      const b = PlanWorkoutBlock(
        orderIndex: 0,
        blockType: 'interval',
        distanceMeters: 400,
      );
      expect(b.blockTypeLabel, 'Intervalo');
    });
  });
}
