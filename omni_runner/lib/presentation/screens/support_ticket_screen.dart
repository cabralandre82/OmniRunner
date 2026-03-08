import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class SupportTicketScreen extends StatefulWidget {
  final String ticketId;
  final String subject;

  const SupportTicketScreen({
    super.key,
    required this.ticketId,
    required this.subject,
  });

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loading = true;
  bool _sending = false;
  String _status = 'open';
  List<Map<String, dynamic>> _messages = [];

  String get _uid => sl<UserIdentityProvider>().userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ticketRes = await sl<SupabaseClient>()
          .from('support_tickets')
          .select('status')
          .eq('id', widget.ticketId)
          .single();

      final msgs = await sl<SupabaseClient>()
          .from('support_messages')
          .select('ticket_id, sender_id, sender_role, body, created_at')
          .eq('ticket_id', widget.ticketId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _status = ticketRes['status'] as String? ?? 'open';
          _messages = (msgs as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
        _scrollToBottom();
      }
    } on Exception catch (e) {
      AppLogger.warn('Caught error', tag: 'SupportTicketScreen', error: e);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final body = _msgCtrl.text.trim();
    if (body.isEmpty) return;

    setState(() => _sending = true);
    try {
      await sl<SupabaseClient>().from('support_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': _uid,
        'sender_role': 'staff',
        'body': body,
      });

      if (_status == 'answered') {
        await sl<SupabaseClient>()
            .from('support_tickets')
            .update({'status': 'open'})
            .eq('id', widget.ticketId);
      }

      _msgCtrl.clear();
      await _load();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.humanize(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isClosed = _status == 'closed';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _StatusChip(status: _status),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text('Nenhuma mensagem',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, DesignTokens.spacingSm),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) => _MessageBubble(
                          message: _messages[i],
                          isMe: _messages[i]['sender_role'] == 'staff',
                        ),
                      ),
          ),
          if (!isClosed)
            Container(
              padding: EdgeInsets.fromLTRB(12, DesignTokens.spacingSm, 12, MediaQuery.of(context).padding.bottom + 8),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                    top: BorderSide(color: cs.outlineVariant, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: 'Escreva sua mensagem...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacingMd, vertical: 10),
                        isDense: true,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4,
                      minLines: 1,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              color: cs.surfaceContainerHighest,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text('Chamado encerrado',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = message['body'] as String? ?? '';
    final createdAt = DateTime.tryParse(message['created_at'] as String? ?? '');
    final isPlatform = message['sender_role'] == 'platform';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? cs.primaryContainer
              : isPlatform
                  ? (isDark ? DesignTokens.primary.withValues(alpha: 0.4) : DesignTokens.primary)
                  : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isPlatform)
              Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spacingXs),
                child: Text(
                  'Equipe Omni Runner',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? DesignTokens.primary : DesignTokens.primary,
                  ),
                ),
              ),
            Text(body, style: const TextStyle(fontSize: 14, height: 1.4)),
            if (createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
                child: Text(
                  _formatTime(createdAt),
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.toLocal().hour.toString().padLeft(2, '0');
    final m = dt.toLocal().minute.toString().padLeft(2, '0');
    final d = dt.toLocal().day;
    final mo = dt.toLocal().month;
    return '$d/$mo $h:$m';
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (Color bg, Color fg, String label) = switch (status) {
      'open' => (
        isDark ? DesignTokens.warning.withValues(alpha: 0.4) : DesignTokens.warning,
        isDark ? DesignTokens.warning : DesignTokens.warning,
        'Aberto'),
      'answered' => (
        isDark ? DesignTokens.primary.withValues(alpha: 0.4) : DesignTokens.primary,
        isDark ? DesignTokens.primary : DesignTokens.primary,
        'Respondido'),
      'closed' => (
        isDark ? DesignTokens.textPrimary : DesignTokens.surface,
        isDark ? DesignTokens.textMuted : DesignTokens.textSecondary,
        'Fechado'),
      _ => (
        isDark ? DesignTokens.textPrimary : DesignTokens.surfaceElevated,
        isDark ? DesignTokens.textMuted : DesignTokens.textSecondary,
        status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: DesignTokens.spacingXs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
