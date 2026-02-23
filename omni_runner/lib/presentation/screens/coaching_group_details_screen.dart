import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_group_details.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_state.dart';
import 'package:omni_runner/presentation/screens/invite_qr_screen.dart';

class CoachingGroupDetailsScreen extends StatelessWidget {
  const CoachingGroupDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CoachingGroupDetailsBloc, CoachingGroupDetailsState>(
      builder: (context, state) => switch (state) {
        CoachingGroupDetailsInitial() => Scaffold(
            appBar: AppBar(title: const Text('Assessoria')),
            body: const Center(child: Text('Carregue os detalhes.')),
          ),
        CoachingGroupDetailsLoading() => Scaffold(
            appBar: AppBar(title: const Text('Assessoria')),
            body: const Center(child: CircularProgressIndicator()),
          ),
        CoachingGroupDetailsLoaded(:final details, :final callerUserId) =>
          _LoadedBody(details: details, callerUserId: callerUserId),
        CoachingGroupDetailsError(:final message) => Scaffold(
            appBar: AppBar(title: const Text('Assessoria')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
      },
    );
  }
}

class _LoadedBody extends StatefulWidget {
  final CoachingGroupDetails details;
  final String callerUserId;

  const _LoadedBody({
    required this.details,
    required this.callerUserId,
  });

  @override
  State<_LoadedBody> createState() => _LoadedBodyState();
}

class _LoadedBodyState extends State<_LoadedBody> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.details.group;
    final members = widget.details.members;
    final theme = Theme.of(context);

    final visibleMembers =
        _showAll || members.length <= 3 ? members : members.sublist(0, 3);

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CoachingGroupDetailsBloc>()
                .add(const RefreshCoachingGroupDetails()),
          ),
        ],
      ),
      body: ListView(
        children: [
          _HeaderCard(group: group, memberCount: widget.details.memberCount),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(
              children: [
                Text(
                  'Membros (${widget.details.memberCount})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (members.length > 3)
                  TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll ? 'Ver menos' : 'Ver todos'),
                  ),
              ],
            ),
          ),
          if (visibleMembers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
              ),
            ),
          const SizedBox(height: 24),
        ],
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
                  backgroundImage: group.logoUrl != null
                      ? NetworkImage(group.logoUrl!)
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
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => InviteQrScreen(
                        inviteCode: group.inviteCode!,
                        groupName: group.name,
                      ),
                    ));
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

  const _CoachingMemberTile({
    required this.member,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final roleLabel = switch (member.role) {
      CoachingRole.adminMaster => 'Admin Master',
      CoachingRole.professor => 'Professor',
      CoachingRole.assistente => 'Assistente',
      CoachingRole.atleta => 'Atleta',
    };
    final roleColor = switch (member.role) {
      CoachingRole.adminMaster => Colors.amber.shade700,
      CoachingRole.professor => Colors.deepPurple,
      CoachingRole.assistente => Colors.blue,
      CoachingRole.atleta => theme.colorScheme.outline,
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
