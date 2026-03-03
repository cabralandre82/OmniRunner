# OS-01 — App Flows

---

## Staff Flows

| Flow           | Screens                   | BLoC             | Actions                                                |
|----------------|---------------------------|------------------|--------------------------------------------------------|
| View agenda    | StaffTrainingListScreen   | TrainingListBloc | Load sessions, filter, pull-to-refresh                 |
| Create session | StaffTrainingCreateScreen | (direct usecase) | Fill form, validate, save                              |
| View detail    | StaffTrainingDetailScreen | TrainingDetailBloc | View session + attendance list                       |
| Scan QR        | StaffTrainingScanScreen   | CheckinBloc      | Scan → decode → mark attendance                        |
| Cancel session | StaffTrainingDetailScreen | TrainingDetailBloc | Confirm → cancel → refresh                           |

## Athlete Flows

| Flow           | Screens                 | BLoC             | Actions                              |
|----------------|-------------------------|------------------|--------------------------------------|
| View trainings | AthleteTrainingListScreen | TrainingListBloc | Upcoming + past sections             |
| Generate QR    | AthleteCheckinQrScreen  | CheckinBloc      | Issue token → render QR → countdown  |
| View attendance| AthleteAttendanceScreen | (direct repo)    | Load own attendance history           |

---

## Architecture

```
Entity → Repo Interface → UseCase → BLoC → Screen
```

---

## File Paths

### Entities
- `omni_runner/lib/domain/entities/training_session_entity.dart`
- `omni_runner/lib/domain/entities/training_attendance_entity.dart`

### Repo Interfaces
- `omni_runner/lib/domain/repositories/i_training_session_repo.dart`
- `omni_runner/lib/domain/repositories/i_training_attendance_repo.dart`

### Repo Implementations
- `omni_runner/lib/data/repositories_impl/supabase_training_session_repo.dart`
- `omni_runner/lib/data/repositories_impl/supabase_training_attendance_repo.dart`

### Use Cases
- `omni_runner/lib/domain/usecases/training/list_training_sessions.dart`
- `omni_runner/lib/domain/usecases/training/create_training_session.dart`
- `omni_runner/lib/domain/usecases/training/cancel_training_session.dart`
- `omni_runner/lib/domain/usecases/training/list_attendance.dart`
- `omni_runner/lib/domain/usecases/training/issue_checkin_token.dart`
- `omni_runner/lib/domain/usecases/training/mark_attendance.dart`

### BLoCs
- `omni_runner/lib/presentation/blocs/training_list/training_list_bloc.dart`
- `omni_runner/lib/presentation/blocs/training_detail/training_detail_bloc.dart`
- `omni_runner/lib/presentation/blocs/checkin/checkin_bloc.dart`

### Screens
- `omni_runner/lib/presentation/screens/staff_training_list_screen.dart`
- `omni_runner/lib/presentation/screens/staff_training_create_screen.dart`
- `omni_runner/lib/presentation/screens/staff_training_detail_screen.dart`
- `omni_runner/lib/presentation/screens/staff_training_scan_screen.dart`
- `omni_runner/lib/presentation/screens/athlete_training_list_screen.dart`
- `omni_runner/lib/presentation/screens/athlete_checkin_qr_screen.dart`
- `omni_runner/lib/presentation/screens/athlete_attendance_screen.dart`
