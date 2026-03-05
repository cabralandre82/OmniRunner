import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';

void main() {
  group('WorkoutBlockEntity from DB row (simulated)', () {
    WorkoutBlockEntity fromRow(Map<String, dynamic> r) {
      final legacyPace = r['target_pace_seconds_per_km'] as int?;
      return WorkoutBlockEntity(
        id: r['id'] as String,
        templateId: r['template_id'] as String,
        orderIndex: r['order_index'] as int,
        blockType: workoutBlockTypeFromString(r['block_type'] as String),
        durationSeconds: r['duration_seconds'] as int?,
        distanceMeters: r['distance_meters'] as int?,
        targetPaceMinSecPerKm:
            r['target_pace_min_sec_per_km'] as int? ?? legacyPace,
        targetPaceMaxSecPerKm:
            r['target_pace_max_sec_per_km'] as int? ?? legacyPace,
        targetHrZone: r['target_hr_zone'] as int?,
        targetHrMin: r['target_hr_min'] as int?,
        targetHrMax: r['target_hr_max'] as int?,
        rpeTarget: r['rpe_target'] as int?,
        repeatCount: r['repeat_count'] as int?,
        notes: r['notes'] as String?,
      );
    }

    test('parses v2 fields correctly', () {
      final block = fromRow({
        'id': 'b1',
        'template_id': 't1',
        'order_index': 0,
        'block_type': 'interval',
        'duration_seconds': null,
        'distance_meters': 1000,
        'target_pace_seconds_per_km': null,
        'target_pace_min_sec_per_km': 270,
        'target_pace_max_sec_per_km': 300,
        'target_hr_zone': null,
        'target_hr_min': 140,
        'target_hr_max': 165,
        'rpe_target': 7,
        'repeat_count': null,
        'notes': 'Forte',
      });

      expect(block.blockType, WorkoutBlockType.interval);
      expect(block.distanceMeters, 1000);
      expect(block.targetPaceMinSecPerKm, 270);
      expect(block.targetPaceMaxSecPerKm, 300);
      expect(block.targetHrMin, 140);
      expect(block.targetHrMax, 165);
      expect(block.rpeTarget, 7);
      expect(block.notes, 'Forte');
      expect(block.hasPaceRange, true);
      expect(block.hasHrRange, true);
    });

    test('falls back to legacy pace when v2 pace is null', () {
      final block = fromRow({
        'id': 'b2',
        'template_id': 't1',
        'order_index': 1,
        'block_type': 'steady',
        'duration_seconds': 1200,
        'distance_meters': null,
        'target_pace_seconds_per_km': 330,
        'target_pace_min_sec_per_km': null,
        'target_pace_max_sec_per_km': null,
        'target_hr_zone': 3,
        'target_hr_min': null,
        'target_hr_max': null,
        'rpe_target': null,
        'repeat_count': null,
        'notes': null,
      });

      expect(block.targetPaceMinSecPerKm, 330);
      expect(block.targetPaceMaxSecPerKm, 330);
      expect(block.targetHrZone, 3);
      expect(block.hasHrRange, false);
    });

    test('parses repeat block', () {
      final block = fromRow({
        'id': 'b3',
        'template_id': 't1',
        'order_index': 2,
        'block_type': 'repeat',
        'duration_seconds': null,
        'distance_meters': null,
        'target_pace_seconds_per_km': null,
        'target_pace_min_sec_per_km': null,
        'target_pace_max_sec_per_km': null,
        'target_hr_zone': null,
        'target_hr_min': null,
        'target_hr_max': null,
        'rpe_target': null,
        'repeat_count': 5,
        'notes': null,
      });

      expect(block.blockType, WorkoutBlockType.repeat);
      expect(block.repeatCount, 5);
      expect(block.isOpen, true);
      expect(block.totalDistanceMeters, 0);
    });

    test('parses rest block', () {
      final block = fromRow({
        'id': 'b4',
        'template_id': 't1',
        'order_index': 3,
        'block_type': 'rest',
        'duration_seconds': 120,
        'distance_meters': null,
        'target_pace_seconds_per_km': null,
        'target_pace_min_sec_per_km': null,
        'target_pace_max_sec_per_km': null,
        'target_hr_zone': null,
        'target_hr_min': null,
        'target_hr_max': null,
        'rpe_target': null,
        'repeat_count': null,
        'notes': null,
      });

      expect(block.blockType, WorkoutBlockType.rest);
      expect(block.durationSeconds, 120);
      expect(block.isOpen, false);
    });

    test('parses open block (no duration or distance)', () {
      final block = fromRow({
        'id': 'b5',
        'template_id': 't1',
        'order_index': 4,
        'block_type': 'cooldown',
        'duration_seconds': null,
        'distance_meters': null,
        'target_pace_seconds_per_km': null,
        'target_pace_min_sec_per_km': null,
        'target_pace_max_sec_per_km': null,
        'target_hr_zone': null,
        'target_hr_min': null,
        'target_hr_max': null,
        'rpe_target': null,
        'repeat_count': null,
        'notes': null,
      });

      expect(block.blockType, WorkoutBlockType.cooldown);
      expect(block.isOpen, true);
    });
  });

  group('WorkoutBlockEntity serialization for insert', () {
    test('serializes all v2 fields', () {
      const block = WorkoutBlockEntity(
        id: 'b1',
        templateId: 't1',
        orderIndex: 0,
        blockType: WorkoutBlockType.interval,
        distanceMeters: 1000,
        targetPaceMinSecPerKm: 270,
        targetPaceMaxSecPerKm: 300,
        targetHrMin: 140,
        targetHrMax: 165,
        rpeTarget: 7,
        notes: 'Sprint',
      );

      final map = {
        'id': block.id,
        'template_id': block.templateId,
        'order_index': block.orderIndex,
        'block_type': workoutBlockTypeToString(block.blockType),
        'duration_seconds': block.durationSeconds,
        'distance_meters': block.distanceMeters,
        'target_pace_min_sec_per_km': block.targetPaceMinSecPerKm,
        'target_pace_max_sec_per_km': block.targetPaceMaxSecPerKm,
        'target_hr_zone': block.targetHrZone,
        'target_hr_min': block.targetHrMin,
        'target_hr_max': block.targetHrMax,
        'rpe_target': block.rpeTarget,
        'repeat_count': block.repeatCount,
        'notes': block.notes,
      };

      expect(map['block_type'], 'interval');
      expect(map['target_pace_min_sec_per_km'], 270);
      expect(map['target_pace_max_sec_per_km'], 300);
      expect(map['target_hr_min'], 140);
      expect(map['target_hr_max'], 165);
      expect(map['rpe_target'], 7);
      expect(map['repeat_count'], isNull);
      expect(map['notes'], 'Sprint');
    });

    test('serializes repeat block', () {
      const block = WorkoutBlockEntity(
        id: 'r1',
        templateId: 't1',
        orderIndex: 1,
        blockType: WorkoutBlockType.repeat,
        repeatCount: 8,
      );

      final map = {
        'block_type': workoutBlockTypeToString(block.blockType),
        'repeat_count': block.repeatCount,
      };

      expect(map['block_type'], 'repeat');
      expect(map['repeat_count'], 8);
    });
  });
}
