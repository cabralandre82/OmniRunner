import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _faqs = <_FaqItem>[
    _FaqItem(
      question: 'Como sincronizar meu relógio?',
      answer:
          'Conecte o Strava na tela de configurações. Suas corridas serão '
          'importadas automaticamente.',
    ),
    _FaqItem(
      question: 'Como entrar em uma assessoria?',
      answer:
          'Peça o código de convite ao seu coach e insira na tela '
          '"Entrar em assessoria".',
    ),
    _FaqItem(
      question: 'Como funcionam os OmniCoins?',
      answer:
          'OmniCoins são moedas virtuais usadas em desafios e competições '
          'dentro da plataforma.',
    ),
    _FaqItem(
      question: 'Como verificar meu perfil?',
      answer:
          'Acesse "Verificação" no menu e envie um registro de atividade '
          'para validação.',
    ),
    _FaqItem(
      question: 'Como reportar um problema?',
      answer: 'Acesse "Suporte" no menu e abra um chamado.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perguntas Frequentes')),
      body: ListView.separated(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        itemCount: _faqs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final faq = _faqs[i];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMd,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(
                DesignTokens.spacingMd,
                0,
                DesignTokens.spacingMd,
                DesignTokens.spacingMd,
              ),
              shape: const Border(),
              title: Text(
                faq.question,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    faq.answer,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}
