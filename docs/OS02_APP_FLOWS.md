# OS-02 — App Flows: CRM do Atleta

---

## Staff Flows

| Flow | Screen | BLoC | Description |
|------|--------|------|-------------|
| CRM list | StaffCrmListScreen | CrmListBloc | Filter athletes by tags, status; see risk indicators |
| Athlete profile | StaffAthleteProfileScreen | AthleteProfileBloc | 5 tabs: Overview, Notas, Tags, Presença, Alertas |
| Add note | StaffAthleteProfileScreen (Notes tab) | AthleteProfileBloc → AddNote | Text input + send |
| Manage tags | StaffCrmListScreen FAB + Profile Tags tab | AthleteProfileBloc → AssignTag/RemoveTag | Create group tags, assign/remove per athlete |
| Change status | StaffAthleteProfileScreen (Overview) | AthleteProfileBloc → UpdateStatus | Dropdown selector |

## Athlete Flows

| Flow | Screen | Description |
|------|--------|-------------|
| My status | AthleteMyStatusScreen | Read-only view of own status |
| My evolution | AthleteMyEvolutionScreen | Own tags, attendance stats, recent attendance |

---

## Architecture

```
Entity → ICrmRepo → UseCase → BLoC → Screen
```

---

## File Paths

### Entities
- `omni_runner/lib/domain/entities/coaching_tag_entity.dart`
- `omni_runner/lib/domain/entities/athlete_note_entity.dart`
- `omni_runner/lib/domain/entities/member_status_entity.dart`

### Repo
- `omni_runner/lib/domain/repositories/i_crm_repo.dart`
- `omni_runner/lib/data/repositories_impl/supabase_crm_repo.dart`

### Use Cases
- `omni_runner/lib/domain/usecases/crm/list_crm_athletes.dart`
- `omni_runner/lib/domain/usecases/crm/manage_tags.dart`
- `omni_runner/lib/domain/usecases/crm/manage_notes.dart`
- `omni_runner/lib/domain/usecases/crm/manage_member_status.dart`

### BLoCs
- `omni_runner/lib/presentation/blocs/crm_list/crm_list_bloc.dart`
- `omni_runner/lib/presentation/blocs/athlete_profile/athlete_profile_bloc.dart`

### Screens
- `omni_runner/lib/presentation/screens/staff_crm_list_screen.dart`
- `omni_runner/lib/presentation/screens/staff_athlete_profile_screen.dart`
- `omni_runner/lib/presentation/screens/athlete_my_status_screen.dart`
- `omni_runner/lib/presentation/screens/athlete_my_evolution_screen.dart`
