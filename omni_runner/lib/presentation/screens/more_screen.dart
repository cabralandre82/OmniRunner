import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/screens/auth_gate.dart';
import 'package:omni_runner/presentation/widgets/login_required_sheet.dart';

import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_event.dart';
import 'package:omni_runner/presentation/screens/friends_screen.dart';
import 'package:omni_runner/presentation/screens/invite_friends_screen.dart';
import 'package:omni_runner/presentation/screens/profile_screen.dart';
import 'package:omni_runner/presentation/screens/settings_screen.dart';
import 'package:omni_runner/presentation/screens/workout_delivery_screen.dart';
import 'package:omni_runner/presentation/screens/staff_qr_hub_screen.dart';
import 'package:omni_runner/presentation/screens/staff_scan_qr_screen.dart';
import 'package:omni_runner/presentation/screens/friends_activity_feed_screen.dart';
import 'package:omni_runner/presentation/screens/partner_assessorias_screen.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/presentation/screens/faq_screen.dart';
import 'package:omni_runner/presentation/screens/support_screen.dart';


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
        backgroundColor: cs.inversePrimary,
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
                Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => const WorkoutDeliveryScreen(),
                ));
              },
            ),
            _ActionTile(
              icon: Icons.fitness_center,
              title: 'Meu Treino do Dia',
              subtitle: 'Ver o treino agendado para hoje',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Treino do Dia')) return;
                Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => const WorkoutDeliveryScreen(),
                ));
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
                Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => const InviteFriendsScreen(),
                ));
              },
            ),
            _ActionTile(
              icon: Icons.group_rounded,
              title: 'Meus Amigos',
              subtitle: 'Amigos são corredores individuais, independente de assessoria',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Amigos')) return;
                Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => BlocProvider(
                    create: (_) => sl<FriendsBloc>()
                      ..add(LoadFriends(sl<UserIdentityProvider>().userId)),
                    child: const FriendsScreen(),
                  ),
                ));
              },
            ),
            _ActionTile(
              icon: Icons.dynamic_feed_rounded,
              title: 'Atividade dos amigos',
              subtitle: 'Corridas recentes dos seus amigos',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Atividade dos amigos')) return;
                Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => const FriendsActivityFeedScreen(),
                ));
              },
            ),
          ]),

          _sectionCard(context, 'Conta', [
            const _ActionTile(
              icon: Icons.person,
              title: 'Meu Perfil',
              subtitle: 'Ver e editar seu perfil',
              pushScreen: ProfileScreen(),
            ),
            _ActionTile(
              icon: Icons.tune,
              title: context.l10n.settings,
              subtitle: _isStaff ? 'Aparência' : 'Strava, tema e unidades',
              pushScreen: SettingsScreen(isStaff: _isStaff),
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
              pushScreen: FaqScreen(isStaff: _isStaff),
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
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute<void>(
                                builder: (_) => const AuthGate(),
                              ),
                              (_) => false,
                            );
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
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.pop(ctx, true),
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
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPartnerAssessorias(BuildContext context) async {
    final uid = sl<UserIdentityProvider>().userId;
    try {
      final rows = await Supabase.instance.client
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
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PartnerAssessoriasScreen(groupId: staffRow['group_id'] as String),
      ));
    } catch (e) {
      AppLogger.warn('Caught error', tag: 'MoreScreen', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao carregar. Tente novamente.')),
      );
    }
  }

  void _openAthleteScan(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider<StaffQrBloc>(
        create: (_) => StaffQrBloc(repo: sl<ITokenIntentRepo>()),
        child: const StaffScanQrScreen(),
      ),
    ));
  }

  Future<void> _openStaffQrHub(BuildContext context) async {
    final uid = sl<UserIdentityProvider>().userId;

    try {
      final rows = await Supabase.instance.client
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

      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StaffQrHubScreen(membership: membership),
      ));
    } catch (e) {
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
      final rows = await Supabase.instance.client
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
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SupportScreen(groupId: groupId),
      ));
    } catch (e) {
      AppLogger.warn('Failed to open support', tag: 'MoreScreen', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao carregar. Tente novamente.')),
      );
    }
  }
}

/// Navigable tile that either pushes a screen or calls a custom [onTap].
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? pushScreen;
  final void Function(BuildContext)? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.pushScreen,
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
        final screen = pushScreen;
        if (tap != null) {
          tap(context);
        } else if (screen != null) {
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => screen));
        }
      },
    );
  }
}

