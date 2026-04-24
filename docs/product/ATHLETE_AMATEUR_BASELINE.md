# Athlete-Amateur Persona Baseline

**Status:** Ratified (2026-04-21, extended 2026-04-24),
implementation Wave 4-5 (see phases)
**Owner:** product + mobile + backend
**Related — K11 batch (sections 1–5):** L22-10 (Watch/Wear),
L22-11 (treadmill), L22-12 (streaks), L22-13 (cycle),
L22-14 (active recovery), L21-12 (training load),
L21-13 (recovery data), L04-04 (health-data consent).
**Related — K12 batch (sections 6–11):** L22-15 (PDF wrapped),
L22-16 (injury triage), L22-17 (weather widget), L22-18
(onboarding goal), L22-19 (healthy social comparison),
L22-20 (D30/D90/D180/D365 retention hooks).

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

### 6. Monthly Wrapped PDF export (L22-15)

**What.** A shareable monthly PDF (1–2 pages) with the big
numbers an amateur actually wants to show off: km, runs,
best 5k, longest run, streak length, favorite route (heat
strip), a motivational line, profile photo in the header.

**Why not the technical export.** We already ship `.fit`
(L21-07), which is the right format for TrainingPeaks /
Garmin / Strava interop. But `.fit` is unreadable by the
amateur's friends and family — the share-worthy artifact is
a visual summary. Splitting the two is the right layering:
`.fit` = data portability, PDF = consumer share object.

**Reuse, don't rebuild.** `generate-wrapped` Edge Function
already produces the aggregate JSON for period = month. We
add **one** rendering path on top:

```
┌──────────────────────┐     ┌──────────────────────┐
│ generate-wrapped     │ --> │ render-wrapped-pdf   │
│  (aggregate JSON)    │     │  (Node + @react-pdf) │
│  existente           │     │  novo Edge/Serverless│
└──────────────────────┘     └─────────┬────────────┘
                                       │
                              ┌────────┴─────────┐
                              │ storage bucket   │
                              │ user-wrapped-pdf │
                              │ signed URL 24h   │
                              └──────────────────┘
```

**Rendering.** `@react-pdf/renderer` running in a Node
runtime (Edge Deno has a React-PDF port but fonts are
painful). Render happens server-side on-demand when the
athlete taps "Exportar em PDF"; 24h signed URL returned.
No pre-generation — monthly wrapped is low-traffic
(< 5% MAU monthly), pre-rendering wastes storage.

**PDF content (page 1).**

- Header: profile photo + month/year ("Outubro 2026").
- Big number row: `km` · `corridas` · `tempo total`.
- Subtext: best 5k time, longest run (with distance + pace).
- "Sua rota favorita" — heat strip of top-visited
  segment (computed already by `compute-leaderboard`).
- Motivational line, picked from a curated JSON (10 options,
  rotating by `hash(user_id + month)` so same user sees
  the same line that month, but it varies month to month).

**PDF content (page 2, optional).**

- Progression graph (monthly km last 6 months, bar chart).
- Badges earned this month (L22-12 streaks + L05-12
  badges).
- Share copy block: "Compartilhe com seus amigos — #Omni".

**Storage.**

```sql
create table public.user_wrapped_pdf (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  period_key text not null,             -- e.g. '2026-10'
  storage_path text not null,           -- user-wrapped-pdf/u/{uid}/{period}.pdf
  generated_at timestamptz not null default now(),
  bytes int not null,
  unique (user_id, period_key)
);

alter table public.user_wrapped_pdf enable row level security;
create policy own_wrapped_pdf on public.user_wrapped_pdf
  for select using (user_id = auth.uid());
```

**Storage bucket.** `user-wrapped-pdf`, private, path
scheme `u/{user_id}/{period_key}.pdf`, RLS mirrors
the table.

**Social sharing.** Mobile uses the OS share sheet with
`application/pdf` mime; no additional watermark / meta
needed beyond what the PDF already shows.

**Out of scope v1.**

- Video wrapped (Reels-style). Separate project; much
  higher cost to generate and distribute.
- Custom theme / color pick. v1 ships one opinionated
  template.

### 7. In-app injury triage (L22-16)

**What.** An in-app flow that triages a musculoskeletal
complaint, gives immediate self-care guidance, and
connects the athlete to a local professional if needed.

