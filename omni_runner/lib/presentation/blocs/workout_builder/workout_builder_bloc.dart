import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_event.dart';
import 'package:omni_runner/presentation/blocs/workout_builder/workout_builder_state.dart';

class WorkoutBuilderBloc
    extends Bloc<WorkoutBuilderEvent, WorkoutBuilderState> {
  final IWorkoutRepo _repo;

  WorkoutBuilderBloc({required IWorkoutRepo repo})
      : _repo = repo,
        super(const BuilderInitial()) {
    on<LoadTemplate>(_onLoad);
    on<AddBlock>(_onAddBlock);
    on<RemoveBlock>(_onRemoveBlock);
    on<ReorderBlocks>(_onReorder);
    on<SaveTemplate>(_onSave);
  }

  Future<void> _onLoad(
    LoadTemplate event,
    Emitter<WorkoutBuilderState> emit,
  ) async {
    emit(const BuilderLoading());
    try {
      if (event.templateId != null) {
        final template = await _repo.getTemplateById(event.templateId!);
        if (template == null) {
          emit(const BuilderError('Template não encontrado'));
          return;
        }
        emit(BuilderLoaded(
          template: template,
          blocks: List.of(template.blocks),
          groupId: event.groupId,
        ));
      } else {
        emit(BuilderLoaded(blocks: const [], groupId: event.groupId));
      }
    } on Object catch (e, stack) {
      AppLogger.error(
        'Erro ao carregar template',
        tag: 'WorkoutBuilderBloc',
        error: e,
        stack: stack,
      );
      emit(BuilderError('Erro ao carregar template: $e'));
    }
  }

  void _onAddBlock(
    AddBlock event,
    Emitter<WorkoutBuilderState> emit,
  ) {
    final current = state;
    if (current is! BuilderLoaded) return;
    final updated = [...current.blocks, event.block];
    emit(current.copyWith(blocks: updated));
  }

  void _onRemoveBlock(
    RemoveBlock event,
    Emitter<WorkoutBuilderState> emit,
  ) {
    final current = state;
    if (current is! BuilderLoaded) return;
    final updated =
        current.blocks.where((b) => b.id != event.blockId).toList();
    emit(current.copyWith(blocks: updated));
  }

  void _onReorder(
    ReorderBlocks event,
    Emitter<WorkoutBuilderState> emit,
  ) {
    final current = state;
    if (current is! BuilderLoaded) return;
    final blocks = List.of(current.blocks);
    var newIndex = event.newIndex;
    if (newIndex > event.oldIndex) newIndex--;
    final item = blocks.removeAt(event.oldIndex);
    blocks.insert(newIndex, item);
    emit(current.copyWith(blocks: blocks));
  }

  Future<void> _onSave(
    SaveTemplate event,
    Emitter<WorkoutBuilderState> emit,
  ) async {
    final current = state;
    if (current is! BuilderLoaded) return;

    emit(const BuilderSaving());
    try {
      final now = DateTime.now();
      WorkoutTemplateEntity saved;
      if (current.template != null) {
        saved = await _repo.updateTemplate(WorkoutTemplateEntity(
          id: current.template!.id,
          groupId: current.groupId,
          name: event.name.trim(),
          description:
              event.description?.trim().isEmpty == true ? null : event.description?.trim(),
          createdBy: current.template!.createdBy,
          createdAt: current.template!.createdAt,
          updatedAt: now,
        ));
      } else {
        saved = await _repo.createTemplate(WorkoutTemplateEntity(
          id: '',
          groupId: current.groupId,
          name: event.name.trim(),
          description:
              event.description?.trim().isEmpty == true ? null : event.description?.trim(),
          createdBy: '',
          createdAt: now,
          updatedAt: now,
        ));
      }

      final reindexed = current.blocks.asMap().entries.map((e) {
        return WorkoutBlockEntity(
          id: e.value.id,
          templateId: saved.id,
          orderIndex: e.key,
          blockType: e.value.blockType,
          durationSeconds: e.value.durationSeconds,
          distanceMeters: e.value.distanceMeters,
          targetPaceMinSecPerKm: e.value.targetPaceMinSecPerKm,
          targetPaceMaxSecPerKm: e.value.targetPaceMaxSecPerKm,
          targetHrZone: e.value.targetHrZone,
          targetHrMin: e.value.targetHrMin,
          targetHrMax: e.value.targetHrMax,
          rpeTarget: e.value.rpeTarget,
          repeatCount: e.value.repeatCount,
          notes: e.value.notes,
        );
      }).toList();

      await _repo.saveBlocks(saved.id, reindexed);
      emit(const BuilderSaved());
    } on Object catch (e, stack) {
      AppLogger.error(
        'Erro ao salvar template',
        tag: 'WorkoutBuilderBloc',
        error: e,
        stack: stack,
      );
      emit(BuilderError('Erro ao salvar template: $e'));
    }
  }
}
