import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/data/services/athlete_export_history_service.dart';
import 'package:omni_runner/domain/entities/athlete_workout_export_entity.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';
import 'package:omni_runner/presentation/widgets/state_widgets.dart';

/// L05-29 — Tela "Meus envios ao relógio".
///
/// Consome `AthleteExportHistoryService` (que lê
/// `coaching_workout_export_log` filtrado por RLS a `auth.uid()`) e
/// exibe um histórico dos últimos `.fit` que o atleta gerou, marcando
/// falhas em vermelho e sucessos em verde.
class AthleteMyExportsScreen extends StatefulWidget {
  const AthleteMyExportsScreen({super.key});

  @override
  State<AthleteMyExportsScreen> createState() => _AthleteMyExportsScreenState();
}

class _AthleteMyExportsScreenState extends State<AthleteMyExportsScreen> {
  List<AthleteWorkoutExport> _items = [];
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
      final rows = await sl<AthleteExportHistoryService>().listMyExports(
        athleteUserId: uid,
      );
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.error(
        'Erro ao carregar histórico de envios',
        tag: 'MyExports',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus envios ao relógio'),
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
            'Você ainda não enviou nenhum treino pro relógio.\n\nQuando enviar, '
            'o histórico aparece aqui.',
        icon: Icons.watch_outlined,
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
        itemBuilder: (context, index) => _ExportCard(export: _items[index]),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.export});

  final AthleteWorkoutExport export;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final statusColor = export.isFailure
        ? DesignTokens.error
        : (export.kind == 'delivered'
            ? DesignTokens.success
            : DesignTokens.info);

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
                    export.templateName ?? 'Treino',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusBadge(label: export.kindLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            _InfoRow(
              icon: Icons.schedule,
              label: _formatWhen(export.createdAt),
            ),
            if (export.deviceLabel != null) ...[
              const SizedBox(height: DesignTokens.spacingXs),
              _InfoRow(
                icon: Icons.watch_outlined,
                label: export.deviceLabel!,
              ),
            ],
            const SizedBox(height: DesignTokens.spacingXs),
            _InfoRow(
              icon: export.surface == 'app' ? Icons.smartphone : Icons.language,
              label: export.surfaceLabel,
            ),
            if (export.scheduledDate != null) ...[
              const SizedBox(height: DesignTokens.spacingXs),
              _InfoRow(
                icon: Icons.event,
                label: 'Agendado para ${_formatDate(export.scheduledDate!)}',
              ),
            ],
            if (export.isFailure && export.errorCode != null) ...[
              const SizedBox(height: DesignTokens.spacingSm),
              Container(
                padding: const EdgeInsets.all(DesignTokens.spacingSm),
                decoration: BoxDecoration(
                  color: DesignTokens.error.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: DesignTokens.error,
                    ),
                    const SizedBox(width: DesignTokens.spacingXs),
                    Expanded(
                      child: Text(
                        _humanizeErrorCode(export.errorCode!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: DesignTokens.error,
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

  static String _formatWhen(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Agora há pouco';
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Há ${diff.inHours}h';
    if (diff.inDays < 7) return 'Há ${diff.inDays}d';
    return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(when);
  }

  static String _formatDate(DateTime d) =>
      DateFormat('dd/MM/yyyy', 'pt_BR').format(d);

  /// Traduz error_codes curtos (da Edge Function) em frases em pt-BR.
  /// Qualquer código desconhecido cai num fallback genérico.
  static String _humanizeErrorCode(String code) => switch (code) {
        'not_found' => 'Treino não encontrado no servidor.',
        'encode_failed' => 'Falha ao codificar o arquivo .fit.',
        'no_blocks' => 'O treino não tem blocos — peça ajuda ao coach.',
        'unauthorized' => 'Sua sessão expirou. Faça login de novo.',
        'unsupported_watch' => 'Seu relógio não é compatível com .fit.',
        _ => 'Erro: $code',
      };
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
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: DesignTokens.spacingXs),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
