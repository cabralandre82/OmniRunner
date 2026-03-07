import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Displays group details and member list, querying Supabase directly.
class CoachingGroupDetailsScreen extends StatefulWidget {
  final String groupId;
  final String callerUserId;

  const CoachingGroupDetailsScreen({
    super.key,
    required this.groupId,
    required this.callerUserId,
  });

  @override
  State<CoachingGroupDetailsScreen> createState() =>
      _CoachingGroupDetailsScreenState();
}

class _CoachingGroupDetailsScreenState
    extends State<CoachingGroupDetailsScreen> {
  bool _loading = true;
  String? _error;
  CoachingGroupEntity? _group;
  List<CoachingMemberEntity> _members = [];
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = Supabase.instance.client;

      final groupRow = await db
          .from('coaching_groups')
          .select('id, name, logo_url, coach_user_id, description, city, invite_code, invite_enabled, created_at_ms')
          .eq('id', widget.groupId)
          .maybeSingle();

      if (groupRow == null) {
        if (mounted) setState(() { _error = 'Assessoria não encontrada.'; _loading = false; });
        return;
      }

      _group = CoachingGroupEntity(
        id: widget.groupId,
        name: (groupRow['name'] as String?) ?? 'Assessoria',
        logoUrl: groupRow['logo_url'] as String?,
        coachUserId: (groupRow['coach_user_id'] as String?) ?? '',
        description: (groupRow['description'] as String?) ?? '',
        city: (groupRow['city'] as String?) ?? '',
        inviteCode: groupRow['invite_code'] as String?,
        inviteEnabled: (groupRow['invite_enabled'] as bool?) ?? true,
        createdAtMs: (groupRow['created_at_ms'] as num?)?.toInt() ?? 0,
      );

      final membersRes = await db
          .from('coaching_members')
          .select('id, user_id, group_id, display_name, role, joined_at_ms')
          .eq('group_id', widget.groupId)
          .order('role')
          .order('joined_at_ms');

      _members = (membersRes as List)
          .cast<Map<String, dynamic>>()
          .map((r) => CoachingMemberEntity(
                id: r['id'] as String,
                userId: r['user_id'] as String,
                groupId: r['group_id'] as String,
                displayName: (r['display_name'] as String?) ?? '',
                role: coachingRoleFromString(r['role'] as String? ?? ''),
                joinedAtMs: (r['joined_at_ms'] as num?)?.toInt() ?? 0,
              ))
          .toList();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar dados: $e';
          _loading = false;
        });
      }
    }
  }

  CoachingRole? get _callerRole {
    final caller = _members
        .where((m) => m.userId == widget.callerUserId)
        .firstOrNull;
    return caller?.role;
  }

  bool _canRemove(CoachingMemberEntity target) {
    final role = _callerRole;
    if (role == null) return false;
    if (target.userId == widget.callerUserId) return false;
    if (target.role == CoachingRole.adminMaster) return false;
    if (role == CoachingRole.assistant && target.isStaff) return false;
    return role == CoachingRole.adminMaster ||
        role == CoachingRole.coach ||
        role == CoachingRole.assistant;
  }

  Future<void> _removeMember(CoachingMemberEntity member) async {
    final roleLabel = switch (member.role) {
      CoachingRole.adminMaster => 'Admin Master',
      CoachingRole.coach => 'Coach',
      CoachingRole.assistant => 'Assistente',
      CoachingRole.athlete => 'Atleta',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.person_remove_rounded,
            size: 40, color: Theme.of(ctx).colorScheme.error),
        title: const Text('Remover membro?'),
        content: Text(
          'Tem certeza que deseja remover ${member.displayName} ($roleLabel) '
          'da assessoria?\n\n'
          'O membro perderá acesso à assessoria e seus OmniCoins '
          'vinculados serão desassociados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await Supabase.instance.client.rpc(
        'fn_remove_member',
        params: {
          'p_target_user_id': member.userId,
          'p_group_id': widget.groupId,
        },
      );
      final status = (res as Map<String, dynamic>?)?['status'];
      if (!mounted) return;

      if (status == 'removed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.displayName} removido da assessoria.'),
            backgroundColor: DesignTokens.success,
          ),
        );
        _load();
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final userMsg = msg.contains('CANNOT_REMOVE_ADMIN_MASTER')
          ? 'O Admin Master não pode ser removido.'
          : msg.contains('INSUFFICIENT_ROLE')
              ? 'Você não tem permissão para remover este membro.'
              : msg.contains('CANNOT_REMOVE_SELF')
                  ? 'Você não pode remover a si mesmo.'
                  : 'Erro ao remover membro. Tente novamente.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMsg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Atletas e Staff')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Atletas e Staff')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final group = _group!;
    final visibleMembers =
        _showAll || _members.length <= 5 ? _members : _members.sublist(0, 5);

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            _HeaderCard(group: group, memberCount: _members.length),
            Padding(
              padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, 20, DesignTokens.spacingMd, DesignTokens.spacingSm),
              child: Row(
                children: [
                  Text(
                    'Membros (${_members.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_members.length > 5)
                    TextButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      child: Text(_showAll ? 'Ver menos' : 'Ver todos'),
                    ),
                ],
              ),
            ),
            if (visibleMembers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
                child: Text(
                  'Nenhum membro encontrado.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              )
            else
              ...visibleMembers.map(
                (m) => _CoachingMemberTile(
                  member: m,
                  isCurrentUser: m.userId == widget.callerUserId,
                  canRemove: _canRemove(m),
                  onRemove: () => _removeMember(m),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final CoachingGroupEntity group;
  final int memberCount;

  const _HeaderCard({required this.group, required this.memberCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: group.logoUrl != null
                      ? CachedNetworkImageProvider(group.logoUrl!)
                      : null,
                  child: group.logoUrl == null
                      ? Icon(Icons.sports,
                          color: theme.colorScheme.primary, size: 28)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$memberCount membros'
                        '${group.city.isNotEmpty ? ' · ${group.city}' : ''}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (group.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(group.description, style: theme.textTheme.bodyMedium),
            ],
            if (group.inviteCode != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.push(
                      AppRoutes.inviteQr,
                      extra: InviteQrExtra(
                        inviteCode: group.inviteCode!,
                        groupName: group.name,
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code_rounded, size: 20),
                  label: const Text('Compartilhar convite'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachingMemberTile extends StatelessWidget {
  final CoachingMemberEntity member;
  final bool isCurrentUser;
  final bool canRemove;
  final VoidCallback? onRemove;

  const _CoachingMemberTile({
    required this.member,
    this.isCurrentUser = false,
    this.canRemove = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final roleLabel = switch (member.role) {
      CoachingRole.adminMaster => 'Admin Master',
      CoachingRole.coach => 'Coach',
      CoachingRole.assistant => 'Assistente',
      CoachingRole.athlete => 'Atleta',
    };
    final roleColor = switch (member.role) {
      CoachingRole.adminMaster => DesignTokens.warning,
      CoachingRole.coach => DesignTokens.info,
      CoachingRole.assistant => DesignTokens.primary,
      CoachingRole.athlete => theme.colorScheme.outline,
    };

    final name = isCurrentUser
        ? '${member.displayName} (você)'
        : member.displayName;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person, color: theme.colorScheme.outline),
      ),
      title: Text(
        name,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(top: DesignTokens.spacingXs),
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 2),
          decoration: BoxDecoration(
            color: roleColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Text(
            roleLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: roleColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      trailing: canRemove
          ? IconButton(
              icon: Icon(Icons.person_remove_outlined,
                  color: theme.colorScheme.error, size: 20),
              tooltip: 'Remover membro',
              onPressed: onRemove,
            )
          : null,
    );
  }
}
