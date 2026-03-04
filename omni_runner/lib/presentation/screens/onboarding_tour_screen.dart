import 'package:flutter/material.dart';

import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Full-screen guided tour shown once after the user completes structural
/// onboarding (role + assessoria). Explains key features via a swipeable
/// PageView before dropping the user into the HomeScreen.
class OnboardingTourScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingTourScreen({super.key, required this.onComplete});

  @override
  State<OnboardingTourScreen> createState() => _OnboardingTourScreenState();
}

class _OnboardingTourScreenState extends State<OnboardingTourScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _slides = <_SlideData>[
    _SlideData(
      icon: Icons.link_rounded,
      color: Color(0xFFFC4C02),
      title: 'Conecte seu Strava',
      body:
          'Suas corridas são importadas automaticamente do Strava.\n'
          'Conecte uma vez e tudo sincroniza sozinho, sem esforço.',
    ),
    _SlideData(
      icon: Icons.emoji_events_rounded,
      color: Color(0xFFFFB300),
      title: 'Desafie outros corredores',
      body:
          'Crie desafios 1v1 ou em equipe. Aposte OmniCoins.\n'
          'Quem cumprir o objetivo primeiro, vence!',
    ),
    _SlideData(
      icon: Icons.groups_rounded,
      color: Color(0xFF1E88E5),
      title: 'Treine com sua assessoria',
      body:
          'Entre na assessoria do seu treinador, participe de campeonatos\n'
          'e veja rankings semanais do grupo.',
    ),
    _SlideData(
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFE53935),
      title: 'Mantenha sua sequência',
      body:
          'Corra todos os dias para construir seu streak.\n'
          'Quanto maior a sequência, mais XP e badges você ganha.',
    ),
    _SlideData(
      icon: Icons.insights_rounded,
      color: Color(0xFF7B1FA2),
      title: 'Acompanhe sua evolução',
      body:
          'DNA do Corredor, Retrospectiva mensal, Liga de Assessorias\n'
          'e previsão de PR — tudo baseado nos seus dados reais.',
    ),
    _SlideData(
      icon: Icons.people_rounded,
      color: Color(0xFF00897B),
      title: 'Encontre amigos',
      body:
          'Adicione amigos de qualquer assessoria, veja perfis com\n'
          'DNA de corrida e compartilhe redes sociais.',
    ),
    _SlideData(
      icon: Icons.sports_kabaddi_rounded,
      color: Color(0xFF43A047),
      title: 'Desafie seus amigos',
      body:
          'Três tipos de desafio:\n'
          '🏃 1v1 — Duelo direto entre dois corredores\n'
          '👥 Grupo — Vários competem, melhor resultado ganha\n'
          '🤝 Time — Equipes cooperam para atingir metas coletivas',
    ),
    _SlideData(
      icon: Icons.monetization_on_rounded,
      color: DesignTokens.warning,
      title: 'OmniCoins',
      body:
          'Suas OmniCoins vêm da sua assessoria de corrida.\n'
          'Use como inscrição nos desafios — o vencedor leva o pool!',
    ),
    _SlideData(
      icon: Icons.verified_user_rounded,
      color: Color(0xFF1565C0),
      title: 'Atleta Verificado',
      body:
          'Complete 7 corridas válidas para se tornar Verificado.\n'
          'Só atletas verificados podem participar de desafios\n'
          'com OmniCoins — isso garante jogo justo para todos.',
    ),
  ];

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    FirstUseTips.markSeen(TipKey.onboardingTour);
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(
                  'Pular',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            // Slides
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                physics: const BouncingScrollPhysics(),
                itemBuilder: (_, i) => _SlideWidget(data: _slides[i]),
              ),
            ),

            // Dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
                    width: active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: active
                          ? _slides[_currentPage].color
                          : theme.colorScheme.outlineVariant,
                    ),
                  );
                }),
              ),
            ),

            // CTA button
            Padding(
              padding: const EdgeInsets.fromLTRB(DesignTokens.spacingXl, 0, DesignTokens.spacingXl, DesignTokens.spacingXl),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: _slides[_currentPage].color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(isLast ? 'COMEÇAR A CORRER' : 'PRÓXIMO'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data ────────────────────────────────────────────────────────────────────

class _SlideData {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _SlideData({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
}

// ── Slide widget ────────────────────────────────────────────────────────────

class _SlideWidget extends StatelessWidget {
  final _SlideData data;

  const _SlideWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, size: 60, color: data.color),
          ),
          const SizedBox(height: 40),
          Text(
            data.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            data.body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
