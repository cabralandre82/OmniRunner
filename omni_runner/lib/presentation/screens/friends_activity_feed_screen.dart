import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Displays a chronological feed of verified workout sessions from the
/// current user's accepted friends.
///
/// Data comes from `fn_friends_activity_feed` RPC which joins friendships,
/// sessions, and profiles server-side.
class FriendsActivityFeedScreen extends StatefulWidget {
  const FriendsActivityFeedScreen({super.key});

  @override
  State<FriendsActivityFeedScreen> createState() =>
      _FriendsActivityFeedScreenState();
}

class _FriendsActivityFeedScreenState extends State<FriendsActivityFeedScreen> {
  static const _pageSize = 30;
  static const _maxRetries = 3;
  static const _retryDelayMs = 800;

  final List<_FeedItem> _items = [];
  bool _loading = true;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    Exception? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final offset = loadMore ? _items.length : 0;
        final rows = await Supabase.instance.client.rpc(
          'fn_friends_activity_feed',
          params: {'p_limit': _pageSize, 'p_offset': offset},
        );

        final newItems = (rows as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(_FeedItem.fromJson)
            .toList();

        if (!mounted) return;
        setState(() {
          if (!loadMore) _items.clear();
          _items.addAll(newItems);
          _hasMore = newItems.length >= _pageSize;
          _loading = false;
        });
        return;
      } on Exception catch (e) {
        lastError = e;
        if (attempt < _maxRetries - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: _retryDelayMs * (attempt + 1)),
          );
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = 'Erro ao carregar feed: $lastError';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Atividade dos Amigos'),
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? _errorState(theme)
              : _items.isEmpty
                  ? _emptyState(theme)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _items.length) {
                            return _loadMoreButton();
                          }
                          return RepaintBoundary(
                            child: _ActivityTile(item: _items[i]),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _errorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Nenhuma atividade recente',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Adicione amigos para ver as corridas deles aqui.\n'
              'Vá em Mais → Amigos para encontrar outros corredores.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadMoreButton() {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Center(
        child: OutlinedButton(
          onPressed: () => _load(loadMore: true),
          child: const Text('Carregar mais'),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

class _FeedItem {
  final String sessionId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int startTimeMs;
  final int? endTimeMs;
  final double? totalDistanceM;
  final bool isVerified;

  const _FeedItem({
    required this.sessionId,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.startTimeMs,
    this.endTimeMs,
    this.totalDistanceM,
    required this.isVerified,
  });

  factory _FeedItem.fromJson(Map<String, dynamic> j) => _FeedItem(
        sessionId: j['session_id'] as String,
        userId: j['user_id'] as String,
        displayName: (j['display_name'] as String?) ?? 'Atleta',
        avatarUrl: j['avatar_url'] as String?,
        startTimeMs: (j['start_time_ms'] as num).toInt(),
        endTimeMs: (j['end_time_ms'] as num?)?.toInt(),
        totalDistanceM: (j['total_distance_m'] as num?)?.toDouble(),
        isVerified: (j['is_verified'] as bool?) ?? false,
      );

  double? get paceSecKm {
    if (endTimeMs == null || totalDistanceM == null || totalDistanceM! < 500) {
      return null;
    }
    final durationSec = (endTimeMs! - startTimeMs) / 1000;
    final distKm = totalDistanceM! / 1000;
    final pace = durationSec / distKm;
    return (pace > 120 && pace < 1200) ? pace : null;
  }

  Duration? get duration {
    if (endTimeMs == null) return null;
    return Duration(milliseconds: endTimeMs! - startTimeMs);
  }

  String get timeAgo {
    final diff = DateTime.now().millisecondsSinceEpoch - startTimeMs;
    final hours = diff ~/ 3600000;
    if (hours < 1) return 'agora há pouco';
    if (hours < 24) return 'há ${hours}h';
    final days = hours ~/ 24;
    if (days == 1) return 'ontem';
    if (days < 7) return 'há $days dias';
    final weeks = days ~/ 7;
    return weeks == 1 ? 'há 1 semana' : 'há $weeks semanas';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

class _ActivityTile extends StatelessWidget {
  final _FeedItem item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final distKm = (item.totalDistanceM ?? 0) / 1000;
    final pace = item.paceSecKm;
    final dur = item.duration;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: DesignTokens.spacingXs),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + name + time ago
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: item.avatarUrl != null
                      ? CachedNetworkImageProvider(item.avatarUrl!)
                      : null,
                  backgroundColor: cs.primaryContainer,
                  child: item.avatarUrl == null
                      ? Text(
                          item.displayName.isNotEmpty
                              ? item.displayName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(item.timeAgo,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.outline)),
                    ],
                  ),
                ),
                Icon(Icons.directions_run_rounded,
                    color: cs.primary, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            // Metrics row
            Row(
              children: [
                _MetricChip(
                  icon: Icons.straighten,
                  value: '${distKm.toStringAsFixed(1)} km',
                  color: DesignTokens.primary,
                ),
                const SizedBox(width: 8),
                if (pace != null)
                  _MetricChip(
                    icon: Icons.speed,
                    value: _formatPace(pace),
                    color: DesignTokens.warning,
                  ),
                if (pace != null) const SizedBox(width: 8),
                if (dur != null)
                  _MetricChip(
                    icon: Icons.timer_outlined,
                    value: _formatDuration(dur),
                    color: DesignTokens.success,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatPace(double secPerKm) {
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).toInt();
    return "$min'${sec.toString().padLeft(2, '0')}'/km";
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}min';
    return '${m}min${s.toString().padLeft(2, '0')}s';
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _MetricChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              )),
        ],
      ),
    );
  }
}
