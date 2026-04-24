import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/data/services/athlete_subscription_invoice_service.dart';
import 'package:omni_runner/domain/policies/financial_alert_policy.dart';

/// L09-17 — Banner in-app que aparece no dashboard do atleta quando
/// há invoice vencendo em até 7 dias ou vencida.
///
/// Usa [FinancialAlertPolicy] para decidir o que exibir. Falhas de
/// rede / RLS / tabela inexistente degradam silenciosamente para
/// banner oculto — NUNCA quebram o dashboard.
///
/// Em modo demo ou sem Supabase configurado, o banner não renderiza
/// nada (zero overhead).
///
/// Posicionamento esperado: topo do dashboard, acima das dicas /
/// primeiros passos, para atenção imediata sem necessidade de
/// rolar.
class FinancialAlertBanner extends StatefulWidget {
  const FinancialAlertBanner({super.key});

  @override
  State<FinancialAlertBanner> createState() => _FinancialAlertBannerState();
}

class _FinancialAlertBannerState extends State<FinancialAlertBanner> {
  FinancialAlert? _alert;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAlert();
  }

  Future<void> _loadAlert() async {
    if (AppConfig.demoMode || !AppConfig.isSupabaseReady) {
      if (mounted) setState(() => _loaded = true);
      return;
    }

    try {
      final uid = sl<UserIdentityProvider>().userId;
      // Limite baixo: banner só precisa saber das invoices recentes.
      // Pegar 6 meses já cobre qualquer "ainda está overdue" sem
      // baixar histórico inteiro só pra exibir um banner.
      final invoices =
          await sl<AthleteSubscriptionInvoiceService>().listMyInvoices(
        athleteUserId: uid,
        limit: 6,
      );
      final alert = FinancialAlertPolicy.computeAlert(invoices);
      if (!mounted) return;
      setState(() {
        _alert = alert;
        _loaded = true;
      });
    } on Object catch (e) {
      // Silenciosamente degrada pra banner oculto. Não queremos que
      // um erro de rede / RLS / tabela ausente quebre o dashboard.
      AppLogger.warn(
        'Falha silenciosa ao calcular alerta financeiro',
        tag: 'FinancialAlertBanner',
        error: e,
      );
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Até a primeira resposta chegar, ocupa zero espaço pra evitar
    // layout shift no dashboard.
    if (!_loaded || _alert == null) return const SizedBox.shrink();
    return _AlertCard(alert: _alert!);
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final FinancialAlert alert;

  Color get _color => switch (alert.level) {
        FinancialAlertLevel.danger => DesignTokens.error,
        FinancialAlertLevel.warning => DesignTokens.warning,
      };

  IconData get _icon => switch (alert.level) {
        FinancialAlertLevel.danger => Icons.error_outline,
        FinancialAlertLevel.warning => Icons.schedule,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: Card(
        margin: EdgeInsets.zero,
        color: color.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          onTap: () => context.push(AppRoutes.myInvoices),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: Row(
              children: [
                Icon(_icon, color: color, size: 28),
                const SizedBox(width: DesignTokens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text(
                        alert.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
