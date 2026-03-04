import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/domain/usecases/wearable/push_to_trainingpeaks.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Screen for staff to assign a workout template to an athlete on a date.
class StaffWorkoutAssignScreen extends StatefulWidget {
  final String groupId;

  const StaffWorkoutAssignScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<StaffWorkoutAssignScreen> createState() =>
      _StaffWorkoutAssignScreenState();
}

class _StaffWorkoutAssignScreenState extends State<StaffWorkoutAssignScreen> {
  List<WorkoutTemplateEntity>? _templates;
  List<CoachingMemberEntity>? _athletes;
  bool _loading = true;
  String? _error;

  WorkoutTemplateEntity? _selectedTemplate;
  CoachingMemberEntity? _selectedAthlete;
  DateTime _selectedDate = DateTime.now();
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final templates =
          await sl<IWorkoutRepo>().listTemplates(widget.groupId);
      final members =
          await sl<ICoachingMemberRepo>().getByGroupId(widget.groupId);
      final athletes =
          members.where((m) => m.role == CoachingRole.athlete).toList();
      if (mounted) {
        setState(() {
          _templates = templates;
          _athletes = athletes;
          _loading = false;
        });
      }
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao carregar dados de atribuição',
        tag: 'WorkoutAssignScreen',
        error: e,
        stack: stack,
      );
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar dados: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null && mounted) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _assign() async {
    if (_selectedTemplate == null) {
      _showError('Selecione um template');
      return;
    }
    if (_selectedAthlete == null) {
      _showError('Selecione um atleta');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final assignment = await sl<IWorkoutRepo>().assignWorkout(
        templateId: _selectedTemplate!.id,
        athleteUserId: _selectedAthlete!.userId,
        scheduledDate: _selectedDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Treino atribuído com sucesso!')),
      );
      await _offerTrainingPeaksSync(assignment.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao atribuir treino',
        tag: 'WorkoutAssignScreen',
        error: e,
        stack: stack,
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Erro ao atribuir: $e';
        });
      }
    }
  }

  Future<void> _offerTrainingPeaksSync(String assignmentId) async {
    final shouldSync = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.sync),
        title: const Text('Sincronizar com TrainingPeaks?'),
        content: const Text(
          'Deseja enviar este treino para o TrainingPeaks do atleta?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Sincronizar'),
          ),
        ],
      ),
    );

    if (shouldSync != true || !mounted) return;

    try {
      final result = await PushToTrainingPeaks(sl<SupabaseClient>())
          .call(assignmentId);
      if (!mounted) return;
      final msg = result['ok'] == true
          ? 'Sincronizado com TrainingPeaks!'
          : (result['message'] ?? 'Erro ao sincronizar');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateLabel =
        DateFormat('dd/MM/yyyy', 'pt_BR').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Atribuir Treino'),
      ),
      body: _loading
          ? const ShimmerListLoader()
          : _error != null && _templates == null
              ? _buildError(theme)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    DropdownButtonFormField<WorkoutTemplateEntity>(
                      value: _selectedTemplate,
                      decoration: const InputDecoration(
                        labelText: 'Template de treino',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Selecione o template'),
                      items: (_templates ?? [])
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.name),
                              ))
                          .toList(),
                      onChanged:
                          _saving ? null : (v) => setState(() => _selectedTemplate = v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<CoachingMemberEntity>(
                      value: _selectedAthlete,
                      decoration: const InputDecoration(
                        labelText: 'Atleta',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Selecione o atleta'),
                      items: (_athletes ?? [])
                          .map((a) => DropdownMenuItem(
                                value: a,
                                child: Text(a.displayName),
                              ))
                          .toList(),
                      onChanged:
                          _saving ? null : (v) => setState(() => _selectedAthlete = v),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Data',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(dateLabel),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        hintText: 'Opcional',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: cs.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _assign,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                          _saving ? 'Atribuindo...' : 'Confirmar atribuição'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
