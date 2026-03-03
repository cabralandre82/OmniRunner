import 'package:equatable/equatable.dart';

final class AnnouncementEntity extends Equatable {
  final String id;
  final String groupId;
  final String createdBy;
  final String title;
  final String body;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Populated from joins — display name of the author.
  final String? authorDisplayName;

  /// Whether the current user has read this announcement.
  final bool isRead;

  /// Read stats (staff only).
  final int? readCount;
  final int? totalMembers;

  const AnnouncementEntity({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.title,
    required this.body,
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.authorDisplayName,
    this.isRead = false,
    this.readCount,
    this.totalMembers,
  });

  double? get readRate =>
      totalMembers != null && totalMembers! > 0 && readCount != null
          ? (readCount! / totalMembers!) * 100
          : null;

  AnnouncementEntity copyWith({
    String? title,
    String? body,
    bool? pinned,
    DateTime? updatedAt,
    bool? isRead,
    int? readCount,
    int? totalMembers,
  }) =>
      AnnouncementEntity(
        id: id,
        groupId: groupId,
        createdBy: createdBy,
        title: title ?? this.title,
        body: body ?? this.body,
        pinned: pinned ?? this.pinned,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        authorDisplayName: authorDisplayName,
        isRead: isRead ?? this.isRead,
        readCount: readCount ?? this.readCount,
        totalMembers: totalMembers ?? this.totalMembers,
      );

  @override
  List<Object?> get props => [
        id, groupId, createdBy, title, body, pinned,
        createdAt, updatedAt, isRead,
      ];
}
