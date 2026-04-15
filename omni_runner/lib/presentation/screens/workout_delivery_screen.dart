import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

/// Full history of workout delivery items for the authenticated athlete.
///
/// Shows all statuses (pending, published, confirmed, failed) with
/// action buttons for published items.
class WorkoutDeliveryScreen extends StatefulWidget {
  const WorkoutDeliveryScreen({super.key});

  @override
  State<WorkoutDeliveryScreen> createState() => _WorkoutDeliveryScreenState();
}

class _WorkoutDeliveryScreenState extends State<WorkoutDeliveryScreen> {
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
      final rows = await sl<SupabaseClient>()
          .from('workout_delivery_items')
          .select()
          .eq('athlete_user_id', uid)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(
            (rows as List).map((r) => Map<String, dynamic>.from(r as Map)),
          );
          _loading = false;
        });
      }
    } on Object catch (e, stack) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('workout_delivery_items')) {
        AppLogger.debug('workout_delivery_items table not available yet', tag: 'WorkoutDelivery');
        if (mounted) setState(() { _items = []; _loading = false; });
        return;
      }
      AppLogger.error(
        'Erro ao carregar entregas',
        tag: 'WorkoutDelivery',
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
      await sl<SupabaseClient>().rpc('fn_athlete_confirm_item', params: {
        'p_item_id': itemId,
        'p_result': result,
        'p_reason': reason,
      });
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
    } on Object catch (e, stack) {
      AppLogger.error(
        'Erro ao confirmar entrega',
        tag: 'WorkoutDelivery',
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
          content: RadioGroup<String>(
            groupValue: selected ?? '',
            onChanged: (v) => setDialogState(() => selected = v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _failureReasons
                  .map((r) => RadioListTile<String>(
                        title: Text(r),
                        value: r,
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed:
                  selected == null ? null : () => Navigator.pop(ctx, true),
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
        title: const Text('Meus Treinos Entregues'),
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
      return Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: ShimmerLoading(
          child: Column(
            children: List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: DesignTokens.textMuted,
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: DesignTokens.spacingMd),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: DesignTokens.spacingLg),
              FilledButton.icon(
                onPressed: _loadItems,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fitness_center,
                  size: 64,
                  color: DesignTokens.textMuted.withValues(alpha: 0.6)),
              const SizedBox(height: DesignTokens.spacingMd),
              Text(
                'Nenhum treino entregue ainda.\n'
                'Sua assessoria publicará treinos aqui.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: DesignTokens.textSecondary,
                    ),
              ),
            ],
          ),
        ),
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
    final status = (item['status'] as String?) ?? 'pending';
    final createdAt = item['created_at'] as String?;
    final payload = item['export_payload'] as Map<String, dynamic>? ?? {};
    final templateName = (payload['template_name'] as String?) ?? 'Treino';
    final isConfirming = _confirmingIds.contains(itemId);

    String dateLabel = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt);
        dateLabel = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dt.toLocal());
      } on Object catch (_) {
        dateLabel = createdAt;
      }
    }

    final statusColor = switch (status) {
      'pending' => DesignTokens.textMuted,
      'published' => DesignTokens.info,
      'confirmed' => DesignTokens.success,
      'failed' => DesignTokens.error,
      _ => DesignTokens.textMuted,
    };
    final statusLabel = switch (status) {
      'pending' => 'Pendente',
      'published' => 'Publicado',
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
            if (status == 'published') ...[
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
                          : const Icon(Icons.check_circle, size: 18),
                      label: const Text('Confirmar'),
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
                      onPressed: isConfirming
                          ? null
                          : () => _showFailureDialog(itemId),
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
          ],
        ),
      ),
    );
  }
}
