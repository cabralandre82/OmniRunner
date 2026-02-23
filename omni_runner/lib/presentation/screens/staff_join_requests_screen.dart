import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Staff screen to view and approve/reject athlete join requests.
class StaffJoinRequestsScreen extends StatefulWidget {
  final String groupId;

  const StaffJoinRequestsScreen({super.key, required this.groupId});

  @override
  State<StaffJoinRequestsScreen> createState() =>
      _StaffJoinRequestsScreenState();
}

class _StaffJoinRequestsScreenState extends State<StaffJoinRequestsScreen> {
  List<_JoinRequest> _pending = [];
  List<_JoinRequest> _processed = [];
  bool _loading = true;
  String? _error;

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
      final rows = await db
          .from('coaching_join_requests')
          .select('id, user_id, display_name, status, requested_at')
          .eq('group_id', widget.groupId)
          .order('requested_at', ascending: false);

      final all = (rows as List)
          .cast<Map<String, dynamic>>()
          .map((r) => _JoinRequest(
                id: r['id'] as String,
                userId: r['user_id'] as String,
                displayName: (r['display_name'] as String?) ?? 'Atleta',
                status: (r['status'] as String?) ?? 'pending',
                requestedAt: DateTime.tryParse(
                        (r['requested_at'] as String?) ?? '') ??
                    DateTime.now(),
              ))
          .toList();

      if (mounted) {
        setState(() {
          _pending = all.where((r) => r.status == 'pending').toList();
          _processed = all.where((r) => r.status != 'pending').toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar as solicitações.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _approve(_JoinRequest req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar entrada?'),
        content: Text(
          '${req.displayName} será adicionado como atleta da sua assessoria.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.rpc(
        'fn_approve_join_request',
        params: {'p_request_id': req.id},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${req.displayName} aprovado!'),
            backgroundColor: Colors.green,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aprovar: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _reject(_JoinRequest req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar solicitação?'),
        content: Text(
          '${req.displayName} não será adicionado. '
          'O atleta poderá solicitar novamente no futuro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.rpc(
        'fn_reject_join_request',
        params: {'p_request_id': req.id},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitação rejeitada.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao rejeitar: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitações de Entrada'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_pending.isEmpty && _processed.isEmpty)
                        _buildEmpty(theme),
                      if (_pending.isNotEmpty) ...[
                        Text(
                          'Pendentes (${_pending.length})',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ..._pending.map((r) => _RequestCard(
                              request: r,
                              onApprove: () => _approve(r),
                              onReject: () => _reject(r),
                            )),
                        const SizedBox(height: 24),
                      ],
                      if (_processed.isNotEmpty) ...[
                        Text(
                          'Histórico',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ..._processed.take(20).map(
                              (r) => _ProcessedTile(request: r),
                            ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_disabled_rounded,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Nenhuma solicitação',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Quando atletas solicitarem entrada na sua\nassessoria, as solicitações aparecerão aqui.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinRequest {
  final String id;
  final String userId;
  final String displayName;
  final String status;
  final DateTime requestedAt;

  const _JoinRequest({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.requestedAt,
  });
}

class _RequestCard extends StatelessWidget {
  final _JoinRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ago = _timeAgo(request.requestedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.person_outline,
                      color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.displayName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Solicitou entrada $ago',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                    child: const Text('Rejeitar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onApprove,
                    child: const Text('Aprovar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays < 7) return 'há ${diff.inDays}d';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
}

class _ProcessedTile extends StatelessWidget {
  final _JoinRequest request;

  const _ProcessedTile({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isApproved = request.status == 'approved';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isApproved
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.red.withValues(alpha: 0.12),
        child: Icon(
          isApproved ? Icons.check_rounded : Icons.close_rounded,
          size: 18,
          color: isApproved ? Colors.green : Colors.red,
        ),
      ),
      title: Text(request.displayName),
      subtitle: Text(
        isApproved ? 'Aprovado' : 'Rejeitado',
        style: theme.textTheme.bodySmall?.copyWith(
          color: isApproved ? Colors.green : Colors.red,
        ),
      ),
    );
  }
}
