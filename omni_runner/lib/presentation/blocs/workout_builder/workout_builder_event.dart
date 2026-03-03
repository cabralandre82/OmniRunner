import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';

sealed class WorkoutBuilderEvent extends Equatable {
  const WorkoutBuilderEvent();

  @override
  List<Object?> get props => [];
}

final class LoadTemplate extends WorkoutBuilderEvent {
  final String? templateId;
  final String groupId;

  const LoadTemplate({this.templateId, required this.groupId});

  @override
  List<Object?> get props => [templateId, groupId];
}

final class AddBlock extends WorkoutBuilderEvent {
  final WorkoutBlockEntity block;

  const AddBlock({required this.block});

  @override
  List<Object?> get props => [block];
}

final class RemoveBlock extends WorkoutBuilderEvent {
  final String blockId;

  const RemoveBlock({required this.blockId});

  @override
  List<Object?> get props => [blockId];
}

final class ReorderBlocks extends WorkoutBuilderEvent {
  final int oldIndex;
  final int newIndex;

  const ReorderBlocks({required this.oldIndex, required this.newIndex});

  @override
  List<Object?> get props => [oldIndex, newIndex];
}

final class SaveTemplate extends WorkoutBuilderEvent {
  final String name;
  final String? description;

  const SaveTemplate({required this.name, this.description});

  @override
  List<Object?> get props => [name, description];
}
