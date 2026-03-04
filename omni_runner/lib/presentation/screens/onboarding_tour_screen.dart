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
      icon: Icons.sync_rounded,
      color: Color(0xFFFC4C02),
      title: 'Importe corridas do Strava',
      body:
          'Funciona com qualquer relógio — Garmin, Coros, Apple Watch.\n'
          'Conecte uma vez e tudo sincroniza sozinho, sem esforço.',
    ),
    _SlideData(
      icon: Icons.emoji_events_rounded,
      color: Color(0xFFFFB300),
      title: 'Desafie outros corredores',
      body:
          'Crie desafios 1v1 ou em grupo com OmniCoins.\n'
          'Quem cumprir o objetivo primeiro, leva o pool!',
    ),
    _SlideData(
      icon: Icons.auto_graph_rounded,
      color: Color(0xFF7B1FA2),
      title: 'Descubra seu DNA de Corredor',
      body:
          'Radar chart com 6 dimensões do seu perfil de corrida.\n'
          'Acompanhe sua evolução mês a mês com dados reais.',
    ),
    _SlideData(
      icon: Icons.groups_rounded,
      color: Color(0xFF1E88E5),
      title: 'Treine com sua assessoria',
      body:
          'Ranking, campeonatos e liga entre grupos.\n'
          'Entre na assessoria do seu treinador e compita com o time.',
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
