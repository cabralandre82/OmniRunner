import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/athlete_workout_export_entity.dart';

/// L05-29 — Leitura do histórico de `.fit` para o atleta logado.
///
/// Fonte: `public.coaching_workout_export_log` com RLS
/// `athlete_export_log_select_own` (criada em L05-26). A policy restringe
/// linhas a `actor_user_id = auth.uid()`, então todo atleta só vê os
/// próprios pushes.
///
/// O `.eq('actor_user_id', uid)` abaixo é redundante com a RLS; deixamos
/// explícito por dois motivos:
///   1. Ajuda o planner a usar `idx_export_log_actor (actor_user_id,
///      created_at DESC)`.
///   2. Se um dia a policy for flexibilizada (p.ex. staff suporte
///      passa a ver exports de atletas do grupo), essa tela continua
///      mostrando SÓ o histórico próprio.
class AthleteExportHistoryService {
  AthleteExportHistoryService(this._client);

  final SupabaseClient _client;

  /// Retorna os últimos `limit` exports do atleta, ordenados do mais
  /// recente pro mais antigo. Tolera `PGRST205` (tabela inexistente em
  /// ambientes sem a migration L05-26 aplicada) devolvendo lista vazia
  /// — mesma convenção de [WorkoutDeliveryService.listPublishedItems].
  Future<List<AthleteWorkoutExport>> listMyExports({
    required String athleteUserId,
    int limit = 100,
  }) async {
    try {
      final rows = await _client
          .from('coaching_workout_export_log')
          .select(
            'id, template_id, assignment_id, surface, kind, device_hint, '
            'bytes, error_code, created_at, '
            'coaching_workout_templates(name), '
            'coaching_workout_assignments(scheduled_date)',
          )
          .eq('actor_user_id', athleteUserId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(
        (rows as List).map((r) => Map<String, dynamic>.from(r as Map)),
      ).map(AthleteWorkoutExport.fromJson).toList();
    } on Object catch (e) {
      if (e.toString().contains('PGRST205')) return [];
      rethrow;
    }
  }
}
