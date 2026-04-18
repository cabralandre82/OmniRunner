---
id: L05-02
audit_ref: "5.2"
lens: 5
title: "Swap não tem TTL/expiração — ofertas ficam para sempre"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "migration", "cron", "performance"]
files:
  - supabase/migrations/20260417270000_swap_orders_expiration.sql
  - portal/src/lib/swap.ts
  - portal/src/lib/swap.test.ts
  - portal/src/app/api/swap/route.ts
  - portal/src/app/api/swap/route.test.ts
  - tools/integration_tests.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/swap.test.ts
  - portal/src/app/api/swap/route.test.ts
  - tools/integration_tests.ts
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-02] Swap não tem TTL/expiração — ofertas ficam para sempre
> **Lente:** 5 — CPO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** DB + PORTAL
**Personas impactadas:** Assessoria (seller/buyer), Plataforma (CFO)

## Achado
`swap_orders` não tinha `expires_at`. Vendedor cria oferta de US$ 500k, esquece, e meses depois um buyer aceita ao preço/fee daquela época. Marketplace ficava poluído de listagens stale (sem cleanup). Sem accountability operacional sobre quanto da custódia de cada clube está "preso" em ofertas dormentes.

## Risco / Impacto
- **Financeiro**: aceite de oferta antiga ao spread/fee desfavoráveis para o seller (se a fee_rate_pct mudou no meio tempo, oferta congela o valor antigo).
- **Operacional**: marketplace listando ofertas anos antigas confunde admin_master.
- **Custódia**: oferta abertas competem pelo `total_deposited_usd - total_committed` do seller na pré-validação de novas operações.

## Correção implementada

### 1. Migration `20260417270000_swap_orders_expiration.sql`

**Schema**:
- `ALTER TABLE swap_orders ADD COLUMN expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days')`. Legacy rows recebem janela de 7d para evitar shock — alternativa de expirar tudo no primeiro run seria UX hostil para clientes confiando no marketplace.
- `swap_orders_status_check` reescrito para incluir `'expired'` (DROP + CREATE atomicamente em DO block, idempotente em re-aplicação).
- `CREATE INDEX idx_swap_orders_open_expires ON swap_orders(expires_at) WHERE status='open'` — sweep parcial fica O(log n) sobre rows abertas, ignora settled/cancelled/expired (~99% do volume após maturação).

**`execute_swap` hardenizado**:
- Adiciona check `IF v_expires_at < now() THEN RAISE EXCEPTION 'SWAP_EXPIRED' USING ERRCODE='P0005'`. Defesa entre runs do cron — se buyer aceita uma oferta cujo `expires_at` já passou mas o sweep ainda não rodou, a operação é abortada antes de mover saldos.
- HINT da exceção carrega `expires_at` em ISO8601 — portal pode mostrar "Oferta expirou em 2026-04-10".
- Mantém SQLSTATEs L05-01 (P0001 NOT_OPEN, P0002 NOT_FOUND, P0003 SELF_BUY, P0004 INSUFFICIENT_BACKING) + adiciona P0005 SWAP_EXPIRED.
- Comentário explica explicitamente por que NÃO marcamos `status='expired'` dentro do RAISE: PL/pgSQL EXCEPTION rollback de subtransaction descarta qualquer write feito antes do RAISE; o cron sweep é o único responsável pela transição. Janela de inconsistência ≤10min é aceitável.

**`fn_expire_swap_orders()`**:
- `RETURNS TABLE(expired_count integer, expired_ids uuid[])` — retorna ids para audit/observability subsequente.
- `UPDATE … RETURNING id` agrega num CTE; row-level locks adquiridos serializam contra `execute_swap` concorrente (quem chegar primeiro vence — caso row já esteja em settle in-flight, sweep não modifica).
- `SECURITY DEFINER` + `search_path=public,pg_temp` (L18-03) + `lock_timeout=5s` (mais frouxo que 2s do execute_swap pq sweep batch tolera atrasos).
- `REVOKE … FROM authenticated, anon` — só `service_role` (cron job + Edge Functions futuras).

**pg_cron schedule**:
- Job `swap-expire` a cada `*/10 * * * *` invoca `SELECT public.fn_expire_swap_orders()`.
- `cron.unschedule()` defensivo se job homônimo já existe (idempotência em re-aplicação).
- `EXCEPTION WHEN undefined_table` tolera dev sem `pg_cron.job` table (NOTICE em vez de fail) — produção (Supabase managed) tem extension preinstalada.

