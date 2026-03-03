import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';
import 'package:omni_runner/domain/usecases/announcements/mark_announcement_read.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_event.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_state.dart';

class AnnouncementDetailBloc
    extends Bloc<AnnouncementDetailEvent, AnnouncementDetailState> {
  final IAnnouncementRepo _repo;
  final MarkAnnouncementRead _markAnnouncementRead;

  AnnouncementDetailBloc({
    required IAnnouncementRepo repo,
    required MarkAnnouncementRead markAnnouncementRead,
  })  : _repo = repo,
        _markAnnouncementRead = markAnnouncementRead,
        super(const AnnouncementDetailInitial()) {
    on<LoadAnnouncementDetail>(_onLoad);
    on<TogglePin>(_onTogglePin);
    on<UpdateAnnouncement>(_onUpdate);
    on<DeleteAnnouncement>(_onDelete);
    on<ConfirmRead>(_onConfirmRead);
  }

  Future<void> _onConfirmRead(
    ConfirmRead _,
    Emitter<AnnouncementDetailState> emit,
  ) async {
    final current = state;
    if (current is! AnnouncementDetailLoaded) return;
    if (current.announcement.isRead) return;

    try {
      await _markAnnouncementRead(current.announcement.id);
      emit(AnnouncementDetailLoaded(
        announcement: current.announcement.copyWith(isRead: true),
        readStats: current.readStats,
      ));
    } on Exception catch (e) {
      emit(AnnouncementDetailError('Não foi possível confirmar leitura: $e'));
    }
  }

  Future<void> _onLoad(
    LoadAnnouncementDetail event,
    Emitter<AnnouncementDetailState> emit,
  ) async {
    emit(const AnnouncementDetailLoading());
    try {
      final announcement = await _repo.getById(event.announcementId);
      if (announcement == null) {
        emit(const AnnouncementDetailError('Anúncio não encontrado.'));
        return;
      }

      await _markAnnouncementRead(event.announcementId);

      AnnouncementReadStats? readStats;
      try {
        readStats = await _repo.getReadStats(event.announcementId);
      } on Exception {
        // Not staff — readStats stays null
      }

      final updated = announcement.copyWith(isRead: true);
      emit(AnnouncementDetailLoaded(
        announcement: updated,
        readStats: readStats,
      ));
    } on Exception catch (e) {
      emit(AnnouncementDetailError('Não foi possível carregar o anúncio: $e'));
    }
  }

  Future<void> _onTogglePin(
    TogglePin _,
    Emitter<AnnouncementDetailState> emit,
  ) async {
    final current = state;
    if (current is! AnnouncementDetailLoaded) return;

    try {
      final updated = await _repo.update(
        current.announcement.copyWith(pinned: !current.announcement.pinned),
      );
      emit(AnnouncementDetailLoaded(
        announcement: updated,
        readStats: current.readStats,
      ));
    } on Exception catch (e) {
      emit(AnnouncementDetailError('Não foi possível fixar: $e'));
    }
  }

  Future<void> _onUpdate(
    UpdateAnnouncement event,
    Emitter<AnnouncementDetailState> emit,
  ) async {
    final current = state;
    if (current is! AnnouncementDetailLoaded) return;

    try {
      final updated = await _repo.update(
        current.announcement.copyWith(title: event.title, body: event.body),
      );
      emit(AnnouncementDetailLoaded(
        announcement: updated,
        readStats: current.readStats,
      ));
    } on Exception catch (e) {
      emit(AnnouncementDetailError('Não foi possível atualizar: $e'));
    }
  }

  Future<void> _onDelete(
    DeleteAnnouncement _,
    Emitter<AnnouncementDetailState> emit,
  ) async {
    final current = state;
    if (current is! AnnouncementDetailLoaded) return;

    try {
      await _repo.delete(current.announcement.id);
      emit(const AnnouncementDeleted());
    } on Exception catch (e) {
      emit(AnnouncementDetailError('Não foi possível excluir: $e'));
    }
  }
}
