import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/screens/invite_qr_screen.dart';
import 'package:omni_runner/presentation/screens/staff_generate_qr_screen.dart';
import 'package:omni_runner/presentation/screens/staff_scan_qr_screen.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Hub screen for staff QR operations. Gated by [CoachingMemberEntity.isStaff].
///
/// If the user is not staff, an access-denied message is shown.
/// Otherwise, three operations are available:
///   - Emitir Token (issue to athlete)
///   - Queimar Token (burn from athlete)
///   - Ativar Badge de Campeonato
/// Plus a scan option for athletes.
class StaffQrHubScreen extends StatelessWidget {
  final CoachingMemberEntity membership;

  const StaffQrHubScreen({super.key, required this.membership});

  @override
  Widget build(BuildContext context) {
    if (!membership.isStaff) return _buildAccessDenied(context);

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Operações QR')),
      body: ListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          _SectionHeader(title: 'Convite da Assessoria', theme: theme),
          _OperationCard(
            icon: Icons.qr_code_rounded,
            title: 'QR de Convite',
            subtitle: 'Compartilhar link para novos membros',
            color: theme.colorScheme.primary,
            onTap: () => _pushInviteQr(context),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Gerar QR (Staff)', theme: theme),
          _OperationCard(
            icon: Icons.card_giftcard,
            title: 'Emitir OmniCoins',
            subtitle: 'Gerar QR para atleta receber moedas',
            color: DesignTokens.success,
            onTap: () => _pushGenerate(
              context,
              TokenIntentType.issueToAthlete,
            ),
          ),
          const SizedBox(height: 8),
          _OperationCard(
            icon: Icons.local_fire_department,
            title: 'Recolher OmniCoins',
            subtitle: 'Gerar QR para atleta devolver moedas',
            color: DesignTokens.warning,
            onTap: () => _pushGenerate(
              context,
              TokenIntentType.burnFromAthlete,
            ),
          ),
          const SizedBox(height: 8),
          _OperationCard(
            icon: Icons.military_tech,
            title: 'Ativar Badge de Campeonato',
            subtitle: 'Gerar QR para inscrição via badge temporário',
            color: DesignTokens.primary,
            onTap: () => _pushGenerate(
              context,
              TokenIntentType.champBadgeActivate,
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Escanear QR', theme: theme),
          _OperationCard(
            icon: Icons.qr_code_scanner,
            title: 'Ler QR Code',
            subtitle: 'Escanear um QR gerado pela equipe para executar operação',
            color: theme.colorScheme.primary,
            onTap: () => _pushScan(context),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DesignTokens.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: Border.all(color: DesignTokens.warning.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    color: DesignTokens.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cada QR tem validade limitada e código de uso único. '
                    'Após expirar ou ser utilizado, não pode ser reaproveitado.',
                    style: TextStyle(
                      fontSize: 12,
                      color: DesignTokens.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pushInviteQr(BuildContext context) async {
    final group = await sl<ICoachingGroupRepo>().getById(membership.groupId);
    final inviteCode = group?.inviteCode;
    if (group == null || inviteCode == null || inviteCode.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código de convite não disponível.')),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => InviteQrScreen(
        inviteCode: inviteCode,
        groupName: group.name,
      ),
    ));
  }

  void _pushGenerate(BuildContext context, TokenIntentType type) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider<StaffQrBloc>(
        create: (_) => StaffQrBloc(repo: sl<ITokenIntentRepo>()),
        child: StaffGenerateQrScreen(
          type: type,
          groupId: membership.groupId,
        ),
      ),
    ));
  }

  void _pushScan(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider<StaffQrBloc>(
        create: (_) => StaffQrBloc(repo: sl<ITokenIntentRepo>()),
        child: const StaffScanQrScreen(),
      ),
    ));
  }

  Widget _buildAccessDenied(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Operações QR')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Acesso Restrito',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Apenas membros staff (admin master, professor ou assistente) '
                'podem acessar as operações QR.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm, top: DesignTokens.spacingXs),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _OperationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
