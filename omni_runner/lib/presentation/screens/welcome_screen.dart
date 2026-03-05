import 'package:flutter/material.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// First screen a new user sees before login.
///
/// Communicates the app's value proposition in four short bullets
/// and a single CTA that navigates to the login flow.
class WelcomeScreen extends StatefulWidget {
  final VoidCallback onStart;
  final VoidCallback? onExplore;

  const WelcomeScreen({super.key, required this.onStart, this.onExplore});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _bulletsFade;
  late final Animation<double> _ctaFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    ));
    _bulletsFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.3, 0.75, curve: Curves.easeOut),
    );
    _ctaFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 24),

                      SlideTransition(
                        position: _logoSlide,
                        child: FadeTransition(
                          opacity: _logoFade,
                          child: Column(
                            children: [
                              Icon(
                                Icons.directions_run_rounded,
                                size: 80,
                                color: primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Seu app de corrida completo',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: primary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Treinos, desafios, métricas e assessoria — tudo em um app.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      FadeTransition(
                        opacity: _bulletsFade,
                        child: const Column(
                          children: [
                            _Bullet(
                              icon: Icons.sync,
                              text: 'Importe corridas via Strava',
                              subtitle: 'Funciona com qualquer relógio',
                            ),
                            SizedBox(height: 12),
                            _Bullet(
                              icon: Icons.emoji_events,
                              text: 'Desafie amigos com OmniCoins',
                              subtitle: 'Competições com moedas virtuais',
                            ),
                            SizedBox(height: 12),
                            _Bullet(
                              icon: Icons.auto_graph,
                              text: 'Descubra seu DNA de Corredor',
                              subtitle: 'Perfil único de 6 dimensões',
                            ),
                            SizedBox(height: 12),
                            _Bullet(
                              icon: Icons.groups,
                              text: 'Treine com sua assessoria',
                              subtitle: 'Ranking, liga e campeonatos',
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),
                      const SizedBox(height: 24),

                      FadeTransition(
                        opacity: _ctaFade,
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: FilledButton(
                                onPressed: widget.onStart,
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: const Text('COMEÇAR'),
                              ),
                            ),
                            if (widget.onExplore != null) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: widget.onExplore,
                                child: Text(
                                  'Explorar sem conta',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? subtitle;

  const _Bullet({required this.icon, required this.text, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 28, color: theme.colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

