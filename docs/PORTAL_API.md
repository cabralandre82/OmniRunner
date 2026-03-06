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

Uptime check endpoint. No authentication required.

**Response:**
```json
{ "status": "ok", "ts": 1709136000000 }
```

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

Distributes coins from group inventory to an athlete's wallet.

**Auth:** `admin_master` role required. Rate limited: 20 req/min.

**Body (Zod: `distributeCoinsSchema`):**
```json
{
  "athlete_user_id": "uuid",
  "amount": 50
}
```

- `amount`: integer 1–1000
- `athlete_user_id`: must be UUID, must be `athlete` in the group

**Flow:**
1. Decrements group token inventory (`decrement_token_inventory` RPC)
2. Credits athlete wallet (`increment_wallet_balance` RPC)
3. Records ledger entry
4. Audit log

**Rollback:** If wallet credit fails, inventory is rolled back.

**Response:**
```json
{ "ok": true, "athlete_user_id": "...", "amount": 50, "athlete_name": "João" }
```

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

## Audit Logging

Mutating operations log to `audit_log` table via `src/lib/audit.ts`:
- Actor ID, group ID, action name
- Target type and ID
- Metadata (JSON)
- Timestamp
