import 'package:flutter/material.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';

/// Full-list view of all members in a coaching group.
///
/// Receives the member list and current user ID directly.
/// Typically pushed from [CoachingGroupDetailsScreen].
class GroupMembersScreen extends StatelessWidget {
  final String groupName;
  final List<CoachingMemberEntity> members;
  final String currentUserId;

  const GroupMembersScreen({
    super.key,
    required this.groupName,
    required this.members,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Membros · $groupName')),
      body: members.isEmpty
          ? Center(
              child: Text(
                'Nenhum membro encontrado.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: members.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final m = members[index];
                return _MemberRow(
                  member: m,
                  isCurrentUser: m.userId == currentUserId,
                );
              },
            ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final CoachingMemberEntity member;
  final bool isCurrentUser;

  const _MemberRow({
    required this.member,
    this.isCurrentUser = false,
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
      CoachingRole.adminMaster => Colors.amber.shade700,
      CoachingRole.coach => Colors.deepPurple,
      CoachingRole.assistant => Colors.blue,
      CoachingRole.athlete => theme.colorScheme.outline,
    };
    final roleIcon = switch (member.role) {
      CoachingRole.adminMaster => Icons.star,
      CoachingRole.coach => Icons.school,
      CoachingRole.assistant => Icons.assistant,
      CoachingRole.athlete => Icons.directions_run,
    };

    final name = isCurrentUser
        ? '${member.displayName} (você)'
        : member.displayName;

    final joinedDate = DateTime.fromMillisecondsSinceEpoch(member.joinedAtMs);
    final joinedLabel =
        '${joinedDate.day.toString().padLeft(2, '0')}/'
        '${joinedDate.month.toString().padLeft(2, '0')}/'
        '${joinedDate.year}';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: roleColor.withValues(alpha: 0.12),
        child: Icon(roleIcon, color: roleColor, size: 20),
      ),
      title: Text(
        name,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        'Desde $joinedLabel',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: roleColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          roleLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: roleColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
