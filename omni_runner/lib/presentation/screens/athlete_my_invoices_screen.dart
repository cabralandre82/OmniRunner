import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/data/services/athlete_subscription_invoice_service.dart';
import 'package:omni_runner/domain/entities/athlete_subscription_invoice_entity.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';
import 'package:omni_runner/presentation/widgets/state_widgets.dart';

/// L09-16 — Tela "Minhas mensalidades".
///
/// Consome `AthleteSubscriptionInvoiceService` (que lê
/// `athlete_subscription_invoices` filtrado por RLS a `auth.uid()`) e
/// exibe:
///
/// 1. **Card de destaque** no topo com a invoice aberta mais próxima
///    do vencimento (pending/overdue). CTA "Pagar agora" abre o link
///    de cobrança do gateway (externalInvoiceUrl) em navegador
///    externo, se disponível.
/// 2. **Histórico** — lista das mensalidades do ano (pagas, canceladas
///    e vencidas passadas), ordenadas do mais recente para o mais
///    antigo.
///
/// Sempre que possível a UI mostra ao atleta o que ele precisa saber
/// SEM ter que perguntar para o coach: status, valor, quando vence /
/// venceu / pagou.
class AthleteMyInvoicesScreen extends StatefulWidget {
  const AthleteMyInvoicesScreen({super.key});

  @override
  State<AthleteMyInvoicesScreen> createState() =>
      _AthleteMyInvoicesScreenState();
}

class _AthleteMyInvoicesScreenState extends State<AthleteMyInvoicesScreen> {
  List<AthleteSubscriptionInvoice> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = sl<UserIdentityProvider>().userId;
      final rows =
          await sl<AthleteSubscriptionInvoiceService>().listMyInvoices(
        athleteUserId: uid,
      );
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.error(
        'Erro ao carregar minhas mensalidades',
        tag: 'MyInvoices',
        error: e,
        stack: stack,
      );
      if (!mounted) return;
      setState(() {
        _error = ErrorMessages.humanize(e);
        _loading = false;
      });
    }
  }

  /// A invoice de destaque é a mais próxima do vencimento entre as
  /// abertas (pending/overdue). Se não houver aberta, mostra null —
  /// UI cai no histórico direto.
  AthleteSubscriptionInvoice? _highlightInvoice() {
    final open = _items
        .where((i) => i.status == 'pending' || i.status == 'overdue')
        .toList();
    if (open.isEmpty) return null;
    open.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return open.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas mensalidades'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoadingState();
    }
    if (_error != null) {
      return ErrorState(
        message: _error ?? '',
        onRetry: _loadItems,
      );
    }
    if (_items.isEmpty) {
      return const AppEmptyState(
        message:
            'Você ainda não tem mensalidades registradas.\n\n'
            'Se você faz parte de uma assessoria com cobrança ativa, '
            'peça ao seu coach para iniciar sua assinatura.',
        icon: Icons.receipt_long_outlined,
      );
    }

    final highlight = _highlightInvoice();
    final history = _items.where((i) => i != highlight).toList();

    return RefreshIndicator(
      onRefresh: _loadItems,
      child: ListView(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spacingSm,
          horizontal: DesignTokens.spacingMd,
        ),
        children: [
          if (highlight != null) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: DesignTokens.spacingXs,
                bottom: DesignTokens.spacingSm,
              ),
              child: Text(
                'Próxima mensalidade',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            _HighlightCard(
              invoice: highlight,
              onPay: () => _openPaymentUrl(highlight.externalInvoiceUrl!),
            ),
            const SizedBox(height: DesignTokens.spacingLg),
          ],
          if (history.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(
                bottom: DesignTokens.spacingSm,
              ),
              child: Text(
                highlight != null ? 'Histórico' : 'Mensalidades',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            ...history.map(
              (invoice) => _HistoryCard(
                invoice: invoice,
                onPay: invoice.isPayable
                    ? () => _openPaymentUrl(invoice.externalInvoiceUrl!)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openPaymentUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link de pagamento inválido.')),
      );
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível abrir o link de pagamento. '
              'Tente copiar e colar no navegador.',
            ),
          ),
        );
      }
    } on Object catch (e, stack) {
      AppLogger.error(
        'Falha ao abrir link de pagamento',
        tag: 'MyInvoices',
        error: e,
        stack: stack,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir cobrança: ${e.toString()}')),
      );
    }
  }
}

