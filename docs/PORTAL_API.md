# Portal API Reference

Base URL: `https://portal.omnirunner.app/api`

All endpoints (except `/health` and `/auth/callback`) require authentication via Supabase session cookie. Most POST endpoints also check caller role via `coaching_members` table.

---

## Authentication

### `GET /api/auth/callback`

OAuth callback handler for Supabase Auth. Exchanges auth code for session.

| Param | Type | Source |
|-------|------|--------|
| `code` | string | query |

**Response:** Redirect to `/dashboard` or `/login` on error.

---

## Health

### `GET /api/health`

Public uptime-probe endpoint. No authentication required.

By design the response is intentionally opaque — it exposes ONLY a
boolean health signal so the endpoint cannot be used for operational
reconnaissance (L06-02, L01-07). External uptime probes read the
HTTP status code (200 vs 503) as their primary signal and the
`status` string for human-readable classification.

**Response shape (ONLY these two keys, always):**
```json
{ "status": "ok" | "degraded" | "down", "ts": 1709136000000 }
```

- `200` when all server-side checks pass (`status: "ok"`).
- `503` when any check fails. `status: "degraded"` when DB is up but
  invariants are violated, `status: "down"` when DB is unreachable.

No `checks` object, no `latencyMs`, no invariant counts — those are
served from `/api/platform/health` (below) behind authentication.

### `GET /api/platform/health`

Detailed health snapshot for platform admins. Returns the check
breakdown + total invariant violation count.

**Auth:** platform_admins membership required.

**Response:**
```json
{
  "ok": true,
  "status": "ok" | "degraded" | "down",
  "ts": 1709136000000,
  "latency_ms": 42,
  "checks": {
    "db": "connected" | "unreachable",
    "invariants": "healthy" | "violations"
  },
  "invariant_count": 0,
  "request_id": "uuid",
  "checked_at": "2026-04-21T12:34:56.000Z"
}
```

Errors return `{ ok: false, error: { code, message, request_id } }`
with `UNAUTHORIZED` (401/403) or standard HTTP 5xx for probe failures.

