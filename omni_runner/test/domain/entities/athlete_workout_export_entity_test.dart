import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_workout_export_entity.dart';

/// L05-29 — AthleteWorkoutExport.fromJson parsing + labels.
///
/// Cobre os shapes que o PostgREST do Supabase devolve em produção:
///   - join embedado como Map (FK para 1);
///   - join embedado como List (FK para N);
///   - join ausente (RLS bloqueou a tabela remota).
void main() {
  group('AthleteWorkoutExport.fromJson', () {
    test('parses full row with both joins as Map', () {
      final e = AthleteWorkoutExport.fromJson({
        'id': 'exp-1',
        'template_id': 'tpl-1',
        'assignment_id': 'asg-1',
        'surface': 'app',
        'kind': 'generated',
        'device_hint': 'garmin',
        'bytes': 1024,
        'error_code': null,
        'created_at': '2026-04-24T14:00:00Z',
        'coaching_workout_templates': {'name': 'Tiros 4x1000m'},
        'coaching_workout_assignments': {
          'scheduled_date': '2026-04-25',
        },
      });

      expect(e.id, 'exp-1');
      expect(e.templateId, 'tpl-1');
      expect(e.assignmentId, 'asg-1');
      expect(e.templateName, 'Tiros 4x1000m');
      expect(e.scheduledDate, isNotNull);
      expect(e.scheduledDate!.year, 2026);
      expect(e.scheduledDate!.month, 4);
      expect(e.scheduledDate!.day, 25);
      expect(e.surface, 'app');
      expect(e.kind, 'generated');
      expect(e.deviceHint, 'garmin');
      expect(e.bytes, 1024);
      expect(e.errorCode, isNull);
    });

    test('parses joins wrapped as a one-element List (postgrest edge case)', () {
      final e = AthleteWorkoutExport.fromJson({
        'id': 'exp-2',
        'template_id': 'tpl-2',
        'assignment_id': 'asg-2',
        'surface': 'app',
        'kind': 'generated',
        'created_at': '2026-04-24T14:00:00Z',
        'coaching_workout_templates': [
          {'name': 'Longão 10km'}
        ],
        'coaching_workout_assignments': [
          {'scheduled_date': '2026-04-26'}
        ],
      });

      expect(e.templateName, 'Longão 10km');
      expect(e.scheduledDate!.day, 26);
    });

    test('nullable joins do not blow up', () {
      final e = AthleteWorkoutExport.fromJson({
        'id': 'exp-3',
        'template_id': null,
        'assignment_id': null,
        'surface': 'portal',
        'kind': 'generated',
        'created_at': '2026-04-24T14:00:00Z',
        'coaching_workout_templates': null,
        'coaching_workout_assignments': null,
      });

      expect(e.templateName, isNull);
      expect(e.scheduledDate, isNull);
      expect(e.surface, 'portal');
    });

    test('unknown device_hint is coerced to "other"', () {
      final e = AthleteWorkoutExport.fromJson({
        'id': 'exp-4',
        'surface': 'app',
        'kind': 'generated',
        'device_hint': 'ticwatch-pro-5',
        'created_at': '2026-04-24T14:00:00Z',
      });
      expect(e.deviceHint, 'other');
    });

    test('null device_hint stays null (no forced coercion)', () {
      final e = AthleteWorkoutExport.fromJson({
        'id': 'exp-5',
        'surface': 'app',
        'kind': 'generated',
        'device_hint': null,
        'created_at': '2026-04-24T14:00:00Z',
      });
      expect(e.deviceHint, isNull);
    });

    test('invalid created_at falls back to epoch instead of throwing', () {
      final e = AthleteWorkoutExport.fromJson({
        'id': 'exp-6',
        'surface': 'app',
        'kind': 'generated',
        'created_at': 'not-a-date',
      });
      expect(e.createdAt.millisecondsSinceEpoch, 0);
    });

    test('missing surface defaults to "app" (conservative client fallback)', () {
      final e = AthleteWorkoutExport.fromJson({
        'id': 'exp-7',
        'kind': 'generated',
        'created_at': '2026-04-24T14:00:00Z',
      });
      expect(e.surface, 'app');
    });
  });

  group('AthleteWorkoutExport labels', () {
    test('kindLabel in pt-BR for each known kind', () {
      AthleteWorkoutExport mk(String kind) => AthleteWorkoutExport.fromJson({
            'id': 'x',
            'surface': 'app',
            'kind': kind,
            'created_at': '2026-04-24T14:00:00Z',
          });

      expect(mk('generated').kindLabel, 'Enviado');
      expect(mk('shared').kindLabel, 'Compartilhado');
      expect(mk('delivered').kindLabel, 'Entregue no relógio');
      expect(mk('failed').kindLabel, 'Falhou');
    });

    test('deviceLabel in pt-BR for each known hint', () {
      AthleteWorkoutExport mk(String hint) => AthleteWorkoutExport.fromJson({
            'id': 'x',
            'surface': 'app',
            'kind': 'generated',
            'device_hint': hint,
            'created_at': '2026-04-24T14:00:00Z',
          });

      expect(mk('garmin').deviceLabel, 'Garmin');
      expect(mk('coros').deviceLabel, 'Coros');
      expect(mk('polar').deviceLabel, 'Polar');
      expect(mk('apple_watch').deviceLabel, 'Apple Watch');
    });

    test('surfaceLabel differentiates app vs portal', () {
      AthleteWorkoutExport mk(String s) => AthleteWorkoutExport.fromJson({
            'id': 'x',
            'surface': s,
            'kind': 'generated',
            'created_at': '2026-04-24T14:00:00Z',
          });
      expect(mk('app').surfaceLabel, 'Pelo app');
      expect(mk('portal').surfaceLabel, 'Pelo coach');
    });

    test('isFailure/isSuccess invariants', () {
      AthleteWorkoutExport mk(String kind) => AthleteWorkoutExport.fromJson({
            'id': 'x',
            'surface': 'app',
            'kind': kind,
            'created_at': '2026-04-24T14:00:00Z',
          });

      expect(mk('failed').isFailure, isTrue);
      expect(mk('failed').isSuccess, isFalse);

      expect(mk('generated').isSuccess, isTrue);
      expect(mk('shared').isSuccess, isTrue);
      expect(mk('delivered').isSuccess, isTrue);

      expect(mk('generated').isFailure, isFalse);
    });
  });
}
