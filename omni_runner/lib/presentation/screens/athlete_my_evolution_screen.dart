import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

/// Tela do atleta exibindo sua evolução: status, tags, presenças e histórico.
class AthleteMyEvolutionScreen extends StatefulWidget {
  final String groupId;
  final String userId;

  const AthleteMyEvolutionScreen({
    super.key,
    required this.groupId,
    required this.userId,
  });

  @override
  State<AthleteMyEvolutionScreen> createState() => _AthleteMyEvolutionScreenState();
}

class _AthleteMyEvolutionScreenState extends State<AthleteMyEvolutionScreen> {
  MemberStatusEntity? _status;
  List<CoachingTagEntity> _tags = [];
  List<TrainingAttendanceEntity> _attendance = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crmRepo = sl<ICrmRepo>();
      final attendanceRepo = sl<ITrainingAttendanceRepo>();

      final results = await Future.wait([
        crmRepo.getStatus(groupId: widget.groupId, userId: widget.userId),
        crmRepo.getAthleteTags(
          groupId: widget.groupId,
          athleteUserId: widget.userId,
        ),
        attendanceRepo.listByAthlete(
          groupId: widget.groupId,
          athleteUserId: widget.userId,
          limit: 50,
        ),
      ]);

      if (mounted) {
        setState(() {
          _status = results[0] as MemberStatusEntity?;
          _tags = results[1] as List<CoachingTagEntity>;
          _attendance = results[2] as List<TrainingAttendanceEntity>;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorMessages.humanize(e);
          _loading = false;
        });
      }
    }
  }

  int get _totalSessionsAttended => _attendance.length;

  int get _attendanceStreak {
    if (_attendance.isEmpty) return 0;
    final dateSet = _attendance
        .map((a) => a.sessionStartsAt ?? a.checkedAt)
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    if (dateSet.isEmpty) return 0;
    var streak = 0;
    var check = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    while (dateSet.contains(check)) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha Evolução'),
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
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildTagsCard(),
          const SizedBox(height: 16),
          _buildAttendanceSummary(),
          const SizedBox(height: 16),
          _buildRecentAttendance(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final (label, color) = _status == null
        ? ('Não definido', DesignTokens.textMuted)
        : _statusBadge(_status!.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ),
            if (_status != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Atualizado ${DateFormat('d/MM/yy', 'pt_BR').format(_status!.updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTagsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tags',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (_tags.isEmpty)
              Text(
                'Nenhuma tag',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _tags.map((t) {
                  final color = _parseTagColor(t.color);
                  return Chip(
                    label: Text(t.name),
                    backgroundColor: color.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: color,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Color _parseTagColor(String? hex) {
    if (hex == null || hex.isEmpty) return DesignTokens.primary;
    try {
      return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
    } on Object catch (_) {
      return DesignTokens.primary;
    }
  }

  Widget _buildAttendanceSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Presenças',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _SummaryChip(
                  label: 'Total',
                  value: _totalSessionsAttended.toString(),
                ),
                const SizedBox(width: 16),
                _SummaryChip(
                  label: 'Sequência',
                  value: _attendanceStreak.toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentAttendance() {
    final recent = _attendance.take(10).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Últimas presenças',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (recent.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Nenhuma presença registrada',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              ...recent.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 18,
                          color: DesignTokens.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.sessionTitle ?? 'Treino',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          a.sessionStartsAt != null
                              ? DateFormat('d/MM/yy', 'pt_BR')
                                  .format(a.sessionStartsAt!)
                              : DateFormat('d/MM/yy', 'pt_BR').format(a.checkedAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  (String label, Color color) _statusBadge(MemberStatusValue status) {
    return switch (status) {
      MemberStatusValue.active => ('Ativo', DesignTokens.success),
      MemberStatusValue.paused => ('Pausado', DesignTokens.warning),
      MemberStatusValue.injured => ('Lesionado', DesignTokens.error),
      MemberStatusValue.inactive => ('Inativo', DesignTokens.textMuted),
      MemberStatusValue.trial => ('Teste', DesignTokens.primary),
    };
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