**Invariants block** valida ao aplicar:
- coluna criada, CHECK inclui 'expired', index parcial existe, RPC retorna shape correto, `execute_swap` rejeita expired (P0005), sweep limpa para 'expired', e re-rodar sweep não re-marca rows já expiradas (idempotência).

### 2. `portal/src/lib/swap.ts`

- **`SwapOrder.expires_at: string | null`** adicionado.
- **`SWAP_TTL_DAYS = [1, 7, 30, 90]`** + `SwapTtlDays` type + `DEFAULT_SWAP_TTL_DAYS = 7`. Discreto e canônico — força UX consistente.
- **`SwapErrorCode` ganha `"expired"`** mapeado de SQLSTATE `P0005`. `toSwapError()` extrai `expires_at` do hint para `detail.expired_at`.
- **`createSwapOffer(seller, amount, expiresInDays = 7)`**:
  - Valida `expiresInDays ∈ SWAP_TTL_DAYS` antes de qualquer side-effect.
  - Calcula `expires_at = now + N*86400_000ms` em UTC e injeta no INSERT.
- **`getOpenSwapOffers()`** filtra `expires_at >= now()` — não retorna zumbis entre runs do cron sweep.
- **`expireSwapOrders()`** wrapper RPC para invocação manual (admin tools, cron HTTP-triggered, observability scripts). Retorna `{expiredCount, expiredIds}`.

### 3. `portal/src/app/api/swap/route.ts`

- `createSchema` aceita `expires_in_days?: 1 | 7 | 30 | 90` (Zod union de literals — strict, rejeita 14 ou 60).
- `swapErrorToResponse` mapeia `expired` → **HTTP 410 Gone** (semântica REST: recurso existiu mas saiu permanentemente). Body inclui `code: "expired"`, `detail.expired_at`.
- `audit` log de `swap.offer.created` agora carrega `expires_in_days` + `expires_at` resolvido — forense de "que TTL o vendedor escolheu".
- Default `DEFAULT_SWAP_TTL_DAYS` aplicado quando `expires_in_days` omitido.

### 4. Testes

**`portal/src/lib/swap.test.ts`** (50 cases total, +13 novos):
- `createSwapOffer`: rejeita `expires_in_days=14` (não-canônico), passa `expires_at` calculado para INSERT, cobre cada TTL canônico (1/7/30/90) com `it.each`.
- `acceptSwapOffer`: P0005 → `code='expired'` + `detail.expired_at` populado.
- `expireSwapOrders`: chama RPC e devolve count+ids; `count=0` quando vazio; propaga erro Supabase.

**`portal/src/app/api/swap/route.test.ts`** (23 cases, +4 novos):
- `POST create` com `expires_in_days=1` propaga para lib e audit log.
- Default 7d quando omitido.
- Strict rejeita `expires_in_days=14`.
- `POST accept` com SwapError `expired` → HTTP 410 + audit `accept_failed` com `code: "expired"`.

**`tools/integration_tests.ts`** (+3 novos):
- Sweep marca expired E é idempotente (2ª chamada não re-toca).
- `execute_swap` em order `expires_at<now()` retorna P0005, status fica `'open'` (rollback de subtransação), sweep manual depois converte para `'expired'`.
- `execute_swap` em order válida (futuro) executa happy path normalmente.

## Garantias finais

- **Sem ofertas zumbi**: `getOpenSwapOffers` + cron sweep limpam dentro de ≤10min do TTL.
- **Atomicidade**: cron sweep faz row-level lock; race contra execute_swap concorrente é resolvida por FOR UPDATE.
- **Defesa em profundidade**: mesmo se cron atrasar, `execute_swap` valida `expires_at < now()` antes de mover saldos.
- **UX**: HTTP 410 Gone + `detail.expired_at` permitem UI mostrar "Esta oferta expirou em DD/MM/YYYY".
- **Auditabilidade**: audit log carrega `expires_in_days` no create + `code: "expired"` em accept_failed.
- **Backwards compat**: legacy rows ganham 7d window; novos clientes podem omitir field e receber default.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.2).
- `2026-04-17` — Fix implementado: schema + RPC sweep + cron + execute_swap defesa + portal TTL UX. Validado 152/152 integration tests + 50/50 swap unit tests + 806/806 portal vitest baseline.
