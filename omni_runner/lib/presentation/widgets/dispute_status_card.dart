import 'package:flutter/material.dart';

/// Status of a cross-assessoria clearing case, from the athlete's perspective.
enum DisputePhase {
  pendingClearing,
  sentConfirmed,
  disputed,
  cleared,
  expired,
}

/// Friendly card explaining the dispute/clearing status of a cross-assessoria
/// challenge reward. Shown in challenge details or credits screen for athletes.
class DisputeStatusCard extends StatelessWidget {
  final DisputePhase phase;
  final int? coinsAmount;
  final DateTime? deadlineAt;

  const DisputeStatusCard({
    super.key,
    required this.phase,
    this.coinsAmount,
    this.deadlineAt,
  });

  @override
  Widget build(BuildContext context) {
    final config = _phaseConfig(phase);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: config.bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: config.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(config.icon, size: 20, color: config.iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  config.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: config.titleColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            config.description,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
          if (coinsAmount != null && coinsAmount! > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.toll_rounded, size: 16,
                    color: config.iconColor),
                const SizedBox(width: 4),
                Text(
                  '$coinsAmount OmniCoins',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: config.titleColor,
                  ),
                ),
              ],
            ),
          ],
          if (deadlineAt != null && phase != DisputePhase.cleared) ...[
            const SizedBox(height: 8),
            _DeadlineRow(deadline: deadlineAt!, phase: phase),
          ],
          const SizedBox(height: 8),
          Text(
            config.nextStep,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeadlineRow extends StatelessWidget {
  final DateTime deadline;
  final DisputePhase phase;

  const _DeadlineRow({required this.deadline, required this.phase});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final remaining = deadline.difference(now);
    final isExpired = remaining.isNegative;

    final label = isExpired
        ? 'Prazo encerrado'
        : 'Prazo: ${_formatRemaining(remaining)}';

    return Row(
      children: [
        Icon(
          isExpired ? Icons.timer_off_rounded : Icons.timer_outlined,
          size: 14,
          color: isExpired ? Colors.red.shade600 : Colors.grey.shade600,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isExpired ? Colors.red.shade600 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  static String _formatRemaining(Duration d) {
    if (d.inDays > 0) {
      return '${d.inDays} ${d.inDays == 1 ? "dia" : "dias"}';
    }
    if (d.inHours > 0) {
      return '${d.inHours} ${d.inHours == 1 ? "hora" : "horas"}';
    }
    return '${d.inMinutes} min';
  }
}

class _PhaseConfig {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;
  final Color titleColor;
  final String title;
  final String description;
  final String nextStep;

  const _PhaseConfig({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
    required this.titleColor,
    required this.title,
    required this.description,
    required this.nextStep,
  });
}

_PhaseConfig _phaseConfig(DisputePhase phase) => switch (phase) {
      DisputePhase.pendingClearing => _PhaseConfig(
          icon: Icons.hourglass_top_rounded,
          iconColor: Colors.orange.shade800,
          bgColor: Colors.orange.shade50,
          borderColor: Colors.orange.shade200,
          titleColor: Colors.orange.shade900,
          title: 'Aguardando confirmação entre assessorias',
          description:
              'Seu prêmio está reservado. As assessorias envolvidas '
              'precisam confirmar a entrega dos OmniCoins entre si.',
          nextStep:
              'Quando ambas as assessorias confirmarem, os OmniCoins '
              'serão liberados automaticamente para você.',
        ),
      DisputePhase.sentConfirmed => _PhaseConfig(
          icon: Icons.send_rounded,
          iconColor: Colors.blue.shade800,
          bgColor: Colors.blue.shade50,
          borderColor: Colors.blue.shade200,
          titleColor: Colors.blue.shade900,
          title: 'Envio confirmado — aguardando recebimento',
          description:
              'Uma assessoria já confirmou o envio. Falta a outra '
              'confirmar o recebimento para liberar seu prêmio.',
          nextStep:
              'O processo geralmente é concluído em poucos dias. '
              'Você será notificado quando os OmniCoins forem liberados.',
        ),
      DisputePhase.disputed => _PhaseConfig(
          icon: Icons.rate_review_rounded,
          iconColor: Colors.orange.shade700,
          bgColor: Colors.orange.shade50,
          borderColor: Colors.orange.shade200,
          titleColor: Colors.orange.shade900,
          title: 'Em análise pelas assessorias',
          description:
              'As assessorias envolvidas estão verificando os '
              'detalhes deste desafio. Isso é normal e faz parte '
              'do processo de confirmação.',
          nextStep:
              'Seus OmniCoins continuam reservados. Quando tudo '
              'for confirmado, o prêmio será liberado. '
              'Fale com seu professor se tiver dúvidas.',
        ),
      DisputePhase.cleared => _PhaseConfig(
          icon: Icons.check_circle_rounded,
          iconColor: Colors.green.shade700,
          bgColor: Colors.green.shade50,
          borderColor: Colors.green.shade200,
          titleColor: Colors.green.shade900,
          title: 'Prêmio liberado!',
          description:
              'As assessorias confirmaram tudo. Seus OmniCoins '
              'já estão disponíveis para uso.',
          nextStep: 'Confira seus OmniCoins na tela de créditos.',
        ),
      DisputePhase.expired => _PhaseConfig(
          icon: Icons.schedule_rounded,
          iconColor: Colors.grey.shade700,
          bgColor: Colors.grey.shade100,
          borderColor: Colors.grey.shade300,
          titleColor: Colors.grey.shade800,
          title: 'Prazo encerrado',
          description:
              'O prazo para confirmação entre as assessorias expirou. '
              'Entre em contato com o professor da sua assessoria '
              'para resolver a situação.',
          nextStep:
              'Seus OmniCoins estão reservados até que as '
              'assessorias resolvam manualmente.',
        ),
    };
