import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_event.dart';
import 'package:omni_runner/presentation/screens/auth_gate.dart';
import 'package:omni_runner/presentation/screens/coaching_groups_screen.dart';
import 'package:omni_runner/presentation/widgets/login_required_sheet.dart';
import 'package:omni_runner/presentation/screens/invite_friends_screen.dart';
import 'package:omni_runner/presentation/screens/my_assessoria_screen.dart';
import 'package:omni_runner/presentation/screens/profile_screen.dart';
import 'package:omni_runner/presentation/screens/settings_screen.dart';
import 'package:omni_runner/presentation/screens/staff_qr_hub_screen.dart';

/// Hub screen for secondary features: coaching, social, integrations, settings.
///
/// Role-aware: staff users see a reduced menu without running-specific items.
class MoreScreen extends StatelessWidget {
  final String? userRole;

  const MoreScreen({super.key, this.userRole});

  bool get _isStaff => userRole == 'ASSESSORIA_STAFF';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mais'),
        backgroundColor: cs.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (!_isStaff) ...[
            _header(context, 'Assessoria'),
            _ActionTile(
              icon: Icons.groups,
              title: 'Assessorias',
              subtitle: 'Gerenciar assessorias e membros',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Assessorias')) return;
                final uid = sl<UserIdentityProvider>().userId;
                Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => BlocProvider<CoachingGroupsBloc>(
                    create: (_) => sl<CoachingGroupsBloc>()
                      ..add(LoadCoachingGroups(uid)),
                    child: const CoachingGroupsScreen(),
                  ),
                ));
              },
            ),
            _ActionTile(
              icon: Icons.swap_horiz,
              title: 'Minha Assessoria',
              subtitle: 'Ver assessoria atual e trocar',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Assessoria')) return;
                final uid = sl<UserIdentityProvider>().userId;
                Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => BlocProvider<MyAssessoriaBloc>(
                    create: (_) => sl<MyAssessoriaBloc>()
                      ..add(LoadMyAssessoria(uid)),
                    child: const MyAssessoriaScreen(),
                  ),
                ));
              },
            ),
            _ActionTile(
              icon: Icons.qr_code,
              title: 'Operações QR (Staff)',
              subtitle: 'Emitir ou recolher OmniCoins, ativar badge',
              onTap: (ctx) {
                if (LoginRequiredSheet.guard(ctx, feature: 'Operações QR')) return;
                _openStaffQrHub(ctx);
              },
            ),
          ],

          _header(context, 'Social'),
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

          _header(context, 'Conta'),
          const _ActionTile(
            icon: Icons.person,
            title: 'Meu Perfil',
            subtitle: 'Ver e editar seu perfil',
            pushScreen: ProfileScreen(),
          ),

          if (!_isStaff) ...[
            _header(context, 'Integrações'),
            const _ActionTile(
              icon: Icons.watch,
              title: 'Wearables e Saúde',
              subtitle: 'Monitor cardíaco, Apple Health, Health Connect',
              pushScreen: _IntegrationsInfoScreen(),
            ),

            _header(context, 'Configurações'),
            const _ActionTile(
              icon: Icons.record_voice_over,
              title: 'Áudio durante a corrida',
              subtitle: 'Preferências de anúncio por voz',
              pushScreen: SettingsScreen(),
            ),
          ],

          if (_isStaff)
            _header(context, 'Informações'),

          _ActionTile(
            icon: Icons.info_outline,
            title: 'Sobre',
            subtitle: 'Omni Runner v1.0.0',
            onTap: (ctx) => showAboutDialog(
              context: ctx,
              applicationName: 'Omni Runner',
              applicationVersion: '1.0.0',
              applicationLegalese: '\u00a9 2026 Omni Runner',
            ),
          ),

          const SizedBox(height: 16),
          if (sl<UserIdentityProvider>().isAnonymous)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_outline,
                              color: Colors.amber.shade800, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Modo Offline',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900)),
                                const SizedBox(height: 2),
                                Text(
                                  'Crie uma conta para desbloquear desafios, '
                                  'campeonatos e assessorias.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.amber.shade800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                            backgroundColor: Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
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
            role == 'professor' ||
            role == 'assistente';
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
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao verificar permissão. Tente novamente.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _header(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
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
        if (onTap != null) {
          onTap!(context);
        } else if (pushScreen != null) {
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => pushScreen!));
        }
      },
    );
  }
}

/// Tile for features not yet available — shows a SnackBar on tap.
class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String reason;

  const _ComingSoonTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title:
          Text(title, style: TextStyle(color: Colors.grey.shade600)),
      subtitle: Text(subtitle),
      trailing: Chip(
        label: const Text('Em breve', style: TextStyle(fontSize: 10)),
        backgroundColor: Colors.grey.shade200,
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
      ),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason), duration: const Duration(seconds: 2)),
      ),
    );
  }
}

/// Info screen about wearable/health integrations.
class _IntegrationsInfoScreen extends StatelessWidget {
  const _IntegrationsInfoScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wearables e Saúde')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _InfoCard(
            icon: Icons.bluetooth,
            title: 'Monitor Cardíaco Bluetooth',
            body: 'Conecte um monitor de frequência cardíaca (Garmin, Polar, '
                'Wahoo) durante a corrida. O pareamento acontece '
                'automaticamente ao iniciar o treino.',
          ),
          SizedBox(height: 12),
          _InfoCard(
            icon: Icons.favorite,
            title: 'Apple Health / Health Connect',
            body: 'Treinos, frequência cardíaca, passos e rotas GPS são '
                'exportados automaticamente para Apple Health (iOS) ou '
                'Health Connect (Android) após cada corrida.',
          ),
          SizedBox(height: 12),
          _InfoCard(
            icon: Icons.watch,
            title: 'Apple Watch / WearOS',
            body: 'Inicie corridas diretamente no relógio. As sessões '
                'sincronizam automaticamente com o celular.',
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
