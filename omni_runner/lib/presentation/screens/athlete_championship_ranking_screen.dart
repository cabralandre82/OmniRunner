import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/presentation/screens/friend_profile_screen.dart';

/// Athlete screen showing the ranking/participants for a championship.
class AthleteChampionshipRankingScreen extends StatefulWidget {
  final String championshipId;
  final String championshipName;
  final String metric;

  const AthleteChampionshipRankingScreen({
    super.key,
    required this.championshipId,
    required this.championshipName,
    required this.metric,
  });

  @override
  State<AthleteChampionshipRankingScreen> createState() =>
      _AthleteChampionshipRankingScreenState();
}

class _AthleteChampionshipRankingScreenState
    extends State<AthleteChampionshipRankingScreen> {
  static const _tag = 'ChampRanking';

  bool _loading = true;
  String? _error;
  List<_Participant> _participants = [];

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    try {
      // Update own progress before fetching ranking
      try {
        await _db.functions.invoke('champ-update-progress', body: {
          'championship_id': widget.championshipId,
        }).timeout(const Duration(seconds: 10));
      } catch (e) {
        AppLogger.debug('Progress update skipped: $e', tag: _tag);
      }

      // Trigger lifecycle transitions (open→active, active→completed)
      try {
        await _db.functions.invoke('champ-lifecycle', body: {
          'championship_id': widget.championshipId,
        }).timeout(const Duration(seconds: 10));
      } catch (e) {
        AppLogger.debug('Lifecycle check skipped: $e', tag: _tag);
      }

      final res = await _db.functions.invoke('champ-participant-list', body: {
        'championship_id': widget.championshipId,
      });
      final data = res.data as Map<String, dynamic>? ?? {};
      final list = (data['participants'] as List<dynamic>?) ?? [];

      _participants = list.map((p) {
        final m = p as Map<String, dynamic>;
        return _Participant(
          displayName: (m['display_name'] as String?) ?? 'Atleta',
          progressValue: ((m['progress_value'] as num?) ?? 0).toDouble(),
          status: (m['status'] as String?) ?? 'enrolled',
          finalRank: m['final_rank'] as int?,
          userId: (m['user_id'] as String?) ?? '',
        );
      }).toList();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      AppLogger.error('Load ranking failed: $e', tag: _tag, error: e);
      if (mounted) setState(() { _error = 'Erro ao carregar ranking.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final uid = _db.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: Text(widget.championshipName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Tentar novamente')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _participants.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Column(children: [
                            Icon(Icons.leaderboard_outlined, size: 56, color: cs.outline),
                            const SizedBox(height: 16),
                            Text('Nenhum participante ainda', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          ])),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: _participants.length,
                          itemBuilder: (_, i) {
                            final p = _participants[i];
                            final rank = i + 1;
                            final isMe = p.userId == uid;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: isMe ? cs.primaryContainer.withValues(alpha: 0.3) : null,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: rank <= 3 ? _medalColor(rank) : cs.surfaceContainerHighest,
                                  child: Text('$rank', style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: rank <= 3 ? Colors.white : cs.onSurfaceVariant,
                                  )),
                                ),
                                title: Row(children: [
                                  Flexible(child: Text(p.displayName, overflow: TextOverflow.ellipsis)),
                                  if (isMe) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(6)),
                                      child: Text('Você', style: theme.textTheme.labelSmall?.copyWith(color: cs.onPrimary, fontSize: 10)),
                                    ),
                                  ],
                                ]),
                                subtitle: Text(_statusLabel(p.status), style: theme.textTheme.bodySmall),
                                trailing: p.progressValue > 0
                                    ? Text(_fmtProgress(p.progressValue, widget.metric), style: const TextStyle(fontWeight: FontWeight.bold))
                                    : null,
                                onTap: isMe ? null : () {
                                  Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => FriendProfileScreen(userId: p.userId),
                                  ));
                                },
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  static Color _medalColor(int rank) => switch (rank) { 1 => Colors.amber.shade700, 2 => Colors.grey.shade500, 3 => Colors.brown.shade400, _ => Colors.grey };
  static String _statusLabel(String s) => switch (s) { 'enrolled' => 'Inscrito', 'active' => 'Ativo', 'completed' => 'Completou', 'withdrawn' => 'Desistiu', _ => s };
  static String _fmtProgress(double v, String metric) => switch (metric) {
    'distance' => '${(v / 1000).toStringAsFixed(1)} km',
    'time' => '${(v / 60).toStringAsFixed(0)} min',
    'pace' => '${(v / 60).toStringAsFixed(1)} min/km',
    'sessions' => '${v.toInt()} corridas',
    'elevation' => '${v.toInt()} m',
    _ => v.toStringAsFixed(1),
  };
}

class _Participant {
  final String displayName, status, userId;
  final double progressValue;
  final int? finalRank;
  const _Participant({required this.displayName, required this.progressValue, required this.status, this.finalRank, required this.userId});
}
