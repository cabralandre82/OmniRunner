import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';
import 'package:omni_runner/domain/usecases/training/create_training_session.dart';

/// Form to create or edit a training session.
/// Uses [groupId] and [userId] from constructor; [existing] for edit mode.
class StaffTrainingCreateScreen extends StatefulWidget {
  final String groupId;
  final String userId;
  final TrainingSessionEntity? existing;

  const StaffTrainingCreateScreen({
    super.key,
    required this.groupId,
    required this.userId,
    this.existing,
  });

  @override
  State<StaffTrainingCreateScreen> createState() =>
      _StaffTrainingCreateScreenState();
}

class _StaffTrainingCreateScreenState extends State<StaffTrainingCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleController.text = e.title;
      _descriptionController.text = e.description ?? '';
      _locationController.text = e.locationName ?? '';
      _startsAt = e.startsAt;
      _endsAt = e.endsAt;
    } else {
      _startsAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(
    bool isStart,
  ) async {
    final initial = isStart ? _startsAt : _endsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        initial ?? DateTime(date.year, date.month, date.day),
      ),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        _startsAt = picked;
        if (_endsAt != null && _endsAt!.isBefore(picked)) {
          _endsAt = null;
        }
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _save() async {
    _error = null;
    if (!_formKey.currentState!.validate()) return;
    if (_startsAt == null) {
      setState(() => _error = 'Selecione a data e hora de início');
      return;
    }

    final endsAt = _endsAt;
    if (endsAt != null && endsAt.isBefore(_startsAt!)) {
      setState(() => _error = 'O término deve ser depois do início');
      return;
    }

    setState(() => _saving = true);

    try {
      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startsAt: _startsAt!,
          endsAt: endsAt,
          locationName: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          updatedAt: DateTime.now(),
        );
        await sl<ITrainingSessionRepo>().update(updated);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Treino salvo com sucesso!')),
        );
        Navigator.of(context).pop(updated);
      } else {
        final created = await sl<CreateTrainingSession>().call(
          id: const Uuid().v4(),
          groupId: widget.groupId,
          createdBy: widget.userId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startsAt: _startsAt!,
          endsAt: endsAt,
          locationName: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Treino salvo com sucesso!')),
        );
        Navigator.of(context).pop(created);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Erro ao salvar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateFormat = _startsAt != null
        ? '${_startsAt!.day.toString().padLeft(2, '0')}/${_startsAt!.month.toString().padLeft(2, '0')}/${_startsAt!.year} ${_startsAt!.hour.toString().padLeft(2, '0')}:${_startsAt!.minute.toString().padLeft(2, '0')}'
        : 'Selecionar';
    final endFormat = _endsAt != null
        ? '${_endsAt!.day.toString().padLeft(2, '0')}/${_endsAt!.month.toString().padLeft(2, '0')}/${_endsAt!.year} ${_endsAt!.hour.toString().padLeft(2, '0')}:${_endsAt!.minute.toString().padLeft(2, '0')}'
        : 'Opcional';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar Treino' : 'Novo Treino'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Salvar'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Título',
                hintText: 'Ex: Treino de velocidade',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              autofocus: !_isEdit,
              validator: (v) {
                if (v == null || v.trim().length < 2) {
                  return 'Mínimo 2 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                hintText: 'Opcional',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Local',
                hintText: 'Opcional',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),
            Text(
              'Data e horário',
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickDateTime(true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(dateFormat),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickDateTime(false),
                    icon: const Icon(Icons.schedule),
                    label: Text(endFormat),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: cs.onErrorContainer),
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
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Salvando...' : 'Salvar treino'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
