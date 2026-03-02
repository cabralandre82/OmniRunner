import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/screens/support_ticket_screen.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/l10n/l10n.dart';

class SupportScreen extends StatefulWidget {
  final String groupId;
  const SupportScreen({super.key, required this.groupId});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _tickets = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('support_tickets')
          .select()
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newTicket() async {
    final result = await showDialog<_NewTicketResult>(
      context: context,
      builder: (_) => const _NewTicketDialog(),
    );
    if (result == null || !mounted) return;

    try {
      final uid = sl<UserIdentityProvider>().userId;

      final ticketRes = await Supabase.instance.client
          .from('support_tickets')
          .insert({
            'group_id': widget.groupId,
            'subject': result.subject,
          })
          .select()
          .single();

      final ticketId = ticketRes['id'] as String;

      await Supabase.instance.client.from('support_messages').insert({
        'ticket_id': ticketId,
        'sender_id': uid,
        'sender_role': 'staff',
        'body': result.message,
      });

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
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar chamado: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.support),
        backgroundColor: cs.inversePrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTicket,
        icon: const Icon(Icons.add),
        label: Text(context.l10n.newTicket),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
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
        isDark ? Colors.orange.shade900.withValues(alpha: 0.4) : Colors.orange.shade100,
        isDark ? Colors.orange.shade300 : Colors.orange.shade800,
        'Aberto', Icons.schedule),
      'answered' => (
        isDark ? Colors.blue.shade900.withValues(alpha: 0.4) : Colors.blue.shade100,
        isDark ? Colors.blue.shade300 : Colors.blue.shade800,
        'Respondido', Icons.reply),
      'closed' => (
        isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        'Fechado', Icons.check_circle_outline),
      _ => (
        isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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
                  borderRadius: BorderRadius.circular(12),
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
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(8),
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
  const _NewTicketDialog();

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

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
