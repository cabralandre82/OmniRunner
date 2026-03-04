import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';

/// Clearing case from the database.
class _ClearingCase {
  final String id;
  final String fromGroupId;
  final String toGroupId;
  final String fromGroupName;
  final String toGroupName;
  final int tokensTotal;
  final String status;
  final DateTime deadlineAt;
  final DateTime createdAt;

  const _ClearingCase({
    required this.id,
    required this.fromGroupId,
    required this.toGroupId,
    required this.fromGroupName,
    required this.toGroupName,
    required this.tokensTotal,
    required this.status,
    required this.deadlineAt,
    required this.createdAt,
  });
}

/// Staff screen listing all clearing cases for the staff's assessoria.
///
/// Staff can:
/// - See all clearing cases where their group is involved
/// - Confirm sending (from_group) or receiving (to_group)
/// - Open a dispute on OPEN or SENT_CONFIRMED cases
class StaffDisputesScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const StaffDisputesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<StaffDisputesScreen> createState() => _StaffDisputesScreenState();
}

class _StaffDisputesScreenState extends State<StaffDisputesScreen> {
  List<_ClearingCase> _cases = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  Future<void> _loadCases() async {
    setState(() { _loading = true; _error = null; });
    try {
      final db = Supabase.instance.client;
      final data = await db
          .from('clearing_cases')
          .select('*, from_group:coaching_groups!clearing_cases_from_group_id_fkey(name), to_group:coaching_groups!clearing_cases_to_group_id_fkey(name)')
          .or('from_group_id.eq.${widget.groupId},to_group_id.eq.${widget.groupId}')
          .order('created_at', ascending: false)
          .limit(50);

      final parsed = (data as List).map((row) {
        final r = row as Map<String, dynamic>;
        return _ClearingCase(
          id: r['id'] as String,
          fromGroupId: r['from_group_id'] as String,
          toGroupId: r['to_group_id'] as String,
          fromGroupName: (r['from_group'] as Map<String, dynamic>?)?['name'] as String? ?? '?',
          toGroupName: (r['to_group'] as Map<String, dynamic>?)?['name'] as String? ?? '?',
          tokensTotal: r['tokens_total'] as int,
          status: r['status'] as String,
          deadlineAt: DateTime.tryParse(r['deadline_at'] as String? ?? '') ?? DateTime.now(),
          createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList();

      if (mounted) setState(() { _cases = parsed; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar os dados.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmSent(String caseId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'clearing-confirm-sent',
        body: {'case_id': caseId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Envio confirmado com sucesso.')),
        );
      }
      await _loadCases();
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'StaffDisputesScreen', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao confirmar envio. Tente novamente.')),
        );
      }
    }
  }

  Future<void> _confirmReceived(String caseId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'clearing-confirm-received',
        body: {'case_id': caseId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recebimento confirmado. OmniCoins liberados!')),
        );
      }
      await _loadCases();
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'StaffDisputesScreen', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao confirmar recebimento. Tente novamente.')),
        );
      }
    }
  }

  Future<void> _openDispute(String caseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir revisão'),
        content: const Text(
          'Isso sinaliza que há uma divergência neste caso. '
          'A resolução será feita entre as assessorias envolvidas.\n\n'
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'clearing-open-dispute',
        body: {'case_id': caseId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revisão aberta. Resolva com a outra assessoria.')),
        );
      }
      await _loadCases();
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'StaffDisputesScreen', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao abrir revisão. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmações entre assessorias'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error ?? '', onRetry: _loadCases)
              : _cases.isEmpty
                  ? const _EmptyBody()
                  : RefreshIndicator(
                      onRefresh: _loadCases,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(DesignTokens.spacingMd),
                        itemCount: _cases.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _CaseTile(
                          cc: _cases[i],
                          myGroupId: widget.groupId,
                          onConfirmSent: _confirmSent,
                          onConfirmReceived: _confirmReceived,
                          onDispute: _openDispute,
                        ),
                      ),
                    ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Case tile
// ═════════════════════════════════════════════════════════════════════════════

class _CaseTile extends StatelessWidget {
  final _ClearingCase cc;
  final String myGroupId;
  final Future<void> Function(String) onConfirmSent;
  final Future<void> Function(String) onConfirmReceived;
  final Future<void> Function(String) onDispute;

  const _CaseTile({
    required this.cc,
    required this.myGroupId,
    required this.onConfirmSent,
    required this.onConfirmReceived,
    required this.onDispute,
  });

  @override
  Widget build(BuildContext context) {
    final isFrom = cc.fromGroupId == myGroupId;
    final otherName = isFrom ? cc.toGroupName : cc.fromGroupName;
    final config = _statusConfig(cc.status);
    final now = DateTime.now();
    final isExpired = cc.deadlineAt.isBefore(now);
    final remaining = cc.deadlineAt.difference(now);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: config.borderColor),
      ),
      color: config.bgColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(config.icon, size: 20, color: config.iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: config.iconColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingSm, vertical: 3),
                  decoration: BoxDecoration(
                    color: config.iconColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Text(
                    '${cc.tokensTotal} OmniCoins',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: config.iconColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isFrom ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 14,
                  color: isFrom ? DesignTokens.error : DesignTokens.success,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isFrom
                        ? 'Enviar para: $otherName'
                        : 'Receber de: $otherName',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isExpired ? Icons.timer_off_rounded : Icons.timer_outlined,
                  size: 14,
                  color: isExpired ? DesignTokens.error : DesignTokens.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  isExpired
                      ? 'Prazo encerrado'
                      : 'Prazo: ${_formatRemaining(remaining)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isExpired ? DesignTokens.error : DesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _actions(context, isFrom),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, bool isFrom) {
    switch (cc.status) {
      case 'OPEN':
        if (isFrom) {
          return Wrap(spacing: 8, runSpacing: 8, children: [
            _ActionBtn(
              label: 'Confirmar envio',
              icon: Icons.send_rounded,
              color: DesignTokens.primary,
              onTap: () => onConfirmSent(cc.id),
            ),
            _ActionBtn(
              label: 'Abrir revisão',
              icon: Icons.rate_review_outlined,
              color: DesignTokens.warning,
              onTap: () => onDispute(cc.id),
            ),
          ]);
        } else {
          return Wrap(spacing: 8, runSpacing: 8, children: [
            _ActionBtn(
              label: 'Abrir revisão',
              icon: Icons.rate_review_outlined,
              color: DesignTokens.warning,
              onTap: () => onDispute(cc.id),
            ),
          ]);
        }
      case 'SENT_CONFIRMED':
        if (!isFrom) {
          return Wrap(spacing: 8, runSpacing: 8, children: [
            _ActionBtn(
              label: 'Confirmar recebimento',
              icon: Icons.check_circle_outline,
              color: DesignTokens.success,
              onTap: () => onConfirmReceived(cc.id),
            ),
            _ActionBtn(
              label: 'Abrir revisão',
              icon: Icons.rate_review_outlined,
              color: DesignTokens.warning,
              onTap: () => onDispute(cc.id),
            ),
          ]);
        } else {
          return Text(
            'Aguardando a outra assessoria confirmar o recebimento.',
            style: TextStyle(fontSize: 11, color: DesignTokens.textSecondary,
                fontStyle: FontStyle.italic),
          );
        }
      case 'DISPUTED':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Em revisão entre as assessorias.',
              style: TextStyle(fontSize: 11, color: DesignTokens.error,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 4),
            Text(
              'Combine com a outra assessoria por telefone ou '
              'mensagem para alinhar os valores. Quando resolvido, '
              'ambas as partes devem confirmar normalmente.',
              style: TextStyle(fontSize: 11, color: DesignTokens.textSecondary),
            ),
          ],
        );
      case 'PAID_CONFIRMED':
        return Text(
          'Concluído. OmniCoins liberados para os atletas.',
          style: TextStyle(fontSize: 11, color: DesignTokens.success,
              fontStyle: FontStyle.italic),
        );
      case 'EXPIRED':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'O prazo de confirmação expirou.',
              style: TextStyle(fontSize: 11, color: DesignTokens.textSecondary,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 4),
            Text(
              'Entre em contato com a outra assessoria para resolver '
              'a situação. Os OmniCoins dos atletas permanecem '
              'reservados até a resolução manual.',
              style: TextStyle(fontSize: 11, color: DesignTokens.textSecondary),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  static String _formatRemaining(Duration d) {
    if (d.inDays > 0) return '${d.inDays} ${d.inDays == 1 ? "dia" : "dias"}';
    if (d.inHours > 0) return '${d.inHours}h';
    return '${d.inMinutes} min';
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: DesignTokens.spacingSm),
        side: BorderSide(color: color.withAlpha(100)),
        foregroundColor: color,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Status config helper
// ═════════════════════════════════════════════════════════════════════════════

class _StatusConfig {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;
  final String label;

  const _StatusConfig({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
    required this.label,
  });
}

_StatusConfig _statusConfig(String status) => switch (status) {
      'OPEN' => _StatusConfig(
          icon: Icons.hourglass_top_rounded,
          iconColor: DesignTokens.warning,
          bgColor: DesignTokens.warning.withValues(alpha: 0.08),
          borderColor: DesignTokens.warning.withValues(alpha: 0.25),
          label: 'Aguardando confirmação',
        ),
      'SENT_CONFIRMED' => _StatusConfig(
          icon: Icons.send_rounded,
          iconColor: DesignTokens.primary,
          bgColor: DesignTokens.primary.withValues(alpha: 0.08),
          borderColor: DesignTokens.primary.withValues(alpha: 0.25),
          label: 'Envio confirmado',
        ),
      'DISPUTED' => _StatusConfig(
          icon: Icons.rate_review_rounded,
          iconColor: DesignTokens.warning,
          bgColor: DesignTokens.warning.withValues(alpha: 0.08),
          borderColor: DesignTokens.warning.withValues(alpha: 0.25),
          label: 'Em revisão',
        ),
      'PAID_CONFIRMED' => _StatusConfig(
          icon: Icons.check_circle_rounded,
          iconColor: DesignTokens.success,
          bgColor: DesignTokens.success.withValues(alpha: 0.08),
          borderColor: DesignTokens.success.withValues(alpha: 0.25),
          label: 'Concluído',
        ),
      'EXPIRED' => _StatusConfig(
          icon: Icons.schedule_rounded,
          iconColor: DesignTokens.textSecondary,
          bgColor: DesignTokens.surfaceElevated,
          borderColor: DesignTokens.textMuted,
          label: 'Prazo expirado',
        ),
      _ => _StatusConfig(
          icon: Icons.help_outline,
          iconColor: DesignTokens.textSecondary,
          bgColor: DesignTokens.surfaceElevated,
          borderColor: DesignTokens.textMuted,
          label: status,
        ),
    };

// ═════════════════════════════════════════════════════════════════════════════
// Empty and error states
// ═════════════════════════════════════════════════════════════════════════════

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.handshake_outlined, size: 48,
                color: DesignTokens.textMuted),
            const SizedBox(height: 12),
            Text(
              'Nenhuma confirmação pendente',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Quando houver desafios entre assessorias diferentes, '
              'as confirmações aparecerão aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: DesignTokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// _ErrorBody removed — replaced by ErrorState from error_state.dart
