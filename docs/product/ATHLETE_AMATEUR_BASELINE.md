# Athlete-Amateur Persona Baseline

**Status:** Ratified (2026-04-21), implementation Wave 4
**Owner:** product + mobile + backend
**Related:** L22-10 (Watch/Wear), L22-11 (treadmill),
L22-12 (streaks), L22-13 (cycle), L22-14 (active recovery),
L21-12 (training load), L21-13 (recovery data),
L04-04 (health-data consent).

## Question being answered

> "The amateur runner doesn't want a deload-week TSS chart.
> They want consistent runs, a streak that doesn't punish a
> rest day, and a smartwatch experience that doesn't require
> pulling the phone out. We have ~ 70% of MAU in this bucket
> and we under-serve them."

## Decision

A **single persona-amateur module** covering five experience
gaps. Like the pro baseline (sister doc), each is small in
isolation; together they make casual training feel
opinionated and friendly.

## The 5 features

### 1. Apple Watch / Wear OS native companion (L22-10)

**What.** Two thin native apps (one Swift+WatchKit, one
Kotlin+Wear) that mirror start/stop/pause/lap to the phone
session via the existing `watch_bridge`. Read-only metrics
stay on watch (HR zone, current pace, distance, elapsed).

**Why thin.** A full-fidelity watch app is a 6-month project.
The amateur use case is "I left my phone at home for a 5k —
can the run still log?". That requires:

- Start/stop on watch (write).
- Display current/avg pace (read).
- Sync session back when phone reconnects (write).

That's it. Maps, segments, music — out of scope.

**Architecture.**

```
┌──────────────┐      Apple WatchConnectivity / Wear DataLayer
│ Phone (main) │ <──────────────────────────────────────────┐
│  - DB        │                                            │
│  - Sync      │   batched JSON payloads matching            │
│  - UI        │   watch_session_payload.dart shape          │
└──────────────┘                                            │
                                                            │
                                              ┌─────────────┴───┐
                                              │ Watch (companion)│
                                              │  - HR streamer  │
                                              │  - GPS streamer │
                                              │  - Local buffer │
                                              └─────────────────┘
```

**Standalone watch run** (no phone):

- Watch records GPS + HR locally to a CoreData / Room buffer.
- On reconnect (phone + watch in BLE range), watch flushes
  buffered samples in chunks of 256 samples.
- Phone validates with the existing anti-cheat pipeline
  (L01-43 — anti-cheat min points, max gap) and persists.

**Schema marker.**

```sql
alter table public.sessions add column recorded_via text
  not null default 'phone'
  check (recorded_via in ('phone','watch','watch_standalone','treadmill'));
```

**Out of scope v1.** WatchOS complications, Garmin IQ data
fields, Wear-OS tiles. Each is its own platform-specific
build target.

### 2. Treadmill mode without GPS (L22-11)

**What.** A recording mode that **skips GPS** and accepts:

- Distance (manual entry, pre-set buttons 5/8/10/15 km).
- Pace (derived from distance/duration).
- HR (BLE chest/optical, same path as outdoor).
- Cadence (phone accelerometer).
- Incline (optional manual entry, default 1%).

**Persistence.**

```sql
-- Already covered by recorded_via above.
update public.sessions set recording_type = 'treadmill'
  where recorded_via = 'treadmill';
-- (recording_type already exists; we tag it.)
```

**Anti-cheat.** Treadmill sessions skip GPS-based anti-cheat
(L01-43) but remain subject to:

- Pace plausibility (pace ≥ 2:30 min/km, ≤ 12:00 min/km).
- HR plausibility (max < 220 - age ± 10).
- Duration plausibility (≤ 4 h).

Sessions tagged `treadmill` are **excluded** from public
GPS leaderboards / segments / FKT, but **included** in
volume, frequency, training-load, streak, and badges that
don't depend on geography.

**UI.** Recording screen has a top toggle "Outdoor /
Treadmill" before start. Once started, treadmill mode shows
a different stat layout (no map; big distance/pace/HR cards).

**Why no foot-pod auto-detect.** Foot-pod hardware is rare
in BR market and requires per-vendor calibration. The manual
distance entry is one tap (pre-set buttons cover 80% of
treadmill runs at 5/8/10 km).

### 3. Streaks with grace period (L22-12)

**What.** A streak ("dias consecutivos com atividade")
that:

- Counts running OR any logged movement (walking, cycling,
  yoga session imported from Garmin/Apple Health).
- Auto-grants 1 grace day per week (Sunday rolls into
  Monday by default).
- Stockpile up to 4 "Streak Shields" (1/month auto-credit;
  use one to skip a day).

**Schema.**

```sql
create table public.user_streaks (
  user_id uuid primary key references auth.users(id),
  current_length int not null default 0,
  longest_length int not null default 0,
  last_active_date date,
  grace_used_this_week boolean not null default false,
  shield_count int not null default 0,
  shield_last_credited_at date,
  updated_at timestamptz not null default now()
);

create table public.streak_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  event_date date not null,
  event_type text not null check (event_type in
    ('extend','grace','shield','reset','manual_freeze')),
  length_after int not null,
  created_at timestamptz not null default now(),
  unique (user_id, event_date)
);
```

**Cron.** Daily 02:00 in user's local TZ:

```
for each user where current_length > 0:
  if last_active_date == yesterday: pass    -- still active
  elif last_active_date == day-before AND grace not used: use grace
  elif shield_count > 0: spend a shield
  else: reset (event_type='reset')
```

**Manual freeze.** Settings → "Pause streak (até X dias)".
Useful for injury / surgery. Max freeze 30 days. Audited.

**Why not punish missed days.** Punishing breaks compliance
(Strava research, Apple Activity ring data). Amateurs train
3-4×/week — a 7-day-only streak design is hostile to the
target persona.

