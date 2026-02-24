import 'package:flutter/material.dart';

import 'package:omni_runner/presentation/widgets/gps_tips_sheet.dart';

/// Maps raw integrity flag codes to friendly, non-accusatory PT-BR messages.
const _flagReasons = <String, String>{
  // Official critical flags (server-authoritative)
  'SPEED_IMPOSSIBLE': 'Velocidade GPS acima do esperado para corrida',
  'GPS_JUMP': 'Salto de posição GPS detectado (sinal instável)',
  'TELEPORT': 'Mudança de posição impossível detectada',
  'VEHICLE_SUSPECTED': 'Movimento incompatível com corrida a pé',
  'NO_MOTION_PATTERN': 'Sem variação de movimento detectada na rota',
  'BACKGROUND_GPS_GAP': 'Falha no rastreamento GPS (app em segundo plano?)',
  'TIME_SKEW': 'Inconsistência nos horários da atividade',
  // Official quality flags
  'TOO_FEW_POINTS': 'Poucos pontos de GPS registrados',
  'TOO_SHORT_DURATION': 'Atividade muito curta',
  'TOO_SHORT_DISTANCE': 'Distância muito curta para validação',
  'IMPLAUSIBLE_PACE': 'Pace registrado abaixo do limite de validação',
  // Legacy flag names (client-side detectors, kept for backward compat)
  'HIGH_SPEED': 'Velocidade GPS acima do esperado para corrida',
  'SPEED_EXCEEDED': 'Velocidade GPS acima do esperado para corrida',
  'TELEPORT_DETECTED': 'Mudança de posição impossível detectada',
  'VEHICLE_SUSPECT': 'Movimento incompatível com corrida a pé',
};

String _friendlyReason(String flag) =>
    _flagReasons[flag] ?? 'Dados inconsistentes detectados';

/// Friendly, non-accusatory card shown when a run fails validation.
///
/// Replaces raw integrity flags with user-friendly reasons and
/// provides clear next-step CTAs.
class InvalidatedRunCard extends StatelessWidget {
  final List<String> integrityFlags;

  /// If non-null, a "Enviar para revisão" CTA is shown.
  final String? coachingGroupId;

  /// Called when user taps "Tentar novamente".
  final VoidCallback? onRetry;

  /// Called when user taps "Enviar para revisão da assessoria".
  final VoidCallback? onRequestReview;

  const InvalidatedRunCard({
    super.key,
    required this.integrityFlags,
    this.coachingGroupId,
    this.onRetry,
    this.onRequestReview,
  });

  @override
  Widget build(BuildContext context) {
    final reasons = integrityFlags
        .map(_friendlyReason)
        .toSet()
        .toList();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 20, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Não conseguimos validar esta atividade',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Isso pode acontecer por sinal de GPS fraco, '
            'interferências ou condições do ambiente. '
            'Não se preocupe — veja as possíveis razões abaixo.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 10),
          ...reasons.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.circle, size: 6,
                          color: Colors.orange.shade400),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(r,
                          style: const TextStyle(fontSize: 12, height: 1.3)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
          Text(
            'Esta corrida foi salva, mas pode ser excluída dos rankings.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onRetry != null)
                _Cta(
                  icon: Icons.refresh_rounded,
                  label: 'Tentar novamente',
                  onTap: onRetry!,
                ),
              if (coachingGroupId != null && onRequestReview != null)
                _Cta(
                  icon: Icons.rate_review_outlined,
                  label: 'Enviar para revisão',
                  onTap: onRequestReview!,
                ),
              _Cta(
                icon: Icons.lightbulb_outline_rounded,
                label: 'Ver dicas de GPS',
                onTap: () => GpsTipsSheet.show(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Cta({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: Colors.orange.shade300),
        foregroundColor: Colors.orange.shade800,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
