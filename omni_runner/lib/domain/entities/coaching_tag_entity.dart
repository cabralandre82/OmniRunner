import 'package:equatable/equatable.dart';

final class CoachingTagEntity extends Equatable {
  final String id;
  final String groupId;
  final String name;
  final String? color;
  final DateTime createdAt;

  const CoachingTagEntity({
    required this.id,
    required this.groupId,
    required this.name,
    this.color,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, groupId, name, color, createdAt];
}
