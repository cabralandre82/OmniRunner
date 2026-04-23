# Athlete onboarding — L23-12 operational runbook

Finding: [L23-12](../audit/findings/L23-12-onboarding-de-novo-atleta-no-clube.md)
Guard: `npm run audit:athlete-onboarding` · `tools/audit/check-athlete-onboarding.ts`

## 1. Why this exists

Before L23-12, adding an athlete to a coaching group was binary:
`INSERT INTO coaching_members` + email invite. The app had no
post-signup wizard, and — crucially — it never asked the athlete
"do you want to import your last 6 months of Strava history so we
can calibrate zones from real data?". The coach ended up shipping
the first plan blind, often over/underestimating fitness.

The finding is explicit: "Coach cadastra atleta → atleta recebe
convite email. Sem wizard 'importe histórico Strava, configuramos
zonas'." The fix ships the state-machine that defines what
onboarding *is* — every surface (wizard UI, coach dashboard,
transactional-email runner, analytics) now agrees on the same 6
canonical steps and on the rules for moving between them.

This runbook is the single source of truth for wiring, tuning, and
debugging the onboarding state-machine.

## 2. Invariants (enforced by CI)

`npm run audit:athlete-onboarding` fails closed on drift in any of:

| Invariant | Enforced by |
|-----------|-------------|
| `AthleteOnboardingStep` declares exactly the 6 canonical values. | `AthleteOnboardingStep.<…> declared` |
| Wire strings stay `invited` / `joined` / `profile_completed` / `strava_choice_made` / `zones_ready` / `completed` — consumers persist and discriminate on these. | `wire string '<…>' present` |
| `athleteOnboardingStepFromWire` null-safe resolver exists. | `athleteOnboardingStepFromWire resolver present` |
| `AthleteOnboardingBounds.staleInviteDays == 14` and `stalledProfileDays == 3`. | `AthleteOnboardingBounds.* == <…>` |
| `StravaImportChoice` declares `undecided` / `imported` / `skipped` with matching wire strings. | `StravaImportChoice.<…> declared` |
| `AthleteOnboardingService` exposes every transition (`invite`, `markJoined`, `markProfileCompleted`, `markStravaChoice`, `markZonesReady`, `markCompleted`) plus `nextStep` and `nudgeFor`. | `service exposes <…>(...)` |
| `markStravaChoice(undecided)` throws. | `markStravaChoice rejects undecided` |
| Nudge resolver reads both bounds. | `nudgeFor reads *` |
| Step / state / service files are pure Dart (no `dart:io`, no `package:flutter/`). | `<file> is pure (no dart:io / flutter imports)` |
| This runbook exists and cross-links the guard + finding + Strava mention. | `runbook cross-links *` |

Dart unit tests
(`flutter test test/domain/services/athlete_onboarding_service_test.dart`,
29 cases) pin the observable behaviour: enum cardinality, wire
strings, bounds, happy paths (Strava imported + skipped), rejected
out-of-order moves, and every nudge outcome.

## 3. What shipped (mobile)

| File | Responsibility |
|------|----------------|
| `omni_runner/lib/domain/value_objects/athlete_onboarding_step.dart` | `AthleteOnboardingStep` enum (6 values) + wire-string extension + null-safe `fromWire` resolver + `AthleteOnboardingBounds` constants. |
| `omni_runner/lib/domain/entities/athlete_onboarding_state.dart` | `AthleteOnboardingState` (Equatable) + `StravaImportChoice` enum. |
| `omni_runner/lib/domain/services/athlete_onboarding_service.dart` | Pure stateless service: `invite`, `markJoined`, `markProfileCompleted`, `markStravaChoice`, `markZonesReady`, `markCompleted`, `nextStep`, `nudgeFor` + `AthleteOnboardingNudge` enum + `AthleteOnboardingTransitionError`. |

Deliberately **not** shipped in this finding (tracked follow-ups):

- **L23-12-persistence**: `coaching_onboarding_state` table /
  `coaching_members.onboarding_step` column storing the wire string.
- **L23-12-wizard**: Flutter wizard UI (`athlete_onboarding_*_screen.dart`)
  that consumes `nextStep()` to decide which page to show.
- **L23-12-strava-backfill**: queue an Edge Function job that pulls
  6 months of Strava activities when the athlete chooses
  `imported`, then bumps `zonesReady = true`.
- **L23-12-email-nudges**: L15-04 email runner dispatches per-
  category templates from `nudgeFor` (one email per day, max).

## 4. State machine

```
           invite()
              │
              ▼
         [invited] ────── staleInvite after 14d ───▶ coach dashboard alert
              │
              │ markJoined(userId)
              ▼
          [joined] ───── profileStalled after 3d ───▶ email nudge
              │
              │ markProfileCompleted()
              ▼
     [profileCompleted] ─────────────▶ nudge: stravaChoiceRequired
              │
              │ markStravaChoice(imported | skipped)
              ▼                                         (undecided → error)
   [stravaChoiceMade] ─── zonesReady=false ───▶ nudge: zonesMissing
              │
              │ markZonesReady()  (set by backfill / test protocol / override)
              ▼
        [zonesReady] ──────────────▶ nudge: readyForFirstPlan
              │
              │ markCompleted()   (coach sanity-checks zones)
              ▼
        [completed]
```

**One-way forward only.** Calling `markJoined` on a state whose
`currentStep` is already `joined` throws
`AthleteOnboardingTransitionError`. Going backwards is a coach
action (future `fn_reset_onboarding`) with its own audit trail, not
a silent repo rewrite.

## 5. How-to: wire the wizard (follow-up L23-12-wizard)

