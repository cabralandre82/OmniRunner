import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Dedicated "Como Funciona" reference page accessible from Settings.
/// Covers Challenges, OmniCoins, Verification, and Integrity in a
/// scrollable, grouped layout.
class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Como Funciona')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingSm, DesignTokens.spacingMd, DesignTokens.spacingXl),
        children: const [
          _Section(
            icon: Icons.emoji_events_rounded,
            color: Color(0xFFFFB300),
            title: 'Desafios',
            children: [
              _InfoCard(
                title: 'O que são?',
                body: 'Competições entre corredores com regras claras. '
                    'Você define a meta, o prazo e a inscrição.',
              ),
              _InfoCard(
                title: '3 Tipos de Desafio',
                body: '🏃 1v1 — Duelo direto. Dois corredores, uma meta, '
                    'quem cumprir melhor vence.\n\n'
                    '👥 Grupo — Vários competidores, cada um corre sozinho. '
                    'O melhor resultado leva o prêmio.\n\n'
                    '🤝 Time — Duas equipes cooperam internamente. '
                    'Os km de todos do time somam para atingir a meta coletiva.',
              ),
              _InfoCard(
                title: '4 Metas possíveis',
                body: '⚡ Mais rápido na distância — Quem corre X km no menor '
                    'tempo?\n\n'
                    '📏 Maior distância — Quem corre mais km no período?\n\n'
                    '🎯 Melhor pace na distância — Quem mantém o melhor ritmo '
                    'em X km?\n\n'
                    '🤝 Distância coletiva — O time inteiro soma km para atingir '
                    'a meta.',
              ),
              _InfoCard(
                title: 'Como o vencedor é decidido?',
                body: 'Depende da meta:\n'
                    '• Mais rápido → menor tempo para completar a distância\n'
                    '• Maior distância → mais km acumulados no período\n'
                    '• Melhor pace → menor pace médio na distância exigida\n'
                    '• Coletiva → primeiro time a atingir a meta total\n\n'
                    'Empates: vence quem atingiu o resultado primeiro.',
              ),
            ],
          ),
          SizedBox(height: 24),
          _Section(
            icon: Icons.monetization_on_rounded,
            color: DesignTokens.warning,
            title: 'OmniCoins',
            children: [
              _InfoCard(
                title: 'De onde vêm?',
                body: 'Sua assessoria distribui OmniCoins como forma de '
                    'engajar os atletas. Você recebe pelo portal da sua '
                    'assessoria — elas não são compráveis.',
              ),
              _InfoCard(
                title: 'Para que servem?',
                body: 'Use como inscrição em desafios competitivos. '
                    'As OmniCoins de todos os participantes formam '
                    'o pool — o vencedor leva tudo!\n\n'
                    'Desafios sem inscrição (gratuitos) também existem e '
                    'são abertos a todos.',
              ),
              _InfoCard(
                title: 'Importante',
                body: 'OmniCoins não podem ser transferidas entre usuários.\n'
                    'São debitadas no momento em que você entra no desafio.\n'
                    'Se o desafio for cancelado, as coins são devolvidas.',
              ),
            ],
          ),
          SizedBox(height: 24),
          _Section(
            icon: Icons.verified_user_rounded,
            color: Color(0xFF1565C0),
            title: 'Verificação',
            children: [
              _InfoCard(
                title: 'Por que existe?',
                body: 'Para garantir que desafios com OmniCoins sejam '
                    'justos. A verificação confirma que suas corridas são '
                    'reais e consistentes.',
              ),
              _InfoCard(
                title: 'Como conseguir?',
                body: '1. Conecte seu Strava\n'
                    '2. Corra normalmente — ao ar livre, com GPS\n'
                    '3. Após 7 corridas válidas, você recebe o status '
                    '"Verificado"\n\n'
                    'O progresso é automático. Acompanhe na tela de '
                    'Verificação.',
              ),
              _InfoCard(
                title: 'Posso perder o status?',
                body: 'Sim. Se corridas futuras apresentarem '
                    'irregularidades frequentes (GPS inconsistente, '
                    'velocidades impossíveis), seu status pode ser '
                    'rebaixado para "Monitorado" até que novas corridas '
                    'válidas o restaurem.',
              ),
            ],
          ),
          SizedBox(height: 24),
          _Section(
            icon: Icons.shield_rounded,
            color: Color(0xFF00897B),
            title: 'Integridade das Corridas',
            children: [
              _InfoCard(
                title: 'Validação automática',
                body: 'Todas as suas corridas são verificadas '
                    'automaticamente no servidor. Não há nada que você '
                    'precise fazer — basta correr normalmente.',
              ),
              _InfoCard(
                title: 'O que é verificado?',
                body: '• Dados GPS do Strava (rota, velocidade, altitude)\n'
                    '• Padrão de movimento (não ficou parado?)\n'
                    '• Velocidade plausível (humana, não de carro)\n'
                    '• Frequência cardíaca, quando disponível\n'
                    '• Duração mínima e distância mínima',
              ),
              _InfoCard(
                title: 'Corrida com problema conta?',
                body: 'Corridas com flags críticas não contam para desafios '
                    'nem para progressão de verificação.\n\n'
                    'Flags de qualidade (ex: GPS ruim em túnel) são '
                    'registrados mas não invalidam a corrida — servem '
                    'apenas para calibrar seu score de confiança.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<Widget> children;

  const _Section({
    required this.icon,
    required this.color,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
