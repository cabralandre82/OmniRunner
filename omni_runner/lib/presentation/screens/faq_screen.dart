import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class FaqScreen extends StatelessWidget {
  final bool isStaff;

  const FaqScreen({super.key, this.isStaff = false});

  static const _athleteFaqs = <_FaqItem>[
    _FaqItem(
      question: 'Como sincronizar meu relógio?',
      answer:
          'Conecte o Strava na tela de configurações. Suas corridas serão '
          'importadas automaticamente.',
    ),
    _FaqItem(
      question: 'Como entrar em uma assessoria?',
      answer:
          'Você pode pedir o código de convite ao seu coach e inserir na '
          'tela "Entrar em assessoria", ou procurar uma assessoria '
          'diretamente no app e solicitar entrada.',
    ),
    _FaqItem(
      question: 'Como funcionam os OmniCoins?',
      answer:
          'OmniCoins são moedas virtuais usadas em desafios e competições '
          'dentro da plataforma. Sua assessoria distribui OmniCoins '
          'pelo portal.',
    ),
    _FaqItem(
      question: 'Como verificar meu perfil?',
      answer:
          'Conecte o Strava e corra normalmente. Após 7 corridas válidas '
          'ao ar livre com GPS, você recebe o status "Verificado" '
          'automaticamente.',
    ),
    _FaqItem(
      question: 'Como reportar um problema?',
      answer: 'Acesse "Suporte" no menu e abra um chamado.',
    ),
  ];

  static const _staffFaqs = <_FaqItem>[
    _FaqItem(
      question: 'Como convidar atletas para minha assessoria?',
      answer:
          'Gere um código de convite no portal da assessoria e compartilhe '
          'com seus atletas. Eles podem inserir o código no app.',
    ),
    _FaqItem(
      question: 'Como distribuir OmniCoins?',
      answer:
          'Acesse o portal da sua assessoria e distribua OmniCoins '
          'individualmente ou em lote para seus atletas.',
    ),
    _FaqItem(
      question: 'Como criar campeonatos?',
      answer:
          'No portal, acesse "Campeonatos" e crie competições entre '
          'assessorias com regras e prazos definidos.',
    ),
    _FaqItem(
      question: 'Como atribuir treinos aos atletas?',
      answer:
          'Use a seção "Treinos" no dashboard para criar e enviar '
          'treinos personalizados para cada atleta.',
    ),
    _FaqItem(
      question: 'Como reportar um problema?',
      answer:
          'Acesse "Suporte" no menu para abrir um chamado com a '
          'equipe Omni Runner.',
    ),
  ];

  List<_FaqItem> get _activeFaqs => isStaff ? _staffFaqs : _athleteFaqs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perguntas Frequentes')),
      body: ListView.separated(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        itemCount: _activeFaqs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final faq = _activeFaqs[i];
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
