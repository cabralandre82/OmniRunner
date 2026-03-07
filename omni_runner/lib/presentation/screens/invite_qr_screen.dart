import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Displays a persistent QR code for an assessoria invite link.
///
/// The QR encodes `https://omnirunner.app/invite/{code}`, which opens the app
/// directly via Universal/App Links or falls back to a web page.
///
/// Unlike token QR codes, invite QR codes do not expire — the invite_code is
/// a permanent group-level attribute that can be disabled via `invite_enabled`.
class InviteQrScreen extends StatefulWidget {
  final String inviteCode;
  final String groupName;

  const InviteQrScreen({
    super.key,
    required this.inviteCode,
    required this.groupName,
  });

  @override
  State<InviteQrScreen> createState() => _InviteQrScreenState();
}

class _InviteQrScreenState extends State<InviteQrScreen> {
  String get inviteCode => widget.inviteCode;
  String get groupName => widget.groupName;

  String get _inviteLink => 'https://omnirunner.app/invite/$inviteCode';

  int? _memberCount;
  bool? _inviteEnabled;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final db = sl<SupabaseClient>();
      final row = await db
          .from('coaching_groups')
          .select('id, invite_enabled')
          .eq('invite_code', inviteCode)
          .maybeSingle();

      int? memberCount;
      if (row != null) {
        final members = await db
            .from('coaching_members')
            .select('id')
            .eq('group_id', row['id'] as String);
        memberCount = (members as List).length;
      }

      if (!mounted) return;
      setState(() {
        _inviteEnabled = (row?['invite_enabled'] as bool?) ?? true;
        _memberCount = memberCount;
      });
    } catch (e) {
      AppLogger.warn('Unexpected error', tag: 'InviteQrScreen', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Convite da Assessoria')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg, vertical: DesignTokens.spacingXl),
        child: Column(
          children: [
            Icon(
              Icons.group_add_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              groupName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Mostre este QR para novos membros '
              'escanearem e entrarem na assessoria.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // QR code
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                border: Border.all(color: DesignTokens.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: _inviteLink,
                version: QrVersions.auto,
                size: 240,
                gapless: true,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: theme.colorScheme.primary,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Invite code chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.key_rounded,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  SelectableText(
                    inviteCode,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Os membros também podem digitar este código manualmente.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            if (_memberCount != null || _inviteEnabled != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (_memberCount != null)
                        Column(
                          children: [
                            Text('$_memberCount',
                                style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary)),
                            Text('entraram via convite',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      if (_inviteEnabled != null)
                        Column(
                          children: [
                            Icon(
                              _inviteEnabled!
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: _inviteEnabled!
                                  ? DesignTokens.success
                                  : DesignTokens.error,
                              size: 28,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _inviteEnabled! ? 'Ativo' : 'Desativado',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: _inviteEnabled!
                                    ? DesignTokens.success
                                    : DesignTokens.error,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyLink(context),
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    label: const Text('Copiar link'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _shareLink,
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text('Compartilhar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                      ),
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

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _inviteLink));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copiado!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareLink() {
    SharePlus.instance.share(
      ShareParams(
        text: 'Entre na assessoria $groupName no Omni Runner: $_inviteLink',
      ),
    );
  }
}