For per-row violation detail (custody + wallet-ledger drift) use
[`GET /api/platform/invariants`](#get-apiplatforminvariants) instead.

---

## Branding

### `GET /api/branding`

Returns portal branding settings for the active group.

**Auth:** Session cookie + `portal_group_id` cookie.

**Response:**
```json
{
  "logo_url": "https://...",
  "primary_color": "#2563eb",
  "sidebar_bg": "#ffffff",
  "sidebar_text": "#111827",
  "accent_color": "#2563eb"
}
```

### `POST /api/branding`

Updates branding settings. Validated with `brandingSchema` (Zod).

**Auth:** `admin_master` role required.

**Body:**
```json
{
  "logo_url": "https://..." | null,
  "primary_color": "#RRGGBB",
  "sidebar_bg": "#RRGGBB",
  "sidebar_text": "#RRGGBB",
  "accent_color": "#RRGGBB"
}
```

All fields optional. Colors must be hex `#RRGGBB`. `logo_url` max 512 chars.

**Response:** `{ "ok": true }` or `{ "error": "..." }`

---

## Credits & Coins

### `POST /api/distribute-coins`

Distributes coins from group inventory to a single athlete's wallet.

**Auth:** `admin_master` role required. Rate limited: 20 req/min.

**Body (Zod: `distributeCoinsSchema`):**
```json
{
  "athlete_user_id": "uuid",
  "amount": 50
}
```

- `amount`: integer 1–100 000 (L05-03 — raised from the legacy 1 000 cap to
  fit weekly bonus distributions for medium clubs without artificial chunking)
- `athlete_user_id`: must be UUID, must be `athlete` in the group

**Flow (atomic, L02-01):** all four mutations run inside a single SQL
transaction via `emit_coins_atomic`:
1. Claim idempotency slot in `coin_ledger_idempotency`
2. Insert ledger row with the reserved `ledger_id`
3. Commit coins against custódia USD (`custody_commit_coins`)
4. Decrement group token inventory (`decrement_token_inventory`)
5. Credit athlete wallet (`increment_wallet_balance`)

Any failure rolls back the whole transaction. Idempotent retries via
`x-idempotency-key` (or generated `ref_id`) replay the same response
without mutating state.

**Response:**
```json
{ "ok": true, "athlete_user_id": "...", "amount": 50, "athlete_name": "João",
  "idempotent": false, "new_balance": 150 }
```

### `POST /api/distribute-coins/batch` (L05-03)

Distributes coins to **up to 200 athletes in a single SQL transaction**.
Replaces the client-side pattern of N sequential calls to
`/api/distribute-coins`, which multiplied the atomicity risk already
addressed by L02-01 and degraded UX for clubs with 200+ atletas.

**Auth:** `admin_master` role required. Rate limited: 5 req/min/group
(tighter than the single-athlete endpoint — each call may move up to
200 atletas at once).

**Body (Zod: `distributeCoinsBatchSchema`):**
```json
{
  "items": [
    { "athlete_user_id": "uuid-1", "amount": 50 },
    { "athlete_user_id": "uuid-2", "amount": 75 }
  ],
  "ref_id": "weekly-bonus-2026-w17"
}
```

| Field | Constraint |
|-------|------------|
| `items.length` | 1 – 200 |
| `items[i].amount` | integer 1 – 100 000 |
| Σ `items[i].amount` | ≤ 1 000 000 per batch |
| `items[i].athlete_user_id` | unique within the batch (no duplicates) |
| `ref_id` | optional, 8 – 128 chars; defaults to `x-idempotency-key` or a derived `portal_batch_<actor>_<ts>` |

**Atomicity:** the whole batch is a single transaction in
`distribute_coins_batch_atomic`. If ANY item fails (`CUSTODY_FAILED`,
`INVENTORY_INSUFFICIENT`, `INVALID_ITEM`), zero athletes are credited.

**Idempotency:** each item gets a deterministic `ref_id = <batch_ref>__<idx>`,
so replaying the same batch (same `ref_id`) returns the existing balances
without mutating anything (`batch_was_idempotent: true`). Mixing new + replayed
items in a single call is allowed and the audit log only records the new
distributions.

**Response (200):**
```json
{
  "ok": true,
  "batch_ref_id": "weekly-bonus-2026-w17",
  "total_amount": 125,
  "total_distributions": 2,
  "batch_was_idempotent": false,
  "items": [
    { "athlete_user_id": "uuid-1", "amount": 50, "new_balance": 200,
      "was_idempotent": false, "ledger_id": "..." },
    { "athlete_user_id": "uuid-2", "amount": 75, "new_balance": 275,
      "was_idempotent": false, "ledger_id": "..." }
  ]
}
```

**Common error codes:**
- `403 FORBIDDEN` — caller is not `admin_master` of the group
- `400 VALIDATION_FAILED` — payload violated Zod / RPC sanity caps
- `422 CUSTODY_FAILED` — lastro USD insuficiente para o lote inteiro
- `422 INVENTORY_INSUFFICIENT` — inventário insuficiente para o lote inteiro
- `503 LOCK_NOT_AVAILABLE` (`Retry-After: 2`) — lock contention; retry
- `503 SERVICE_UNAVAILABLE` — invariants check failed
- `503 FEATURE_DISABLED` — `distribute_coins.enabled` kill switch off

### `POST /api/coins/reverse` (L03-13)

Canonical reembolso/estorno endpoint for the three financial flows
covered by atomic RPCs in
`supabase/migrations/20260421130000_l03_reverse_coin_flows.sql`:

| `kind`      | Inverts                    | Primary failure modes                                        |
|-------------|----------------------------|--------------------------------------------------------------|
| `emission`  | `emit_coins_atomic`        | `INSUFFICIENT_BALANCE` (atleta já gastou)                    |
| `burn`      | `execute_burn_atomic`      | `NOT_REVERSIBLE` (settlement já settled inter-club)          |
| `deposit`   | `confirm_custody_deposit`  | `INVARIANT_VIOLATION` (refund quebraria lastro)              |

Replaces the manual SQL blocks in `CHARGEBACK_RUNBOOK §3.2` with a
transactional, idempotent, audited path.

**Auth:** `platform_role='admin'` ONLY — `admin_master` do grupo **não**
tem permissão. Rate limit: 10 req/min por actor. Kill switch:
`coins.reverse.enabled`. CSRF default-deny (L17-06).

**Body (Zod: `reverseCoinsSchema`, discriminated union):**

```json
// kind: emission
{
  "kind": "emission",
  "original_ledger_id": "uuid",
  "reason": "Chargeback Stripe CH_xxx. Postmortem #PR-4815.",
  "idempotency_key": "rev-emi-abc123"   // or x-idempotency-key header
}

// kind: burn
{
  "kind": "burn",
  "burn_ref_id": "<burn ref used in execute_burn_atomic>",
  "reason": "Bug UI redeem duplicou. Postmortem #PR-4890.",
  "idempotency_key": "rev-burn-abc123"
}

// kind: deposit
{
  "kind": "deposit",
  "deposit_id": "uuid",
  "reason": "Chargeback Stripe CH_yyy. Postmortem #PR-4815.",
  "idempotency_key": "rev-dep-abc123"
}
```

Validação: `reason` mínimo 10 chars, máximo 500 (postmortem
obrigatório). `idempotency_key` mínimo 8 chars (no body ou header
`x-idempotency-key`; um dos dois é obrigatório).

**Response (200, shape varia por `kind`):**

```json
// emission
{
  "ok": true,
  "kind": "emission",
  "reversal_id": "uuid",
  "reversal_ledger_id": "uuid",
  "athlete_user_id": "uuid",
  "reversed_amount": 100,
  "new_balance": 0,
  "was_idempotent": false
}

// burn
{
  "ok": true,
  "kind": "burn",
  "reversal_id": "uuid",
  "clearing_event_id": "uuid",
  "athlete_user_id": "uuid",
  "reversed_amount": 80,
  "new_balance": 80,
  "settlements_cancelled": 2,
  "was_idempotent": false
}

// deposit
{
  "ok": true,
  "kind": "deposit",
  "reversal_id": "uuid",
  "deposit_id": "uuid",
  "group_id": "uuid",
  "refunded_usd": "200.00",
  "was_idempotent": false
}
```

**Idempotency:** idempotency anchor é a tabela `coin_reversal_log` com
`UNIQUE (kind, idempotency_key)`. Replays retornam
`was_idempotent: true` sem re-aplicar a mutação. Se você usar o header
`x-idempotency-key`, o wrapper `withIdempotency` (L18-02) também
cacheia a resposta inteira.

**Common error codes:**
- `401 UNAUTHORIZED` — sem sessão.
- `403 FORBIDDEN` — caller não é `platform_admin`.
- `400 VALIDATION_FAILED` — payload Zod inválido, `idempotency_key`
  ausente ou reason < 10 chars.
- `404 NOT_FOUND` — `LEDGER_NOT_FOUND`, `BURN_NOT_FOUND` ou
  `DEPOSIT_NOT_FOUND`.
- `422 INSUFFICIENT_BALANCE` — atleta já gastou as coins; ir para
  `CHARGEBACK_RUNBOOK §3.3` (dívida do grupo).
- `422 NOT_REVERSIBLE` — burn com settlement `settled` inter-club;
  `REVERSE_COINS_RUNBOOK §5` (unwind manual).
- `422 INVARIANT_VIOLATION` — refund quebraria
  `deposited >= committed`; reverter emissões primeiro.
- `422 INVALID_TARGET_STATE` — alvo não está no estado reversível
  (reason ou status inválidos).
- `422 CUSTODY_RECOMMIT_FAILED` — lastro atual insuficiente para
  re-commitar custódia ao reverter burn.
- `503 LOCK_NOT_AVAILABLE` (`Retry-After: 2`) — lock contention.
- `503 SERVICE_UNAVAILABLE` — invariants health drift.
- `503 FEATURE_DISABLED` — `coins.reverse.enabled` kill switch off.

Runbook completo: `docs/runbooks/REVERSE_COINS_RUNBOOK.md`.

### `POST /api/checkout`

Creates a checkout session for purchasing credit packages.

**Auth:** Session required. Rate limited: 5 req/min.

**Body (Zod: `checkoutSchema`):**
```json
{
  "product_id": "prod_xxx",
  "gateway": "mercadopago" | "stripe"
}
```

`gateway` defaults to `"mercadopago"`. Calls the corresponding Supabase Edge Function.

**Response:**
```json
{ "checkout_url": "https://...", "purchase_id": "..." }
```

### `POST /api/billing-portal`

Opens the Stripe billing portal for subscription management.

**Auth:** Session required.

**Response:** Redirect URL to Stripe portal.

---

## Team Management

### `POST /api/team/invite`

Invites a user to the coaching group as staff.

**Auth:** `admin_master` role required. Rate limited: 10 req/min.

**Body (Zod: `teamInviteSchema`):**
```json
{
  "email": "user@example.com",
  "role": "coach" | "assistant"
}
```

**Flow:**
1. Looks up user by email (`fn_get_user_id_by_email` RPC)
2. Checks not already a member
3. Inserts into `coaching_members`
4. Audit log

**Errors:** 404 if user not found, 409 if already a member.

### `POST /api/team/remove`

Removes a staff member from the group.

**Auth:** `admin_master` role required. Rate limited: 10 req/min.

**Body (Zod: `teamRemoveSchema`):**
```json
{ "member_id": "membership-row-id" }
```

**Constraints:** Cannot remove self. Cannot remove another `admin_master`.

**Response:** `{ "ok": true }`

---

## Verification

### `POST /api/verification/evaluate`

Triggers the automated verification evaluation for an athlete.

**Auth:** `admin_master` or `coach` role required.

**Body (Zod: `verificationEvaluateSchema`):**
```json
{ "user_id": "athlete-uuid" }
```

Calls `eval_athlete_verification` RPC. Athlete must belong to the group.

**Response:** `{ "ok": true }`

---

## Gateway Preference

### `GET /api/gateway-preference`

Returns the group's preferred payment gateway.

**Auth:** Session required (uses `getUser`).

**Response:**
```json
{ "preferred_gateway": "mercadopago" | "stripe" }
```

### `POST /api/gateway-preference`

Sets the preferred payment gateway.

**Auth:** `admin_master` role required.

**Body (Zod: `gatewayPreferenceSchema`):**
```json
{ "preferred_gateway": "mercadopago" | "stripe" }
```

Creates billing customer record if none exists.

**Response:** `{ "ok": true, "preferred_gateway": "stripe" }`

---

## Auto Top-up

### `POST /api/auto-topup`

Configures automatic credit replenishment.

**Auth:** `admin_master` role required.

**Body (Zod: `autoTopupSchema`):**
```json
{
  "enabled": true,
  "threshold_tokens": 50,
  "product_id": "prod_xxx",
  "max_per_month": 3
}
```

All fields optional on update. `product_id` required on initial setup.

**Response:** `{ "ok": true }`

---

## Export

### `GET /api/export/athletes`

Exports athlete list as CSV download.

**Auth:** Session required + `portal_group_id` cookie.

**Response:** `text/csv` file download.

---

## Platform Admin Routes

These routes require `platform_admin` role (checked via `getUser` + profiles table).

### `POST /api/platform/assessorias`

Manages coaching groups (approve, reject, suspend).

### `POST /api/platform/products`

Manages credit packages (create, update, toggle).

### `POST /api/platform/refunds`

Processes refund requests.

### `POST /api/platform/support`

Manages support tickets.

### `POST /api/platform/liga`

Manages league/competition settings.

---

## Common Error Responses

| Status | Meaning |
|--------|---------|
| 400 | Validation error (Zod) or missing required data |
| 401 | Not authenticated |
| 403 | Insufficient permissions (wrong role) |
| 404 | Resource not found |
| 409 | Conflict (duplicate) |
| 422 | Business logic error (e.g., insufficient credits) |
| 429 | Rate limit exceeded |
| 500 | Server error |
| 502 | Gateway error (payment provider) |

## Rate Limiting

In-memory rate limiter per user ID per endpoint. Resets on deploy.

| Endpoint | Max requests | Window |
|----------|:----------:|:------:|
| `/api/distribute-coins` | 20 | 60s |
| `/api/distribute-coins/batch` (L05-03) | 5 | 60s |
| `/api/coins/reverse` (L03-13) | 10 | 60s (per actor) |
| `/api/checkout` | 5 | 60s |
| `/api/team/invite` | 10 | 60s |
| `/api/team/remove` | 10 | 60s |
| `/api/branding` | 10 | 60s |

## Input Validation

All POST routes use Zod schemas defined in `src/lib/schemas.ts`. Invalid input returns 400 with the first validation error message.

## Attendance / Treinos Prescritos

### `GET /api/export/attendance`

Exporta CSV com registros de cumprimento dos treinos prescritos.

| Param | Type | Source | Description |
|-------|------|--------|-------------|
| `from` | string (ISO) | query | Data inicial (opcional) |
| `to` | string (ISO) | query | Data final (opcional) |
| `session_id` | uuid | query | Filtrar por treino específico (opcional) |

**Response:** CSV file download

**Colunas CSV:**
```
Título Sessão,Data,Atleta,Check-in,Método,Status
```

**Valores de status:** Presente, Concluído, Parcial, Ausente, Atrasado, Justificado  
**Valores de método:** QR, Manual, Automático

**Acesso:** admin_master, coach, assistant (membros do grupo)

---

## Workouts / Treinos

### `POST /api/workouts/templates`

Cria ou atualiza um template de treino com seus blocos.

**Auth:** `admin_master` ou `coach` (via RLS).

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `id` | uuid | Não (se omitido, cria novo) |
| `name` | string | Sim (min 2 chars) |
| `description` | string | Não |
| `blocks` | Block[] | Sim (pode ser vazio) |

**Block:**
| Campo | Tipo |
|-------|------|
| `id` | uuid |
| `block_type` | `warmup` \| `interval` \| `recovery` \| `cooldown` \| `steady` \| `rest` \| `repeat` |
| `duration_seconds` | int \| null |
| `distance_meters` | int \| null |
| `target_pace_min_sec_per_km` | int \| null |
| `target_pace_max_sec_per_km` | int \| null |
| `target_hr_zone` | int (1-5) \| null |
| `target_hr_min` | int \| null |
| `target_hr_max` | int \| null |
| `rpe_target` | int (1-10) \| null |
| `repeat_count` | int \| null |
| `notes` | string \| null |

**Response:** `{ "ok": true, "id": "template-uuid" }`

### `DELETE /api/workouts/templates`

Exclui um template e todos os seus blocos.

**Auth:** `admin_master` ou `coach` (via RLS, mesmo grupo).

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `id` | uuid | Sim |

**Response:** `{ "ok": true }`

### `POST /api/workouts/assign`

Atribuição em lote de treinos a múltiplos atletas.

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `template_id` | uuid | Sim |
| `athlete_user_ids` | uuid[] | Sim |
| `scheduled_date` | date (YYYY-MM-DD) | Sim |

**Response:**
```json
{
  "ok": true,
  "total": 3,
  "success": 3,
  "results": [
    { "userId": "...", "ok": true, "message": "ASSIGNED" }
  ]
}
```

Chama `fn_assign_workout` para cada atleta. Resultados parciais são possíveis (alguns ok, outros com erro).

### `POST /api/workouts/watch-type`

Define o tipo de relógio de um atleta (coach override).

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `member_id` | uuid | Sim |
| `watch_type` | string \| null | Sim |

Valores: `garmin`, `coros`, `suunto`, `apple_watch`, `polar`, `other`, `""` (reset to auto-detect).

Chama `fn_set_athlete_watch_type` (SECURITY DEFINER, coach-only).

---

## Billing / Cobrança

### `POST /api/billing/asaas`

Proxy para Edge Function asaas-sync e operações locais.

**Actions:**
- `test_connection` — testa conexão com API Asaas
- `save_config` — salva/atualiza configuração Asaas (api_key, environment)
- `setup_webhook` — configura webhook no Asaas automaticamente
- `create_customer` — cria customer no Asaas e mapeia ao atleta
- `create_subscription` — cria subscription no Asaas com split automático
- `cancel_subscription` — cancela subscription no Asaas
- `disconnect` — desativa integração Asaas

**Body:** `{ action: string, ...params }`

**Auth:** admin_master required (coach for read-only operations)

---

## Financial / Planos e Assinaturas

### `POST /api/financial/plans`

Cria ou atualiza um plano financeiro.

**Auth:** `admin_master` ou `coach` (via RLS).

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `id` | uuid | Não (se omitido, cria novo) |
| `name` | string | Sim (min 2 chars) |
| `description` | string | Não |
| `monthly_price` | number | Sim (>= 0) |
| `billing_cycle` | `monthly` \| `quarterly` | Não (default: monthly) |
| `max_workouts_per_week` | int \| null | Não |
| `status` | `active` \| `inactive` | Não (default: active) |

**Response:** `{ "ok": true, "id": "plan-uuid" }`

### `DELETE /api/financial/plans`

Exclui um plano. Falha se houver assinaturas ativas vinculadas (409).

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `id` | uuid | Sim |

**Response:** `{ "ok": true }` ou `{ "error": "Não é possível excluir: N assinatura(s) ativa(s)" }`

### `POST /api/financial/subscriptions`

Atribuição em lote de plano a múltiplos atletas (upsert por athlete+group).

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `plan_id` | uuid | Sim |
| `athlete_user_ids` | uuid[] | Sim |
| `started_at` | date (YYYY-MM-DD) | Sim |
| `next_due_date` | date (YYYY-MM-DD) | Sim |

**Response:**
```json
{
  "ok": true,
  "total": 3,
  "success": 3,
  "results": [
    { "userId": "...", "ok": true }
  ]
}
```

---

---

## Platform Fees — `GET/POST /api/platform/fees`

**Auth:** Platform admin.

### GET
Returns all fee configurations from `platform_fee_config`.

**Response:** `{ "fees": [{ "id", "fee_type", "rate_pct", "rate_usd", "is_active", "updated_at" }] }`

### POST
Updates a fee configuration. Supports both percentage-based fees (`rate_pct`) and fixed-amount fees (`rate_usd`).

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `fee_type` | `clearing` \| `swap` \| `maintenance` \| `billing_split` | Sim |
| `rate_pct` | number (0–100) | Não (para clearing, swap, billing_split) |
| `rate_usd` | number (0–10) | Não (para maintenance — USD por atleta) |
| `is_active` | boolean | Não |

**Response:** `{ "ok": true }`

---

## Platform Products — Server Actions

Product mutations use **Server Actions** (`src/app/platform/produtos/mutations.ts`) instead of API routes.
Each action includes `requirePlatformAdmin()`, `rateLimit`, and `revalidatePath("/platform/produtos", "page")`.

| Action | Descrição |
|--------|-----------|
| `toggleProduct(id)` | Ativa/suspende um produto |
| `deleteProduct(id)` | Remove produto (falha com FK constraint → mensagem amigável) |
| `updateProduct(id, data)` | Atualiza campos do produto |
| `createProduct(data)` | Cria novo produto |

---

---

## Training Plan (Passagem de Treino)

All endpoints require staff session (`admin_master`, `coach`, or `assistant` role in `coaching_members`). Group context is read from the `portal_group_id` session cookie.

---

### `GET /api/training-plan`

Lists all non-archived plans for the session group (max 50, ordered by `created_at` desc).

**Auth:** `admin_master` or `coach` required.

**Response:** `{ "ok": true, "data": [{ "id", "name", "sport_type", "status", "starts_on", "ends_on", "created_at", "athlete", "weeks" }] }`

---

### `POST /api/training-plan`

Creates a new training plan via `fn_create_training_plan` RPC.

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `name` | string (2–120) | Sim |
| `sport_type` | `running\|cycling\|triathlon\|swimming\|strength\|multi` | Não (default: `running`) |
| `athlete_user_id` | uuid | Não (omitir = modelo de grupo) |
| `description` | string (max 500) | Não |
| `starts_on` | YYYY-MM-DD | Não |
| `ends_on` | YYYY-MM-DD | Não |

**Response:** `{ "ok": true, "data": { "id": "<planId>" } }` (201)

---

### `GET /api/training-plan/[planId]`

Returns plan header with resolved athlete name and avatar.

**Response:**
```json
{
  "ok": true,
  "data": {
    "id": "...", "name": "...", "sport_type": "running", "status": "active",
    "starts_on": "2026-04-14", "ends_on": null,
    "athlete_user_id": "...", "athlete_name": "João Silva", "athlete_avatar": null,
    "group_id": "...", "description": null
  }
}
```

---

### `DELETE /api/training-plan/[planId]`

Soft-deletes the plan (sets `status = archived`). Plan disappears from all list views. Data is preserved.

**Auth:** `admin_master` or `coach` required.

**Response:** `{ "ok": true }`

---

### `GET /api/training-plan/[planId]/weeks`

Returns all weeks for the plan with embedded workouts, completion metrics and feedback.

**Response:**
```json
{
  "ok": true,
  "data": [{
    "id", "week_number", "starts_on", "ends_on", "label", "coach_notes", "cycle_type", "status",
    "workouts": [{
      "id", "scheduled_date", "workout_order", "release_status", "workout_type",
      "workout_label", "coach_notes", "content_version",
      "template": { "id", "name", "description" },
      "completed": [{ "id", "actual_distance_m", "actual_duration_s", "actual_avg_hr", "perceived_effort", "finished_at" }],
      "feedback": [{ "rating", "mood", "how_was_it" }]
    }]
  }]
}
```

---

### `POST /api/training-plan/[planId]/weeks`

Creates a new week via `fn_create_plan_week` RPC. Week must start on Monday.

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `starts_on` | YYYY-MM-DD (must be Monday) | Sim |
| `cycle_type` | `base\|build\|peak\|recovery\|test\|free\|taper\|transition` | Não (default: `base`) |
| `label` | string (max 80) | Não |
| `coach_notes` | string (max 500) | Não |

**Response:** `{ "ok": true, "data": { "id": "<weekId>" } }` (201)

---

### `GET /api/training-plan/templates`

Returns workout templates for the group, enriched with block count and estimated distance.

**Query params:** `groupId` (uuid, optional — falls back to session cookie)

**Response:**
```json
{
  "ok": true,
  "data": [{
    "id", "name", "description", "workout_type",
    "estimated_distance_m": 12000,
    "block_count": 4
  }]
}
```

> `sport_type` foi removido (coluna nunca existiu na tabela). `workout_type` adicionado via migration `20260415000000_workout_template_type.sql`.

---

### `POST /api/training-plan/weeks/[weekId]/workouts`

Adds a workout to a week day. Supports two modes:
- **Template-based** (with `template_id`): calls `fn_create_plan_workout`, builds `content_snapshot` from template blocks
- **Descriptive** (without `template_id`): calls `fn_create_descriptive_workout`, uses free-text `workout_label` + `description` + optional `blocks[]` for GPS watch compatibility

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `athlete_id` | uuid | Sim |
| `template_id` | uuid | Somente modo template |
| `scheduled_date` | YYYY-MM-DD | Sim |
| `workout_type` | enum | Não (default: `continuous`) |
| `workout_label` | string (max 120) | Obrigatório no modo descritivo |
| `description` | string (max 2000) | Não (modo descritivo) |
| `coach_notes` | string (max 500) | Não |
| `video_url` | string (max 500) | Não (URL do vídeo explicativo) |
| `blocks` | `ReleaseBlock[]` (max 30) | Não (apenas modo descritivo — define estrutura de GPS watch) |

**`ReleaseBlock` shape:**
```ts
{
  order_index: number;           // 0-based
  block_type: "warmup"|"steady"|"interval"|"recovery"|"repeat"|"rest"|"cooldown";
  distance_meters: number|null;  // gatilho distância (alternativo a duration)
  duration_seconds: number|null; // gatilho tempo
  target_pace_min_sec_per_km: number|null; // pace mais rápido (segundos/km)
  target_pace_max_sec_per_km: number|null; // pace mais lento
  target_hr_zone: number|null;   // zona 1–5
  target_hr_min: number|null;    // FC mínima absoluta
  target_hr_max: number|null;    // FC máxima absoluta
  rpe_target: number|null;       // 1–10
  repeat_count: number|null;     // só em block_type=repeat
  notes: string|null;
}
```

**Response:** `{ "ok": true, "data": { "id": "<releaseId>" } }` (201)

---

### `POST /api/training-plan/weeks/[weekId]/release`

Bulk-releases all draft workouts in the week to athletes.

**Body:** `{ "reason": string }`

**Response:** `{ "ok": true, "data": { "released_count": 3 } }`

---

### `POST /api/training-plan/weeks/[weekId]/duplicate`

Duplicates the week (all workouts copied as drafts). Use `target_starts_on` to control where the copy lands; omit to let the RPC pick the next available week number.

**Body (JSON, optional):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `target_starts_on` | YYYY-MM-DD | Não (deve ser segunda-feira) |
| `target_plan_id` | uuid | Não |

Tip: for "Replicar como próxima semana", the frontend calculates `week.ends_on + 1 day` (= next Monday) and passes as `target_starts_on`.

**Response:** `{ "ok": true, "data": { "id": "<newWeekId>" } }`

---

### `POST /api/training-plan/workouts/[workoutId]/release`

Releases a single draft workout to the athlete.

**Response:** `{ "ok": true }`

---

### `POST /api/training-plan/workouts/[workoutId]/cancel`

Cancels a released workout.

**Response:** `{ "ok": true }`

---

### `POST /api/training-plan/workouts/[workoutId]/copy`

Copies a workout to a different date.

**Body:** `{ "target_date": "YYYY-MM-DD" }`

**Response:** `{ "ok": true, "data": { "id": "<newReleaseId>" } }`

---

### `PATCH /api/training-plan/workouts/[workoutId]/update`

Updates label, coach notes, and/or structured blocks of a workout (per-athlete customization).

**Body (JSON):** any subset of:
```json
{
  "workout_label": "string|null",
  "coach_notes": "string|null",
  "blocks": "<ReleaseBlock[] max 30 — see POST workouts schema above>"
}
```

When `blocks` is present, the endpoint fetches the current `content_snapshot`, replaces only the `blocks` array (preserving `template_name`, `description`, etc.), and increments `content_version`.

**Response:** `{ "ok": true, "data": { "id", "workout_label", "coach_notes", "content_snapshot", "content_version" } }`

---

### `POST /api/training-plan/workouts/[workoutId]/schedule`

Schedules a workout for automatic release at a future datetime.

**Body:** `{ "scheduled_release_at": "ISO 8601 datetime" }`

**Response:** `{ "ok": true }`

---

### `POST /api/training-plan/bulk-assign`

Distributes a source week's workouts to multiple athletes via `fn_bulk_assign_week` RPC. Returns per-athlete results.

**Body (JSON):**
| Campo | Tipo | Obrigatório |
|-------|------|-------------|
| `source_week_id` | uuid | Sim |
| `target_athlete_ids` | uuid[] (max 100) | Sim |
| `target_start_date` | YYYY-MM-DD | Sim |
| `group_id` | uuid | Sim |

**Response:**
```json
{
  "ok": true,
  "data": {
    "success_count": 3,
    "results": [
      { "athlete_id": "...", "success": true, "new_week_id": "..." },
      { "athlete_id": "...", "success": false, "error": "athlete_not_member" }
    ]
  }
}
```

---

### `GET /api/training-plan/athletes-overview`

Returns all athletes in the group enriched with their training status for the current week. Used by the athlete-centric view of `/training-plan`.

**Auth:** Session cookie + `portal_group_id` cookie.

**Response:**
```json
{
  "ok": true,
  "data": [
    {
      "user_id": "...",
      "display_name": "João Silva",
      "avatar_url": null,
      "plan": { "id": "...", "name": "Maratona SP 2026", "status": "active" },
      "current_week": {
        "id": "...", "week_number": 8,
        "starts_on": "2026-04-14", "ends_on": "2026-04-20",
        "status": "draft",
        "total": 5, "draft": 2, "released": 3, "completed": 0
      },
      "avg_rpe_last5": 8.4,
      "fatigue_alert": true
    }
  ]
}
```

`fatigue_alert` is `true` when `avg_rpe_last5 >= 8`. `current_week` reflects the week that covers today (or the most recent week if no current week exists). Sorted: athletes with plans first, fatigue alerts first within that group.

---

### `POST /api/training-plan/ai/parse-workout`

Parses a free-text workout description into structured fields **and GPS watch blocks** using GPT-4o-mini. Requires `OPENAI_API_KEY` environment variable.

**Body:** `{ "text": string (3–1000 chars) }`

**Response:**
```json
{
  "ok": true,
  "data": {
    "workout_type": "interval",
    "workout_label": "Intervalado 4×1km em 4:30/km",
    "description": "4 repetições de 1km cada no pace 4:30/km com 2 minutos de recuperação ativa",
    "coach_notes": "Aquecimento de 10min antes. Foco no pace.",
    "estimated_distance_km": 6,
    "estimated_duration_minutes": 40,
    "blocks": [
      { "order_index": 0, "block_type": "warmup", "duration_seconds": 600, "distance_meters": null,
        "target_pace_min_sec_per_km": null, "target_pace_max_sec_per_km": null,
        "target_hr_zone": 2, "rpe_target": 3, "repeat_count": null, "notes": null },
      { "order_index": 1, "block_type": "repeat", "duration_seconds": null, "distance_meters": null,
        "target_hr_zone": null, "rpe_target": null, "repeat_count": 4, "notes": null },
      { "order_index": 2, "block_type": "interval", "distance_meters": 1000, "duration_seconds": null,
        "target_pace_min_sec_per_km": 255, "target_pace_max_sec_per_km": 275,
        "target_hr_zone": 4, "rpe_target": 8, "repeat_count": null, "notes": null },
      { "order_index": 3, "block_type": "recovery", "duration_seconds": 120, "distance_meters": null,
        "target_hr_zone": 2, "rpe_target": 3, "repeat_count": null, "notes": null },
      { "order_index": 4, "block_type": "cooldown", "duration_seconds": 600, "distance_meters": null,
        "target_hr_zone": 2, "rpe_target": 3, "repeat_count": null, "notes": null }
    ]
  }
}
```

- `blocks` é um array de `ReleaseBlock` (max 30). Para treinos livres pode ser `[]`.
- `max_tokens`: 1200 (aumentado de 400 para suportar a estrutura de blocos).
- Bloco com `block_type` inválido é convertido automaticamente para `steady`.
- Returns `503 AI_NOT_CONFIGURED` if `OPENAI_API_KEY` is not set.

---

## Athletes

### `GET /api/athletes`

Returns active athlete members of the session group. Used by training-plan creation dropdown and any component needing an athlete list without knowing the `groupId` ahead of time.

**Auth:** Session cookie + `portal_group_id` cookie.

**Response:**
```json
{
  "ok": true,
  "data": [
    { "user_id": "...", "display_name": "João Silva", "avatar_url": null }
  ]
}
```

---

## Group Members

### `GET /api/groups/[groupId]/members`

Returns active athlete members of a specific group. Requires the caller to be a member of that group and the `groupId` to match the `portal_group_id` session cookie.

**Response:** `{ "ok": true, "data": [{ "user_id", "display_name", "avatar_url" }] }`

---

## Audit Logging

Mutating operations log to `audit_log` table via `src/lib/audit.ts`:
- Actor ID, group ID, action name
- Target type and ID
- Metadata (JSON)
- Timestamp
