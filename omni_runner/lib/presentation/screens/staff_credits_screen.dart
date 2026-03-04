import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';

/// Staff screen showing the assessoria's OmniCoin inventory,
/// distribution history, and a CTA to contact the platform.
///
/// No monetary values, no purchase flow, no payment references.
/// Complies with DECISAO 046 / GAMIFICATION_POLICY §5.
class StaffCreditsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const StaffCreditsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<StaffCreditsScreen> createState() => _StaffCreditsScreenState();
}

class _StaffCreditsScreenState extends State<StaffCreditsScreen> {
  bool _loading = true;
  String? _error;
  int _available = 0;
  int _lifetimeIssued = 0;
  int _lifetimeBurned = 0;
  List<_CreditEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = Supabase.instance.client;

      final inv = await db
          .from('coaching_token_inventory')
          .select('available_tokens, lifetime_issued, lifetime_burned')
          .eq('group_id', widget.groupId)
          .maybeSingle();

      if (inv != null) {
        _available = (inv['available_tokens'] as int?) ?? 0;
        _lifetimeIssued = (inv['lifetime_issued'] as int?) ?? 0;
        _lifetimeBurned = (inv['lifetime_burned'] as int?) ?? 0;
      }

      final rows = await db
          .from('institution_credit_purchases')
          .select('credits_amount, source_reference, notes, purchased_at')
          .eq('group_id', widget.groupId)
          .order('purchased_at', ascending: false)
          .limit(50);

      _history = (rows as List).map((r) {
        final m = r as Map<String, dynamic>;
        return _CreditEntry(
          credits: (m['credits_amount'] as int?) ?? 0,
          reference: (m['source_reference'] as String?) ?? '',
          note: m['notes'] as String?,
          date: DateTime.tryParse(
                  (m['purchased_at'] as String?) ?? '') ??
              DateTime.now(),
        );
      }).toList();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'StaffCreditsScreen', error: e);
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar os dados.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tela de Créditos da Assessoria',
      child: Scaffold(
      appBar: AppBar(title: const Text('Créditos da assessoria')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error ?? '', onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(DesignTokens.spacingMd),
                    children: [
                      _InventoryCard(
                        available: _available,
                        issued: _lifetimeIssued,
                        burned: _lifetimeBurned,
                      ),
                      const SizedBox(height: 16),
                      const _PortalCta(),
                      const SizedBox(height: 24),
                      _HistorySection(entries: _history),
                    ],
                  ),
                ),
    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Inventory card
// ═══════════════════════════════════════════════════════════════════════════

class _InventoryCard extends StatelessWidget {
  final int available;
  final int issued;
  final int burned;

  const _InventoryCard({
    required this.available,
    required this.issued,
    required this.burned,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: DesignTokens.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: DesignTokens.warning.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(Icons.toll_rounded, size: 36, color: DesignTokens.warning),
          const SizedBox(height: 8),
          Text(
            '$available',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: DesignTokens.warning,
            ),
          ),
          Text(
            'OmniCoins disponíveis',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: DesignTokens.warning,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MiniStat(
                label: 'Distribuídos',
                value: '$issued',
                icon: Icons.arrow_upward_rounded,
                color: DesignTokens.success,
              ),
              _MiniStat(
                label: 'Devolvidos',
                value: '$burned',
                icon: Icons.arrow_downward_rounded,
                color: DesignTokens.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Portal CTA — opens external browser, never checkout inside the app
// ═══════════════════════════════════════════════════════════════════════════

class _PortalCta extends StatelessWidget {
  const _PortalCta();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Portal de Assessorias',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Acesse o Portal Web para gerenciar créditos e equipe da sua assessoria.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// History section — credit allocations from the platform
// ═══════════════════════════════════════════════════════════════════════════

class _HistorySection extends StatelessWidget {
  final List<_CreditEntry> entries;

  const _HistorySection({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Histórico de créditos',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXl),
            child: Center(
              child: Text(
                'Nenhum registro de créditos ainda.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ...entries.map(_EntryTile.new),
      ],
    );
  }
}

class _CreditEntry {
  final int credits;
  final String reference;
  final String? note;
  final DateTime date;

  const _CreditEntry({
    required this.credits,
    required this.reference,
    this.note,
    required this.date,
  });
}

class _EntryTile extends StatelessWidget {
  final _CreditEntry entry;

  const _EntryTile(this.entry);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: DesignTokens.success.withValues(alpha: 0.1),
        child: const Icon(Icons.add_circle_outline,
            color: DesignTokens.success, size: 20),
      ),
      title: Text('+${entry.credits} OmniCoins'),
      subtitle: Text(
        entry.note ?? entry.reference,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _fmt(entry.date),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

// ═══════════════════════════════════════════════════════════════════════════
// Error body
// ═══════════════════════════════════════════════════════════════════════════
