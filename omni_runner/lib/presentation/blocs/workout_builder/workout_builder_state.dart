import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';

sealed class WorkoutBuilderState extends Equatable {
  const WorkoutBuilderState();

  @override
  List<Object?> get props => [];
}

final class BuilderInitial extends WorkoutBuilderState {
  const BuilderInitial();
}

final class BuilderLoading extends WorkoutBuilderState {
  const BuilderLoading();
}

final class BuilderLoaded extends WorkoutBuilderState {
  final WorkoutTemplateEntity? template;
  final List<WorkoutBlockEntity> blocks;
  final String groupId;

  const BuilderLoaded({
    this.template,
    required this.blocks,
    required this.groupId,
  });

  @override
  List<Object?> get props => [template, blocks, groupId];

  BuilderLoaded copyWith({
    WorkoutTemplateEntity? template,
    List<WorkoutBlockEntity>? blocks,
  }) =>
      BuilderLoaded(
        template: template ?? this.template,
        blocks: blocks ?? this.blocks,
        groupId: groupId,
      );
}

final class BuilderSaving extends WorkoutBuilderState {
  const BuilderSaving();
}

final class BuilderSaved extends WorkoutBuilderState {
  const BuilderSaved();
}

final class BuilderError extends WorkoutBuilderState {
  final String message;

  const BuilderError(this.message);

  @override
  List<Object?> get props => [message];
}
