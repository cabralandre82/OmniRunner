import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';

/// Onboarding screen where the user picks their role.
///
/// Calls `set-user-role` Edge Function — both roles stay at ROLE_SELECTED.
/// [AuthGate] re-resolves and routes to the appropriate next screen:
///   - ATLETA → [JoinAssessoriaScreen]
///   - ASSESSORIA_STAFF → [StaffSetupScreen]
class OnboardingRoleScreen extends StatefulWidget {
  final OnboardingState initialState;
  final VoidCallback onComplete;
  final VoidCallback? onBack;

  const OnboardingRoleScreen({
    super.key,
    required this.initialState,
    required this.onComplete,
    this.onBack,
  });

  @override
  State<OnboardingRoleScreen> createState() => _OnboardingRoleScreenState();
}

class _OnboardingRoleScreenState extends State<OnboardingRoleScreen> {
  static const _tag = 'OnboardingRole';

  String? _selectedRole;
  bool _busy = false;
  String? _error;

  Future<void> _showConfirmDialog() async {
    final roleName = _selectedRole == 'ATLETA' ? 'Atleta' : 'Assessoria';
    final roleDesc = _selectedRole == 'ATLETA'
        ? 'Você vai treinar, participar de desafios e acompanhar sua evolução.'
        : 'Você vai gerenciar atletas, organizar eventos e acompanhar seu grupo.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Colors.orange.shade700, size: 48),
        title: Text('Confirmar: $roleName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(roleDesc,
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock, size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Essa escolha é permanente e não pode ser alterada depois. '
                      'Se precisar trocar, entre em contato com o suporte.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Sim, sou $roleName'),
          ),
        ],
      ),
    );

    if (confirmed == true) _confirm();
  }

  Future<void> _confirm() async {
    if (_selectedRole == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      Map<String, dynamic>? lastData;
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          final res = await Supabase.instance.client.functions.invoke(
            'set-user-role',
            body: {'role': _selectedRole},
          );
          lastData = res.data as Map<String, dynamic>? ?? {};
          if (lastData['ok'] == true) break;
        } catch (e) {
          AppLogger.warn('set-user-role attempt $attempt/3: $e', tag: _tag);
          if (attempt == 3) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }

      if (lastData?['ok'] != true) {
        final err = lastData?['error'] as Map<String, dynamic>?;
        throw Exception(err?['message'] ?? 'Erro ao salvar papel');
      }

      AppLogger.info('set-user-role OK: $_selectedRole', tag: _tag);

      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      AppLogger.error('Role selection failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível salvar. Verifique sua conexão e tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              if (widget.onBack != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _busy ? null : widget.onBack,
                    tooltip: 'Voltar para o login',
                  ),
                ),
              ],
              const Spacer(flex: 2),

              Text(
                'Como você quer usar\no Omni Runner?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Essa escolha é permanente e define toda a sua experiência no app.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              // Role cards
              _RoleOption(
                icon: Icons.directions_run_rounded,
                title: 'Sou atleta',
                subtitle: 'Treinar, competir em desafios e acompanhar minha evolução',
                selected: _selectedRole == 'ATLETA',
                onTap: _busy ? null : () => setState(() => _selectedRole = 'ATLETA'),
              ),
              const SizedBox(height: 14),
              _RoleOption(
                icon: Icons.groups_rounded,
                title: 'Represento uma assessoria',
                subtitle: 'Gerenciar atletas, organizar eventos e acompanhar o grupo',
                selected: _selectedRole == 'ASSESSORIA_STAFF',
                onTap: _busy
                    ? null
                    : () => setState(() => _selectedRole = 'ASSESSORIA_STAFF'),
              ),

              if (_error != null) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const Spacer(flex: 2),

              // Confirm button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _selectedRole != null && !_busy
                      ? _showConfirmDialog
                      : null,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Continuar'),
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

class _RoleOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const _RoleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? primary : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
        color: selected
            ? primary.withValues(alpha: 0.06)
            : theme.colorScheme.surface,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? primary.withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: selected ? primary : Colors.grey.shade600),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? primary : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Radio<bool>(
                value: true,
                groupValue: selected ? true : null,
                onChanged: (_) => onTap?.call(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
