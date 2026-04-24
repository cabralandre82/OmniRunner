import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_subscription_invoice_entity.dart';
import 'package:omni_runner/domain/policies/financial_alert_policy.dart';

/// L09-17 — Testes exaustivos da política de alerta financeiro.
///
/// Objetivo: garantir que a regra de urgência é estável e previsível
/// em todos os cenários relevantes, sem depender de hora atual nem
/// de infra Flutter/Supabase.
void main() {
  // "now" fixo pra todos os testes — meio-dia evita confusão com
  // virada de dia quando o teste rodar de madrugada.
  final now = DateTime(2026, 4, 24, 12);

  /// Helper pra montar invoice com valores-default. Simula o que o
  /// PostgREST devolve (string dates).
  AthleteSubscriptionInvoice invoice({
    required String status,
    required DateTime dueDate,
    String? url = 'https://cobranca.example/abc',
  }) {
    return AthleteSubscriptionInvoice.fromJson({
      'id': 'inv-${dueDate.toIso8601String()}-$status',
      'subscription_id': 'sub-1',
      'group_id': 'grp-1',
      'period_month': '2026-04-01',
      'amount_cents': 20000,
      'currency': 'BRL',
      'status': status,
      'due_date':
          '${dueDate.year.toString().padLeft(4, '0')}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
      'external_invoice_url': url,
      'paid_at': status == 'paid' ? '2026-04-03T10:00:00Z' : null,
      'created_at': '2026-04-01T00:00:00Z',
    });
  }

  group('FinancialAlertPolicy.computeAlert — casos triviais', () {
    test('lista vazia retorna null', () {
      expect(FinancialAlertPolicy.computeAlert([], now: now), isNull);
    });

    test('só invoices paid retorna null', () {
      final invoices = [
        invoice(status: 'paid', dueDate: DateTime(2026, 4, 5)),
        invoice(status: 'paid', dueDate: DateTime(2026, 3, 5)),
      ];
      expect(
        FinancialAlertPolicy.computeAlert(invoices, now: now),
        isNull,
      );
    });

    test('só invoices cancelled retorna null', () {
      final invoices = [
        invoice(status: 'cancelled', dueDate: DateTime(2026, 4, 5)),
      ];
      expect(
        FinancialAlertPolicy.computeAlert(invoices, now: now),
        isNull,
      );
    });

    test('pending vencendo daqui a 10 dias retorna null (fora da janela)',
        () {
      final invoices = [
        invoice(status: 'pending', dueDate: DateTime(2026, 5, 4)), // 10 dias
      ];
      expect(
        FinancialAlertPolicy.computeAlert(invoices, now: now),
        isNull,
      );
    });
  });

  group('FinancialAlertPolicy.computeAlert — warning (4..7 dias)', () {
    test('pending em 7 dias → warning', () {
      final invoices = [
        invoice(status: 'pending', dueDate: DateTime(2026, 5, 1)),
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.level, FinancialAlertLevel.warning);
    });

    test('pending em 4 dias → warning (limite superior do danger)', () {
      final invoices = [
        invoice(status: 'pending', dueDate: DateTime(2026, 4, 28)),
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.level, FinancialAlertLevel.warning);
    });

    test('pending em 8 dias → null (fora da janela warning)', () {
      final invoices = [
        invoice(status: 'pending', dueDate: DateTime(2026, 5, 2)),
      ];
      expect(
        FinancialAlertPolicy.computeAlert(invoices, now: now),
        isNull,
      );
    });
  });

  group('FinancialAlertPolicy.computeAlert — danger (0..3 dias)', () {
    test('pending em 3 dias → danger', () {
      final invoices = [
        invoice(status: 'pending', dueDate: DateTime(2026, 4, 27)),
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.level, FinancialAlertLevel.danger);
      expect(result.subtitle, contains('3 dias'));
    });

    test('pending em 1 dia → danger com texto "amanhã"', () {
      final invoices = [
        invoice(status: 'pending', dueDate: DateTime(2026, 4, 25)),
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.level, FinancialAlertLevel.danger);
      expect(result.subtitle, contains('amanhã'));
    });

    test('pending em 0 dias (hoje) → danger com texto "hoje"', () {
      final invoices = [
        invoice(status: 'pending', dueDate: DateTime(2026, 4, 24)),
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.level, FinancialAlertLevel.danger);
      expect(result.subtitle, contains('hoje'));
    });
  });

  group('FinancialAlertPolicy.computeAlert — overdue', () {
    test('overdue → danger com texto de atraso', () {
      final invoices = [
        invoice(status: 'overdue', dueDate: DateTime(2026, 4, 20)), // 4 dias
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.level, FinancialAlertLevel.danger);
      expect(result.title, 'Mensalidade vencida');
      expect(result.subtitle, contains('4 dias'));
    });

    test('overdue vencido há 1 dia → texto "ontem"', () {
      final invoices = [
        invoice(status: 'overdue', dueDate: DateTime(2026, 4, 23)),
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.subtitle, contains('ontem'));
    });
  });

  group('FinancialAlertPolicy.computeAlert — prioridade entre múltiplas', () {
    test('overdue vence pending (mesmo pending em 1 dia)', () {
      final invoices = [
        invoice(status: 'overdue', dueDate: DateTime(2026, 4, 22)), // 2 dias atrás
        invoice(status: 'pending', dueDate: DateTime(2026, 4, 25)), // amanhã
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.title, 'Mensalidade vencida');
    });

    test('entre 2 overdue escolhe a mais atrasada', () {
      final older = invoice(status: 'overdue', dueDate: DateTime(2026, 3, 15));
      final newer = invoice(status: 'overdue', dueDate: DateTime(2026, 4, 20));
      final result = FinancialAlertPolicy.computeAlert(
        [newer, older],
        now: now,
      );
      expect(result, isNotNull);
      // "mais atrasada" = days = now - due mais alto = dueDate mais antiga
      expect(result!.invoice.id, older.id);
    });

    test('entre 2 pending escolhe a de vencimento mais próximo', () {
      final soon = invoice(status: 'pending', dueDate: DateTime(2026, 4, 26));
      final later = invoice(status: 'pending', dueDate: DateTime(2026, 5, 1));
      final result = FinancialAlertPolicy.computeAlert(
        [later, soon],
        now: now,
      );
      expect(result, isNotNull);
      expect(result!.invoice.id, soon.id);
      expect(result.level, FinancialAlertLevel.danger);
    });

    test('mix pending-7d + paid não ignora o pending', () {
      final invoices = [
        invoice(status: 'paid', dueDate: DateTime(2026, 3, 5)),
        invoice(status: 'pending', dueDate: DateTime(2026, 5, 1)),
      ];
      final result = FinancialAlertPolicy.computeAlert(invoices, now: now);
      expect(result, isNotNull);
      expect(result!.level, FinancialAlertLevel.warning);
    });
  });

  group('FinancialAlert.canPayInline', () {
    test('pending com URL → canPayInline true', () {
      final inv = invoice(
        status: 'pending',
        dueDate: DateTime(2026, 4, 27),
      );
      final result =
          FinancialAlertPolicy.computeAlert([inv], now: now);
      expect(result!.canPayInline, true);
    });

    test('pending sem URL → canPayInline false', () {
      final inv = invoice(
        status: 'pending',
        dueDate: DateTime(2026, 4, 27),
        url: null,
      );
      final result =
          FinancialAlertPolicy.computeAlert([inv], now: now);
      expect(result!.canPayInline, false);
    });
  });
}
