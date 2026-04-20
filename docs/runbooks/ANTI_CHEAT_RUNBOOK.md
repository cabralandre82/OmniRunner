# Anti-cheat thresholds — runbook

> **Findings principais:** L21-01 (`MAX_SPEED_MS` invalidava velocistas elite) + L21-02 (`MAX_HR_BPM = 220` ignorava atletas jovens com HR medido).
> **Severidade base:** P3 (curadoria); P2 se atleta verificado for re-flag em onda.
> **Tempo alvo:** triagem < 4 h, mitigação < 24 h, política revista < 7 dias.

## Quando este runbook se aplica

1. Atleta legítimo (medalhista, elite club, sub-11 100 m, etc.) reporta
   que sessões verificadas viraram `is_verified=false` com flag
   `SPEED_IMPOSSIBLE` ou `IMPLAUSIBLE_HR_HIGH`.
2. Onboarding novo — assessor / admin precisa cadastrar atleta de elite
   sem histórico de sessões (default seria `beginner`, threshold 12,5 m/s).
3. Suporte percebeu spike em `IMPLAUSIBLE_HR_HIGH` numa coorte (jovens,
   atletas em VO2max, chest-strap recém-adquirido) e quer subir o teto
   global por bracket — **NÃO faça isso** sem revisar este runbook.
4. Você precisa **adicionar uma nova categoria/threshold** ao pipeline
   (ex.: cap específico para `cycling_only` ou `triathlon_run`).
5. Auditoria pediu para revisar policy de retenção dos dados HR
   (`measured_max_hr_bpm` / `measured_max_hr_at`) — ver §5.

## 1. Arquitetura (após L21-01/02)

```
┌──────────────────────────────────────────────────────────────┐
│ Edge Function (verify-session OR strava-webhook)             │
│   1. requireUser → user.id                                   │
│   2. loadAntiCheatThresholds(db, user.id)                    │
│       └─ db.rpc('fn_get_anti_cheat_thresholds', { p_user_id })│
│   3. runAntiCheatPipeline(input, thresholds)                 │
│   4. persist sessions.{is_verified, integrity_flags}         │
└──────────────────────────────────────────────────────────────┘
                           │ supabase-js (service_role)
                           ▼
┌──────────────────────────────────────────────────────────────┐
│ Postgres                                                     │
│   public.profiles                                            │
│     • birth_date              DATE  (opt-in)                 │
│     • measured_max_hr_bpm     SMALLINT [120,250]             │
│     • measured_max_hr_at      TIMESTAMPTZ                    │
│     • skill_bracket_override  TEXT                           │
│   public.fn_compute_skill_bracket(uuid) → TEXT               │
│     (média de pace dos últimos 10 sessions verificadas)      │
│   public.fn_get_anti_cheat_thresholds(uuid) → SETOF          │
│     (resolve override → computed → 'beginner' default,       │
│      aplica Tanaka floor + measured-HR floor, clamp 250)     │
└──────────────────────────────────────────────────────────────┘
```

Ambas as constantes da pipeline estão duplicadas em
`supabase/functions/_shared/anti_cheat.ts` (`getThresholdsForBracket`)
e `public.fn_get_anti_cheat_thresholds` — a paridade é coberta pelo
runner `tools/test_l21_01_02_anti_cheat_profile.ts` (cross-platform
parity test). **Mexeu num lado, mexa no outro e rode o runner.**

## 2. Threshold ladder

| Bracket        | `max_speed_ms` | `teleport_speed_ms` | `min_hr_running_bpm` | `max_hr_bpm` (base) |
|----------------|---------------:|--------------------:|---------------------:|---------------------:|
| `beginner`     | 12,5 m/s       | 50,0 m/s            | 80                   | 220                  |
| `intermediate` | 12,5 m/s       | 50,0 m/s            | 75                   | 220                  |
| `advanced`     | 13,5 m/s       | 55,0 m/s            | 70                   | 225                  |
| `elite`        | 15,0 m/s       | 60,0 m/s            | 60                   | 230                  |

`max_hr_bpm` final = `MAX(base, tanaka_floor, measured_floor)` clamped
para `[185, 250]`, onde:

* `tanaka_floor = 225 - age_years` (somente se `birth_date` setado e
  age ∈ [10, 90]).
* `measured_floor = measured_max_hr_bpm + 5`, somente se
  `measured_max_hr_at >= now() - interval '6 months'`.

