import 'package:equatable/equatable.dart';

enum TrainingSessionStatus { scheduled, cancelled, done }

TrainingSessionStatus trainingStatusFromString(String value) => switch (value) {
      'scheduled' => TrainingSessionStatus.scheduled,
      'cancelled' => TrainingSessionStatus.cancelled,
      'done' => TrainingSessionStatus.done,
      _ => TrainingSessionStatus.scheduled,
    };

String trainingStatusToString(TrainingSessionStatus s) => switch (s) {
      TrainingSessionStatus.scheduled => 'scheduled',
      TrainingSessionStatus.cancelled => 'cancelled',
      TrainingSessionStatus.done => 'done',
    };

final class TrainingSessionEntity extends Equatable {
  final String id;
  final String groupId;
  final String createdBy;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? locationName;
  final double? locationLat;
  final double? locationLng;
  final TrainingSessionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TrainingSessionEntity({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.title,
    this.description,
    required this.startsAt,
    this.endsAt,
    this.locationName,
    this.locationLat,
    this.locationLng,
    this.status = TrainingSessionStatus.scheduled,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isScheduled => status == TrainingSessionStatus.scheduled;
  bool get isCancelled => status == TrainingSessionStatus.cancelled;
  bool get isDone => status == TrainingSessionStatus.done;
  bool get isPast => startsAt.isBefore(DateTime.now());
  bool get isUpcoming => !isPast && isScheduled;

  TrainingSessionEntity copyWith({
    String? title,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
    String? locationName,
    double? locationLat,
    double? locationLng,
    TrainingSessionStatus? status,
    DateTime? updatedAt,
  }) =>
      TrainingSessionEntity(
        id: id,
        groupId: groupId,
        createdBy: createdBy,
        title: title ?? this.title,
        description: description ?? this.description,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
        locationName: locationName ?? this.locationName,
        locationLat: locationLat ?? this.locationLat,
        locationLng: locationLng ?? this.locationLng,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [
        id, groupId, createdBy, title, description,
        startsAt, endsAt, locationName, locationLat, locationLng,
        status, createdAt, updatedAt,
      ];
}
