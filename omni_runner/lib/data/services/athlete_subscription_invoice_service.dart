import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/athlete_subscription_invoice_entity.dart';

/// L09-16 — Leitura das mensalidades (`athlete_subscription_invoices`)
/// do atleta logado.
///
/// Fonte: `public.athlete_subscription_invoices` com RLS
/// `athlete_sub_invoices_athlete_read` (criada em L23-09). A policy
/// restringe linhas a `athlete_user_id = auth.uid()`, então todo
/// atleta só vê as próprias invoices.
///
/// O `.eq('athlete_user_id', uid)` abaixo é redundante com a RLS;
/// deixamos explícito por dois motivos:
///   1. Ajuda o planner a usar o índice
///      `athlete_sub_invoices_athlete_due_idx` (athlete, due) se ele
///      for criado — hoje o planner cai no composite de
///      `(group_id, period_month DESC)` filtrado.
///   2. Se um dia a policy for flexibilizada (p.ex. staff suporte
///      passa a ver invoices de atletas do grupo), essa tela
///      continua mostrando SÓ o próprio histórico.
class AthleteSubscriptionInvoiceService {
  AthleteSubscriptionInvoiceService(this._client);

  final SupabaseClient _client;

  /// Retorna as últimas `limit` mensalidades do atleta, ordenadas por
  /// `period_month` decrescente (mais recente primeiro). O default de
  /// 24 cobre 2 anos — enough pra qualquer dúvida operacional, sem
  /// paginar.
  ///
  /// Tolera `PGRST205` (tabela inexistente em ambientes sem a
  /// migration L23-09 aplicada) devolvendo lista vazia — mesma
  /// convenção de [AthleteExportHistoryService.listMyExports].
  Future<List<AthleteSubscriptionInvoice>> listMyInvoices({
    required String athleteUserId,
    int limit = 24,
  }) async {
    try {
      final rows = await _client
          .from('athlete_subscription_invoices')
          .select(
            'id, subscription_id, group_id, period_month, amount_cents, '
            'currency, status, due_date, external_invoice_url, paid_at, '
            'created_at',
          )
          .eq('athlete_user_id', athleteUserId)
          .order('period_month', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(
        (rows as List).map((r) => Map<String, dynamic>.from(r as Map)),
      ).map(AthleteSubscriptionInvoice.fromJson).toList();
    } on Object catch (e) {
      if (e.toString().contains('PGRST205')) return [];
      rethrow;
    }
  }
}
