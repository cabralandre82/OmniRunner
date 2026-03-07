import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_event.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_state.dart';
import 'package:omni_runner/presentation/widgets/cached_avatar.dart';
import 'package:omni_runner/presentation/widgets/empty_state.dart';
import 'package:omni_runner/presentation/widgets/error_state.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.friends),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search_rounded),
            tooltip: 'Buscar corredores',
            onPressed: () => _showSearch(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<FriendsBloc>().add(const RefreshFriends()),
          ),
        ],
      ),
      body: BlocBuilder<FriendsBloc, FriendsState>(
        builder: (context, state) => switch (state) {
          FriendsInitial() || FriendsLoading() => const ShimmerListLoader(),
          FriendsLoaded() => _Body(state: state),
          FriendsError(:final message) => ErrorState(
              message: message,
              onRetry: () =>
                  context.read<FriendsBloc>().add(const RefreshFriends()),
            ),
        },
      ),
    );
  }

  void _showSearch(BuildContext context) {
    final bloc = context.read<FriendsBloc>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FriendSearchScreen(
          onInvite: (userId) {
            bloc.add(SendFriendRequest(userId));
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Body with sections
// ─────────────────────────────────────────────────────────────────────

class _Body extends StatefulWidget {
  final FriendsLoaded state;
  const _Body({required this.state});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final Map<String, _UserInfo> _userCache = {};
  bool _loadingNames = false;

  @override
  void initState() {
    super.initState();
    _fetchNames();
  }

  @override
  void didUpdateWidget(covariant _Body old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _fetchNames();
  }

  Future<void> _fetchNames() async {
    final allIds = <String>{};
    for (final f in [
      ...widget.state.accepted,
      ...widget.state.pendingReceived,
      ...widget.state.pendingSent,
    ]) {
      allIds.add(f.otherUserId(widget.state.userId));
    }

    if (allIds.isEmpty) return;

    setState(() => _loadingNames = true);
    try {
      final rows = await sl<SupabaseClient>()
          .from('profiles')
          .select('id, display_name, avatar_url, instagram_handle, tiktok_handle')
          .inFilter('id', allIds.toList());

      for (final r in rows) {
        _userCache[r['id'] as String] = _UserInfo(
          displayName: r['display_name'] as String? ?? 'Corredor',
          avatarUrl: r['avatar_url'] as String?,
          instagramHandle: r['instagram_handle'] as String?,
          tiktokHandle: r['tiktok_handle'] as String?,
        );
      }
    } on Exception {
      // Best effort — tiles will show IDs
    }
    if (mounted) setState(() => _loadingNames = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;

    if (s.accepted.isEmpty &&
        s.pendingReceived.isEmpty &&
        s.pendingSent.isEmpty) {
      return _empty(context);
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<FriendsBloc>().add(const RefreshFriends());
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
      child: ListView(
      children: [
        if (s.pendingReceived.isNotEmpty) ...[
          _SectionHeader(
            title: 'Pedidos recebidos',
            count: s.pendingReceived.length,
            icon: Icons.person_add,
            color: DesignTokens.warning,
          ),
          ...s.pendingReceived.map((f) => _PendingReceivedTile(
                friendship: f,
                userId: s.userId,
                info: _userCache[f.otherUserId(s.userId)],
              )),
        ],
        if (s.accepted.isNotEmpty) ...[
          _SectionHeader(
            title: 'Amigos',
            count: s.accepted.length,
            icon: Icons.people,
            color: DesignTokens.success,
          ),
          ...s.accepted.map((f) => _AcceptedTile(
                friendship: f,
                userId: s.userId,
                info: _userCache[f.otherUserId(s.userId)],
              )),
        ],
        if (s.pendingSent.isNotEmpty) ...[
          _SectionHeader(
            title: 'Enviados',
            count: s.pendingSent.length,
            icon: Icons.send,
            color: DesignTokens.textMuted,
          ),
          ...s.pendingSent.map((f) => _PendingSentTile(
                friendship: f,
                userId: s.userId,
                info: _userCache[f.otherUserId(s.userId)],
              )),
        ],
        if (_loadingNames)
          const Padding(
            padding: EdgeInsets.all(DesignTokens.spacingMd),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        const SizedBox(height: 24),
      ],
    ),
    );
  }

  Widget _empty(BuildContext context) {
    return EmptyState(
      icon: Icons.people_outline_rounded,
      title: 'Nenhum amigo ainda',
      subtitle: 'Busque corredores pelo nome ou adicione '
          'após desafios e campeonatos!',
      actionLabel: 'Buscar corredores',
      actionIcon: Icons.person_search_rounded,
      onAction: () {
        final bloc = context.read<FriendsBloc>();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _FriendSearchScreen(
              onInvite: (userId) {
                bloc.add(SendFriendRequest(userId));
              },
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Tiles
// ─────────────────────────────────────────────────────────────────────

class _AcceptedTile extends StatelessWidget {
  final FriendshipEntity friendship;
  final String userId;
  final _UserInfo? info;

  const _AcceptedTile({
    required this.friendship,
    required this.userId,
    this.info,
  });

  Future<void> _confirmRemove(BuildContext context) async {
    final name = info?.displayName ?? 'este amigo';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover amigo'),
        content: Text('Deseja remover $name da sua lista de amigos?'),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            style: FilledButton.styleFrom(backgroundColor: DesignTokens.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<FriendsBloc>().add(RemoveFriend(friendship.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name removido da lista de amigos')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final otherId = friendship.otherUserId(userId);
    final name = info?.displayName ?? otherId.substring(0, 8);

    return Dismissible(
      key: ValueKey(friendship.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmRemove(context);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: cs.error,
        child: const Icon(Icons.person_remove, color: Colors.white),
      ),
      child: ListTile(
        leading: CachedAvatar(
          url: info?.avatarUrl,
          fallbackText: info?.displayName ?? 'U',
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: _socialSubtitle(info),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.friendProfilePath(otherId)),
        onLongPress: () => _confirmRemove(context),
      ),
    );
  }
}

class _PendingReceivedTile extends StatelessWidget {
  final FriendshipEntity friendship;
  final String userId;
  final _UserInfo? info;

  const _PendingReceivedTile({
    required this.friendship,
    required this.userId,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final otherId = friendship.otherUserId(userId);
    final name = info?.displayName ?? otherId.substring(0, 8);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: DesignTokens.warning,
        child: const Icon(Icons.person_add, color: DesignTokens.warning),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: const Text('Quer ser seu amigo',
          style: TextStyle(color: DesignTokens.warning, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.check_circle, color: cs.primary),
            tooltip: 'Aceitar',
            onPressed: () {
              HapticFeedback.lightImpact();
              context.read<FriendsBloc>().add(AcceptFriendEvent(friendship.id));
            },
          ),
          IconButton(
            icon: Icon(Icons.cancel_outlined, color: cs.error),
            tooltip: 'Recusar',
            onPressed: () {
              HapticFeedback.lightImpact();
              context.read<FriendsBloc>().add(DeclineFriendEvent(friendship.id));
            },
          ),
        ],
      ),
    );
  }
}

class _PendingSentTile extends StatelessWidget {
  final FriendshipEntity friendship;
  final String userId;
  final _UserInfo? info;

  const _PendingSentTile({
    required this.friendship,
    required this.userId,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final otherId = friendship.otherUserId(userId);
    final name = info?.displayName ?? otherId.substring(0, 8);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: DesignTokens.borderSubtle,
        child: const Icon(Icons.hourglass_top, color: DesignTokens.textMuted),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: const Text('Aguardando resposta',
          style: TextStyle(color: DesignTokens.textMuted, fontSize: 12)),
      trailing: IconButton(
        icon: Icon(Icons.close_rounded, color: cs.error, size: 20),
        tooltip: 'Cancelar convite',
        onPressed: () {
          context.read<FriendsBloc>().add(RemoveFriend(friendship.id));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Convite cancelado')),
          );
        },
      ),
    );
  }
}

Widget? _socialSubtitle(_UserInfo? info) {
  if (info == null) return null;
  final parts = <String>[];
  if (info.instagramHandle != null && info.instagramHandle!.isNotEmpty) {
    parts.add('@${info.instagramHandle}');
  }
  if (info.tiktokHandle != null && info.tiktokHandle!.isNotEmpty) {
    parts.add('TikTok: @${info.tiktokHandle}');
  }
  if (parts.isEmpty) return null;
  return Text(parts.join(' · '),
      style: const TextStyle(fontSize: 12, color: DesignTokens.textMuted));
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingMd, DesignTokens.spacingSm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Friend search screen
// ─────────────────────────────────────────────────────────────────────

class _FriendSearchScreen extends StatefulWidget {
  final void Function(String userId) onInvite;
  const _FriendSearchScreen({required this.onInvite});

  @override
  State<_FriendSearchScreen> createState() => _FriendSearchScreenState();
}

class _FriendSearchScreenState extends State<_FriendSearchScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  final _sentIds = <String>{};
  final _existingFriendIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadExistingFriends();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadExistingFriends() async {
    try {
      final uid = sl<UserIdentityProvider>().userId;
      final repo = sl<IFriendshipRepo>();
      final all = await repo.getByUserId(uid);
      final ids = <String>{};
      for (final f in all) {
        if (f.status == FriendshipStatus.accepted ||
            f.status == FriendshipStatus.pending) {
          ids.add(f.otherUserId(uid));
        }
      }
      if (mounted) setState(() => _existingFriendIds.addAll(ids));
    } on Exception {
      // best effort
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final uid = sl<UserIdentityProvider>().userId;
      final rows = await sl<SupabaseClient>()
          .rpc('fn_search_users', params: {
        'p_query': query.trim(),
        'p_caller_id': uid,
        'p_limit': 20,
      });
      setState(() {
        _results = (rows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on Exception {
      setState(() {
        _results = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.search),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Nome do corredor...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
                filled: true,
              ),
              onChanged: _search,
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _controller.text.length < 2
                          ? 'Digite pelo menos 2 caracteres'
                          : 'Nenhum corredor encontrado',
                      style: TextStyle(color: cs.outline),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final r = _results[i];
                      final uid = r['user_id'] as String;
                      final name = r['display_name'] as String? ?? 'Corredor';
                      final avatar = r['avatar_url'] as String?;
                      final insta = r['instagram_handle'] as String?;
                      final sent = _sentIds.contains(uid);
                      final alreadyFriend = _existingFriendIds.contains(uid);

                      return ListTile(
                        leading: CachedAvatar(
                          url: avatar,
                          fallbackText: name,
                        ),
                        title: Text(name),
                        subtitle: insta != null && insta.isNotEmpty
                            ? Text('@$insta',
                                style: const TextStyle(
                                    fontSize: 12, color: DesignTokens.textMuted))
                            : null,
                        trailing: alreadyFriend
                            ? const Chip(
                                label: Text('Amigo'),
                                avatar: Icon(Icons.check, size: 16),
                              )
                            : sent
                                ? Chip(
                                    label: const Text('Enviado'),
                                    backgroundColor: cs.secondaryContainer,
                                  )
                                : IconButton(
                                    icon: Icon(Icons.person_add,
                                        color: cs.primary),
                                    onPressed: () {
                                      widget.onInvite(uid);
                                      setState(() => _sentIds.add(uid));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Convite enviado!')),
                                      );
                                    },
                                  ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Helper model
// ─────────────────────────────────────────────────────────────────────

class _UserInfo {
  final String displayName;
  final String? avatarUrl;
  final String? instagramHandle;
  final String? tiktokHandle;

  const _UserInfo({
    required this.displayName,
    this.avatarUrl,
    this.instagramHandle,
    this.tiktokHandle,
  });
}
