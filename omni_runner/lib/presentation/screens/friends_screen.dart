import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_event.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_state.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amigos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<FriendsBloc>().add(const RefreshFriends()),
          ),
        ],
      ),
      body: BlocBuilder<FriendsBloc, FriendsState>(
        builder: (context, state) => switch (state) {
          FriendsInitial() =>
            const Center(child: Text('Carregue sua lista de amigos.')),
          FriendsLoading() =>
            const Center(child: CircularProgressIndicator()),
          FriendsLoaded() => _body(context, state),
          FriendsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
        },
      ),
    );
  }

  static Widget _body(BuildContext context, FriendsLoaded state) {
    if (state.accepted.isEmpty &&
        state.pendingReceived.isEmpty &&
        state.pendingSent.isEmpty) {
      return _empty(context);
    }

    return ListView(
      children: [
        if (state.pendingReceived.isNotEmpty) ...[
          _SectionHeader(
            title: 'Pedidos recebidos',
            count: state.pendingReceived.length,
            icon: Icons.person_add,
            color: Colors.orange,
          ),
          ...state.pendingReceived.map(
            (f) => _FriendTile(friendship: f, currentUserId: state.userId, isPending: true),
          ),
        ],
        if (state.accepted.isNotEmpty) ...[
          _SectionHeader(
            title: 'Amigos',
            count: state.accepted.length,
            icon: Icons.people,
            color: Colors.green,
          ),
          ...state.accepted.map(
            (f) => _FriendTile(friendship: f, currentUserId: state.userId, isPending: false),
          ),
        ],
        if (state.pendingSent.isNotEmpty) ...[
          _SectionHeader(
            title: 'Enviados',
            count: state.pendingSent.length,
            icon: Icons.send,
            color: Colors.grey,
          ),
          ...state.pendingSent.map(
            (f) => _FriendTile(friendship: f, currentUserId: state.userId, isPending: true),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  static Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Nenhum amigo ainda', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Adicione amigos para competir\ne compartilhar suas corridas!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final FriendshipEntity friendship;
  final String currentUserId;
  final bool isPending;

  const _FriendTile({
    required this.friendship,
    required this.currentUserId,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final otherId = friendship.otherUserId(currentUserId);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isPending
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        child: Icon(
          isPending ? Icons.hourglass_top : Icons.person,
          color: isPending
              ? theme.colorScheme.outline
              : theme.colorScheme.primary,
        ),
      ),
      title: Text(
        otherId.length > 12 ? '${otherId.substring(0, 12)}...' : otherId,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        isPending ? 'Pendente' : 'Amigo',
        style: theme.textTheme.bodySmall?.copyWith(
          color: isPending ? Colors.orange : Colors.green,
        ),
      ),
      trailing: isPending && friendship.userIdB == currentUserId
          ? const Icon(Icons.check_circle_outline, color: Colors.green)
          : null,
    );
  }
}
