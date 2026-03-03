import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';

sealed class CrmListState extends Equatable {
  const CrmListState();

  @override
  List<Object?> get props => [];
}

final class CrmListInitial extends CrmListState {
  const CrmListInitial();
}

final class CrmListLoading extends CrmListState {
  const CrmListLoading();
}

final class CrmListLoaded extends CrmListState {
  final List<CrmAthleteView> athletes;
  final List<CoachingTagEntity> tags;
  final List<String> activeTagFilters;
  final MemberStatusValue? activeStatusFilter;
  final bool hasMore;
  final bool loadingMore;

  const CrmListLoaded({
    required this.athletes,
    required this.tags,
    this.activeTagFilters = const [],
    this.activeStatusFilter,
    this.hasMore = true,
    this.loadingMore = false,
  });

  CrmListLoaded copyWith({
    List<CrmAthleteView>? athletes,
    List<CoachingTagEntity>? tags,
    List<String>? activeTagFilters,
    MemberStatusValue? activeStatusFilter,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      CrmListLoaded(
        athletes: athletes ?? this.athletes,
        tags: tags ?? this.tags,
        activeTagFilters: activeTagFilters ?? this.activeTagFilters,
        activeStatusFilter: activeStatusFilter ?? this.activeStatusFilter,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );

  @override
  List<Object?> get props => [
        athletes,
        tags,
        activeTagFilters,
        activeStatusFilter,
        hasMore,
        loadingMore,
      ];
}

final class CrmListError extends CrmListState {
  final String message;

  const CrmListError(this.message);

  @override
  List<Object?> get props => [message];
}