```dart
final svc = AthleteOnboardingService();
final next = svc.nextStep(currentState);
switch (next) {
  case AthleteOnboardingStep.joined:
    // should never render — server moves to joined on sign-in
    break;
  case AthleteOnboardingStep.profileCompleted:
    return ProfileFormScreen(onDone: _markProfileDone);
  case AthleteOnboardingStep.stravaChoiceMade:
    return StravaChoiceScreen(
      onImport: () => _markStravaChoice(StravaImportChoice.imported),
      onSkip:   () => _markStravaChoice(StravaImportChoice.skipped),
    );
  case AthleteOnboardingStep.zonesReady:
    return ZonesCalibrationScreen();
  case AthleteOnboardingStep.completed:
    return ReadyToStartScreen();
  case null:
    Navigator.of(context).pop();
}
```

## 6. How-to: wire the coach dashboard nudge list

```dart
final nudges = athletes
  .map((a) => (a, svc.nudgeFor(a.state, now: DateTime.now())))
  .where((e) => e.$2 != AthleteOnboardingNudge.none)
  .toList();
```

The enum values map one-to-one to coach-facing copy:

| Nudge | Coach-side copy (pt-BR) |
|-------|-------------------------|
| `staleInvite` | "Convite enviado há 14 dias sem resposta — reenviar?" |
| `profileStalled` | "Atleta entrou mas não preencheu o perfil há 3 dias." |
| `stravaChoiceRequired` | "Aguardando decisão sobre importação do Strava." |
| `zonesMissing` | "Zonas não calibradas — agendar time trial?" |
| `readyForFirstPlan` | "Pronto para o primeiro plano." |

## 7. How-to: add a new step

1. Add the value to `AthleteOnboardingStep` **in canonical order**
   (between existing steps, not at the end — order encodes
   progression).
2. Add the wire string in the extension switch.
3. Bump `nextStep()` to handle both sides of the new value.
4. Add a transition method (`markFoo(...)`) to
   `AthleteOnboardingService` with a `_requireAt(...)` call that
   matches the step before the new value.
5. Add a new `AthleteOnboardingNudge` value + `nudgeFor` branch.
6. Add cases to every test group that iterates steps.
7. Bump the guard (`check-athlete-onboarding.ts`): add the new
   value to the canonical lists and the new service method to
   `service exposes (...)`.
8. Update this runbook: state-machine diagram §4, nudge table §6.

## 8. How-to: tune `staleInviteDays` / `stalledProfileDays`

The numbers live on `AthleteOnboardingBounds` so the CI guard pins
them. Moving either requires a PR that:

1. Edits the constant.
2. Edits the guard's expected value.
3. Edits the relevant test expectation.
4. Updates this runbook (§4 diagram, §6 copy).

Do **not** move these values to remote config: they are part of the
UX contract (email nudge cadence) and drift between clients on
different versions would be confusing to coaches and athletes alike.

## 9. Operational playbooks

### "Athlete says they joined but coach dashboard still says 'invited'"

1. Check the server `markJoined` call actually landed — search the
   API logs for the athlete's `auth.users.id`.
2. If it didn't, the sign-in webhook fired too early or got
   swallowed. Manually call `markJoined(...)` via the admin RPC
   once the follow-up persistence lands.

### "Coach complains that stravaChoiceRequired nudge keeps firing"

1. The athlete is still at `profileCompleted` — they never tapped
   Import or Skip. This is the whole point of L23-12: the wizard
   forces the choice.
2. If the athlete says they did tap it, check whether the UI event
   actually called `markStravaChoice`. With the pre-persistence
   follow-up, the write path is easy to forget.

### "CI fails with `markStravaChoice rejects undecided`"

You changed `markStravaChoice` to accept `undecided`. Revert — the
whole purpose of the state-machine is to force an explicit choice.
If product wants "later", add a new `StravaImportChoice.deferred`
value with its own analytics and a nudge that keeps firing until a
terminal choice is made.

### "Bronze / gold onboarding badges broken"

Those are L22-09 scope. `onboarding_completed` event is emitted on
`markCompleted`; the milestone detector consumes that event. Check
the event was emitted before suspecting the badge logic.

## 10. Detection signals

- CI red: `npm run audit:athlete-onboarding` failing.
- Flutter tests red: `flutter test test/domain/services/athlete_onboarding_service_test.dart`.
- Funnel telemetry (when wired): drop-off rate per step. A spike
  at `profileCompleted → stravaChoiceMade` means the Strava flow
  is broken; at `stravaChoiceMade → zonesReady` means backfill
  failures.
- Coach complaints about "Nudge que nunca some" → playbook §9.

## 11. Rollback

Fully additive. Three new files, zero changes to existing code.
Revert the commit and nothing regresses. The follow-ups
(persistence, wizard, backfill) are all opt-in — none of them is
required for the current "email invite only" flow to keep working.

## 12. Cross-references

- [L23-12 finding](../audit/findings/L23-12-onboarding-de-novo-atleta-no-clube.md)
- [L07-04 Strava OAuth state validation](./STRAVA_OAUTH_STATE_RUNBOOK.md) —
  the Strava-import follow-up (L23-12-strava-backfill) depends on
  this.
- [L15-04 transactional email](./EMAIL_TRANSACTIONAL_RUNBOOK.md) —
  `nudgeFor` categories map to email templates.
- [L21-05 athlete_zones] — pending critical (Wave 0). When it
  lands, the backfill follow-up fills the table and `markZonesReady`
  is called automatically.
- [L23-14 time trial](./TIME_TRIAL_RUNBOOK.md) — alternative path
  to `zonesReady` when Strava is skipped.
