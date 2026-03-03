import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';

final class ManageNotes {
  final ICrmRepo _repo;

  const ManageNotes({required ICrmRepo repo}) : _repo = repo;

  Future<List<AthleteNoteEntity>> list({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) =>
      _repo.listNotes(
        groupId: groupId,
        athleteUserId: athleteUserId,
        limit: limit,
        offset: offset,
      );

  Future<AthleteNoteEntity> create({
    required String groupId,
    required String athleteUserId,
    required String note,
  }) {
    if (note.trim().isEmpty) throw ArgumentError('Note cannot be empty');
    return _repo.createNote(
      groupId: groupId,
      athleteUserId: athleteUserId,
      note: note.trim(),
    );
  }

  Future<void> delete(String noteId) => _repo.deleteNote(noteId);
}
