import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/features/parks/data/parks_seed.dart';
import 'package:omni_runner/features/parks/domain/park_entity.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';

/// Listing of parks the athlete frequents + discovery of nearby parks.
///
/// Shows:
///   1. "Seus parques" — parks where the user has run
///   2. "Descobrir" — all seeded parks for browsing
class MyParksScreen extends StatefulWidget {
  const MyParksScreen({super.key});

  @override
  State<MyParksScreen> createState() => _MyParksScreenState();
}

class _MyParksScreenState extends State<MyParksScreen> {
  bool _loading = true;
  List<_ParkSummary> _myParks = [];
  List<_PopularPark> _popularParks = [];
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (AppConfig.isSupabaseReady) {
        final uid = sl<UserIdentityProvider>().userId;

        // Re-import Strava activities with start coordinates and
        // backfill park_activities so recent runs show up immediately.
        await _ensureParkBackfill(uid);

        final res = await sl<SupabaseClient>()
            .from('park_activities')
            .select('park_id, distance_m')
            .eq('user_id', uid);

        final byPark = <String, _ParkAgg>{};
        for (final raw in res as List<dynamic>) {
          final r = raw as Map<String, dynamic>;
          final pid = r['park_id'] as String;
          byPark.putIfAbsent(pid, () => _ParkAgg());
          byPark[pid]!.count++;
          byPark[pid]!.totalDistM +=
              (r['distance_m'] as num?)?.toDouble() ?? 0;
        }

        _myParks = byPark.entries
            .map((e) {
              final park = kBrazilianParksSeed
                  .where((p) => p.id == e.key)
                  .firstOrNull;
              if (park == null) return null;
              return _ParkSummary(
                park: park,
                runCount: e.value.count,
                totalDistKm: e.value.totalDistM / 1000,
              );
            })
            .whereType<_ParkSummary>()
            .toList()
          ..sort((a, b) => b.runCount.compareTo(a.runCount));
      }

      // Load popular parks by runner count
      try {
        final popRows = await sl<SupabaseClient>()
            .from('park_activities')
            .select('park_id, user_id');

        final parkUserCounts = <String, Set<String>>{};
        for (final raw in popRows as List<dynamic>) {
          final r = raw as Map<String, dynamic>;
          final pid = r['park_id'] as String;
          final uid2 = r['user_id'] as String;
          parkUserCounts.putIfAbsent(pid, () => {}).add(uid2);
        }

        final sorted = parkUserCounts.entries.toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length));

        _popularParks = sorted.take(10).map((e) {
          final park = kBrazilianParksSeed
              .where((p) => p.id == e.key)
              .firstOrNull;
          if (park == null) return null;
          return _PopularPark(park: park, runnerCount: e.value.length);
        }).whereType<_PopularPark>().toList();
      } on Object catch (e) {
        AppLogger.debug('Popular parks load failed', tag: 'MyParksScreen', error: e);
      }

      if (mounted) setState(() => _loading = false);
    } on Exception catch (e) {
      AppLogger.warn('Caught error', tag: 'MyParksScreen', error: e);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parques'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _buildContent(cs),
            ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _buildContent(ColorScheme cs) {
    final q = _search.toLowerCase();
    final filtered = q.isEmpty
        ? kBrazilianParksSeed
        : kBrazilianParksSeed
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.city.toLowerCase().contains(q) ||
                p.state.toLowerCase().contains(q))
            .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_myParks.isNotEmpty && q.isEmpty) ...[
          const _SectionTitle(title: 'Seus parques', icon: Icons.favorite),
          const SizedBox(height: 8),
          ..._myParks.map((s) => _MyParkCard(
                summary: s,
                onTap: () => _openPark(s.park),
              )),
          const SizedBox(height: 20),
        ] else if (q.isEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.explore_rounded,
                    size: 32, color: Colors.green.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Corra em um parque para aparecer no ranking local. '
                    'Parques mapeados: Ibirapuera, Aterro, Villa-Lobos e mais.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_popularParks.isNotEmpty) ...[
            const _SectionTitle(
                title: 'Top parques por corredores', icon: Icons.leaderboard),
            const SizedBox(height: 8),
            ..._popularParks.map((p) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child:
                        Icon(Icons.park, color: Colors.green.shade700, size: 20),
                  ),
                  title: Text(p.park.name),
                  subtitle: Text(
                      '${p.park.city} \u00b7 ${p.runnerCount} corredor${p.runnerCount == 1 ? '' : 'es'}'),
                  trailing: Icon(Icons.chevron_right,
                      color: cs.onSurfaceVariant),
                  onTap: () => _openPark(p.park),
                )),
            const SizedBox(height: 20),
          ],
        ],
        const _SectionTitle(title: 'Descobrir parques', icon: Icons.explore),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar por nome, cidade ou estado...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text('Nenhum parque encontrado',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...filtered.map((park) {
            final isMine = _myParks.any((s) => s.park.id == park.id);
            return _DiscoverParkTile(
              park: park,
              isMine: isMine,
              onTap: () => _openPark(park),
            );
          }),
      ],
    );
  }

  Future<void> _ensureParkBackfill(String uid) async {
    try {
      final controller = sl<StravaConnectController>();
      final connected = await controller.isConnected;
      if (!connected) return;

      await controller.importStravaHistory(count: 30);
      await sl<SupabaseClient>()
          .rpc('backfill_strava_sessions', params: {'p_user_id': uid});
      await sl<SupabaseClient>()
          .rpc('backfill_park_activities', params: {'p_user_id': uid});
    } on Object catch (e) {
      AppLogger.warn('Park backfill skipped: $e', tag: 'MyParksScreen');
    }
  }

  void _openPark(ParkEntity park) {
    context.push(AppRoutes.parkDetail, extra: park);
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _MyParkCard extends StatelessWidget {
  final _ParkSummary summary;
  final VoidCallback onTap;

  const _MyParkCard({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.park, color: Colors.green.shade700, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.park.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.park.city} · '
                      '${summary.runCount} corrida${summary.runCount > 1 ? 's' : ''} · '
                      '${summary.totalDistKm.toStringAsFixed(1)} km',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverParkTile extends StatelessWidget {
  final ParkEntity park;
  final bool isMine;
  final VoidCallback onTap;

  const _DiscoverParkTile({
    required this.park,
    required this.isMine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor:
            isMine ? Colors.green.shade100 : cs.surfaceContainerHighest,
        child: Icon(
          isMine ? Icons.check : Icons.park,
          color: isMine ? Colors.green.shade700 : cs.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(park.name),
      subtitle: Text('${park.city}, ${park.state}'),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

// ── Data helpers ─────────────────────────────────────────────────────────────

class _ParkSummary {
  final ParkEntity park;
  final int runCount;
  final double totalDistKm;

  const _ParkSummary({
    required this.park,
    required this.runCount,
    required this.totalDistKm,
  });
}

class _ParkAgg {
  int count = 0;
  double totalDistM = 0;
}

class _PopularPark {
  final ParkEntity park;
  final int runnerCount;

  const _PopularPark({required this.park, required this.runnerCount});
}