**Ethical stance (must-have).** We do **not** diagnose. We
**triage** (a narrower, safer scope: "should you rest, or
should you see a professional?"). Copy across the flow
reinforces this boundary. All outputs end with "Em caso
de dúvida, consulte um profissional."

**Flow.**

1. Trigger points: Settings → "Reportar lesão" · post-run
   sheet "Senti dor hoje" · weekly retrospective prompt.
2. Screen 1 — Location: body-map picker with 8 regions
   (pé, tornozelo, canela, joelho, coxa, quadril, lombar,
   outro). Single-select.
3. Screen 2 — Onset + intensity: "Quando começou?"
   (today / this week / longer) · "Quão forte?" (EVA 0–10
   slider, labels: 0 = "não incomoda", 10 = "insuportável").
4. Screen 3 — Context: "Dói em repouso?" / "Dói só
   correndo?" / "Dói até caminhando?" (radio, single).
5. Output — Recommendation, from a decision matrix (see
   below).

**Decision matrix (v1, conservative).**

```
if intensity >= 8                         → professional NOW
elif intensity >= 5 AND hurts_at_rest     → professional within 48h
elif intensity >= 5                       → rest 3-5d + pro if ≥ day 3 same
elif intensity < 5 AND onset > 7d         → rest 3d + pro if no improvement
elif intensity < 5                        → rest 2-3d + gentle ROM
```

All branches include: RICE mnemonic card (Rest/Ice/
Compression/Elevation), a "pausar treino" one-tap that
freezes the streak (L22-12 manual_freeze, audited) and
pauses the current plan, and a "find local professional"
CTA.

**Professional directory.** Read from a new table,
curated manually (v1 not crowd-sourced):

```sql
create table public.injury_professionals (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in
    ('physio','orthopedist','sports_medicine','podiatry')),
  name text not null,
  city text not null,
  state text not null check (char_length(state) = 2),
  phone text,
  whatsapp text,
  website text,
  accepts_insurance text[],
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create index injury_pro_state_city on public.injury_professionals
  (state, city) where verified_at is not null;
```

Surfaced only when the triage result is "professional"
and sorted by distance (city-level; no GPS tracking —
uses the city on user profile). No booking integration
in v1 — we link to WhatsApp / website.

**Data capture.**

```sql
create table public.injury_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  region text not null,
  intensity int not null check (intensity between 0 and 10),
  onset text not null check (onset in
    ('today','this_week','longer')),
  hurts_at_rest boolean not null,
  hurts_walking boolean not null,
  recommendation text not null check (recommendation in
    ('rest_light','rest_firm','pro_48h','pro_now')),
  created_at timestamptz not null default now()
);

alter table public.injury_reports enable row level security;
create policy own_injury on public.injury_reports
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());
```

**LGPD posture.** Health data (Art. 11). Stored per-user
with own-only RLS. **Never** shared with coach automatically
— if the athlete wants to tell the coach, they send a
message. Hard-deleted on account deletion via
`fn_delete_user_data`.

**Out of scope v1.**

- ML triage (training data is too sparse, ethical floor
  is too high).
- In-app telemedicine. Partner deep-link only.
- Insurance claim assist. Partner territory.
- Medication dosing / naming. Strict no-go.

### 8. Home weather widget (L22-17)

**What.** The today-screen header shows a 3-line block:
now + next 6h precipitation + "running window" hint.

**Why.** Amateurs routinely open the window or another app
to decide "do I go out now?". The alternative is not
running. Bringing the decision into the run app is cheap
(one API call) and materially helps adherence.

**Data source.** Primary: OpenWeatherMap One Call API 3.0
(cache-friendly, good BR coverage). Fallback: Open-Meteo
(free, sufficient for "will it rain in 2h?"). Budget cap
at OpenWeatherMap free tier (1,000 calls/day) — any call
over the ceiling falls back to Open-Meteo automatically.

**Coordinates.** From the athlete's home city on profile
(not runtime GPS — that would require background location
permission we don't need). Resolution: city centroid,
cached at user level.

```sql
alter table public.profiles
  add column home_city_lat double precision,
  add column home_city_lng double precision;
```

We geocode `home_city` once on save, not at every
weather read.

**Caching.** We **never** call the weather API on
app open. `weather-cache-cron` (pg_cron every 30 min)
pulls current+forecast for distinct (lat/lng) bins used
by ≥1 user, and stores:

```sql
create table public.weather_cache (
  cache_key text primary key,       -- '{lat3}:{lng3}' (3 decimals ≈ 100m)
  fetched_at timestamptz not null default now(),
  payload jsonb not null,           -- { now, hourly[6], alerts[] }
  source text not null check (source in ('openweather','openmeteo'))
);
```

App reads `weather_cache` by key; no direct API call from
client. The bin resolution (3 decimals) trades 100m
precision for dramatic API cost reduction (1,000 active
cities, not 1M athletes).

**UI (home screen).**

```
┌──────────────────────────────────────────────┐
│ Hoje · 06:00   22°C · nublado                │
│ Próximas 6h: chuva começa ~ 08:30            │
│ 👟 Boa janela: agora até 08:00               │
└──────────────────────────────────────────────┘
```

The "running window" is a simple heuristic:

```
pleasant if temperature in [12, 28] AND precipitation_mm = 0
  AND wind_speed < 6 m/s AND no lightning alert
marginal if temperature in [8, 32] AND precipitation_mm < 0.5
harsh otherwise
```

**Consent.** Weather isn't sensitive, but the home-city
geocoding stores a lat/lng. We add a short line in
onboarding: "Para o widget de clima — se desativar, a
tela pula o bloco". Preference persists in `athlete_settings`.

**Out of scope v1.**

- Per-run GPS-based forecasting (unnecessary, adds perms).
- Pollen / UV / AQI. Nice-to-haves; separate spec.
- Alerts push (e.g. "chuva em 30 min"). Pilot separately
  once we trust the data source volume on BR metros.

### 9. Onboarding goal step (L22-18)

**What.** A mandatory step in amateur onboarding that asks
"Qual seu objetivo?" with 5 canonical goals and an
optional target date. The plan generator reads the goal;
the home screen reads it; the social copy reads it.

**The 5 canonical goals.**

1. `general_health` — "Saúde geral / bem-estar".
2. `run_5k` — "Terminar um 5k".
3. `run_10k` — "Terminar um 10k".
4. `run_half_marathon` — "Terminar uma meia (21k)".
5. `run_marathon` — "Terminar uma maratona (42k)".

We ship 5, not 20. 5 covers >90% of the amateur cohort and
keeps periodization logic simple. "Sub-20 5k" /
"qualificar-me para Boston" are pro-tier concerns
(`ATHLETE_PRO_BASELINE.md`).

**Target date.** Optional. If provided, must be ≥ 4 weeks
out for 5k, ≥ 8 weeks for 10k, ≥ 16 weeks for half,
≥ 20 weeks for marathon. Shorter windows show a warning
"prazo apertado — plano agressivo" but are allowed
(adults, informed consent).

**Schema.**

```sql
alter table public.profiles
  add column athlete_goal text check (athlete_goal in
    ('general_health','run_5k','run_10k',
     'run_half_marathon','run_marathon')),
  add column athlete_goal_target_date date;

create index profile_goal on public.profiles (athlete_goal)
  where athlete_goal is not null;
```

Column is nullable so the existing unboarded users aren't
forced to backfill; the next app open prompts a
"completa seu perfil em 30s" card.

**Plan generator consumption.** `generate-fit-workout`
reads `athlete_goal`:

- `general_health` → 3× easy runs + 1× walk per week,
  volume cap 25 km/wk unless user overrides.
- `run_5k` → 3–4× runs, one interval, one long
  run ≤ 7 km at steady pace.
- `run_10k` → 4× runs, one tempo, long run up to 12 km.
- `run_half_marathon` → 4–5× runs, tempo + intervals
  alternating, long run scaling to 18–22 km.
- `run_marathon` → 5× runs, long run scaling to 32 km
  over 16–20 wks.

The existing coach-prescribed plan (L09-12) overrides all
of this. Goal is only used when the user is self-guided.

**Analytics.** A product event fires on goal set / change:

```
product_event: athlete_goal_set
  goal: <one of 5>
  has_target_date: bool
  distance_experience_weeks: int
  source: 'onboarding' | 'settings'
```

Onboarding funnel: goal-set CTR is a KPI for this finding's
post-ship review.

**Out of scope v1.**

- Trail / ultra / vertical km goals. Niche personas;
  separate spec.
- Multi-goal athletes (marathon + 5k concurrent). Pro
  tier; the plan generator for amateur assumes one
  primary goal.

### 10. Healthy social comparison (L22-19)

**What.** The default feed is scoped to the athlete's
group + followed users + ability-bracket peers. A global
feed is opt-in, warned on entry, and remembered as a
choice per session.

**Why.** Amateurs joining the app mid-journey ("eu estava
animada por ter corrido 8 min/km") see a shared feed full
of 4 min/km runners and silently disengage. The
Instagram / Strava research on social comparison is
well-documented; the fix is scope, not content moderation.

**Scope layers (default on).**

```
feed_default = {
  group_members,           -- coaching_group_members for joined groups
  followed_users,          -- existing follows
  bracket_peers            -- see below
}
```

**Bracket matching.** Pace decile from the last 8 weeks
of the athlete's own runs. The feed includes users whose
pace decile is within ±1 of the viewer's. Deciles are
re-computed weekly:

```sql
create materialized view public.athlete_pace_decile as
select
  user_id,
  ntile(10) over (order by median_pace_secs_per_km) as decile,
  median_pace_secs_per_km
from (
  select user_id,
         percentile_cont(0.5) within group
           (order by moving_time_secs::float / distance_km)
           as median_pace_secs_per_km
  from public.sessions
  where started_at > now() - interval '56 days'
    and distance_km >= 2
    and recording_type in ('outdoor','treadmill')
  group by user_id
) t;

create unique index athlete_pace_decile_uid
  on public.athlete_pace_decile (user_id);
```

Refreshed by a weekly cron (Mondays 03:00 UTC).

**Feed query sketch.**

```sql
select p.*
from posts p
join athletes a on a.id = p.author_id
where
  -- group & followed
  (p.author_id in (select followed_id from follows where follower_id = $viewer))
  or (p.group_id in (select group_id from coaching_members
                      where user_id = $viewer))
  -- bracket peers
  or (
     a.decile between $viewer_decile - 1 and $viewer_decile + 1
     and p.visibility in ('public','followers_of_followers')
  );
```

**"Feed global" opt-in.** Settings → "Feed". Toggle with
a sheet:

> Ativar o Feed Global mostra corridas de todos os atletas
> — incluindo performances bem acima das suas. Útil se
> você curte comparar, desmotivante se você está no
> começo. Pode voltar a desligar a qualquer momento.

Opt-in persists in `athlete_settings.feed_scope` (`home`,
`global`), defaults to `home`.

**Leaderboard posture.** Leaderboards (L21-16 races,
championships) are **not** scoped by bracket — they show
everyone. The finding is about the *default feed*, not
competitive surfaces. Opt-in not required because users
browsing a 10k leaderboard already expect to see fast
runners (self-selection into the surface).

**Copy nudges.** On amateur onboarding (L22-18) we include:
"Seu feed começa com o seu grupo e pessoas de ritmo
parecido. Você pode ver todo mundo nas Configurações."
Sets the expectation up-front.

**Out of scope v1.**

- ML-ranked feed. Over-engineered for current scale.
- Block / mute based on pace differential. We don't want
  to hide specific users; we want to change the default
  surface.

### 11. D30/D90/D180/D365 retention hooks (L22-20)

**What.** `lifecycle-cron` emits a dedicated push + email
+ in-app card on the athlete's D30, D90, D180, D365
anniversary of signup. Each delivers a "wrapped-lite"
artifact scoped to the period.

**Why.** Our existing retention stack (streak, badges,
inactivity_nudge, streak_at_risk) covers the D0–D7
window well. D30+ is under-served; the absolute biggest
win in retention research (Sean Ellis, Reforge, Strava
internal) is celebrating milestones the user wouldn't
have noticed.

**Delivery matrix.**

| Day | Artifact                         | Channels        |
|-----|----------------------------------|-----------------|
| D30 | "Seu primeiro mês" 1-pager       | push + in-app   |
| D90 | "Trimestre no ar" 1-pager        | push + in-app   |
| D180| "Meio ano!" + PDF wrapped (L22-15)| push + email + in-app |
| D365| "1 ano!" + PDF wrapped + badge   | push + email + in-app |

**Cron expansion.** `lifecycle-cron` already runs every
5 minutes. We add one phase (after phase 8 — streak at
risk):

```
# ── 9. Retention milestones (once per user lifetime) ──
for target_day in [30, 90, 180, 365]:
  for user in select user_id, created_at from auth.users
              where date_trunc('day', created_at + interval target_day 'day')
                    = date_trunc('day', now())
                and not exists (select 1 from retention_hooks_sent
                                where user_id = u.user_id
                                  and milestone_day = target_day):
    call notify-rules(rule='retention_milestone',
                      user_id=u.user_id,
                      milestone_day=target_day)
    insert retention_hooks_sent (user_id, milestone_day)
```

**Idempotency table.**

```sql
create table public.retention_hooks_sent (
  user_id uuid not null references auth.users(id),
  milestone_day int not null check (milestone_day in (30,90,180,365)),
  sent_at timestamptz not null default now(),
  primary key (user_id, milestone_day)
);
```

**notify-rules rule.** `retention_milestone` renders a
`wrapped-lite`:

```
{
  title: "Seu primeiro mês!",
  subtitle: "42 km · 8 corridas · streak de 5 dias",
  cta: "Ver detalhes",
  deep_link: "/(athlete)/wrapped?period=since_signup"
}
```

The deep link opens `wrapped_screen.dart` already in the
app (parameterized for the period since signup).

**Quiet hours.** Respect existing notification settings.
If user has push off, we fall back to in-app card only
(no nag on email channel).

**D180 / D365 email.** These two only, because by D180 we
trust the user will still be active and won't flinch at
an email. A subject line pattern: "180 dias — parabéns,
[first_name]" / "1 ano de Omni, [first_name]".

**Measurement.** We track:

- Send rate per milestone (should be ~1:1 with signups
  180 days ago).
- Open / tap rate per milestone.
- D+7 retention post-milestone (did the hook lift
  activity?).

**Out of scope v1.**

- D7 retention hooks. Already covered by streak /
  streak_at_risk (overlap would spam).
- Milestone-specific rewards (OmniCoins, badges) beyond
  the D365 badge. Growth can iterate.
- A/B variants of copy. Launch one tone; iterate.

## What we DO NOT do

- **Calorie tracking**: tried by 5 fitness apps and 4 of them
  abandoned. Out of scope; partner integration if user demand
  spikes.
- **Group walking challenges**: real product but huge surface;
  separate finding if it comes up.
- **In-app exercise videos**: licensing nightmare; partner
  integration if needed.
- **ML-ranked feed / ML injury triage**: precision floor is
  too high for us; both would leak health claims. Wave 6+
  conversation if at all.
- **Medical device classification**: we stay firmly in the
  general-wellness lane. Injury triage + weather hints are
  triage/UX, not diagnosis.

## Implementation phases

Wave 4 already had 5 phases (W4-G…K, sections 1–5).
K12 adds 6 new phases spread across Wave 4 and Wave 5:

### Wave 4 (continuation — K11 phases already defined)

1. **W4-G** Streaks: schema, cron, UI badge. (L22-12)
2. **W4-H** Treadmill mode: recording flag, anti-cheat
   carve-out, UI toggle. (L22-11)
3. **W4-I** Active recovery suggestion. (L22-14)
4. **W4-J** Apple Watch / Wear OS thin companion. (L22-10)
5. **W4-K** Cycle tracking (last — LGPD review). (L22-13)

### Wave 4 — K12 additions (product-feature batch)

6. **W4-L** Onboarding goal step (L22-18): small migration
   + onboarding screen + plan-generator hook. Cheap, high
   leverage; first to ship of K12.
7. **W4-M** Healthy social comparison (L22-19): decile
   materialized view + feed query change +
   `athlete_settings.feed_scope`. Depends on
   `athlete_pace_decile` cron — owned by data platform.
8. **W4-N** D30/D90/D180/D365 retention hooks (L22-20):
   new `lifecycle-cron` phase + `retention_hooks_sent`
   idempotency table + `notify-rules` template. Smallest
   infra footprint; ship alongside W4-L.

### Wave 5 — K12 (heavier features)

9. **W5-A** Home weather widget (L22-17): requires
   OpenWeatherMap contract + `weather-cache-cron` +
   home-city geocoding. Partner dependency shifts it
   out of Wave 4.
10. **W5-B** Monthly Wrapped PDF (L22-15): new edge/serverless
    runtime (`@react-pdf`) + `user-wrapped-pdf` bucket.
    Ship after the weather widget so the template has
    one more "real" output to amortize.
11. **W5-C** In-app injury triage (L22-16): legal review of
    copy + `injury_professionals` curated directory seed
    + hard-delete integration. Heaviest compliance load
    — ships last.

Cycle tracking (W4-K) remains the LGPD-hairiest; injury
triage (W5-C) is the heaviest compliance load of the K12
batch. Both ship at the end of their respective waves.

## See also

- `docs/product/ATHLETE_PRO_BASELINE.md` (sibling)
- `docs/product/COACH_BASELINE.md` (K12 sibling, treinador
  persona)
- `docs/product/RECOVERY_SLEEP_TRACKING.md` (L21-13)
- `docs/policies/HEALTH_DATA_CONSENT.md` (L04-04)
- `docs/runbooks/MOBILE_OFFLINE_SESSION_BACKUP.md` (L05-19)
