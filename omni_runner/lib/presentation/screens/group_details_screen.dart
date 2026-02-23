import 'package:flutter/material.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';

class GroupDetailsScreen extends StatelessWidget {
  final GroupEntity group;
  final List<GroupMemberEntity> members;
  final List<GroupGoalEntity> goals;

  const GroupDetailsScreen({
    super.key,
    required this.group,
    this.members = const [],
    this.goals = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: ListView(
        children: [
          _HeaderCard(group: group),
          if (goals.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Metas ativas',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            ...goals.map((g) => _GoalTile(goal: g)),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Membros (${members.length})',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Nenhum membro carregado.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline)),
            )
          else
            ...members.map((m) => _MemberTile(member: m)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final GroupEntity group;
  const _HeaderCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
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
                  child: Icon(Icons.group,
                      color: theme.colorScheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '${group.memberCount} membros · '
                        '${_privacyLabel(group.privacy)}',
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
          ],
        ),
      ),
    );
  }

  static String _privacyLabel(GroupPrivacy p) => switch (p) {
        GroupPrivacy.open => 'Aberto',
        GroupPrivacy.closed => 'Fechado',
        GroupPrivacy.secret => 'Secreto',
      };
}

class _GoalTile extends StatelessWidget {
  final GroupGoalEntity goal;
  const _GoalTile({required this.goal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = goal.progressFraction;
    final percent = (fraction * 100).toStringAsFixed(0);
    final isDone = goal.isCompleted;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isDone ? Icons.check_circle : Icons.flag,
                    color: isDone ? Colors.teal : theme.colorScheme.primary,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(goal.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text('$percent%',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDone
                            ? Colors.teal
                            : theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                    isDone ? Colors.teal : theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatGoalProgress(goal),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatGoalProgress(GroupGoalEntity g) {
    if (g.metric == GoalMetric.distance) {
      return '${(g.currentValue / 1000).toStringAsFixed(1)} / '
          '${(g.targetValue / 1000).toStringAsFixed(0)} km';
    }
    if (g.metric == GoalMetric.sessions) {
      return '${g.currentValue.toStringAsFixed(0)} / '
          '${g.targetValue.toStringAsFixed(0)} corridas';
    }
    final curMin = (g.currentValue / 60000).toStringAsFixed(0);
    final tgtMin = (g.targetValue / 60000).toStringAsFixed(0);
    return '$curMin / $tgtMin min';
  }
}

class _MemberTile extends StatelessWidget {
  final GroupMemberEntity member;
  const _MemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleLabel = switch (member.role) {
      GroupRole.admin => 'Admin',
      GroupRole.moderator => 'Moderador',
      GroupRole.member => 'Membro',
    };
    final roleColor = switch (member.role) {
      GroupRole.admin => Colors.amber,
      GroupRole.moderator => Colors.blue,
      GroupRole.member => theme.colorScheme.outline,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person, color: theme.colorScheme.outline),
      ),
      title: Text(member.displayName,
          style:
              theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: roleColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(roleLabel,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: roleColor, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
