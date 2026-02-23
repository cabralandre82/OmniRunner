import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/presentation/screens/run_details_screen.dart';

/// History screen listing the last 20 sessions.
///
/// Optional [pickGhostMode]: if true, tapping a completed session returns it
/// via `Navigator.pop` instead of navigating to details.
class HistoryScreen extends StatefulWidget {
  final bool pickGhostMode;
  final bool isVisible;
  const HistoryScreen({super.key, this.pickGhostMode = false, this.isVisible = true});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _tag = 'History';
  List<WorkoutSessionEntity>? _sessions;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() { super.initState(); _loadSessions(); }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    final repo = sl<ISessionRepo>();

    // Pull completed sessions from Supabase and merge into Isar
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final rows = await Supabase.instance.client
            .from('sessions')
            .select('id, user_id, status, start_time_ms, end_time_ms, '
                'total_distance_m, moving_ms, is_verified, integrity_flags, '
                'ghost_session_id')
            .eq('user_id', uid)
            .order('start_time_ms', ascending: false)
            .limit(30);

        for (final r in (rows as List).cast<Map<String, dynamic>>()) {
          final sid = r['id'] as String;
          final existing = await repo.getById(sid);
          if (existing != null) continue;

          final statusInt = (r['status'] as num?)?.toInt() ?? 0;
          final status = switch (statusInt) {
            1 => WorkoutStatus.running,
            2 => WorkoutStatus.paused,
            3 => WorkoutStatus.completed,
            4 => WorkoutStatus.discarded,
            _ => WorkoutStatus.initial,
          };

          final flags = (r['integrity_flags'] as List<dynamic>?)
                  ?.cast<String>() ??
              const [];

          final session = WorkoutSessionEntity(
            id: sid,
            userId: r['user_id'] as String?,
            status: status,
            startTimeMs: (r['start_time_ms'] as num).toInt(),
            endTimeMs: (r['end_time_ms'] as num?)?.toInt(),
            totalDistanceM: (r['total_distance_m'] as num?)?.toDouble(),
            route: const [],
            ghostSessionId: r['ghost_session_id'] as String?,
            isVerified: (r['is_verified'] as bool?) ?? true,
            integrityFlags: flags,
            isSynced: true,
          );
          await repo.save(session);
        }
      }
    } catch (e) {
      AppLogger.warn('History: Supabase pull failed (showing local): $e',
          tag: _tag);
    }

    final all = await repo.getAll();
    if (mounted) setState(() { _sessions = all.take(20).toList(); _loading = false; });
  }

  Future<void> _onSync() async {
    setState(() => _syncing = true);
    final failure = await sl<ISyncRepo>().syncPending();
    await _loadSessions();
    if (!mounted) return;
    setState(() => _syncing = false);
    final msg = failure == null ? 'Sincronização concluída' : 'Falha na sincronização';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _sessions?.where((s) => !s.isSynced && s.status == WorkoutStatus.completed).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickGhostMode ? 'Escolher fantasma' : 'Histórico'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: widget.pickGhostMode ? null : [
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(child: Text('$pending pendente${pending > 1 ? 's' : ''}', style: const TextStyle(fontSize: 12))),
            ),
          IconButton(
            icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            tooltip: 'Sincronizar pendentes',
            onPressed: _syncing ? null : _onSync,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions == null || _sessions!.isEmpty
              ? const Center(child: Text(
                  'Nenhuma corrida ainda.\nVá correr!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),)
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _sessions!.length,
                    itemBuilder: (context, i) => _SessionTile(
                      session: _sessions![i],
                      pickGhostMode: widget.pickGhostMode,
                    ),
                  ),
                ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final WorkoutSessionEntity session;
  final bool pickGhostMode;
  const _SessionTile({required this.session, this.pickGhostMode = false});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(session.startTimeMs);
    final dateStr = '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final distStr = _fmtDist(session.totalDistanceM);
    final durStr = _fmtDur(session.startTimeMs, session.endTimeMs);
    final (statusLabel, statusColor) = _statusInfo(session.status);
    final canGhost = pickGhostMode && session.status == WorkoutStatus.completed;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          canGhost ? Icons.person_add_alt_1 : Icons.directions_run,
          color: canGhost ? Colors.purple : statusColor, size: 32,
        ),
        title: Text('$dateStr  $timeStr'),
        subtitle: Row(children: [
          Expanded(child: Text('$distStr  •  $durStr  •  $statusLabel')),
          if (!canGhost && session.status == WorkoutStatus.completed)
            _SyncBadge(synced: session.isSynced),
        ],),
        trailing: canGhost
            ? const Chip(
                label: Text('Fantasma', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFE1BEE7),
                visualDensity: VisualDensity.compact,
              )
            : const Icon(Icons.chevron_right),
        onTap: () {
          if (canGhost) { Navigator.of(context).pop(session); return; }
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => RunDetailsScreen(session: session)),
          );
        },
      ),
    );
  }

  static String _fmtDist(double? m) {
    if (m == null || m <= 0) return '0.00 km';
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(2)} km';
  }

  static String _fmtDur(int startMs, int? endMs) {
    if (endMs == null) return '--:--';
    final t = ((endMs - startMs) / 1000).round();
    if (t <= 0) return '00:00';
    final h = t ~/ 3600; final m = (t % 3600) ~/ 60; final s = t % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static (String, Color) _statusInfo(WorkoutStatus status) => switch (status) {
    WorkoutStatus.completed => ('Concluída', Colors.green),
    WorkoutStatus.running => ('Em andamento', Colors.blue),
    WorkoutStatus.paused => ('Pausada', Colors.orange),
    WorkoutStatus.discarded => ('Descartada', Colors.grey),
    WorkoutStatus.initial => ('Inicial', Colors.grey),
  };
}

class _SyncBadge extends StatelessWidget {
  final bool synced;
  const _SyncBadge({required this.synced});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: synced ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: synced ? Colors.green : Colors.orange, width: 0.5),
      ),
      child: Text(
        synced ? 'SYNC' : 'PENDENTE',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: synced ? Colors.green.shade800 : Colors.orange.shade800),
      ),
    );
  }
}