### 4. Menstrual cycle tracking (opt-in, sensitive) (L22-13)

**What.** A separate, opt-in feature where female athletes
can log cycle phase and (optionally) symptoms; suggested
intensity / volume nudges adapt accordingly.

**Consent posture.** Health data under LGPD Art. 11. **Off
by default**. Opt-in is a dedicated screen, separate from
general settings, with explicit copy:

> "OmniRunner armazenará informações sobre seu ciclo menstrual
> apenas para te ajudar a treinar melhor. Os dados ficam só
> com você (criptografados em repouso) e nunca são
> compartilhados, mesmo com seu coach, salvo se você ativar
> isso explicitamente. Você pode apagar tudo a qualquer
> momento — e a apagamento é hard-delete (não reversível)."

**Schema.**

```sql
create table public.athlete_cycle_data (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,
  phase text check (phase in
    ('menstrual','follicular','ovulation','luteal','unknown')),
  flow_intensity text check (flow_intensity in
    ('none','spotting','light','medium','heavy')),
  symptoms text[],                          -- short controlled vocab
  shared_with_coach boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, date)
);

-- Encryption at rest via pgsodium for PII columns
-- (phase + symptoms). Filter by date is unencrypted.
alter table public.athlete_cycle_data
  enable row level security;

create policy own_cycle on public.athlete_cycle_data
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Coach access requires BOTH the existing share toggle AND
-- per-row shared_with_coach=true.
```

**Coach visibility.** Even if `coaching_share_recovery=true`
(L21-13), coach **NEVER** sees cycle data unless the athlete
**also** explicitly toggles `shared_with_coach=true` per row
(or globally via a switch). This is a higher bar than the
recovery data because the data is more sensitive culturally.

**Suggestion engine.** Local-only, on-device. The phase
informs intensity nudges:

- Luteal → "Suggest a recovery day" if user is feeling
  fatigued (logged symptoms include 'fatigue').
- Follicular / ovulation → "Hard workout window if you want
  to push".

The suggestion is **never auto-published**. It's a soft tip
in the daily recap.

**No prediction / forecasting.** We do not forecast next
cycle. That's the job of dedicated cycle-tracker apps with
medical-device classifications.

**Hard-delete on opt-out.** Drops all rows for the user. No
soft-delete. We treat this like a "withdraw consent" event
and write to `consent_registry` (L04-09) accordingly.

### 5. Active-recovery suggestion (L22-14)

**What.** When the heuristic detects an athlete is
accumulating training load too fast, the next workout
suggestion in `generate-fit-workout` is replaced with an
active-recovery option (20-30 min walk OR easy 3-4 km run).

**Heuristic.** Uses Acute / Chronic load ratio (ACWR) from
L21-12:

```
acwr = acute_load_7d / chronic_load_28d

if acwr > 1.5  → mandatory recovery (replaces workout)
if acwr > 1.3  → soft suggestion (banner + accept/dismiss)
else           → no intervention
```

ACWR thresholds borrowed from peer-reviewed sports-science
literature (Gabbett 2016, Hulin et al. 2014). Conservative
defaults; user override available in coach-prescribed plans
(coach can sign off on a high-ACWR week if intentional).

**UI surface.**

- **Mandatory** (`acwr > 1.5`): The "today's workout" card
  shows "Recommended: Active Recovery — 20 min walk", with
  a smaller "Override (not recommended)" link.
- **Soft suggestion**: A dismissible banner on top of the
  prescribed workout: "You've ramped up fast this week.
  Consider an easy day."

**Schema.** No new table. Reuses existing `daily_recommendations`
output of `generate-fit-workout`, adding a `reason` field:

```sql
alter table public.daily_recommendations
  add column reason text check (reason in
    ('plan','active_recovery_acwr','active_recovery_back_to_back',
     'race_day','user_override'));
```

**`active_recovery_back_to_back`** triggers when last 2 days
were both `intensity >= 'tempo'`. Heuristic nudge for amateurs
who don't yet read their own load.

**Coach override.** A coach with the athlete on a structured
plan (L08-11 cohort + L09-12 plan) can disable the heuristic
for that athlete: `athlete_settings.acwr_nudges_enabled = false`.
We log this in audit_logs.

**Why not block a hard workout outright.** Paternalism is bad
UX. The mandatory recovery card has a "I know what I'm doing"
override, but logs the override (so the coach sees it later).

## What we DO NOT do

- **Calorie tracking**: tried by 5 fitness apps and 4 of them
  abandoned. Out of scope; partner integration if user demand
  spikes.
- **Group walking challenges**: real product but huge surface;
  separate finding if it comes up.
- **In-app exercise videos**: licensing nightmare; partner
  integration if needed.

## Implementation phases (Wave 4)

1. **W4-G** Streaks: schema, cron, UI badge.
2. **W4-H** Treadmill mode: recording flag, anti-cheat
   carve-out, UI toggle.
3. **W4-I** Active recovery suggestion: heuristic in
   `generate-fit-workout`, daily_recommendations field, UI.
4. **W4-J** Apple Watch / Wear OS thin companion (each is
   its own native target; can ship in parallel).
5. **W4-K** Cycle tracking: dedicated opt-in flow, schema
   with pgsodium encryption, hard-delete on opt-out.

Cycle tracking is **last** because it needs the most legal /
LGPD review and we want the rest of the persona-baseline
features shipped first.

## See also

- `docs/product/ATHLETE_PRO_BASELINE.md` (sibling)
- `docs/product/RECOVERY_SLEEP_TRACKING.md` (L21-13)
- `docs/policies/HEALTH_DATA_CONSENT.md` (L04-04)
- `docs/runbooks/MOBILE_OFFLINE_SESSION_BACKUP.md` (L05-19)
