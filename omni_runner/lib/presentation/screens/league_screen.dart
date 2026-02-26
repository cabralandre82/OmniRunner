import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';

const _tag = 'LeagueScreen';

/// Liga de Assessorias — ranked list of coaching groups.
///
/// Fetches data from the `league-list` Edge Function. Shows:
///   - Season name and remaining time
///   - Ranked list with top-3 medals
///   - Highlight on the user's own assessoria
///   - Personal contribution card
class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key});

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _season;
  List<Map<String, dynamic>> _ranking = [];
  String? _myGroupId;
  Map<String, dynamic>? _myContribution;

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
      final res = await Supabase.instance.client.functions.invoke(
        'league-list',
        method: HttpMethod.get,
      );

      final body = res.data as Map<String, dynamic>? ?? {};
      final season = body['season'] as Map<String, dynamic>?;
      final ranking = (body['ranking'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      final myGroupId = body['my_group_id'] as String?;
      final myContribution = body['my_contribution'] as Map<String, dynamic>?;

      setState(() {
        _loading = false;
        _season = season;
        _ranking = ranking;
        _myGroupId = myGroupId;
        _myContribution = myContribution;
      });
    } on Exception catch (e) {
      AppLogger.warn('League load failed: $e', tag: _tag);
      setState(() {
        _loading = false;
        _season = null;
        _ranking = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liga de Assessorias'),
        backgroundColor: cs.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_season == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_rounded, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Nenhuma temporada ativa',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'A próxima temporada da liga será anunciada em breve.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _SeasonHeader(season: _season!),
          if (_myContribution != null && _myGroupId != null)
            _MyContributionCard(
              contribution: _myContribution!,
              ranking: _ranking,
              myGroupId: _myGroupId!,
            ),
          const _HowItWorksCard(),
          if (_ranking.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'O ranking será atualizado semanalmente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ..._ranking.asMap().entries.map((e) => _RankingTile(
                  entry: e.value,
                  isMyGroup: e.value['group_id'] == _myGroupId,
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Season header
// ─────────────────────────────────────────────────────────────────────

class _SeasonHeader extends StatelessWidget {
  final Map<String, dynamic> season;
  const _SeasonHeader({required this.season});

  @override
  Widget build(BuildContext context) {
    final name = season['name'] as String? ?? 'Liga OmniRunner';
    final endMs = season['end_at_ms'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingDays = ((endMs - now) / 86400000).ceil();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF4A148C)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: Colors.amberAccent, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            remainingDays > 0
                ? 'Termina em $remainingDays ${remainingDays == 1 ? "dia" : "dias"}'
                : 'Temporada encerrada',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// My contribution card
// ─────────────────────────────────────────────────────────────────────

class _MyContributionCard extends StatelessWidget {
  final Map<String, dynamic> contribution;
  final List<Map<String, dynamic>> ranking;
  final String myGroupId;

  const _MyContributionCard({
    required this.contribution,
    required this.ranking,
    required this.myGroupId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final myKm = (contribution['total_km'] as num?)?.toDouble() ?? 0;
    final mySessions = contribution['total_sessions'] as int? ?? 0;

    final myEntry = ranking.cast<Map<String, dynamic>?>().firstWhere(
      (e) => e?['group_id'] == myGroupId,
      orElse: () => null,
    );
    final myRank = myEntry?['rank'] as int?;
    final groupName = myEntry?['group_name'] as String? ?? 'Sua assessoria';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: cs.onPrimaryContainer, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Sua contribuição',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ContribStat(
                    value: '${myKm.toStringAsFixed(1)} km',
                    label: 'corridos',
                  ),
                ),
                Expanded(
                  child: _ContribStat(
                    value: '$mySessions',
                    label: 'sessões',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              myRank != null
                  ? '$groupName — #$myRank no ranking'
                  : groupName,
              style: TextStyle(
                color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContribStat extends StatelessWidget {
  final String value;
  final String label;
  const _ContribStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// How it works
// ─────────────────────────────────────────────────────────────────────

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: cs.secondaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: cs.secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'A liga rankeia as assessorias por km corridos, '
                'sessões, membros ativos e desafios vencidos. '
                'Contribua correndo para subir sua assessoria!',
                style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Ranking tile
// ─────────────────────────────────────────────────────────────────────

class _RankingTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool isMyGroup;

  const _RankingTile({required this.entry, required this.isMyGroup});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rank = entry['rank'] as int? ?? 0;
    final prevRank = entry['prev_rank'] as int?;
    final groupName = entry['group_name'] as String? ?? 'Assessoria';
    final city = entry['city'] as String?;
    final score = (entry['cumulative_score'] as num?)?.toDouble() ?? 0;
    final totalKm = (entry['total_km'] as num?)?.toDouble() ?? 0;
    final activeMembers = entry['active_members'] as int? ?? 0;
    final totalMembers = entry['total_members'] as int? ?? 0;

    Widget rankWidget;
    if (rank == 1) {
      rankWidget = const Text('🥇', style: TextStyle(fontSize: 24));
    } else if (rank == 2) {
      rankWidget = const Text('🥈', style: TextStyle(fontSize: 24));
    } else if (rank == 3) {
      rankWidget = const Text('🥉', style: TextStyle(fontSize: 24));
    } else {
      rankWidget = SizedBox(
        width: 32,
        child: Text(
          '#$rank',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }

    Widget? rankDelta;
    if (prevRank != null && prevRank != rank) {
      final diff = prevRank - rank;
      if (diff > 0) {
        rankDelta = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_upward_rounded, size: 12, color: Colors.green),
            Text('$diff', style: const TextStyle(fontSize: 11, color: Colors.green)),
          ],
        );
      } else {
        rankDelta = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_downward_rounded, size: 12, color: Colors.red),
            Text('${diff.abs()}', style: const TextStyle(fontSize: 11, color: Colors.red)),
          ],
        );
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: isMyGroup
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: isMyGroup
            ? Border.all(color: cs.primary, width: 2)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: rankWidget,
        title: Row(
          children: [
            Expanded(
              child: Text(
                groupName,
                style: TextStyle(
                  fontWeight: isMyGroup ? FontWeight.bold : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (rankDelta != null) ...[
              const SizedBox(width: 4),
              rankDelta,
            ],
          ],
        ),
        subtitle: Text(
          [
            if (city != null) city,
            '$activeMembers de $totalMembers correram',
            '${totalKm.toStringAsFixed(0)} km/semana',
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              score.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
            const Text('pts', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
