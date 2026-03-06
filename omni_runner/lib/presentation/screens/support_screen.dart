import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/screens/support_ticket_screen.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class SupportScreen extends StatefulWidget {
  final String groupId;
  const SupportScreen({super.key, required this.groupId});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _tickets = [];
  _NewTicketResult? _pendingTicket;

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
      final res = await Supabase.instance.client
          .from('support_tickets')
          .select('id, group_id, subject, status, created_at, updated_at')
          .eq('group_id', widget.groupId)
          .order('updated_at', ascending: false);

      if (mounted) {
        setState(() {
          _tickets = (res as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } on Exception catch (e) {
      AppLogger.warn('Caught error', tag: 'SupportScreen', error: e);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar os chamados.';
        });
      }
    }
  }

  Future<void> _newTicket() async {
    if (_busy) return;
    final result = await showDialog<_NewTicketResult>(
      context: context,
      builder: (_) => _NewTicketDialog(
        initialSubject: _pendingTicket?.subject,
        initialMessage: _pendingTicket?.message,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final uid = sl<UserIdentityProvider>().userId;

      final ticketRes = await Supabase.instance.client
          .from('support_tickets')
          .insert({
            'group_id': widget.groupId,
            'subject': result.subject,
          })
          .select('id, group_id, subject, status, created_at, updated_at')
          .single();

      final ticketId = ticketRes['id'] as String;

      await Supabase.instance.client.from('support_messages').insert({
        'ticket_id': ticketId,
        'sender_id': uid,
        'sender_role': 'staff',
        'body': result.message,
      });

      _pendingTicket = null;

      if (mounted) {
        await _load();
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SupportTicketScreen(
              ticketId: ticketId,
              subject: result.subject,
            ),
          ));
        }
      }
    } on Exception {
      _pendingTicket = result;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao criar chamado. Sua mensagem foi preservada — tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.support),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTicket,
        icon: const Icon(Icons.add),
        label: Text(context.l10n.newTicket),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DesignTokens.spacingXl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 48, color: cs.error),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: cs.error,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
              onRefresh: _load,
              child: _tickets.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Icon(Icons.support_agent, size: 64,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum chamado ainda',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Abra um chamado para falar com a equipe Omni Runner',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 12, DesignTokens.spacingMd, 80),
                      itemCount: _tickets.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final t = _tickets[i];
                        return _TicketCard(
                          ticket: t,
                          onTap: () async {
                            await Navigator.of(context)
                                .push(MaterialPageRoute<void>(
                              builder: (_) => SupportTicketScreen(
                                ticketId: t['id'] as String,
                                subject: t['subject'] as String,
                              ),
                            ));
                            _load();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket card
// ---------------------------------------------------------------------------

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

  const _TicketCard({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = ticket['status'] as String? ?? 'open';
    final subject = ticket['subject'] as String? ?? '';
    final updatedAt = DateTime.tryParse(ticket['updated_at'] as String? ?? '');

    final isDark = theme.brightness == Brightness.dark;
    final (Color bg, Color fg, String label, IconData icon) = switch (status) {
      'open' => (
        isDark ? DesignTokens.warning.withValues(alpha: 0.4) : DesignTokens.warning,
        isDark ? DesignTokens.warning : DesignTokens.warning,
        'Aberto', Icons.schedule),
      'answered' => (
        isDark ? DesignTokens.primary.withValues(alpha: 0.4) : DesignTokens.primary,
        isDark ? DesignTokens.primary : DesignTokens.primary,
        'Respondido', Icons.reply),
      'closed' => (
        isDark ? DesignTokens.textPrimary : DesignTokens.surface,
        isDark ? DesignTokens.textMuted : DesignTokens.textSecondary,
        'Fechado', Icons.check_circle_outline),
      _ => (
        isDark ? DesignTokens.textPrimary : DesignTokens.surfaceElevated,
        isDark ? DesignTokens.textMuted : DesignTokens.textSecondary,
        status, Icons.help_outline),
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Icon(icon, color: fg, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spacingSm, vertical: 2),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                          ),
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: fg)),
                        ),
                        if (updatedAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(updatedAt),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return '${diff.inMinutes}min';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// New ticket dialog
// ---------------------------------------------------------------------------

class _NewTicketResult {
  final String subject;
  final String message;
  const _NewTicketResult({required this.subject, required this.message});
}

class _NewTicketDialog extends StatefulWidget {
  final String? initialSubject;
  final String? initialMessage;

  const _NewTicketDialog({this.initialSubject, this.initialMessage});

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _messageCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _subjectCtrl = TextEditingController(text: widget.initialSubject ?? '');
    _messageCtrl = TextEditingController(text: widget.initialMessage ?? '');
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.newTicket),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(
                labelText: 'Assunto',
                hintText: 'Descreva brevemente o problema',
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 200,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o assunto' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _messageCtrl,
              decoration: const InputDecoration(
                labelText: 'Mensagem',
                hintText: 'Detalhe sua dúvida ou problema',
                alignLabelWithHint: true,
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              maxLength: 2000,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Escreva a mensagem' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                _NewTicketResult(
                  subject: _subjectCtrl.text.trim(),
                  message: _messageCtrl.text.trim(),
                ),
              );
            }
          },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
