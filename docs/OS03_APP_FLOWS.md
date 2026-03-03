# OS-03 — App Flows: Mural de Avisos

---

## Flows

| Flow   | Screen                | BLoC                 | Description                                                                 |
|--------|------------------------|----------------------|-----------------------------------------------------------------------------|
| Feed   | AnnouncementFeedScreen | AnnouncementFeedBloc | Fixados primeiro, indicador de não lido, pull-to-refresh                    |
| Detail | AnnouncementDetailScreen | AnnouncementDetailBloc | Auto-marca como lido, estatísticas de leitura para staff, botão confirmar fallback |
| Create | AnnouncementCreateScreen | (direct usecase)   | Título + corpo + toggle fixado                                              |
| Edit   | AnnouncementCreateScreen (modo edição) | (direct repo) | Formulário pré-preenchido                                                    |

---

## Architecture

```
Entity → IAnnouncementRepo → UseCase → BLoC → Screen
```

---

## File Paths

### Entities

- `omni_runner/lib/domain/entities/announcement_entity.dart`

### Repo

- `omni_runner/lib/domain/repositories/i_announcement_repo.dart`
- `omni_runner/lib/data/repositories_impl/supabase_announcement_repo.dart`

### Use Cases

- `omni_runner/lib/domain/usecases/announcements/list_announcements.dart`
- `omni_runner/lib/domain/usecases/announcements/create_announcement.dart`
- `omni_runner/lib/domain/usecases/announcements/mark_announcement_read.dart`

### BLoCs

- `omni_runner/lib/presentation/blocs/announcement_feed/announcement_feed_bloc.dart`
- `omni_runner/lib/presentation/blocs/announcement_feed/announcement_feed_event.dart`
- `omni_runner/lib/presentation/blocs/announcement_feed/announcement_feed_state.dart`
- `omni_runner/lib/presentation/blocs/announcement_detail/announcement_detail_bloc.dart`
- `omni_runner/lib/presentation/blocs/announcement_detail/announcement_detail_event.dart`
- `omni_runner/lib/presentation/blocs/announcement_detail/announcement_detail_state.dart`

### Screens

- `omni_runner/lib/presentation/screens/announcement_feed_screen.dart` (AnnouncementFeedScreen)
- `omni_runner/lib/presentation/screens/announcement_detail_screen.dart` (AnnouncementDetailScreen)
- `omni_runner/lib/presentation/screens/announcement_create_screen.dart` (AnnouncementCreateScreen — Create/Edit)
