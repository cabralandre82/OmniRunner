import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/failures/auth_failure.dart';

/// Login screen with social sign-in buttons (Google, Apple, Instagram, TikTok).
///
/// Calls [onSuccess] after a successful authentication so the [AuthGate]
/// can re-evaluate the routing destination.
///
/// When [hasPendingInvite] is true, a banner informs the user that their
/// invite link was captured and will be applied after login.
class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  final bool hasPendingInvite;

  const LoginScreen({
    super.key,
    required this.onSuccess,
    this.hasPendingInvite = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _errorMessage;

  AuthRepository get _auth => sl<AuthRepository>();

  Future<void> _signInWithGoogle() async {
    _clearError();
    setState(() => _busy = true);
    final result = await _auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.failure != null) {
      _handleFailure(result.failure!);
      return;
    }
    widget.onSuccess();
  }

  Future<void> _signInWithApple() async {
    _clearError();
    setState(() => _busy = true);
    final result = await _auth.signInWithApple();
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.failure != null) {
      _handleFailure(result.failure!);
      return;
    }
    widget.onSuccess();
  }

  Future<void> _signInWithInstagram() async {
    _clearError();
    setState(() => _busy = true);
    final result = await _auth.signInWithInstagram();
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.failure != null) {
      _handleFailure(result.failure!);
      return;
    }
    widget.onSuccess();
  }

  void _handleFailure(AuthFailure f) {
    if (f is AuthSocialCancelled) return;
    if (!mounted) return;
    setState(() => _errorMessage = f.message);
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // Header
              Icon(
                Icons.directions_run_rounded,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Entrar no Omni Runner',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Use sua conta para sincronizar treinos, '
                'desafios e progresso entre dispositivos.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),

              if (widget.hasPendingInvite) ...[
                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.group_add_rounded,
                          size: 22, color: theme.colorScheme.onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Você recebeu um convite! '
                          'Faça login para entrar na assessoria.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(flex: 2),

              // Buttons or spinner
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                )
              else ...[
                // Google
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _signInWithGoogle,
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                    label: const Text('Continuar com Google'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Apple (iOS only)
                if (Platform.isIOS) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _signInWithApple,
                      icon: const Icon(Icons.apple_rounded, size: 26),
                      label: const Text('Continuar com Apple'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Instagram (via Meta/Facebook OAuth)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _signInWithInstagram,
                    icon: const Icon(Icons.camera_alt_outlined, size: 24),
                    label: const Text('Continuar com Instagram'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE1306C),
                      side: const BorderSide(color: Color(0xFFE1306C)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // TikTok — hidden until validate-social-login EF is deployed
              ],

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
