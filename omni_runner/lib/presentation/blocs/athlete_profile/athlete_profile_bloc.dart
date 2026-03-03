import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/usecases/crm/manage_member_status.dart';
import 'package:omni_runner/domain/usecases/crm/manage_notes.dart';
import 'package:omni_runner/domain/usecases/crm/manage_tags.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_event.dart';
import 'package:omni_runner/presentation/blocs/athlete_profile/athlete_profile_state.dart';

class AthleteProfileBloc extends Bloc<AthleteProfileEvent, AthleteProfileState> {
  final ManageTags _manageTags;
  final ManageNotes _manageNotes;
  final ManageMemberStatus _manageMemberStatus;
  // ignore: unused_field - injected per spec for future extensibility
  final ICrmRepo _crmRepo;

  String _groupId = '';
  String _athleteUserId = '';

  AthleteProfileBloc({
    required ManageTags manageTags,
    required ManageNotes manageNotes,
    required ManageMemberStatus manageMemberStatus,
    required ICrmRepo crmRepo,
  })  : _manageTags = manageTags,
        _manageNotes = manageNotes,
        _manageMemberStatus = manageMemberStatus,
        _crmRepo = crmRepo,
        super(const AthleteProfileInitial()) {
    on<LoadAthleteProfile>(_onLoadAthleteProfile);
    on<RefreshAthleteProfile>(_onRefreshAthleteProfile);
    on<AddNote>(_onAddNote);
    on<DeleteNote>(_onDeleteNote);
    on<AssignTag>(_onAssignTag);
    on<RemoveTag>(_onRemoveTag);
    on<UpdateStatus>(_onUpdateStatus);
  }

  Future<void> _onLoadAthleteProfile(
    LoadAthleteProfile event,
    Emitter<AthleteProfileState> emit,
  ) async {
    _groupId = event.groupId;
    _athleteUserId = event.athleteUserId;

    emit(const AthleteProfileLoading());
    await _fetch(emit);
  }

  Future<void> _onRefreshAthleteProfile(
    RefreshAthleteProfile event,
    Emitter<AthleteProfileState> emit,
  ) async {
    if (_groupId.isEmpty || _athleteUserId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _onAddNote(
    AddNote event,
    Emitter<AthleteProfileState> emit,
  ) async {
    if (_groupId.isEmpty || _athleteUserId.isEmpty) return;
    try {
      await _manageNotes.create(
        groupId: _groupId,
        athleteUserId: _athleteUserId,
        note: event.note,
      );
      await _fetch(emit);
    } on Exception catch (e) {
      emit(AthleteProfileError('Erro ao adicionar nota: $e'));
    }
  }

  Future<void> _onDeleteNote(
    DeleteNote event,
    Emitter<AthleteProfileState> emit,
  ) async {
    if (_groupId.isEmpty || _athleteUserId.isEmpty) return;
    try {
      await _manageNotes.delete(event.noteId);
      await _fetch(emit);
    } on Exception catch (e) {
      emit(AthleteProfileError('Erro ao excluir nota: $e'));
    }
  }

  Future<void> _onAssignTag(
    AssignTag event,
    Emitter<AthleteProfileState> emit,
  ) async {
    if (_groupId.isEmpty || _athleteUserId.isEmpty) return;
    try {
      await _manageTags.assign(
        groupId: _groupId,
        athleteUserId: _athleteUserId,
        tagId: event.tagId,
      );
      await _fetch(emit);
    } on Exception catch (e) {
      emit(AthleteProfileError('Erro ao atribuir tag: $e'));
    }
  }

  Future<void> _onRemoveTag(
    RemoveTag event,
    Emitter<AthleteProfileState> emit,
  ) async {
    if (_groupId.isEmpty || _athleteUserId.isEmpty) return;
    try {
      await _manageTags.remove(
        groupId: _groupId,
        athleteUserId: _athleteUserId,
        tagId: event.tagId,
      );
      await _fetch(emit);
    } on Exception catch (e) {
      emit(AthleteProfileError('Erro ao remover tag: $e'));
    }
  }

  Future<void> _onUpdateStatus(
    UpdateStatus event,
    Emitter<AthleteProfileState> emit,
  ) async {
    if (_groupId.isEmpty || _athleteUserId.isEmpty) return;
    try {
      await _manageMemberStatus.upsert(
        groupId: _groupId,
        userId: _athleteUserId,
        status: event.status,
      );
      await _fetch(emit);
    } on Exception catch (e) {
      emit(AthleteProfileError('Erro ao atualizar status: $e'));
    }
  }

  Future<void> _fetch(Emitter<AthleteProfileState> emit) async {
    try {
      final results = await Future.wait([
        _manageTags.forAthlete(groupId: _groupId, athleteUserId: _athleteUserId),
        _manageTags.list(_groupId),
        _manageNotes.list(groupId: _groupId, athleteUserId: _athleteUserId),
        _manageMemberStatus.get(groupId: _groupId, userId: _athleteUserId),
      ]);

      final tags = results[0] as List<CoachingTagEntity>;
      final allGroupTags = results[1] as List<CoachingTagEntity>;
      final notes = results[2] as List<AthleteNoteEntity>;
      final status = results[3] as MemberStatusEntity?;

      emit(AthleteProfileLoaded(
        tags: tags,
        allGroupTags: allGroupTags,
        notes: notes,
        status: status,
        athleteUserId: _athleteUserId,
        groupId: _groupId,
      ));
    } on Exception catch (e) {
      emit(AthleteProfileError('Erro ao carregar perfil: $e'));
    }
  }
}
