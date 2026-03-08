import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/data/services/workout_delivery_service.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/presentation/widgets/state_widgets.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';

class AthleteDeliveryScreen extends StatefulWidget {
  const AthleteDeliveryScreen({super.key});

  @override
  State<AthleteDeliveryScreen> createState() => _AthleteDeliveryScreenState();
}

class _AthleteDeliveryScreenState extends State<AthleteDeliveryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final _confirmingIds = <String>{};

  static const _failureReasons = [
    'Não sincronizou',
    'Treino diferente',
    'Erro no relógio',
    'Outro',
  ];

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
      final rows = await sl<WorkoutDeliveryService>().listPublishedItems(uid);

      if (mounted) {
        setState(() {
          _items = rows;
          _loading = false;
        });
      }
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao carregar entregas pendentes',
        tag: 'DeliveryScreen',
        error: e,
        stack: stack,
      );
      if (mounted) {
        setState(() {
          _error = ErrorMessages.humanize(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmItem(String itemId, String result,
      {String? reason}) async {
    if (_confirmingIds.contains(itemId)) return;
    setState(() => _confirmingIds.add(itemId));
    try {
      await sl<WorkoutDeliveryService>().confirmItem(
        itemId: itemId,
        result: result,
        reason: reason,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result == 'confirmed'
              ? 'Entrega confirmada!'
              : 'Falha registrada.'),
        ),
      );
      _loadItems();
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao confirmar entrega',
        tag: 'DeliveryScreen',
        error: e,
        stack: stack,
      );
      if (mounted) {
        setState(() => _confirmingIds.remove(itemId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.humanize(e))),
        );
      }
    }
  }

  Future<void> _showFailureDialog(String itemId) async {
    String? selected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Motivo da falha'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _failureReasons
                .map((r) => RadioListTile<String>(
                      title: Text(r),
                      value: r,
                      groupValue: selected,
                      onChanged: (v) => setDialogState(() => selected = v),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: DesignTokens.error,
              ),
              child: const Text('Confirmar falha'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && selected != null) {
      _confirmItem(itemId, 'failed', reason: selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entregas Pendentes'),
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
        message: 'Nenhuma entrega pendente',
        icon: Icons.check_circle_outline,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadItems,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spacingSm,
          horizontal: DesignTokens.spacingMd,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) => _buildItemCard(_items[index]),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final itemId = item['id'] as String;
    final payload = item['export_payload'] as Map<String, dynamic>? ?? {};
    final templateName =
        (payload['template_name'] as String?) ?? 'Treino';
    final scheduledDate = payload['scheduled_date'] as String?;
    final status = (item['status'] as String?) ?? '';
    final isConfirming = _confirmingIds.contains(itemId);

    String dateLabel = '';
    if (scheduledDate != null) {
      try {
        final dt = DateTime.parse(scheduledDate);
        dateLabel = DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);
      } catch (_) {
        dateLabel = scheduledDate;
      }
    }

    final statusColor = switch (status) {
      'published' => DesignTokens.info,
      'confirmed' => DesignTokens.success,
      'failed' => DesignTokens.error,
      _ => DesignTokens.textMuted,
    };
    final statusLabel = switch (status) {
      'published' => 'Pendente',
      'confirmed' => 'Confirmado',
      'failed' => 'Falhou',
      _ => status,
    };

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
                    templateName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: DesignTokens.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingSm,
                    vertical: DesignTokens.spacingXs,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (dateLabel.isNotEmpty) ...[
              const SizedBox(height: DesignTokens.spacingSm),
              Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 14, color: DesignTokens.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    dateLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: DesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: DesignTokens.spacingMd),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isConfirming
                        ? null
                        : () => _confirmItem(itemId, 'confirmed'),
                    icon: isConfirming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.watch, size: 18),
                    label: const Text('Apareceu no relógio'),
                    style: FilledButton.styleFrom(
                      backgroundColor: DesignTokens.success,
                      padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.spacingSm),
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacingSm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        isConfirming ? null : () => _showFailureDialog(itemId),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Não apareceu'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DesignTokens.error,
                      side: const BorderSide(color: DesignTokens.error),
                      padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.spacingSm),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
