import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Athlete screen to invite friends to the Omni Runner app.
///
/// Three sharing methods:
///   1. Personal referral link (copyable)
///   2. QR code (scannable)
///   3. Share via native sheet (redes sociais, WhatsApp, etc.)
///
/// The referral link encodes the athlete's user ID so the platform can
/// track organic growth. Format: `https://omnirunner.app/refer/{userId}`
///
/// No monetary values. No prohibited terms. Complies with GAMIFICATION_POLICY §5.
class InviteFriendsScreen extends StatelessWidget {
  const InviteFriendsScreen({super.key});

  String get _userId => sl<UserIdentityProvider>().userId;
  String get _referLink => 'https://omnirunner.app/refer/$_userId';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Convidar amigos')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg, vertical: 28),
        child: Column(
          children: [
            // Hero section
            Icon(Icons.people_alt_rounded,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Traga seus amigos!',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Compartilhe seu link pessoal e corra junto '
              'com outros atletas no Omni Runner.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                data: _referLink,
                version: QrVersions.auto,
                size: 220,
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
            const SizedBox(height: 20),

            Text(
              'Mostre o QR ou compartilhe o link abaixo',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Link chip
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _referLink,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _copyLink(context),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.all(DesignTokens.spacingXs),
                      child: Icon(Icons.copy_rounded,
                          size: 18, color: theme.colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

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
            const SizedBox(height: 24),

            // Info section
            const _InfoCard(
              icon: Icons.group_add_rounded,
              title: 'Como funciona?',
              items: [
                'Seu amigo abre o link ou escaneia o QR',
                'Ele baixa o Omni Runner e cria a conta',
                'Vocês já podem se desafiar e treinar juntos!',
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _referLink));
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
        text: 'Corra comigo no Omni Runner! '
            'Baixe o app e vamos treinar juntos: $_referLink',
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Info card
// ═══════════════════════════════════════════════════════════════════════════

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${e.key + 1}',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.value,
                          style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
