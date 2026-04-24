# Athlete-Pro Persona Baseline

**Status:** Ratified (2026-04-21), implementation Wave 4
**Owner:** product + mobile + backend
**Related:** L21-15 (weather), L21-16 (race results),
L21-17 (sponsor disclosure), L21-18 (HR-BLE drop),
L21-19 (post-run nutrition), L21-20 (privacy mode),
L21-12 (training load), L21-13 (recovery),
L21-14 (race predictor).

## Question being answered

> "What does the elite / sponsored / competitive athlete need
> from us that the amateur doesn't? Today they're using us as
> a glorified Strava — losing them when they upgrade to
> Garmin / TrainingPeaks."

## Decision

A **single persona-pro module** (`omni_runner/lib/features/
pro/`) that gates 6 features behind a `pro_features_enabled`
profile flag (free for now; future paid tier). Each feature
is small in isolation, but together they make the "I'm
training for a race" workflow first-class.

## The 6 features

### 1. Weather enrichment per session (L21-15)

**What.** Each session row gets `weather jsonb` post-
populated from OpenWeather One Call 3.0 (historical) using
the session's start coordinates and start timestamp.

**Schema.**

```sql
alter table public.sessions add column weather jsonb;
-- shape: {
--   "temp_c": 24.3,
--   "feels_like_c": 26.1,
--   "humidity_pct": 78,
--   "wind_kph": 8,
--   "pressure_hpa": 1015,
--   "condition": "clear",
--   "source": "openweather_onecall_v3",
--   "fetched_at": "..."
-- }
```

**Backfill.** Cron `enrich-weather` runs every 4 h, picks up
sessions older than 30 minutes (so wind/temp have settled in
the API) without `weather` set, max 1000/run, batched 100/min
to fit OpenWeather's free-tier ratelimit (1k req/day).

**Cost guardrail.** If `cron_metrics.openweather_calls_today
> 900` we skip remaining sessions and re-queue. Switches to
free `Open-Meteo` archive API as fallback (no key, no
ratelimit, lower precision).

**Why post-process and not at session-end.** Session-end
network can be flaky (post-trail run), and we don't want to
block save on a third-party call.

### 2. Official race results table (L21-16)

**What.** First-class table separate from `sessions`. The
race_result row is **owned by the athlete** but can be
verified by linking to a known event, and bib/chip-time
become first-class fields.

**Schema.**

```sql
create table public.race_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  event_name text not null,
  event_id uuid references public.events(id),  -- optional FK to known events
  date date not null,
  distance_m int not null,
  chip_time_s int not null,
  gun_time_s int,
  bib text,
  category text,                       -- 'M40', 'F30', etc.
  place_overall int,
  place_category int,
  source text not null check (source in ('manual','imported_csv','event_partner')),
  verified boolean not null default false,
  session_id uuid references public.sessions(id),  -- optional link if recorded
  created_at timestamptz not null default now()
);

create index race_results_user_date_idx
  on public.race_results (user_id, date desc);
```

RLS: `user_id = auth.uid()`. Coaches read via existing share
toggle. Public profile (opt-in) shows verified results only.

**Verification path (Wave 5).** When `event_id` is set and an
event-partner integration confirms the bib + chip time match
(via official results CSV import), `verified` flips to true.
v1 ships with `verified=false` for all manual entries.

**Race Predictor seed (L21-14).** Race predictor preferently
uses `race_results.chip_time_s` over `sessions` when
`verified=true OR source='manual' AND date < now()`.

### 3. Sponsorship disclosure auto-tag (L21-17)

**What.** Atletas patrocinados marcam **uma vez** suas marcas
ativas; o portal/mobile auto-marca posts e race-results como
"#Patrocinado" quando publicados em surfaces sociais.

**Schema.**

```sql
create table public.sponsorships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  brand_name text not null,
  start_date date not null,
  end_date date,
  category text check (category in ('shoe','apparel','nutrition','watch','other')),
  disclosure_required boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, brand_name, start_date)
);
```

**UI.** Em compose-post / share-race-result, se houver
sponsor ativo (`end_date is null OR end_date >= today`) E
`disclosure_required=true`, checkbox "Post patrocinado" vem
**marcado por padrão**. O atleta pode desmarcar (e a ação é
auditada em `audit_logs` com motivo opcional).

**Tag publicado.** Posts marcados aparecem com badge
"Patrocinado" e, no fim do texto, sufixo automático
"Conteúdo patrocinado por <brand>." (Brasil: Lei 13.146 + CONAR;
EUA: FTC 16 CFR Part 255).

**Por que opt-in para desmarcar.** Default seguro: a violação
de disclosure é assimétrica — o downside legal é alto, o
custo de uma marcação a mais é zero.

### 4. Dual heart-rate source with visible recovery (L21-18)

**What.** O recording aceita até 2 sensores BLE de HR
simultaneamente (chest + optical wrist). Prioriza chest;
fallback automático para optical se chest cair > 5 s sem
amostra; UI mostra qual está ativa em tempo real.

**Implementation.** `omni_runner/lib/core/ble/dual_hr_source.dart`
(novo) wraps `ble_reconnect_manager.dart` (existente):

