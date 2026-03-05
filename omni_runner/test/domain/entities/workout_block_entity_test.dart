import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';

void main() {
  // ── WorkoutBlockType enum ──────────────────────────────────────────────

  group('WorkoutBlockType', () {
    test('has 7 values including rest and repeat', () {
      expect(WorkoutBlockType.values.length, 7);
      expect(WorkoutBlockType.values, contains(WorkoutBlockType.rest));
      expect(WorkoutBlockType.values, contains(WorkoutBlockType.repeat));
    });

    test('toString round-trips all values', () {
      for (final t in WorkoutBlockType.values) {
        final s = workoutBlockTypeToString(t);
        final back = workoutBlockTypeFromString(s);
        expect(back, t, reason: 'round-trip failed for $t');
      }
    });

    test('fromString defaults to steady for unknown', () {
      expect(workoutBlockTypeFromString('invalid'), WorkoutBlockType.steady);
      expect(workoutBlockTypeFromString(''), WorkoutBlockType.steady);
    });

    test('labels return correct Portuguese strings', () {
      expect(workoutBlockTypeLabel(WorkoutBlockType.warmup), 'Aquecimento');
      expect(workoutBlockTypeLabel(WorkoutBlockType.interval), 'Intervalo');
      expect(workoutBlockTypeLabel(WorkoutBlockType.recovery), 'Recuperação');
      expect(workoutBlockTypeLabel(WorkoutBlockType.cooldown), 'Desaquecimento');
      expect(workoutBlockTypeLabel(WorkoutBlockType.steady), 'Contínuo');
      expect(workoutBlockTypeLabel(WorkoutBlockType.rest), 'Descanso');
      expect(workoutBlockTypeLabel(WorkoutBlockType.repeat), 'Repetir');
    });

    test('every value has a non-empty label', () {
      for (final t in WorkoutBlockType.values) {
        expect(workoutBlockTypeLabel(t).isNotEmpty, true);
      }
    });
  });

  // ── WorkoutBlockEntity ─────────────────────────────────────────────────

  group('WorkoutBlockEntity', () {
    WorkoutBlockEntity block({
      WorkoutBlockType type = WorkoutBlockType.interval,
      int? durationSeconds,
      int? distanceMeters,
      int? paceMin,
      int? paceMax,
      int? hrZone,
      int? hrMin,
      int? hrMax,
      int? rpe,
      int? repeatCount,
    }) =>
        WorkoutBlockEntity(
          id: 'b1',
          templateId: 't1',
          orderIndex: 0,
          blockType: type,
          durationSeconds: durationSeconds,
          distanceMeters: distanceMeters,
          targetPaceMinSecPerKm: paceMin,
          targetPaceMaxSecPerKm: paceMax,
          targetHrZone: hrZone,
          targetHrMin: hrMin,
          targetHrMax: hrMax,
          rpeTarget: rpe,
          repeatCount: repeatCount,
        );

    test('stores all v2 fields correctly', () {
      final b = block(
        paceMin: 270,
        paceMax: 300,
        hrMin: 140,
        hrMax: 165,
        rpe: 7,
        repeatCount: 5,
        distanceMeters: 1000,
        durationSeconds: 300,
      );

      expect(b.targetPaceMinSecPerKm, 270);
      expect(b.targetPaceMaxSecPerKm, 300);
      expect(b.targetHrMin, 140);
      expect(b.targetHrMax, 165);
      expect(b.rpeTarget, 7);
      expect(b.repeatCount, 5);
      expect(b.distanceMeters, 1000);
      expect(b.durationSeconds, 300);
    });

    group('isOpen', () {
      test('true when no duration and no distance', () {
        expect(block().isOpen, true);
      });

      test('false when duration set', () {
        expect(block(durationSeconds: 300).isOpen, false);
      });

      test('false when distance set', () {
        expect(block(distanceMeters: 1000).isOpen, false);
      });
    });

    group('hasPaceRange', () {
      test('true when both min and max pace set', () {
        expect(block(paceMin: 270, paceMax: 300).hasPaceRange, true);
      });

      test('false when only min pace set', () {
        expect(block(paceMin: 270).hasPaceRange, false);
      });

      test('false when neither set', () {
        expect(block().hasPaceRange, false);
      });
    });

    group('hasHrRange', () {
      test('true when both min and max HR set', () {
        expect(block(hrMin: 130, hrMax: 160).hasHrRange, true);
      });

      test('false when only max HR set', () {
        expect(block(hrMax: 160).hasHrRange, false);
      });

      test('false when neither set', () {
        expect(block().hasHrRange, false);
      });
    });

    group('totalDistanceMeters', () {
      test('returns distance for non-repeat block', () {
        expect(block(distanceMeters: 1000).totalDistanceMeters, 1000);
      });

      test('returns 0 for repeat block regardless of distance', () {
        expect(
          block(type: WorkoutBlockType.repeat, distanceMeters: 1000)
              .totalDistanceMeters,
          0,
        );
      });

      test('returns 0 when distance is null', () {
        expect(block().totalDistanceMeters, 0);
      });
    });

    group('Equatable props', () {
      test('includes all v2 fields in props', () {
        final b = block(
          paceMin: 270,
          paceMax: 300,
          hrMin: 140,
          hrMax: 165,
          rpe: 7,
          repeatCount: 5,
          distanceMeters: 1000,
          durationSeconds: 300,
        );

        expect(b.props, contains(270));
        expect(b.props, contains(300));
        expect(b.props, contains(140));
        expect(b.props, contains(165));
        expect(b.props, contains(7));
        expect(b.props, contains(5));
      });

      test('two blocks with same fields are equal', () {
        final a = block(paceMin: 270, paceMax: 300, distanceMeters: 1000);
        final b = block(paceMin: 270, paceMax: 300, distanceMeters: 1000);
        expect(a, equals(b));
      });

      test('blocks with different pace range are not equal', () {
        final a = block(paceMin: 270, paceMax: 300);
        final b = block(paceMin: 280, paceMax: 300);
        expect(a, isNot(equals(b)));
      });
    });
  });

  // ── WorkoutTemplateEntity ──────────────────────────────────────────────

  group('WorkoutTemplateEntity', () {
    test('stores blocks list', () {
      final blocks = [
        const WorkoutBlockEntity(
          id: 'b1',
          templateId: 't1',
          orderIndex: 0,
          blockType: WorkoutBlockType.warmup,
          durationSeconds: 600,
        ),
        const WorkoutBlockEntity(
          id: 'b2',
          templateId: 't1',
          orderIndex: 1,
          blockType: WorkoutBlockType.repeat,
          repeatCount: 5,
        ),
        const WorkoutBlockEntity(
          id: 'b3',
          templateId: 't1',
          orderIndex: 2,
          blockType: WorkoutBlockType.interval,
          distanceMeters: 1000,
          targetPaceMinSecPerKm: 270,
          targetPaceMaxSecPerKm: 300,
        ),
        const WorkoutBlockEntity(
          id: 'b4',
          templateId: 't1',
          orderIndex: 3,
          blockType: WorkoutBlockType.rest,
          durationSeconds: 120,
        ),
        const WorkoutBlockEntity(
          id: 'b5',
          templateId: 't1',
          orderIndex: 4,
          blockType: WorkoutBlockType.cooldown,
          durationSeconds: 600,
        ),
      ];

      final template = WorkoutTemplateEntity(
        id: 't1',
        groupId: 'g1',
        name: 'Intervalado 5x1km',
        createdBy: 'u1',
        createdAt: DateTime(2026, 3, 4),
        updatedAt: DateTime(2026, 3, 4),
        blocks: blocks,
      );

      expect(template.blocks.length, 5);
      expect(template.blocks[1].blockType, WorkoutBlockType.repeat);
      expect(template.blocks[1].repeatCount, 5);
      expect(template.blocks[2].hasPaceRange, true);
      expect(template.blocks[3].blockType, WorkoutBlockType.rest);
    });

    test('defaults to empty blocks list', () {
      final template = WorkoutTemplateEntity(
        id: 't1',
        groupId: 'g1',
        name: 'Simples',
        createdBy: 'u1',
        createdAt: DateTime(2026, 3, 4),
        updatedAt: DateTime(2026, 3, 4),
      );

      expect(template.blocks, isEmpty);
    });
  });
}
