import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omni_runner/core/logging/logger.dart';

const _tag = 'FriendProfileScreen';

/// Displays a friend's (or potential friend's) public profile.
///
/// Shows: display name, avatar, level, assessoria, DNA scores,
/// social links (Instagram/TikTok), recent badges.
class FriendProfileScreen extends StatefulWidget {
  final String userId;
  const FriendProfileScreen({super.key, required this.userId});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  bool _loading = true;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _dna;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = Supabase.instance.client;
    try {
      final profileFuture = db
          .from('profiles')
          .select('display_name, avatar_url, instagram_handle, tiktok_handle, user_role')
          .eq('id', widget.userId)
          .maybeSingle();

      final progressFuture = db
          .from('profile_progress')
          .select('total_xp, daily_streak_count, streak_best, lifetime_session_count, lifetime_distance_m')
          .eq('user_id', widget.userId)
          .maybeSingle();

      final dnaFuture = db
          .from('running_dna')
          .select('radar_scores, stats')
          .eq('user_id', widget.userId)
          .maybeSingle();

      final results = await Future.wait<Map<String, dynamic>?>(
          [profileFuture, progressFuture, dnaFuture]);

      setState(() {
        _loading = false;
        _profile = results[0];
        _progress = results[1];
        _dna = results[2];
      });
    } on Exception catch (e) {
      AppLogger.warn('Friend profile load failed: $e', tag: _tag);
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _profile?['display_name'] as String? ?? 'Corredor';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        backgroundColor: cs.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('Perfil não encontrado'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      _ProfileHeader(profile: _profile!, progress: _progress),
                      if (_dna != null) _DnaPreview(dna: _dna!),
                      _SocialLinks(profile: _profile!),
                      _StatsCard(progress: _progress),
                    ],
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Profile header
// ─────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> profile;
  final Map<String, dynamic>? progress;

  const _ProfileHeader({required this.profile, this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = profile['display_name'] as String? ?? 'Corredor';
    final avatarUrl = profile['avatar_url'] as String?;
    final totalXp = progress?['total_xp'] as int? ?? 0;
    final level = _levelFromXp(totalXp);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.surface],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundImage:
                avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? const Icon(Icons.person, size: 48)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Nível $level · $totalXp XP',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static int _levelFromXp(int xp) {
    if (xp <= 0) return 0;
    return math.max(0, math.pow(xp / 100, 2 / 3).floor());
  }
}

// ─────────────────────────────────────────────────────────────────────
// DNA preview (mini radar as horizontal bars)
// ─────────────────────────────────────────────────────────────────────

class _DnaPreview extends StatelessWidget {
  final Map<String, dynamic> dna;
  const _DnaPreview({required this.dna});

  static const _axes = [
    ('speed', 'Velocidade'),
    ('endurance', 'Resistência'),
    ('consistency', 'Consistência'),
    ('evolution', 'Evolução'),
    ('versatility', 'Versatilidade'),
    ('competitiveness', 'Competitividade'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scores = dna['radar_scores'] as Map<String, dynamic>? ?? {};

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hexagon_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                const Text('DNA de Corredor',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ..._axes.map((a) {
              final v = (scores[a.$1] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(a.$2,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: v / 100,
                          minHeight: 6,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 24,
                      child: Text('${v.round()}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Social links
// ─────────────────────────────────────────────────────────────────────

class _SocialLinks extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _SocialLinks({required this.profile});

  @override
  Widget build(BuildContext context) {
    final insta = profile['instagram_handle'] as String?;
    final tiktok = profile['tiktok_handle'] as String?;

    if ((insta == null || insta.isEmpty) &&
        (tiktok == null || tiktok.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Redes sociais',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (insta != null && insta.isNotEmpty)
              _SocialRow(
                icon: Icons.camera_alt_outlined,
                label: 'Instagram',
                handle: '@$insta',
                url: 'https://instagram.com/$insta',
              ),
            if (tiktok != null && tiktok.isNotEmpty)
              _SocialRow(
                icon: Icons.music_note_rounded,
                label: 'TikTok',
                handle: '@$tiktok',
                url: 'https://tiktok.com/@$tiktok',
              ),
          ],
        ),
      ),
    );
  }
}

class _SocialRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String handle;
  final String url;

  const _SocialRow({
    required this.icon,
    required this.label,
    required this.handle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Text(handle,
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.open_in_new, size: 16, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Stats card
// ─────────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final Map<String, dynamic>? progress;
  const _StatsCard({this.progress});

  @override
  Widget build(BuildContext context) {
    if (progress == null) return const SizedBox.shrink();

    final sessions = progress!['lifetime_session_count'] as int? ?? 0;
    final distM = (progress!['lifetime_distance_m'] as num?)?.toDouble() ?? 0;
    final streak = progress!['streak_best'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Estatísticas',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MiniStat(value: '$sessions', label: 'corridas'),
                _MiniStat(
                    value: '${(distM / 1000).toStringAsFixed(0)} km',
                    label: 'total'),
                _MiniStat(value: '$streak dias', label: 'melhor sequência'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  const _MiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