Resolução de bracket:

1. `profiles.skill_bracket_override` (escape hatch admin/onboarding)
2. `fn_compute_skill_bracket(user_id)` — média de pace de até 10
   sessões verificadas com distância ≥ 1 km.
3. Default `'beginner'` (sem sessões e sem override).

A coluna `source` do retorno documenta a derivação para forense:

```
override                                  ← admin pinou bracket
computed,measured_max_hr=224              ← bracket veio de pace + chest strap
computed,tanaka_floor=210,measured_max_hr=234  ← ambos os floors lifted
default                                   ← edge case — sem profiles e sem sessions
```

Sentry tag sugerida: `anti_cheat.threshold_source` ← `result.source`.

## 3. Procedimentos

### 3.1 Atleta elite reporta `SPEED_IMPOSSIBLE` em sprint legítimo

1. **Triagem** (≤ 30 min): pegar `session_id` e checar
   `integrity_flags`, `total_distance_m`, `duration_ms` em
   `public.sessions`.
2. **Confirmação rápida**: rodar
   ```sql
   SELECT * FROM public.fn_get_anti_cheat_thresholds('<user_id>');
   ```
   * Se `skill_bracket = 'beginner'` ou `'intermediate'` mas o atleta é
     elite (linkar evidência: clube, federação, ranking), prosseguir para 3.2.
   * Se `skill_bracket = 'elite'` mas pico ainda > 15 m/s (ex.: ciclista
     pego no GPS de corrida), abrir incidente em `CUSTODY_INCIDENT_RUNBOOK.md`.
3. **Restaurar verificação** (até 2 h): backfill conservador via
   ```sql
   UPDATE public.sessions
      SET is_verified    = true,
          integrity_flags = ARRAY(SELECT unnest(integrity_flags)
                                  EXCEPT SELECT unnest(ARRAY['SPEED_IMPOSSIBLE']))
    WHERE id = '<session_id>'
      AND user_id = '<user_id>';
   ```
4. **Política**: setar override para o atleta — ver 3.2.

### 3.2 Setar `skill_bracket_override` para atleta novo

```sql
UPDATE public.profiles
   SET skill_bracket_override = 'elite' -- ou 'advanced'
 WHERE id = '<user_id>';
```

* **Quem pode**: assessor `assessoria_owner`, admin platform.
* **Quando expirar**: nunca automaticamente — o registro vira a fonte
  da verdade até alguém remover. Para **revogar** durante uma
  investigação: `SET skill_bracket_override = NULL` reverterá ao
  resultado de `fn_compute_skill_bracket()`.
* **Logging**: a coluna não tem trigger de auditoria nesta primeira
  passada. Se você esperava ver no `audit_log`, abra ticket
  `tracking#anti_cheat_override_audit_log`.

### 3.3 Cadastrar `measured_max_hr_bpm` (chest-strap)

```sql
UPDATE public.profiles
   SET measured_max_hr_bpm = 224, -- valor REAL do strap; CHECK [120,250]
       measured_max_hr_at  = now()
 WHERE id = '<user_id>';
```

* **Quem pode**: o próprio usuário (via app/portal — `update_own`
  policy já existente em `profiles`), ou platform admin.
* **Validade**: 6 meses. Após isso o valor é ignorado e o teto cai
  para o ladder do bracket. O usuário pode re-medir e reenviar.
* **Por que +5 BPM de headroom**: chest-straps têm ruído típico de
  2–3 BPM em pico. O margin protege contra 1-frame spike.

### 3.4 Adicionar nova categoria de threshold (ex.: cycling)

1. Crie nova coluna em `profiles` (ex.: `discipline TEXT NOT NULL DEFAULT 'running'`).
2. Adicione novo `CASE` em `fn_get_anti_cheat_thresholds` retornando
   ladder específico (cycling permite `max_speed_ms` ~ 25 m/s).
3. Espelhe o ladder em `getThresholdsForBracket()` (TS).
4. Atualize parity test em `tools/test_l21_01_02_anti_cheat_profile.ts`.
5. Atualize esta tabela na seção 2.
6. Rode:
   ```bash
   deno test --no-check supabase/functions/_shared/anti_cheat.test.ts
   NODE_PATH=portal/node_modules npx tsx tools/test_l21_01_02_anti_cheat_profile.ts
   ```

