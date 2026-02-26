import 'package:flutter/material.dart';
import 'package:omni_runner/domain/entities/athlete_verification_entity.dart';
import 'package:omni_runner/presentation/screens/athlete_verification_screen.dart';

/// Shows a modal bottom sheet explaining that VERIFIED status is required
/// for stake > 0 challenges, with a CTA to the verification screen.
///
/// Returns `true` if the user is already verified and can proceed.
/// Returns `false` if the modal was shown (user is NOT verified).
///
/// This is a UX pre-check. The server ALSO blocks via EF + DB triggers.
Future<bool> checkVerificationGate(
  BuildContext context, {
  required AthleteVerificationEntity? verification,
  required int entryFeeCoins,
}) async {
  if (entryFeeCoins <= 0) return true;

  if (verification != null && verification.isVerified) return true;

  if (!context.mounted) return false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _VerificationGateSheet(verification: verification),
  );

  return false;
}

class _VerificationGateSheet extends StatelessWidget {
  final AthleteVerificationEntity? verification;

  const _VerificationGateSheet({this.verification});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = verification;
    final statusLabel = v != null ? _statusText(v.status) : 'Desconhecido';
    final runsText = v != null
        ? '${v.validRunsCount}/${v.requiredValidRuns} corridas válidas'
        : '';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_user_outlined,
                size: 40, color: Colors.orange.shade700),
          ),
          const SizedBox(height: 16),
          Text(
            'Verificação necessária',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Desafios com inscrição de OmniCoins exigem que você seja um '
            'Atleta Verificado. Isso garante competições justas para todos.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (v != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Seu status',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.outline)),
                      Text(statusLabel,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Progresso',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.outline)),
                      Text(runsText,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AthleteVerificationScreen(),
                ));
              },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Ver minha verificação'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusText(VerificationStatus s) => switch (s) {
        VerificationStatus.unverified => 'Não Verificado',
        VerificationStatus.calibrating => 'Em Calibração',
        VerificationStatus.monitored => 'Em Observação',
        VerificationStatus.verified => 'Verificado',
        VerificationStatus.downgraded => 'Rebaixado',
      };
}
