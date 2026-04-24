import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/widgets/login_required_sheet.dart';
import 'package:omni_runner/core/logging/logger.dart';


/// Hub screen for secondary features: coaching, social, integrations, settings.
///
/// Role-aware: staff users see a reduced menu without running-specific items.
class MoreScreen extends StatefulWidget {
  final String? userRole;

  const MoreScreen({super.key, this.userRole});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _busy = false;

  bool get _isStaff => widget.userRole == 'ASSESSORIA_STAFF';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.more),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spacingSm,
          horizontal: DesignTokens.spacingMd,
        ),
        children: [
          if (!_isStaff) _sectionCard(context, 'Treinos', [
            _ActionTile(
              icon: Icons.qr_code_scanner,
              title: 'Escanear QR',
              subtitle: 'Ler QR da assessoria para receber ou devolver OmniCoins',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'QR Scanner')) return;
                _openAthleteScan(ctx);
              },
            ),
            _ActionTile(
              icon: Icons.delivery_dining,
              title: 'Entregas Pendentes',
              subtitle: 'Treinos enviados pela assessoria para seu relógio',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Entregas')) return;
                ctx.push(AppRoutes.workoutDelivery);
              },
            ),
            _ActionTile(
              icon: Icons.watch_outlined,
              title: 'Meus envios ao relógio',
              subtitle:
                  'Histórico de treinos que você mandou pro seu relógio (.fit)',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Meus envios')) {
                  return;
                }
                ctx.push(AppRoutes.myExports);
              },
            ),
            _ActionTile(
              icon: Icons.fitness_center,
              title: 'Meu Treino do Dia',
              subtitle: 'Ver o treino agendado para hoje',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Treino do Dia')) return;
                ctx.push(AppRoutes.workoutDelivery);
              },
            ),
          ]),

          if (_isStaff) _sectionCard(context, 'Minha Assessoria (grupo de corrida com treinador)', [
            _ActionTile(
              icon: Icons.handshake,
              title: 'Assessorias Parceiras',
              subtitle: 'Parcerias e campeonatos entre assessorias',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Parceiras')) return;
                _openPartnerAssessorias(ctx);
              },
            ),
            _ActionTile(
              icon: Icons.qr_code,
              title: 'Operações QR',
              subtitle: 'Emitir ou recolher OmniCoins, ativar badge',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Operações QR')) return;
                _openStaffQrHub(ctx);
              },
            ),
          ]),

          if (!_isStaff) _sectionCard(context, 'Social', [
            _ActionTile(
              icon: Icons.people_alt_rounded,
              title: 'Convidar amigos',
              subtitle: 'Compartilhe o app com outros corredores',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Convites')) return;
                ctx.push(AppRoutes.inviteFriends);
              },
            ),
            _ActionTile(
              icon: Icons.group_rounded,
              title: 'Meus Amigos',
              subtitle: 'Amigos são corredores individuais, independente de assessoria',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Amigos')) return;
                ctx.push(AppRoutes.friends);
              },
            ),
            _ActionTile(
              icon: Icons.dynamic_feed_rounded,
              title: 'Atividade dos amigos',
              subtitle: 'Corridas recentes dos seus amigos',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Atividade dos amigos')) return;
                ctx.push(AppRoutes.friendsActivity);
              },
            ),
          ]),

          _sectionCard(context, 'Conta', [
            _ActionTile(
              icon: Icons.person,
              title: 'Meu Perfil',
              subtitle: 'Ver e editar seu perfil',
              onTap: (ctx) => ctx.push(AppRoutes.profile),
            ),
            _ActionTile(
              icon: Icons.tune,
              title: context.l10n.settings,
              subtitle: _isStaff ? 'Aparência' : 'Strava, tema e unidades',
              onTap: (ctx) => ctx.push(
                _isStaff ? '${AppRoutes.settings}?staff=true' : AppRoutes.settings,
              ),
            ),
          ]),

          _sectionCard(context, 'Ajuda', [
            if (_isStaff) _ActionTile(
              icon: Icons.support_agent,
              title: context.l10n.support,
              subtitle: 'Suporte da plataforma Omni Runner',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Suporte')) return;
                _openSupport(ctx);
              },
            ),
            _ActionTile(
              icon: Icons.help_outline,
              title: 'Perguntas Frequentes',
              subtitle: 'Dúvidas comuns sobre o app',
              onTap: (ctx) => ctx.push(
                _isStaff ? '${AppRoutes.faq}?staff=true' : AppRoutes.faq,
              ),
            ),
            _ActionTile(
              icon: Icons.info_outline,
              title: context.l10n.about,
              subtitle: 'Omni Runner',
              onTap: (ctx) async {
                final info = await PackageInfo.fromPlatform();
                if (!ctx.mounted) return;
                showAboutDialog(
                  context: ctx,
                  applicationName: 'Omni Runner',
                  applicationVersion: '${info.version} (${info.buildNumber})',
                  applicationLegalese: '\u00a9 2026 Omni Runner',
                );
              },
            ),
          ]),

          const SizedBox(height: DesignTokens.spacingMd),
          if (sl<UserIdentityProvider>().isAnonymous)
            Card(
                color: DesignTokens.warning.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_outline,
                              color: DesignTokens.warning, size: 28),
                          SizedBox(width: DesignTokens.spacingMd),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Modo Offline',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: DesignTokens.warning)),
                                SizedBox(height: DesignTokens.spacingXs),
                                Text(
                                  'Crie uma conta para desbloquear desafios, '
                                  'campeonatos e assessorias.',
                                  style: TextStyle(
                                      fontSize: 12, color: DesignTokens.warning),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spacingSm),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            AppConfig.demoMode = false;
                            context.go(AppRoutes.welcome);
                          },
                          icon: const Icon(Icons.login_rounded, size: 18),
                          label: const Text('Criar conta / Entrar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: DesignTokens.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ),
          if (!sl<UserIdentityProvider>().isAnonymous) ...[
            const SizedBox(height: DesignTokens.spacingMd),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _signOut(context),
                  icon: _busy
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.logout_rounded),
                  label: Text(context.l10n.logout),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error),
                    padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
                  ),
                ),
            ),
          ],
          const SizedBox(height: DesignTokens.spacingLg),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    if (_busy) return;
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.logout_rounded, color: cs.error, size: 40),
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você será redirecionado para a tela de login. '
          'Seus dados não serão perdidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => ctx.pop(true),
            child: Text(context.l10n.logout),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _busy = true);
    try {
      await sl<AuthRepository>().signOut();
      if (!context.mounted) return;
      context.go(AppRoutes.welcome);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPartnerAssessorias(BuildContext context) async {
    final uid = sl<UserIdentityProvider>().userId;
    try {
      final rows = await sl<SupabaseClient>()
          .from('coaching_members')
          .select('group_id, role')
          .eq('user_id', uid);
      final staffRow = (rows as List).cast<Map<String, dynamic>>().where((r) {
        final role = r['role'] as String? ?? '';
        return role == 'admin_master' || role == 'coach' || role == 'assistant';
      }).firstOrNull;
      if (!context.mounted) return;
      if (staffRow == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acesso restrito a staff.')),
        );
        return;
      }
      context.push(AppRoutes.partnerAssessoriasPath(staffRow['group_id'] as String));
    } on Object catch (e) {
      AppLogger.warn('Caught error', tag: 'MoreScreen', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao carregar. Tente novamente.')),
      );
    }
  }

  void _openAthleteScan(BuildContext context) {
    context.push(AppRoutes.staffScanQr);
  }

  Future<void> _openStaffQrHub(BuildContext context) async {
    final uid = sl<UserIdentityProvider>().userId;

    try {
      final rows = await sl<SupabaseClient>()
          .from('coaching_members')
          .select('id, user_id, group_id, display_name, role, joined_at_ms')
          .eq('user_id', uid);

      final staffRow = (rows as List).cast<Map<String, dynamic>>().where((r) {
        final role = r['role'] as String? ?? '';
        return role == 'admin_master' ||
            role == 'coach' ||
            role == 'assistant';
      }).firstOrNull;

      if (!context.mounted) return;
      if (staffRow == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Acesso restrito a staff (admin master, professor ou assistente).',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final membership = CoachingMemberEntity(
        id: staffRow['id'] as String,
        userId: staffRow['user_id'] as String,
        groupId: staffRow['group_id'] as String,
        displayName: (staffRow['display_name'] as String?) ?? '',
        role: coachingRoleFromString(staffRow['role'] as String? ?? ''),
        joinedAtMs: (staffRow['joined_at_ms'] as num?)?.toInt() ?? 0,
      );

      context.push(AppRoutes.staffQrHub, extra: membership);
    } on Object catch (e) {
      AppLogger.warn('Caught error', tag: 'MoreScreen', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao verificar permissão. Tente novamente.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _sectionCard(BuildContext context, String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacingMd,
              DesignTokens.spacingMd,
              DesignTokens.spacingMd,
              DesignTokens.spacingXs,
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Future<void> _openSupport(BuildContext context) async {
    final uid = sl<UserIdentityProvider>().userId;
    try {
      final rows = await sl<SupabaseClient>()
          .from('coaching_members')
          .select('group_id')
          .eq('user_id', uid)
          .limit(1);
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (!context.mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você precisa estar em uma assessoria para acessar o suporte.')),
        );
        return;
      }
      final groupId = list.first['group_id'] as String;
      context.push(AppRoutes.supportPath(groupId));
    } on Object catch (e) {
      AppLogger.warn('Failed to open support', tag: 'MoreScreen', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao carregar. Tente novamente.')),
      );
    }
  }
}

/// Navigable tile that calls a custom [onTap].
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final void Function(BuildContext)? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final tap = onTap;
        if (tap != null) {
          tap(context);
        }
      },
    );
  }
}

