import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/screens/run_details_screen.dart';
import 'package:omni_runner/presentation/widgets/ds/fade_in.dart';
import 'package:omni_runner/presentation/widgets/empty_state.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

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
  static const _staleThreshold = Duration(seconds: 30);
  static const _pageSize = 30;

  List<WorkoutSessionEntity>? _sessions;
  bool _loading = true;
  bool _syncing = false;
  bool _hasMore = true;
  DateTime? _lastLoadAt;

  @override
  void initState() { super.initState(); _loadSessions(); }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      final stale = _lastLoadAt == null ||
          DateTime.now().difference(_lastLoadAt!) > _staleThreshold;
      if (stale) _loadSessions();
    }
  }

  Future<void> _loadSessions({bool loadMore = false}) async {
    final repo = sl<ISessionRepo>();
    final offset = loadMore ? (_sessions?.length ?? 0) : 0;

    // Pull completed sessions from Supabase and merge into Isar
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final rows = await Supabase.instance.client
            .from('sessions')
            .select('id, user_id, status, start_time_ms, end_time_ms, '
                'total_distance_m, moving_ms, is_verified, integrity_flags, '
                'ghost_session_id, source, device_name')
            .eq('user_id', uid)
            .eq('status', 3)
            .gte('total_distance_m', 1000)
            .order('start_time_ms', ascending: false)
            .range(offset, offset + _pageSize - 1);

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
            source: (r['source'] as String?) ?? 'app',
            deviceName: r['device_name'] as String?,
          );
          await repo.save(session);
        }
      }
    } catch (e) {
      AppLogger.warn('History: Supabase pull failed (showing local): $e',
          tag: _tag);
    }

    final all = await repo.getAll();
    if (mounted) {
      final sorted = all
          .where((s) => (s.totalDistanceM ?? 0) >= 1000)
          .toList()
        ..sort((a, b) => b.startTimeMs.compareTo(a.startTimeMs));
      if (loadMore) {
        setState(() {
          _sessions = sorted.take(offset + _pageSize).toList();
          _hasMore = sorted.length > offset + _pageSize;
          _loading = false;
        });
      } else {
        setState(() {
          _sessions = sorted.take(_pageSize).toList();
          _hasMore = sorted.length > _pageSize;
          _loading = false;
        });
      }
      _lastLoadAt = DateTime.now();
    }
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
        title: Text(widget.pickGhostMode ? 'Escolher fantasma' : context.l10n.history),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: widget.pickGhostMode ? null : [
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: DesignTokens.spacingXs),
              child: Center(child: Text('$pending pendente${pending > 1 ? 's' : ''}', style: const TextStyle(fontSize: 12))),
            ),
          IconButton(
            icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            tooltip: 'Sincronizar pendentes',
            onPressed: _syncing ? null : _onSync,
          ),
        ],
      ),
      body: FadeIn(
        child: _loading
            ? const ShimmerListLoader()
            : _sessions == null || _sessions!.isEmpty
                ? const EmptyState(
                    icon: Icons.directions_run_rounded,
                    title: 'Nenhuma corrida ainda',
                    subtitle: 'Conecte o Strava e faça sua primeira corrida.\n'
                        'Ela aparecerá aqui automaticamente!',
                  )
                : RefreshIndicator(
                    onRefresh: _loadSessions,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(DesignTokens.spacingMd),
                      itemCount: _sessions!.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _sessions!.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
                            child: Center(
                              child: OutlinedButton(
                                onPressed: () => _loadSessions(loadMore: true),
                                child: const Text('Carregar mais'),
                              ),
                            ),
                          );
                        }
                        return RepaintBoundary(
                          child: _SessionTile(
                            session: _sessions![i],
                            pickGhostMode: widget.pickGhostMode,
                          ),
                        );
                      },
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

    final (sourceIcon, sourceColor, sourceTooltip) = _sourceInfo(session.source);

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: ListTile(
        leading: Icon(
          canGhost ? Icons.person_add_alt_1 : sourceIcon,
          color: canGhost ? DesignTokens.info : statusColor, size: 32,
        ),
        title: Row(children: [
          Text('$dateStr  $timeStr'),
          if (session.source != 'app') ...[
            const SizedBox(width: 6),
            _SourceBadge(source: session.source, deviceName: session.deviceName),
          ],
        ]),
        subtitle: Row(children: [
          Expanded(child: Text('$distStr  •  $durStr  •  $statusLabel')),
          if (!canGhost && session.status == WorkoutStatus.completed)
            _SyncBadge(synced: session.isSynced),
        ],),
        trailing: canGhost
            ? Chip(
                label: const Text('Fantasma', style: TextStyle(fontSize: 11)),
                backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
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
    WorkoutStatus.completed => ('Concluída', DesignTokens.success),
    WorkoutStatus.running => ('Em andamento', DesignTokens.info),
    WorkoutStatus.paused => ('Pausada', DesignTokens.warning),
    WorkoutStatus.discarded => ('Descartada', DesignTokens.textMuted),
    WorkoutStatus.initial => ('Inicial', DesignTokens.textMuted),
  };

  static (IconData, Color, String) _sourceInfo(String source) => switch (source) {
    'strava' => (Icons.watch, DesignTokens.warning, 'Via Strava'),
    'watch' => (Icons.watch, DesignTokens.textSecondary, 'Relógio'),
    'manual' => (Icons.edit, DesignTokens.textMuted, 'Manual'),
    _ => (Icons.directions_run, DesignTokens.success, 'OmniRunner'),
  };
}

class _SourceBadge extends StatelessWidget {
  final String source;
  final String? deviceName;
  const _SourceBadge({required this.source, this.deviceName});

  @override
  Widget build(BuildContext context) {
    final (label, bgColor) = switch (source) {
      'strava' => (deviceName ?? 'Strava', DesignTokens.warning),
      'watch' => (deviceName ?? 'Relógio', DesignTokens.textSecondary),
      'manual' => ('Manual', DesignTokens.textMuted),
      _ => ('App', DesignTokens.success),
    };

    return Tooltip(
      message: deviceName != null ? 'Gravado no $deviceName via Strava' : 'Importado via $source',
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingXs, vertical: DesignTokens.spacingXs),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(color: bgColor.withValues(alpha: 0.4), width: 0.5),
        ),
        child: Text(
          source == 'strava' ? 'STRAVA' : label.toUpperCase(),
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: bgColor),
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  final bool synced;
  const _SyncBadge({required this.synced});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingXs),
      decoration: BoxDecoration(
        color: synced
            ? DesignTokens.success.withValues(alpha: 0.1)
            : DesignTokens.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
            color: synced ? DesignTokens.success : DesignTokens.warning, width: 0.5),
      ),
      child: Text(
        synced ? 'SYNC' : 'PENDENTE',
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: synced ? DesignTokens.success : DesignTokens.warning),
      ),
    );
  }
}
