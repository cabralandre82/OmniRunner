import 'package:omni_runner/domain/entities/athlete_subscription_invoice_entity.dart';

/// L09-17 — Política que decide se um alerta financeiro in-app deve
/// ser mostrado para o atleta logado, e em qual nível de urgência.
///
/// Função pura (sem dependência de Flutter / Supabase / DI) pra ser
/// facilmente testável. Recebe a lista de invoices que o atleta
/// pode ver (via RLS) e devolve o alerta mais urgente — ou null
/// quando nada precisa ser mostrado.
///
/// A regra de urgência (ordem de prioridade):
///
///   1. **danger** — há pelo menos uma invoice `overdue`. Escolhe
///      a com mais dias de atraso (mais urgente).
///   2. **danger** — há invoice `pending` vencendo em até 3 dias
///      (`daysUntilDue <= 3`). Escolhe a mais próxima.
///   3. **warning** — há invoice `pending` vencendo em até 7 dias
///      (`daysUntilDue <= 7`). Escolhe a mais próxima.
///   4. null — nada pra alertar; banner fica oculto.
///
/// Invoices `paid` e `cancelled` são ignoradas: não geram alerta.
///
/// A janela de 7 dias foi escolhida como padrão porque bate com o
/// ciclo semanal de vida do atleta (próximo longão, próximo payday
/// típico) — tempo suficiente pra agir sem saturar o banner de
/// ruído.
class FinancialAlertPolicy {
  const FinancialAlertPolicy._();

  /// Janela "atenção" (amarelo). Invoices pending vencendo em até
  /// [warningWindowDays] aparecem como warning.
  static const int warningWindowDays = 7;

  /// Janela "urgente" (vermelho). Invoices pending vencendo em até
  /// [dangerWindowDays] aparecem como danger (sobrepõe warning).
  static const int dangerWindowDays = 3;

  /// Calcula o alerta mais urgente para o atleta. Retorna null
  /// quando nenhum alerta se aplica (lista vazia, só pagas,
  /// só canceladas, só vencendo daqui a mais de 7 dias).
  ///
  /// [now] é injetável pra testar sem flakiness em viradas de dia.
  static FinancialAlert? computeAlert(
    List<AthleteSubscriptionInvoice> invoices, {
    DateTime? now,
  }) {
    if (invoices.isEmpty) return null;

    final overdue = invoices.where((i) => i.isOverdue).toList();
    if (overdue.isNotEmpty) {
      overdue.sort(
        (a, b) => a.daysUntilDue(now: now).compareTo(b.daysUntilDue(now: now)),
      );
      final most = overdue.first;
      final daysLate = -most.daysUntilDue(now: now);
      return FinancialAlert(
        level: FinancialAlertLevel.danger,
        invoice: most,
        title: 'Mensalidade vencida',
        subtitle: daysLate == 0
            ? 'Sua mensalidade venceu hoje. Toque para pagar.'
            : daysLate == 1
                ? 'Sua mensalidade venceu ontem. Toque para pagar.'
                : 'Sua mensalidade está vencida há $daysLate dias. '
                    'Toque para pagar.',
      );
    }

    final pending = invoices
        .where((i) => i.status == 'pending' && i.daysUntilDue(now: now) >= 0)
        .toList();
    if (pending.isEmpty) return null;

    pending.sort(
      (a, b) => a.daysUntilDue(now: now).compareTo(b.daysUntilDue(now: now)),
    );
    final closest = pending.first;
    final days = closest.daysUntilDue(now: now);

    if (days <= dangerWindowDays) {
      return FinancialAlert(
        level: FinancialAlertLevel.danger,
        invoice: closest,
        title: 'Mensalidade vence em breve',
        subtitle: days == 0
            ? 'Sua mensalidade vence hoje. Toque para pagar.'
            : days == 1
                ? 'Sua mensalidade vence amanhã. Toque para pagar.'
                : 'Sua mensalidade vence em $days dias. '
                    'Toque para pagar.',
      );
    }

    if (days <= warningWindowDays) {
      return FinancialAlert(
        level: FinancialAlertLevel.warning,
        invoice: closest,
        title: 'Mensalidade se aproximando',
        subtitle: 'Sua mensalidade vence em $days dias. '
            'Toque para ver ou pagar.',
      );
    }

    return null;
  }
}

/// Um alerta pronto pra renderização. Campos já estão em pt-BR e em
/// formato de banner (título curto + subtítulo explicativo).
class FinancialAlert {
  const FinancialAlert({
    required this.level,
    required this.invoice,
    required this.title,
    required this.subtitle,
  });

  final FinancialAlertLevel level;
  final AthleteSubscriptionInvoice invoice;
  final String title;
  final String subtitle;

  /// True quando o banner deve mostrar CTA "Pagar agora" — caso
  /// contrário o CTA cai pra "Ver detalhes".
  bool get canPayInline => invoice.isPayable;
}

enum FinancialAlertLevel {
  /// Amarelo — invoice vencendo dentro da janela de atenção (3-7d).
  warning,

  /// Vermelho — invoice vencendo em 0-3d ou já vencida.
  danger,
}
