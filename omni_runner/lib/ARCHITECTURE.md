# Omni Runner Architecture

## Clean Architecture Target

The app follows (or should follow) Clean Architecture:

```
Screens/Widgets (Presentation)
       ↓
BLoC / Cubit (Presentation Logic)
       ↓
Use Cases (Domain)
       ↓
Repository Interface (Domain)
       ↓
Repository Implementation (Data)
       ↓
DataSource (Data) → Supabase / Isar / etc.
```

**Rule:** The presentation layer (screens, BLoCs) must never import `Supabase.instance.client` or any Supabase-specific types directly.

---

## Current Violations (Screens Calling Supabase Directly)

Many screens bypass the architecture and call Supabase from the presentation layer. As of the last audit, the following screens violate the pattern:

| Screen | Direct Supabase Usage |
|--------|------------------------|
| `today_screen.dart` | `recalculate_profile_progress` RPC, `profile_progress`/`sessions`/`challenge_participants`/`championships` tables, `session_journal_entries` |
| `athlete_workout_day_screen.dart` | `workout_delivery_items` query |
| `athlete_delivery_screen.dart` | `workout_delivery_items` query, `fn_athlete_confirm_item` RPC |
| `profile_screen.dart` | `profiles` select/update, `avatars` storage, `delete-account` function |
| `staff_workout_assign_screen.dart` | Uses `PushToTrainingPeaks(SupabaseClient)` - indirect dependency |
| `more_screen.dart` | Member/group queries |
| `support_screen.dart` | Support tickets, messages |
| `auth_gate.dart` | Invite lookup, join requests |
| `run_details_screen.dart` | Session, storage |
| `progress_hub_screen.dart` | Profile/session queries |
| `personal_evolution_screen.dart` | Sessions query |
| `friends_screen.dart` | Profile name resolution |
| `friends_activity_feed_screen.dart` | `fn_friends_activity_feed` RPC |
| `matchmaking_screen.dart` | Multiple tables, functions |
| `league_screen.dart` | Edge function |
| `leaderboards_screen.dart` | Direct Supabase |
| `streaks_leaderboard_screen.dart` | Direct Supabase |
| `partner_assessorias_screen.dart` | Several RPCs |
| `join_assessoria_screen.dart` | Auth, profiles |
| `invite_qr_screen.dart` | Direct Supabase |
| `coaching_group_details_screen.dart` | Group queries, RPCs |
| `challenge_join_screen.dart` | Challenges, participants |
| `history_screen.dart` | Sessions |
| `my_assessoria_screen.dart` | Profiles, groups |
| `staff_dashboard_screen.dart` | Groups, members |
| `athlete_dashboard_screen.dart` | Profiles, groups |
| And others... | (~40 screens total) |

---

## Target Architecture

### Correct Flow

1. **Screen** receives user events, displays UI, and calls BLoC methods (or a service for simple cases).
2. **BLoC/Cubit** or **Service** orchestrates domain logic. It calls **Repository** or **Use Case**, not Supabase.
3. **Repository** implements `I*Repo` interface. It uses **DataSource** (e.g. Supabase) for persistence.
4. **DataSource** performs the actual HTTP/WebSocket calls to Supabase.

### Example (Ideal)

```dart
// Screen – no Supabase
class ProfileScreen extends StatelessWidget {
  void _save() {
    context.read<ProfileBloc>().add(SaveProfile(name: _nameCtrl.text));
  }
}

// BLoC – no Supabase
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc(this._profileRepo) : super(ProfileInitial());
  final IProfileRepo _profileRepo;

  Future<void> _onSaveProfile(SaveProfile e, Emitter emit) async {
    await _profileRepo.updateDisplayName(e.name);
    add(LoadProfile());
  }
}

// Repository – depends on DataSource (which uses Supabase internally)
class ProfileRepo implements IProfileRepo {
  ProfileRepo(this._remote);
  final IProfileDataSource _remote;
  // ...
}
```

---

## Migration Guide for Developers

### Step 1: Identify Supabase Calls

Search the screen for:

- `Supabase.instance.client`
- `Supabase.instance.client.from(...)`
- `Supabase.instance.client.rpc(...)`
- `Supabase.instance.client.storage`
- `Supabase.instance.client.functions`
- `Supabase.instance.client.auth`

### Step 2: Create or Extend a Service/Repository

**Option A – Existing repository:** If a suitable `I*Repo` exists (e.g. `IProfileRepo`, `IWorkoutRepo`), add the missing methods to the interface and implementation.

**Option B – New service:** For ad-hoc or screen-specific logic, create a `*Service` class that wraps the Supabase calls. Register it in `service_locator.dart`.

```dart
// lib/data/services/today_data_service.dart
class TodayDataService {
  TodayDataService(this._client);
  final SupabaseClient _client;

  Future<void> recalculateProfileProgress(String userId) async {
    await _client.rpc('recalculate_profile_progress', params: {'p_user_id': userId});
  }
  // ...
}
```

### Step 3: Register in Service Locator

```dart
// service_locator.dart
sl.registerLazySingleton<TodayDataService>(
  () => TodayDataService(Supabase.instance.client),
);
```

### Step 4: Update the Screen

Replace direct Supabase calls with service calls:

```dart
// Before
await Supabase.instance.client.rpc('recalculate_profile_progress', ...);

// After
await sl<TodayDataService>().recalculateProfileProgress(uid);
```

### Step 5: (Optional) Move to Full Clean Architecture

When ready, introduce a BLoC and repository layer:

- Add `I*Repo` interface in `domain/repositories/`
- Implement in `data/repositories_impl/`
- Use `*UseCase` classes in `domain/usecases/`
- Have the BLoC call use cases instead of services

---

## Pragmatic Approach (Current State)

Given the number of screens with violations, a full migration is risky. The recommended strategy:

1. **New code:** Follow Clean Architecture from the start (Repository → DataSource → Supabase).
2. **Critical screens:** Extract Supabase calls into service classes as an intermediate step (see `TodayDataService`, `WorkoutDeliveryService`, `ProfileDataService`).
3. **Low-traffic screens:** Leave as-is for now, add TODO comments.
4. **Refactoring:** Migrate one screen at a time when touching it for feature work.

---

## Reference: Services Extracted

The following services have been created to reduce direct Supabase usage in screens:

- `TodayDataService` – Used by `today_screen.dart`
- `WorkoutDeliveryService` – Used by `athlete_delivery_screen.dart`, `athlete_workout_day_screen.dart`
- `ProfileDataService` – Used by `profile_screen.dart`

These services are registered in `service_locator.dart` and can serve as examples for further migration.

## Reference: Full Clean Architecture (Training/Attendance)

The training sessions & attendance feature (OS-01 / DECISAO 134) follows the full Clean Architecture pattern end-to-end:

- **Entities:** `TrainingSessionEntity`, `TrainingAttendanceEntity`
- **Repo Interfaces:** `ITrainingSessionRepo`, `ITrainingAttendanceRepo`
- **Repo Implementations:** `SupabaseTrainingSessionRepo`, `SupabaseTrainingAttendanceRepo`
- **Use Cases:** `CreateTrainingSession`, `ListTrainingSessions`, `CancelTrainingSession`, `MarkAttendance`, `ListAttendance`, `IssueCheckinToken`
- **BLoCs:** `TrainingListBloc`, `TrainingDetailBloc`, `CheckinBloc`
- **Screens:** `staff_training_list_screen.dart`, `staff_training_create_screen.dart`, `staff_training_detail_screen.dart`, `athlete_training_list_screen.dart`, `athlete_attendance_screen.dart`

This serves as the reference implementation for all new features.