```dart
class DualHrSource {
  final BleHrSource? chest;
  final BleHrSource? optical;
  HrSampleSource activeSource = HrSampleSource.chest;

  Stream<HrSample> stream() async* {
    int chestStaleSinceMs = 0;
    await for (final tick in _tickStream(period: Duration(seconds: 1))) {
      final chestSample = await chest?.latest();
      if (chestSample != null &&
          tick.differenceMs(chestSample.recordedAt) < 5000) {
        activeSource = HrSampleSource.chest;
        yield chestSample;
      } else if (optical != null) {
        if (activeSource == HrSampleSource.chest) {
          // First fallback: emit a marker the UI can show.
          activeSource = HrSampleSource.optical;
        }
        final opticalSample = await optical!.latest();
        if (opticalSample != null) yield opticalSample;
      }
    }
  }
}
```

**UI.** Recording screen mostra ícone-pílula:
- ●●  Chest + Optical OK
- ●○  Chest OK (optical desconectado)
- ○●  Fallback: usando optical (chest caiu)
- ○○  Sem HR — banner em laranja "Sem HRM"

**Persistência.** Cada amostra HR carrega `source` enum no
buffer local; ao subir, `session_hr_samples` ganha coluna
`source text`. Garante que a análise pós (zonas, drift) saiba
distinguir.

### 5. Post-run nutrition log (L21-19)

**What.** Notification push 20 min depois de uma sessão
"long-run" (definição abaixo) abre uma tela de log de
refeição rápido.

**Definição "long-run".** Sessão satisfaz **TODAS**:

- `distance_m >= 12_000`
- `duration_s >= 60 * 60` (≥ 1h)
- `workout_type in ('long_run', 'race')` OU heuristic (volume
  > 1.3 × user 7-day average)

**UI.** Notification → tela com 5 chips ("café da manhã",
"shake de proteína", "frutas", "comida normal", "ainda não").
Sem foto/macro detalhe v1 — friction kills logging.

**Persistência.**

```sql
create table public.post_run_nutrition_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  session_id uuid not null references public.sessions(id),
  consumed_at timestamptz not null,
  category text not null,
  ate_within_carb_window boolean,
  created_at timestamptz not null default now(),
  unique (session_id)
);
```

`ate_within_carb_window` = true se `consumed_at - session.ended_at <= 60 min`.

**Nudge respect.** Se o user já logou via Apple Health /
HealthConnect, suprimimos o push (consumimos o weeklysync de
recovery em L21-13). Se opt-out global, desliga.

**Por que não macros.** Macro-tracking é um app inteiro
(MyFitnessPal). Aqui só queremos o sinal "comeu × não comeu"
para dar contexto ao coach e gerar gráfico de adherence.

### 6. Privacy / Competition mode (L21-20)

**What.** Antes de iniciar uma sessão (ou após), o atleta
pode marcar:

- **Public** (default) — flui para feed quando publicar.
- **Private** — nunca aparece em feed nem em achievements
  públicos. Visível só para coach se share-with-coach=true.
- **Competition** — privado por X horas pós-evento, depois
  promove a Public automaticamente.

**Schema.**

```sql
alter table public.sessions add column privacy_mode text
  not null default 'public'
  check (privacy_mode in ('public','private','competition'));

alter table public.sessions add column promote_to_public_at timestamptz;
```

Cron `promote-competition-sessions` (a cada 15 min) seta
`privacy_mode='public'` quando `promote_to_public_at < now()`.

**UI.** Tela de start-recording tem segmented-control 3-way.
Edit pós-fato disponível em session detail. **NÃO existe
"competition mode" para usuários gratuitos** (gating de
tier-pro).

**Feed RLS.** Filtro existente do feed (`social_posts.session_id`)
adiciona predicado `EXISTS (sessions WHERE id = session_id
AND privacy_mode = 'public')`.

## What we DO NOT do

- **Live racing telemetry / lap split UI**: scope-creep, requer
  re-arquitetar recording para >= 10Hz GPS sampling. Diferido.
- **Coach-to-coach race feedback**: requer chat, está em outro
  finding.
- **Sponsorship contract management** (revenue share / brand
  payouts): só metadata para disclosure; payment lives em
  outros sistemas.

## Implementation phases (Wave 4)

1. **W4-A**: Schema + RLS + cron `enrich-weather`. Backfill
   últimos 90 dias de sessões em background.
2. **W4-B**: Race results CRUD UI (mobile + portal); seed do
   race-predictor.
3. **W4-C**: Sponsorships CRUD + disclosure auto-tag em
   compose-post.
4. **W4-D**: Dual-HR source com UI status. (Mobile only.)
5. **W4-E**: Post-run nutrition push + log screen.
6. **W4-F**: Privacy/competition mode + cron de promoção.

Cada fase é shippable independente. Nenhuma exige o mesmo PR
que a anterior.

## See also

- `docs/product/RACE_PREDICTOR.md` (L21-14)
- `docs/product/RECOVERY_SLEEP_TRACKING.md` (L21-13)
- `docs/policies/HEALTH_DATA_CONSENT.md` (L04-04)
- `docs/policies/SOCIAL_MODERATION_POLICY.md` (L05-14)
