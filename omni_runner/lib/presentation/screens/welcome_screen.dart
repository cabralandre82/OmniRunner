import 'package:flutter/material.dart';

/// First screen a new user sees before login.
///
/// Communicates the app's value proposition in four short bullets
/// and a single CTA that navigates to the login flow.
class WelcomeScreen extends StatelessWidget {
  final VoidCallback onStart;

  const WelcomeScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo / icon
              Icon(
                Icons.directions_run_rounded,
                size: 96,
                color: primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Omni Runner',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),

              const SizedBox(height: 40),

              // Value propositions
              const _Bullet(
                icon: Icons.emoji_events_outlined,
                text: 'Desafie corredores',
              ),
              const SizedBox(height: 16),
              const _Bullet(
                icon: Icons.groups_outlined,
                text: 'Treine com sua assessoria',
              ),
              const SizedBox(height: 16),
              const _Bullet(
                icon: Icons.military_tech_outlined,
                text: 'Participe de campeonatos',
              ),
              const SizedBox(height: 16),
              const _Bullet(
                icon: Icons.insights_outlined,
                text: 'Evolua com métricas reais',
              ),

              const Spacer(flex: 3),

              // CTA
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('COMEÇAR'),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Bullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 28, color: theme.colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
