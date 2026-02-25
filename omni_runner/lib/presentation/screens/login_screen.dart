import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/config/app_config.dart';
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
  bool _showEmailForm = false;
  bool _isSignUp = false;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  AuthRepository get _auth => sl<AuthRepository>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    if (!_checkConnection()) return;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Preencha email e senha.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _errorMessage = 'A senha deve ter pelo menos 6 caracteres.');
      return;
    }
    _clearError();
    setState(() => _busy = true);

    final result = _isSignUp
        ? await _auth.signUp(email: email, password: pass)
        : await _auth.signIn(email: email, password: pass);

    if (!mounted) return;
    setState(() => _busy = false);

    if (result.failure != null) {
      _handleFailure(result.failure!);
      return;
    }
    widget.onSuccess();
  }

  Future<void> _resetPassword() async {
    if (!_checkConnection()) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Digite seu email acima para recuperar a senha.');
      return;
    }
    _clearError();
    setState(() => _busy = true);

    final failure = await _auth.resetPassword(email: email);

    if (!mounted) return;
    setState(() => _busy = false);

    if (failure != null) {
      _handleFailure(failure);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Email de recuperação enviado para $email'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (!_checkConnection()) return;
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
    if (!_checkConnection()) return;
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

  bool _checkConnection() {
    if (!AppConfig.isSupabaseReady) {
      setState(() => _errorMessage =
          'Sem conexão com o servidor. Verifique sua internet e tente novamente.');
      return false;
    }
    return true;
  }

  Future<void> _signInWithInstagram() async {
    if (!_checkConnection()) return;
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
                    icon: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFFCAF45),
                          Color(0xFFE1306C),
                          Color(0xFFC13584),
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ).createShader(bounds),
                      child: const Icon(Icons.camera_alt, size: 24,
                          color: Colors.white),
                    ),
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

                // Email/password
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => _showEmailForm = !_showEmailForm),
                    icon: const Icon(Icons.email_outlined, size: 22),
                    label: const Text('Continuar com Email'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade400),
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

                if (_showEmailForm) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _signInWithEmail(),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _signInWithEmail,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_isSignUp ? 'Criar conta' : 'Entrar'),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _isSignUp = !_isSignUp),
                        child: Text(
                          _isSignUp
                              ? 'Já tem conta? Entrar'
                              : 'Não tem conta? Criar agora',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      if (!_isSignUp) ...[
                        Text('·',
                            style: TextStyle(color: Colors.grey.shade400)),
                        TextButton(
                          onPressed: _resetPassword,
                          child: Text(
                            'Esqueci a senha',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
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