### 3.5 Migrar coorte para um bracket diferente em massa

```sql
UPDATE public.profiles p
   SET skill_bracket_override = 'advanced'
  FROM (
    SELECT user_id
      FROM public.sessions
     WHERE is_verified = true
       AND total_distance_m >= 5000
       AND created_at > now() - interval '90 days'
     GROUP BY user_id
    HAVING AVG((duration_ms / 1000.0) / (total_distance_m / 1000.0)) < 270
  ) AS fast_runners
 WHERE p.id = fast_runners.user_id
   AND p.skill_bracket_override IS NULL;
```

## 4. Flags de integridade afetadas pelo ladder

| Flag                  | Threshold lido          | Mudança vs. pré-L21        |
|-----------------------|-------------------------|----------------------------|
| `SPEED_IMPOSSIBLE`    | `max_speed_ms`          | Variável por bracket       |
| `TELEPORT`            | `teleport_speed_ms`     | Variável por bracket       |
| `IMPLAUSIBLE_HR_HIGH` | `max_hr_bpm`            | Lift por measured + Tanaka |
| `IMPLAUSIBLE_HR_LOW`  | `min_hr_running_bpm`    | Variável por bracket       |
| `GPS_JUMP`            | `gps_jump_threshold_m`  | Inalterado (500 m)         |
| `BACKGROUND_GPS_GAP`  | `gps_gap_threshold_ms`  | Inalterado (60 s)          |
| `NO_MOTION_PATTERN`   | `motion_radius_m`       | Inalterado (150 m)         |
| `IMPLAUSIBLE_PACE`    | `max_pace_sec_km`       | Inalterado (90 s/km)       |

Os thresholds inalterados são da pipeline central — ainda variáveis
via `AntiCheatThresholds`, mas o RPC só sobrescreve speed/HR. Para
ajustar os outros, monte o objeto manualmente antes de chamar
`runAntiCheatPipeline(input, customThresholds)`.

## 5. Privacy / LGPD

* `birth_date`, `measured_max_hr_bpm`, `measured_max_hr_at` são
  considerados **dados de saúde sensíveis** (Lei 13.709/18 art. 5º
  inciso II). Acompanhar policy em
  `20260417230000_sensitive_health_data_protection.sql`.
* Retenção: as três colunas são apagadas via cascata quando o usuário
  invoca o fluxo de `account_deletion` (ver `ACCOUNT_DELETION_RUNBOOK.md`).
* Acesso: hoje a `profiles` tem RLS `update_own`. Coach/assessor não
  vê os campos novos a menos que o time de produto explicitamente
  exponha. **Não adicione SELECT amplo** sem revisar a matriz de
  consent em `sensitive_health_data_protection`.

## 6. Como rodar o cross-platform parity test

```bash
# 1. SQL changes
docker exec -i supabase_db_omni_runner psql -U postgres \
  < supabase/migrations/20260421110000_l21_athlete_anti_cheat_profile.sql

# 2. Sandboxed integration test (PG)
NODE_PATH=portal/node_modules npx tsx tools/test_l21_01_02_anti_cheat_profile.ts

# 3. Pure-TS unit suite (Deno)
cd supabase
deno test --no-check --allow-net --allow-env \
  functions/_shared/anti_cheat.test.ts
```

Resultado esperado: `18 passed` (PG) e `23 passed` (Deno).

## 7. Quando NÃO mexer nos thresholds

* **Cluster suspeito de fraude** (vários atletas com mesma seed UUID,
  mesmo IP, mesmas coordenadas iniciais) — abrir
  `CUSTODY_INCIDENT_RUNBOOK.md`, NÃO subir threshold.
* **Strava import** com chest-strap zerado por bug do device — o
  `IMPLAUSIBLE_HR_LOW` está fazendo o trabalho dele, peça troca de
  dispositivo ao usuário.
* **Solicitação de "remova essa flag" sem evidência objetiva** —
  recuse e peça (a) link de ranking, (b) fotograma do device com pico
  de pace ou (c) histórico de chest-strap. Threshold só sobe com data,
  não com pedido.

## 8. Histórico

| Data       | Quem    | O quê                                                           |
|------------|---------|-----------------------------------------------------------------|
| 2026-04-21 | Eng-Sec | L21-01 + L21-02 — thresholds passam a ser por bracket + override + measured/Tanaka floor |
