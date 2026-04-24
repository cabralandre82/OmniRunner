import 'package:equatable/equatable.dart';

/// L09-16 — Uma linha do histórico de mensalidades do atleta.
///
/// Espelha `public.athlete_subscription_invoices` restrito pela policy
/// `athlete_sub_invoices_athlete_read` (`athlete_user_id = auth.uid()`),
/// criada em L23-09. Todo atleta só vê as próprias invoices.
///
/// A entity é intencionalmente tolerante:
/// - `paidAt` só existe quando `status = 'paid'` (constraint no banco).
/// - `externalInvoiceUrl` pode ser null quando o gateway ainda não
///   respondeu com o link de cobrança — a UI esconde o CTA "Pagar".
/// - `status` fora do conjunto conhecido é normalizado para 'pending'
///   (defensivo contra futuros estados adicionados no servidor antes
///   do client ser atualizado).
class AthleteSubscriptionInvoice extends Equatable {
  const AthleteSubscriptionInvoice({
    required this.id,
    required this.subscriptionId,
    required this.groupId,
    required this.periodMonth,
    required this.amountCents,
    required this.currency,
    required this.status,
    required this.dueDate,
    this.externalInvoiceUrl,
    this.paidAt,
    required this.createdAt,
  });

  final String id;
  final String subscriptionId;
  final String groupId;

  /// Primeiro dia do mês de referência (ex: 2026-04-01 = "Abril/26").
  final DateTime periodMonth;

  final int amountCents;
  final String currency;

  /// 'pending' | 'paid' | 'overdue' | 'cancelled'. Outros valores são
  /// coagidos para 'pending' em [fromJson].
  final String status;

  final DateTime dueDate;

  /// Link de pagamento do gateway (e.g. Asaas checkout). Só presente
  /// quando o gateway já respondeu. UI mostra CTA "Pagar agora"
  /// somente quando esse link não é null E status ∈ {pending, overdue}.
  final String? externalInvoiceUrl;

  final DateTime? paidAt;
  final DateTime createdAt;

  static const _knownStatuses = <String>{
    'pending',
    'paid',
    'overdue',
    'cancelled',
  };

  factory AthleteSubscriptionInvoice.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String?;
    final status = (rawStatus != null && _knownStatuses.contains(rawStatus))
        ? rawStatus
        : 'pending';

    return AthleteSubscriptionInvoice(
      id: json['id'] as String,
      subscriptionId: json['subscription_id'] as String,
      groupId: json['group_id'] as String,
      periodMonth: _parseDate(json['period_month']) ?? DateTime(1970),
      amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String?) ?? 'BRL',
      status: status,
      dueDate: _parseDate(json['due_date']) ?? DateTime(1970),
      externalInvoiceUrl: json['external_invoice_url'] as String?,
      paidAt: _parseDateTime(json['paid_at']),
      createdAt: _parseDateTime(json['created_at']) ?? DateTime(1970),
    );
  }

  /// `DATE` vem como 'YYYY-MM-DD' — `DateTime.parse` interpreta como
  /// meia-noite UTC. Converte pra local pra bater com o relógio do
  /// usuário (evita "apareceu o mês errado" em timezones negativos).
  static DateTime? _parseDate(Object? raw) {
    if (raw is String) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    if (raw is DateTime) return raw.toLocal();
    return null;
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is String) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    if (raw is DateTime) return raw.toLocal();
    return null;
  }

  /// Label pt-BR do status — usado no badge.
  String get statusLabel => switch (status) {
        'pending' => 'Pendente',
        'paid' => 'Paga',
        'overdue' => 'Vencida',
        'cancelled' => 'Cancelada',
        _ => status,
      };

  /// True quando o atleta pode / deve pagar agora: status aberto E
  /// há link de cobrança do gateway. UI usa pra mostrar CTA "Pagar".
  bool get isPayable =>
      (status == 'pending' || status == 'overdue') &&
      (externalInvoiceUrl != null && externalInvoiceUrl!.isNotEmpty);

  bool get isOverdue => status == 'overdue';
  bool get isPaid => status == 'paid';
  bool get isCancelled => status == 'cancelled';

  /// Dias até o vencimento — negativo se já venceu. Calcula em dias
  /// calendarísticos (truncando hora) pra não mostrar "1 dia" em
  /// invoice que vence hoje à tarde se já são 8h da manhã.
  int daysUntilDue({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final due = _dateOnly(dueDate);
    return due.difference(today).inDays;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  List<Object?> get props => [
        id,
        subscriptionId,
        groupId,
        periodMonth,
        amountCents,
        currency,
        status,
        dueDate,
        externalInvoiceUrl,
        paidAt,
        createdAt,
      ];
}
