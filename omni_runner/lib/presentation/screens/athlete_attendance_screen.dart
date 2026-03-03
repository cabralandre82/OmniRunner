import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

/// Histórico de presença do atleta nos treinos do grupo.
class AthleteAttendanceScreen extends StatefulWidget {
  final String groupId;
  final String athleteUserId;

  const AthleteAttendanceScreen({
    super.key,
    required this.groupId,
    required this.athleteUserId,
  });

  @override
  State<AthleteAttendanceScreen> createState() => _AthleteAttendanceScreenState();
}

class _AthleteAttendanceScreenState extends State<AthleteAttendanceScreen> {
  List<TrainingAttendanceEntity>? _attendance;
  bool _loading = true;
  String? _error;

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
      final repo = sl<ITrainingAttendanceRepo>();
      final list = await repo.listByAthlete(
        groupId: widget.groupId,
        athleteUserId: widget.athleteUserId,
      );
      if (!mounted) return;
      setState(() {
        _attendance = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar presença: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha Presença'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ShimmerListLoader();
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar Novamente'),
              ),
            ],
          ),
        ),
      );
    }
    final list = _attendance ?? [];
    if (list.isEmpty) {
      return _buildEmpty();
    }
    return _buildList(list);
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Nenhuma presença registrada',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Sua presença nos treinos aparecerá aqui.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<TrainingAttendanceEntity> list) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        itemCount: list.length,
        itemBuilder: (context, index) => _AttendanceCard(attendance: list[index]),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final TrainingAttendanceEntity attendance;

  const _AttendanceCard({required this.attendance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusInfo = _statusInfo(theme);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              attendance.sessionTitle ?? 'Treino',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  DateFormat('d MMM yyyy, HH:mm', 'pt_BR').format(attendance.checkedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusInfo.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusInfo.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusInfo.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, Color color}) _statusInfo(ThemeData theme) {
    return switch (attendance.status) {
      AttendanceStatus.present => (
          label: 'Presente',
          color: Colors.green.shade700,
        ),
      AttendanceStatus.late_ => (
          label: 'Atrasado',
          color: Colors.orange.shade700,
        ),
      AttendanceStatus.excused => (
          label: 'Justificado',
          color: Colors.blue.shade700,
        ),
      AttendanceStatus.absent => (
          label: 'Ausente',
          color: theme.colorScheme.error,
        ),
    };
  }
}