// ════════════════════════════════════════════════════════════════════
// Helpers de formatação e cor
// ════════════════════════════════════════════════════════════════════

String _formatCents(int cents, String currency) {
  final value = cents / 100.0;
  try {
    return NumberFormat.simpleCurrency(locale: 'pt_BR', name: currency)
        .format(value);
  } on Object {
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}

String _formatPeriod(DateTime period) {
  return DateFormat('MMMM/yy', 'pt_BR').format(period);
}

String _formatDate(DateTime d) =>
    DateFormat('dd/MM/yyyy', 'pt_BR').format(d);

/// "vence em 11 dias" / "venceu há 3 dias" / "vence hoje".
String _humanDueRelative(AthleteSubscriptionInvoice invoice) {
  final days = invoice.daysUntilDue();
  if (invoice.isPaid) {
    if (invoice.paidAt != null) {
      return 'Paga em ${_formatDate(invoice.paidAt!)}';
    }
    return 'Paga';
  }
  if (invoice.isCancelled) return 'Cancelada';
  if (days == 0) return 'Vence hoje';
  if (days > 0) {
    return days == 1 ? 'Vence amanhã' : 'Vence em $days dias';
  }
  final past = -days;
  return past == 1 ? 'Venceu ontem' : 'Venceu há $past dias';
}

Color _statusColor(AthleteSubscriptionInvoice invoice) {
  switch (invoice.status) {
    case 'paid':
      return DesignTokens.success;
    case 'overdue':
      return DesignTokens.error;
    case 'cancelled':
      return DesignTokens.textSecondary;
    case 'pending':
    default:
      return DesignTokens.warning;
  }
}

// ════════════════════════════════════════════════════════════════════
// Cards
// ════════════════════════════════════════════════════════════════════

/// Card de destaque com a próxima invoice aberta. Mostra o CTA
/// "Pagar agora" quando há `external_invoice_url`.
class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.invoice, required this.onPay});

  final AthleteSubscriptionInvoice invoice;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _statusColor(invoice);

    return Card(
      margin: EdgeInsets.zero,
      color: isDark ? DesignTokens.surface : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatPeriod(invoice.periodMonth),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusBadge(label: invoice.statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              _formatCents(invoice.amountCents, invoice.currency),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            _InfoRow(
              icon: Icons.event,
              label: '${_humanDueRelative(invoice)} · '
                  'vencimento ${_formatDate(invoice.dueDate)}',
              color: statusColor,
            ),
            if (invoice.isPayable) ...[
              const SizedBox(height: DesignTokens.spacingMd),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Pagar agora'),
                ),
              ),
            ] else if (invoice.status == 'pending' ||
                invoice.status == 'overdue') ...[
              const SizedBox(height: DesignTokens.spacingSm),
              Container(
                padding: const EdgeInsets.all(DesignTokens.spacingSm),
                decoration: BoxDecoration(
                  color: DesignTokens.info.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: DesignTokens.info,
                    ),
                    const SizedBox(width: DesignTokens.spacingXs),
                    Expanded(
                      child: Text(
                        'Link de pagamento ainda não disponível. '
                        'Peça ao seu coach para enviar.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: DesignTokens.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Card compacto usado no histórico e nas mensalidades fora do
/// destaque.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.invoice, this.onPay});

  final AthleteSubscriptionInvoice invoice;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _statusColor(invoice);

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      color: isDark ? DesignTokens.surface : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatPeriod(invoice.periodMonth),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusBadge(label: invoice.statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            _InfoRow(
              icon: Icons.payments_outlined,
              label: _formatCents(invoice.amountCents, invoice.currency),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            _InfoRow(
              icon: Icons.event,
              label: _humanDueRelative(invoice),
              color: statusColor,
            ),
            if (onPay != null) ...[
              const SizedBox(height: DesignTokens.spacingSm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Pagar agora'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingSm,
        vertical: DesignTokens.spacingXs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 14, color: effectiveColor),
        const SizedBox(width: DesignTokens.spacingXs),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: effectiveColor),
          ),
        ),
      ],
    );
  }
}
