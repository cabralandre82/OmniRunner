import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_subscription_invoice_entity.dart';

/// L09-16 — AthleteSubscriptionInvoice.fromJson parsing + getters.
///
/// Cobre os shapes que o PostgREST do Supabase devolve em produção:
///   - row completa (status paid com paid_at);
///   - row pending sem paid_at;
///   - status desconhecido → coage para 'pending';
///   - amount_cents como int E como double;
///   - external_invoice_url null → isPayable false;
///   - getters derivados (isPayable, isOverdue, daysUntilDue,
///     statusLabel).
void main() {
  group('AthleteSubscriptionInvoice.fromJson', () {
    test('parses full paid row', () {
      final inv = AthleteSubscriptionInvoice.fromJson({
        'id': 'inv-1',
        'subscription_id': 'sub-1',
        'group_id': 'grp-1',
        'period_month': '2026-03-01',
        'amount_cents': 20000,
        'currency': 'BRL',
        'status': 'paid',
        'due_date': '2026-03-05',
        'external_invoice_url': 'https://cobranca.asaas.com/c/abc',
        'paid_at': '2026-03-03T10:15:00Z',
        'created_at': '2026-03-01T00:00:00Z',
      });

      expect(inv.id, 'inv-1');
      expect(inv.subscriptionId, 'sub-1');
      expect(inv.groupId, 'grp-1');
      expect(inv.periodMonth.year, 2026);
      expect(inv.periodMonth.month, 3);
      expect(inv.amountCents, 20000);
      expect(inv.currency, 'BRL');
      expect(inv.status, 'paid');
      expect(inv.dueDate.day, 5);
      expect(inv.externalInvoiceUrl, 'https://cobranca.asaas.com/c/abc');
      expect(inv.paidAt, isNotNull);
      expect(inv.isPaid, true);
      expect(inv.isPayable, false); // paid não é payable
      expect(inv.statusLabel, 'Paga');
    });

    test('parses pending row without paid_at', () {
      final inv = AthleteSubscriptionInvoice.fromJson({
        'id': 'inv-2',
        'subscription_id': 'sub-1',
        'group_id': 'grp-1',
        'period_month': '2026-04-01',
        'amount_cents': 20000,
        'currency': 'BRL',
        'status': 'pending',
        'due_date': '2026-04-05',
        'external_invoice_url': 'https://cobranca.asaas.com/c/xyz',
        'paid_at': null,
        'created_at': '2026-04-01T00:00:00Z',
      });

      expect(inv.status, 'pending');
      expect(inv.paidAt, isNull);
      expect(inv.isPaid, false);
      expect(inv.isOverdue, false);
      expect(inv.isCancelled, false);
      expect(inv.isPayable, true); // pending + url → payable
      expect(inv.statusLabel, 'Pendente');
    });

    test('parses overdue row', () {
      final inv = AthleteSubscriptionInvoice.fromJson({
        'id': 'inv-3',
        'subscription_id': 'sub-1',
        'group_id': 'grp-1',
        'period_month': '2026-02-01',
        'amount_cents': 20000,
        'currency': 'BRL',
        'status': 'overdue',
        'due_date': '2026-02-05',
        'external_invoice_url': 'https://cobranca.asaas.com/c/old',
        'paid_at': null,
        'created_at': '2026-02-01T00:00:00Z',
      });

      expect(inv.status, 'overdue');
      expect(inv.isOverdue, true);
      expect(inv.isPayable, true); // overdue + url → payable
      expect(inv.statusLabel, 'Vencida');
    });

    test('parses cancelled row', () {
      final inv = AthleteSubscriptionInvoice.fromJson({
        'id': 'inv-4',
        'subscription_id': 'sub-1',
        'group_id': 'grp-1',
        'period_month': '2026-01-01',
        'amount_cents': 20000,
        'currency': 'BRL',
        'status': 'cancelled',
        'due_date': '2026-01-05',
        'external_invoice_url': null,
        'paid_at': null,
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(inv.status, 'cancelled');
      expect(inv.isCancelled, true);
      expect(inv.isPayable, false);
      expect(inv.statusLabel, 'Cancelada');
    });

    test('coerces unknown status to pending (forward-compat defensive)', () {
      final inv = AthleteSubscriptionInvoice.fromJson({
        'id': 'inv-5',
        'subscription_id': 'sub-1',
        'group_id': 'grp-1',
        'period_month': '2026-04-01',
        'amount_cents': 20000,
        'currency': 'BRL',
        'status': 'disputed', // status que o backend poderia adicionar no futuro
        'due_date': '2026-04-05',
        'external_invoice_url': null,
        'paid_at': null,
        'created_at': '2026-04-01T00:00:00Z',
      });

      expect(inv.status, 'pending');
    });

    test('parses amount_cents as double (PostgREST às vezes devolve num)', () {
      final inv = AthleteSubscriptionInvoice.fromJson({
        'id': 'inv-6',
        'subscription_id': 'sub-1',
        'group_id': 'grp-1',
        'period_month': '2026-04-01',
        'amount_cents': 20000.0,
        'currency': 'BRL',
        'status': 'pending',
        'due_date': '2026-04-05',
        'external_invoice_url': null,
        'paid_at': null,
        'created_at': '2026-04-01T00:00:00Z',
      });

      expect(inv.amountCents, 20000);
    });

    test('isPayable=false when status is pending but url is null', () {
      final inv = AthleteSubscriptionInvoice.fromJson({
        'id': 'inv-7',
        'subscription_id': 'sub-1',
        'group_id': 'grp-1',
        'period_month': '2026-04-01',
        'amount_cents': 20000,
        'currency': 'BRL',
        'status': 'pending',
        'due_date': '2026-04-05',
        'external_invoice_url': null,
        'paid_at': null,
        'created_at': '2026-04-01T00:00:00Z',
      });

      expect(inv.status, 'pending');
      expect(inv.externalInvoiceUrl, isNull);
      expect(inv.isPayable, false); // sem url → não é payable
    });

    test('isPayable=false when url is empty string', () {
      final inv = AthleteSubscriptionInvoice.fromJson({
        'id': 'inv-8',
        'subscription_id': 'sub-1',
        'group_id': 'grp-1',
        'period_month': '2026-04-01',
        'amount_cents': 20000,
        'currency': 'BRL',
        'status': 'pending',
        'due_date': '2026-04-05',
        'external_invoice_url': '',
        'paid_at': null,
        'created_at': '2026-04-01T00:00:00Z',
      });

      expect(inv.isPayable, false);
    });
  });

  group('daysUntilDue', () {
    /// Usa um "now" fixo pra garantir determinismo (evita falha quando
    /// o teste rodar perto da virada do dia).
    final now = DateTime(2026, 4, 24, 10, 30);

    AthleteSubscriptionInvoice inv(String dueIso) {
      return AthleteSubscriptionInvoice.fromJson({
        'id': 'x',
        'subscription_id': 's',
        'group_id': 'g',
        'period_month': '2026-04-01',
        'amount_cents': 10000,
        'currency': 'BRL',
        'status': 'pending',
        'due_date': dueIso,
        'external_invoice_url': null,
        'paid_at': null,
        'created_at': '2026-04-01T00:00:00Z',
      });
    }

    test('positive when due_date is in the future', () {
      expect(inv('2026-05-05').daysUntilDue(now: now), 11);
    });

    test('zero when due_date is today', () {
      expect(inv('2026-04-24').daysUntilDue(now: now), 0);
    });

    test('negative when due_date is in the past', () {
      expect(inv('2026-04-20').daysUntilDue(now: now), -4);
    });
  });
}
