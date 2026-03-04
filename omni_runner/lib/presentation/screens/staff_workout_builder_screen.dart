import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_bloc.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_event.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_state.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Form to create or edit a workout template with its blocks.
class StaffWorkoutBuilderScreen extends StatelessWidget {
  final String groupId;
  final String? templateId;

  const StaffWorkoutBuilderScreen({
    super.key,
    required this.groupId,
    this.templateId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<WorkoutBuilderBloc>()
        ..add(LoadTemplate(templateId: templateId, groupId: groupId)),
      child: _BuilderView(templateId: templateId),
    );
  }
}

class _BuilderView extends StatefulWidget {
  final String? templateId;

  const _BuilderView({this.templateId});

  @override
  State<_BuilderView> createState() => _BuilderViewState();
}

class _BuilderViewState extends State<_BuilderView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _didInit = false;

  bool get _isEdit => widget.templateId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _initFields(BuilderLoaded loaded) {
    if (_didInit) return;
    _didInit = true;
    final t = loaded.template;
    if (t != null) {
      _nameController.text = t.name;
      _descriptionController.text = t.description ?? '';
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    context.read<WorkoutBuilderBloc>().add(
          SaveTemplate(
            name: _nameController.text,
            description: _descriptionController.text,
          ),
        );
  }

  void _showAddBlockSheet() {
    showModalBottomSheet<WorkoutBlockEntity>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddBlockSheet(),
    ).then((block) {
      if (block != null && mounted) {
        context.read<WorkoutBuilderBloc>().add(AddBlock(block: block));
      }
    });
  }

  Future<void> _confirmRemoveBlock(
      BuildContext context, WorkoutBlockEntity block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
        title: const Text('Confirmar remoção'),
        content: const Text(
          'Tem certeza que deseja remover este bloco do treino? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<WorkoutBuilderBloc>().add(RemoveBlock(blockId: block.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WorkoutBuilderBloc, WorkoutBuilderState>(
      listener: (context, state) {
        if (state is BuilderSaved) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template salvo com sucesso!')),
          );
          Navigator.of(context).pop(true);
        }
        if (state is BuilderError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        final isSaving = state is BuilderSaving;

        return Semantics(
          label: 'Tela de Editor de Template de Treino',
          child: Scaffold(
          appBar: AppBar(
            title: Text(_isEdit ? 'Editar Template' : 'Novo Template'),
            actions: [
              if (isSaving)
                const Padding(
                  padding: EdgeInsets.all(DesignTokens.spacingMd),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (state is BuilderLoaded)
                TextButton(
                  onPressed: _save,
                  child: const Text('Salvar'),
                ),
            ],
          ),
          body: _buildBody(context, state),
        ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, WorkoutBuilderState state) {
    final theme = Theme.of(context);

    return switch (state) {
      BuilderInitial() || BuilderLoading() =>
        const ShimmerListLoader(),
      BuilderSaving() => const Center(child: CircularProgressIndicator()),
      BuilderSaved() => const SizedBox.shrink(),
      BuilderError(:final message) => Center(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.error)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    context.read<WorkoutBuilderBloc>().add(
                          LoadTemplate(
                            templateId: widget.templateId,
                            groupId: '',
                          ),
                        );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      BuilderLoaded() => _buildLoaded(context, state),
    };
  }

  Widget _buildLoaded(BuildContext context, BuilderLoaded loaded) {
    _initFields(loaded);
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nome do template',
              hintText: 'Ex: Treino intervalado 5x1km',
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
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Blocos',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _showAddBlockSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (loaded.blocks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXl),
              child: Center(
                child: Text(
                  'Nenhum bloco adicionado',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: loaded.blocks.length,
              onReorder: (oldIndex, newIndex) {
                context.read<WorkoutBuilderBloc>().add(
                      ReorderBlocks(oldIndex: oldIndex, newIndex: newIndex),
                    );
              },
              itemBuilder: (context, index) {
                final block = loaded.blocks[index];
                return _BlockTile(
                  key: ValueKey(block.id),
                  block: block,
                  index: index,
                  onRemove: () => _confirmRemoveBlock(context, block),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  final WorkoutBlockEntity block;
  final int index;
  final VoidCallback onRemove;

  const _BlockTile({
    super.key,
    required this.block,
    required this.index,
    required this.onRemove,
  });

  static const _typeLabels = {
    WorkoutBlockType.warmup: 'Aquecimento',
    WorkoutBlockType.interval: 'Intervalo',
    WorkoutBlockType.recovery: 'Recuperação',
    WorkoutBlockType.cooldown: 'Desaquecimento',
    WorkoutBlockType.steady: 'Contínuo',
  };

  static const _typeColors = {
    WorkoutBlockType.warmup: DesignTokens.warning,
    WorkoutBlockType.interval: DesignTokens.error,
    WorkoutBlockType.recovery: DesignTokens.success,
    WorkoutBlockType.cooldown: DesignTokens.primary,
    WorkoutBlockType.steady: DesignTokens.success,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _typeColors[block.blockType] ?? theme.colorScheme.outline;
    final label = _typeLabels[block.blockType] ?? 'Bloco';
    final isDark = theme.brightness == Brightness.dark;
    final chipTextColor = isDark ? color.withValues(alpha: 0.9) : color;

    final details = <String>[];
    if (block.durationSeconds != null) {
      final min = block.durationSeconds! ~/ 60;
      final sec = block.durationSeconds! % 60;
      details.add(sec > 0 ? '${min}m${sec}s' : '${min}min');
    }
    if (block.distanceMeters != null) {
      if (block.distanceMeters! >= 1000) {
        details.add('${(block.distanceMeters! / 1000).toStringAsFixed(1)}km');
      } else {
        details.add('${block.distanceMeters}m');
      }
    }
    if (block.targetHrZone != null) details.add('Z${block.targetHrZone}');
    if (block.rpeTarget != null) details.add('RPE ${block.rpeTarget}');
    if (block.targetPaceSecondsPerKm != null) {
      final m = block.targetPaceSecondsPerKm! ~/ 60;
      final s = block.targetPaceSecondsPerKm! % 60;
      details.add('${m}:${s.toString().padLeft(2, '0')}/km');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
      child: ListTile(
        leading: Container(
          width: 8,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DesignTokens.spacingXs),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.25 : 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: chipTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  details.join(' · '),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.close, size: 20, color: theme.colorScheme.error),
          onPressed: onRemove,
          tooltip: 'Remover bloco',
        ),
      ),
    );
  }
}

class _AddBlockSheet extends StatefulWidget {
  const _AddBlockSheet();

  @override
  State<_AddBlockSheet> createState() => _AddBlockSheetState();
}

class _AddBlockSheetState extends State<_AddBlockSheet> {
  WorkoutBlockType _blockType = WorkoutBlockType.steady;
  final _durationController = TextEditingController();
  final _distanceController = TextEditingController();
  final _paceMinController = TextEditingController();
  final _paceSecController = TextEditingController();
  int? _hrZone;
  int? _rpe;

  static const _typeLabels = {
    WorkoutBlockType.warmup: 'Aquecimento',
    WorkoutBlockType.interval: 'Intervalo',
    WorkoutBlockType.recovery: 'Recuperação',
    WorkoutBlockType.cooldown: 'Desaquecimento',
    WorkoutBlockType.steady: 'Contínuo',
  };

  @override
  void dispose() {
    _durationController.dispose();
    _distanceController.dispose();
    _paceMinController.dispose();
    _paceSecController.dispose();
    super.dispose();
  }

  void _confirm() {
    final durMin = int.tryParse(_durationController.text);
    final distM = int.tryParse(_distanceController.text);
    final paceMin = int.tryParse(_paceMinController.text);
    final paceSec = int.tryParse(_paceSecController.text);

    int? paceSecondsPerKm;
    if (paceMin != null) {
      paceSecondsPerKm = paceMin * 60 + (paceSec ?? 0);
    }

    final block = WorkoutBlockEntity(
      id: const Uuid().v4(),
      templateId: '',
      orderIndex: 0,
      blockType: _blockType,
      durationSeconds: durMin != null ? durMin * 60 : null,
      distanceMeters: distM,
      targetPaceSecondsPerKm: paceSecondsPerKm,
      targetHrZone: _hrZone,
      rpeTarget: _rpe,
    );

    Navigator.of(context).pop(block);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 600,
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Adicionar Bloco',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            DropdownButtonFormField<WorkoutBlockType>(
              value: _blockType,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              items: WorkoutBlockType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(_typeLabels[t]!),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _blockType = v);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _durationController,
                    decoration: const InputDecoration(
                      labelText: 'Duração (min)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _distanceController,
                    decoration: const InputDecoration(
                      labelText: 'Distância (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _paceMinController,
                    decoration: const InputDecoration(
                      labelText: 'Pace min',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
                  child: Text(':'),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _paceSecController,
                    decoration: const InputDecoration(
                      labelText: 'Pace seg',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('/km'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: _hrZone,
                    decoration: const InputDecoration(
                      labelText: 'Zona FC',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (int z = 1; z <= 5; z++)
                        DropdownMenuItem(value: z, child: Text('Z$z')),
                    ],
                    onChanged: (v) => setState(() => _hrZone = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: _rpe,
                    decoration: const InputDecoration(
                      labelText: 'RPE',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (int r = 1; r <= 10; r++)
                        DropdownMenuItem(value: r, child: Text('$r')),
                    ],
                    onChanged: (v) => setState(() => _rpe = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.check),
              label: const Text('Adicionar'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
