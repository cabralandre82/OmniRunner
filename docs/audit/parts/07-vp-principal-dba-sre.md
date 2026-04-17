# PARTE 7 de 8 — LENTES 17 (VP Engineering), 18 (Principal Engineer), 19 (DBA: SQL & Performance) e 20 (SRE: Observability & Reliability)

Auditoria de **40 itens** — análise técnica profunda.

---

## LENTE 17 — VP Engineering: Organização do código, DX, Qualidade de código

### 🔴 [17.1] **`withErrorHandler` não é usado** em endpoints financeiros críticos

**Achado** — `portal/src/lib/api-handler.ts:10-30` exporta `withErrorHandler(handler, routeName)`. Grep em `/api/custody/route.ts`, `/api/swap/route.ts`, `/api/distribute-coins/route.ts`, `/api/custody/withdraw/route.ts` mostra que **nenhum** usa o wrapper. Cada endpoint tem seu próprio `try/catch` inconsistente (ver [14.5]).

**Risco** —

- Erros não capturados por Sentry quando `try` não envolve linha problemática.
- `x-request-id` não propagado na resposta de erro.
- Mensagem de erro hardcoded em pt-BR ([7.1]).

**Correção** — Refatorar:

```typescript
// portal/src/app/api/swap/route.ts
import { withErrorHandler } from "@/lib/api-handler";

export const POST = withErrorHandler(async (req) => {
  // actual logic, throw on errors
  // wrapper converts to JSON + logs + request_id
}, "api.swap.post");
```

Criar lint rule custom (`eslint-plugin-custom-omni`) que proíbe `export async function POST/GET/...` sem wrapper.

**Teste** — CI grep: `rg "^export async function (POST|GET|PUT|DELETE|PATCH)" portal/src/app/api` → deve retornar 0 matches (tudo deve vir de `withErrorHandler`).

---

### 🔴 [17.2] **5378 linhas em `portal/src/lib/*.ts`** e sem segregação por bounded context

**Achado** — `portal/src/lib/` contém 45+ arquivos lado-a-lado: `custody.ts`, `clearing.ts`, `swap.ts`, `audit.ts`, `cache.ts`, `csrf.ts`, `feature-flags.ts`, etc. Sem subdirs de domínio. Refactor de "custódia" toca arquivo no mesmo nível de "format".

**Risco** — Conforme cresce (projeção: 20k+ linhas em 12 meses), merge conflicts multiplicam, onboarding de novos devs fica lento, circular imports aparecem.

**Correção** — Reorganizar em bounded contexts:

```
portal/src/lib/
├── financial/      # custody, clearing, swap, withdrawal
│   ├── custody.ts
│   ├── clearing.ts
│   ├── swap.ts
│   └── index.ts    # barrel
├── security/       # csrf, rate-limit, audit, webhook
├── platform/       # feature-flags, roles, metrics
├── infra/          # supabase, redis, logger, cache
└── shared/         # format, schemas (cross-context)
```

Migration gradual: renomear um contexto por sprint, atualizar imports via codemod (`jscodeshift`).

---

### 🟠 [17.3] **`withErrorHandler` usa `any`** em routeArgs

**Achado** — Linha 11:

```11:11:portal/src/lib/api-handler.ts
  handler: (req: NextRequest, ...routeArgs: any[]) => Promise<NextResponse>,
```

`any` derrota o type-checking em favor de ergonomia.

**Correção** —

```typescript
export function withErrorHandler<TArgs extends unknown[]>(
  handler: (req: NextRequest, ...routeArgs: TArgs) => Promise<NextResponse>,
  routeName: string,
): (req: NextRequest, ...routeArgs: TArgs) => Promise<NextResponse> {
  return async (req, ...args) => { ... };
}
```

Mais: habilitar `"noImplicitAny": true` em `tsconfig.json` e rodar `npx tsc --noEmit --strict`.

---

### 🟠 [17.4] **Testes unitários** em `portal/src/lib/qa-*.test.ts` — arquivos >800 linhas

**Achado** — `qa-e2e.test.ts` com 839 linhas, `partnerships.test.ts` 545 linhas. Mega-arquivos-teste são cheirinho de "testes cobrem tudo de uma tabela, não de um comportamento".

**Risco** — Quando uma mudança quebra 3 testes, dev tende a comentar o bloco em vez de entender. Long test files + shared setup = flaky tests.

**Correção** — Split por feature; cada test file < 200 linhas; use `describe.concurrent` para paralelizar; `vitest --coverage` garante que não perde cobertura no split.

---

### 🟠 [17.5] Logger **silencia errors não-Error**

**Achado** — `portal/src/lib/logger.ts:31-35`:

```31:35:portal/src/lib/logger.ts
    if (error instanceof Error) {
      Sentry.captureException(error, { extra: { msg, ...meta } });
    } else if (error) {
      Sentry.captureMessage(msg, { level: "error", extra: { error, ...meta } });
    }
```

Chamada `logger.error("failed", undefined)` passa pelo segundo branch (undefined é falsy), **não captura nada no Sentry**.

**Correção** —

```typescript
error(msg: string, error?: unknown, meta?: LogMeta) {
  const errorInfo = error instanceof Error
    ? { message: error.message, stack: error.stack }
    : error !== undefined ? { value: String(error) } : {};
  console.error(format("error", msg, { ...meta, ...errorInfo }));

  // Always report to Sentry, even without error object
  if (error instanceof Error) {
    Sentry.captureException(error, { extra: { msg, ...meta } });
  } else {
    Sentry.captureMessage(msg, { level: "error", extra: { error, ...meta } });
  }
},
```

---

### 🟠 [17.6] `csrfCheck` **não é chamado** no middleware central

**Achado** — Existe `portal/src/lib/csrf.ts` mas `portal/src/middleware.ts` **não importa nem invoca**. Cada route handler deveria chamar individualmente — não encontrei uso.

**Risco** — CSRF protection presente em código mas **inativa na produção**.

**Correção** — Chamar no middleware **antes** de auth:

```typescript
// middleware.ts
import { csrfCheck } from "@/lib/csrf";

export async function middleware(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith("/api/") &&
      !["/api/custody/webhook", "/api/auth/callback"].includes(request.nextUrl.pathname)) {
    const csrfFail = csrfCheck(request);
    if (csrfFail) return csrfFail;
  }
  // ... rest
}
```

Exceções: webhooks (precisam receber POST sem origin), OAuth callback.

---

### 🟡 [17.7] Não há **`docs/adr/`** ativo para decisões arquiteturais

**Achado** — Pasta `docs/adr/` existe (visto no `ls docs/`) mas auditoria rápida não revela densidade/atualização.

**Correção** — Processo: toda decisão arquitetural significativa exige ADR merged junto ao PR. Template Madr ou Michael Nygard.

---

### 🟡 [17.8] **Ausência de monorepo tooling** (turbo, nx, pnpm-workspaces)

**Achado** — `portal/` e `omni_runner/` coexistem na raiz mas sem gerenciador unificado. Não há `turbo.json`, `nx.json`, `pnpm-workspace.yaml`.

**Correção** — Quando atingir 3+ pacotes (portal, shared-types, partner-sdk), adotar Turborepo com caches de CI remotos.

---

### 🟡 [17.9] **Sem shared types** TS/Dart entre portal e mobile

**Achado** — `portal/src/lib/schemas.ts` define Zod schemas; mobile Flutter re-define manualmente em `lib/domain/entities/*.dart`. Divergência potencial.

**Correção** — `packages/shared-contracts/` gerando:

- TS types a partir de Zod
- Dart classes via `freezed` + `json_serializable`
- OpenAPI JSON único fonte da verdade

Ferramenta: `@hey-api/openapi-ts` (TS) + `openapi_generator` (Dart).

---

## LENTE 18 — Principal Engineer: Arquitetura em profundidade, trade-offs, invariantes

### 🔴 [18.1] **Duas fontes da verdade** para balance de wallet (wallets.balance_coins vs SUM(coin_ledger))

**Achado** — O ledger é append-only e canônico; `wallets.balance_coins` é cache mutável. `execute_burn_atomic`, `fn_increment_wallets_batch`, e outros atualizam `wallets` diretamente. `reconcile_all_wallets` corrige drift — mas a existência de drift é o sintoma de arquitetura frágil.

**Risco** — Qualquer RPC nova esquecer de atualizar `wallets` = drift silencioso até próximo reconcile (que [12.1] revelou não estar agendado).

**Correção** — Três opções arquiteturais:

1. **Calcular balance sempre** do ledger (view materializada incremental):

```sql
CREATE MATERIALIZED VIEW mv_wallet_balance AS
SELECT user_id, SUM(delta_coins) AS balance_coins,
       MAX(created_at_ms) AS last_ms
FROM coin_ledger GROUP BY user_id;

CREATE UNIQUE INDEX ON mv_wallet_balance(user_id);

-- Incremental refresh not supported natively; use triggers
```

2. **Single gateway function**: toda mutação de wallet passa por `fn_mutate_wallet(user_id, delta, reason, ref_id)` que insere em ledger **e** atualiza wallet atomicamente. Proibir `UPDATE wallets SET balance_coins = ...` via trigger guard:

```sql
CREATE OR REPLACE FUNCTION fn_forbid_direct_wallet_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('app.allow_wallet_mutation', true) != 'yes' THEN
    RAISE EXCEPTION 'Direct wallet mutation forbidden. Use fn_mutate_wallet.';
  END IF;
  RETURN NEW;
END;$$;
CREATE TRIGGER trg_wallet_gate BEFORE UPDATE ON wallets
  FOR EACH ROW EXECUTE FUNCTION fn_forbid_direct_wallet_update();
```

A RPC autorizada faz `SET LOCAL app.allow_wallet_mutation = 'yes'` dentro da transação.

3. **Event sourcing puro**: remove `wallets.balance_coins` completamente. Calcular on-the-fly com index `WHERE user_id = X`.

**Recomendação**: Opção **2** (gateway) — mais pragmática com menos refactor.

---

### 🔴 [18.2] **Idempotência ad-hoc** em cada RPC — padrão não unificado

**Achado** — `confirm_custody_deposit` usa `FOR UPDATE` + status check. `execute_burn_atomic` usa `FOR UPDATE` no wallet. `execute_swap` usa UUID ordering. `execute_withdrawal` NÃO tem idempotency. `distribute-coins` (JS) NÃO tem. Padrão diferente em cada função.

**Risco** — Duas chamadas concorrentes do mesmo `withdraw` via retry de Vercel edge → duas execuções.

**Correção** — Pattern de idempotency key server-side:

```sql
CREATE TABLE public.idempotency_keys (
  key text PRIMARY KEY,
  request_hash bytea NOT NULL,
  response jsonb,
  status_code int,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '24 hours')
);

CREATE INDEX idx_idem_expires ON idempotency_keys(expires_at);

CREATE OR REPLACE FUNCTION public.fn_idem_check_or_store(
  p_key text, p_request_hash bytea
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_existing jsonb;
BEGIN
  SELECT jsonb_build_object(
    'found', true, 'response', response, 'status_code', status_code,
    'hash_match', request_hash = p_request_hash
  ) INTO v_existing
  FROM idempotency_keys WHERE key = p_key AND expires_at > now() FOR UPDATE;

  IF FOUND THEN RETURN v_existing; END IF;

  INSERT INTO idempotency_keys(key, request_hash) VALUES (p_key, p_request_hash);
  RETURN jsonb_build_object('found', false);
END;$$;
```

Middleware API consulta antes de executar; store após. Cobre ambos RPC e Route Handler.

---

### 🔴 [18.3] **SECURITY DEFINER sem `SET search_path`** em funções antigas

**Achado** — `fn_delete_user_data` em `20260312000000_fix_broken_functions.sql:5-10` — tem `SET search_path = public`. Mas muitas outras funções criadas em migrations mais antigas (`execute_burn_atomic` em `20260228160001`) não têm.

**Risco** — Search-path injection: atacante com acesso a criar schema `attacker_schema` (qualquer user autenticado pode `CREATE SCHEMA` se não revogado) cria função `coin_ledger` nesse schema; se a função SECURITY DEFINER não fixa `search_path`, pode chamar função errada.

**Correção** — Migration de hardening:

```sql
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.proname, n.nspname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef = true
      AND NOT EXISTS (
        SELECT 1 FROM pg_db_role_setting s
        WHERE s.setconfig::text LIKE '%search_path=%'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = public, pg_temp',
                   r.proname, r.args);
  END LOOP;
END $$;

-- Also revoke CREATE on public from PUBLIC
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

Migration `20260322500000_medium_severity_fixes.sql:66` já faz para algumas — auditar cobertura total.

---

### 🔴 [18.4] Architecture: **Flutter viola Clean Arch** em vários pontos

**Achado** — Conforme resumo conversacional prévio, `omni_runner/lib` tem:

- `drift_database.dart` (data layer) sendo importado diretamente de `presentation/screens/*`
- `product_event_tracker.dart` chama `sl<SupabaseClient>()` direto (não via repository)
- Use cases misturando domain + data responsibilities

**Risco** — Inability to migrate backend (se algum dia sair do Supabase), testing painful (Supabase client precisa ser mockado em 50 lugares).

**Correção** — Estabelecer fence arquitetural com `dart_code_metrics` rules:

```yaml
# analysis_options.yaml
dart_code_metrics:
  rules:
    - avoid-direct-imports:
        source: "presentation"
        forbidden: ["data/datasources/*"]
```

Refactor prioritário: `secure_storage`, `deep_links`, `auth_repository` — camadas core com mais impacto.

---

### 🟠 [18.5] **Event bus inexistente** — cascatas de efeitos em código imperativo

**Achado** — Quando um `session` é marcada `is_verified=true`, devem acontecer: compute skill bracket, update leaderboard, compute kpis, check badges, notify coach. Hoje, cada caller orquestra. Se esquecer um, estado fica inconsistente.

**Correção** — Postgres triggers ou NOTIFY/LISTEN:

```sql
CREATE OR REPLACE FUNCTION fn_on_session_verified()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_verified AND OLD.is_verified IS DISTINCT FROM true THEN
    PERFORM pg_notify('session_verified',
      jsonb_build_object('session_id', NEW.id, 'user_id', NEW.user_id)::text);
  END IF;
  RETURN NEW;
END;$$;

CREATE TRIGGER trg_session_verified AFTER UPDATE ON sessions
  FOR EACH ROW EXECUTE FUNCTION fn_on_session_verified();
```

Edge Function "session-events-consumer" consome (com retry, DLQ). Trocou orquestração implícita por explícita.

---

### 🟠 [18.6] `cachedFlags` em `feature-flags.ts` — **cache de módulo com TTL racional**

**Achado** — `portal/src/lib/feature-flags.ts:9-11`:

```9:11:portal/src/lib/feature-flags.ts
let cachedFlags: Map<string, Flag> | null = null;
let lastFetchMs = 0;
const TTL_MS = 60_000;
```

Cache em escopo de módulo (edge function = por instância serverless). Cada instância Vercel tem seu cache; 60s TTL. Aceitável. Mas admin toggle leva até 60s pra propagar (feature-flag de emergência para cortar operação financeira — [6.6] — deve ser instantâneo).

**Correção** — Para flags **críticas** (`custody.*.enabled`), TTL = 5s. Ou propagação via Supabase Realtime broadcast:

```typescript
supabase.channel("feature-flags").on("postgres_changes", {
  event: "UPDATE", schema: "public", table: "feature_flags"
}, () => { cachedFlags = null; lastFetchMs = 0; }).subscribe();
```

Realtime só funciona em instância long-lived → em serverless Vercel não resolve. Alternativa: `rollout_pct = 0` no DB + invalidação por `POST /api/internal/flags/invalidate` chamado broadcast a todas as instâncias (via Vercel Edge Config ou similar).

---

### 🟠 [18.7] `userBucket` em feature-flags usa hash **Java-style** (inseguro, colisões)

**Achado** — Linhas 43-51 implementam hash `(hash << 5) - hash + charCodeAt`. Não é crypto-secure nem uniform. Para split 50/50 funciona, mas para 90/10 distribuição pode ser enviesada.

**Correção** — Usar `crypto.subtle.digest` (Web Crypto):

```typescript
async function userBucket(userId: string, key: string): Promise<number> {
  const data = new TextEncoder().encode(`${userId}:${key}`);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return new DataView(hash).getUint32(0) % 100;
}
```

Trade-off: assíncrono. Vale pela robustez estatística em A/B.

---

### 🟠 [18.8] **Edge Functions vs Route Handlers** — responsabilidade duplicada

**Achado** — `distribute-coins` tem versão em `portal/src/app/api/distribute-coins/route.ts` E existe função `fn_increment_wallets_batch` chamada por Edge Functions. Dois caminhos que fazem coisas parecidas, mantidos separadamente.

**Risco** — Mudança de regra de negócio em um path esquece o outro. Divergência.

**Correção** — **Canonical path**: tudo financeiro flui por RPC Postgres. Route Handler e Edge Function ambos apenas validam + chamam RPC. Business logic 100% no banco (SECURITY DEFINER funcs).

---

### 🟡 [18.9] **Sem domain events** em audit_log

**Achado** — `audit_logs` registra action string + metadata. Sem tipagem — `"custody.deposit.confirmed"` ao lado de `"user.login"` sem distinguir escopos.

**Correção** — Schema versionado em `audit_logs.event_schema_version`; eventos tipados com Zod:

```typescript
const CustodyDepositConfirmedEvent = z.object({
  event: z.literal("custody.deposit.confirmed"),
  v: z.literal(1),
  deposit_id: z.string().uuid(),
  amount_usd: z.number(),
  actor_id: z.string().uuid(),
});
```

---

### 🟡 [18.10] **Sem health-check de business logic** (vs infra)

**Achado** — `/api/health` checa DB + invariants. Não checa:

- Latência média do RPC `execute_burn_atomic` nos últimos 5 min
- Taxa de falha de webhooks entrantes
- Backlog de `clearing_settlements` em `pending`

**Correção** — Endpoint `/api/internal/business-health` com métricas:

```typescript
{
  rpc_latency_p99_ms: { execute_burn: 230, execute_swap: 180 },
  webhook_success_rate: { stripe: 0.999, mercadopago: 0.987, asaas: 0.95 },
  clearing_pending_count: 7,
  withdrawal_processing_count: 2,
  oldest_pending_deposit_hours: 0.3,
}
```

---

## LENTE 19 — DBA: SQL, Performance, Indexing, Locking

### 🔴 [19.1] `coin_ledger` **não é particionada** — tabela crescendo sem controle

**Achado** — `grep "PARTITION" supabase/migrations/*.sql` retorna matches apenas em `strava-time-index-and-partitioning.sql:20-25` que cria **tabela de arquivo** (não partição). O ledger principal:

```274:274:supabase/migrations/20260218000000_full_schema.sql
CREATE INDEX idx_ledger_user ON public.coin_ledger(user_id, created_at_ms DESC);
```

é tabela monolítica. Em 2 anos de crescimento com 100k usuários ativos × 50 tx/mês = 120M rows. Reconciliação full scan = horas.

**Risco** — Performance degrada; VACUUM bloqueia; backup demora.

**Correção** — Migrar para `PARTITION BY RANGE (created_at_ms)`, partições mensais:

```sql
-- Requires downtime or blue/green table swap
CREATE TABLE coin_ledger_new (LIKE coin_ledger INCLUDING ALL)
  PARTITION BY RANGE (created_at_ms);

-- Create partitions for past 24 months + future 6 months
-- Move data in batches, swap names.
```

Após partition: archive cron move partições antigas para `coin_ledger_archive` via `ATTACH/DETACH` (instantâneo) ao invés de DELETE (lento + bloat).

---

### 🔴 [19.2] **`DELETE` em archive cron gera table bloat massivo**

**Achado** — `supabase/migrations/20260320000000_strava_time_index_and_partitioning.sql:66` arquiva via `DELETE FROM coin_ledger WHERE …`. Cada delete marca tuples como dead; VACUUM não roda automaticamente em intervalo curto; tabela fica inchada.

**Risco** — Até 50% de espaço desperdiçado; queries varrem pages com dead tuples; performance linearmente pior.

**Correção** — Após partitioning ([19.1]), arquivar = `ALTER TABLE coin_ledger DETACH PARTITION ledger_202501`, rename, move. **Zero bloat**.

---

### 🔴 [19.3] Indexes **redundantes** em `sessions`

**Achado** —

```79:81:supabase/migrations/20260218000000_full_schema.sql
CREATE INDEX idx_sessions_user ON public.sessions(user_id, start_time_ms DESC);
CREATE INDEX idx_sessions_status ON public.sessions(user_id, status);
CREATE INDEX idx_sessions_verified ON public.sessions(user_id) WHERE is_verified = true;
```

Adicionado depois em `20260303700000_portal_performance_indexes.sql:7`:

```sql
CREATE INDEX idx_sessions_user_start
  ON public.sessions (user_id, start_time_ms DESC);
```

**Duplicata** de `idx_sessions_user`. Mesmo custo de INSERT, dobrado.

**Correção** — Auditar todos índices duplicados:

```sql
SELECT tablename, array_agg(indexname) AS dups
FROM (
  SELECT tablename, indexname,
         pg_get_indexdef(indexrelid) AS def
  FROM pg_indexes i JOIN pg_stat_user_indexes s ON i.indexname = s.indexrelname
  WHERE schemaname = 'public'
) x
GROUP BY tablename, regexp_replace(def, 'idx_\w+', 'idx_')
HAVING COUNT(*) > 1;
```

Dropar duplicados. Regra de code review: novo index deve ser justificado por query real em `pg_stat_statements`.

---

### 🟠 [19.4] `idx_ledger_user` vs `idx_coin_ledger_user_created` — **evoluções sem limpeza**

**Achado** — Migration 2026-02-18 cria `idx_ledger_user`; migration 2026-03-08 cria `idx_coin_ledger_user_created`. Nomenclatura inconsistente; provavelmente ambos persistem.

**Correção** — Migration `CREATE INDEX CONCURRENTLY idx_X; DROP INDEX CONCURRENTLY idx_Y;` para trocar sem lock.

---

### 🟠 [19.5] **Falta `FOR UPDATE NOWAIT`** em funções de lock crítico

**Achado** — `execute_burn_atomic` faz `SELECT … FOR UPDATE` — se outra transação bloquear, espera indefinidamente (até `statement_timeout` se configurado). Em cenário de contenção alta, filas de requests se acumulam.

**Correção** —

```sql
-- Explicit timeout per lock
SELECT balance_coins INTO v_wallet_balance
FROM public.wallets
WHERE user_id = p_user_id
FOR UPDATE NOWAIT;
-- If lock not obtained → raises 55P03 lock_not_available
EXCEPTION WHEN lock_not_available THEN
  RAISE EXCEPTION 'Wallet busy, retry' USING ERRCODE = 'W001';
```

Client retries with backoff ou return 429 imediato.

---

### 🟠 [19.6] `JSONB` em `audit_logs.metadata` **sem índice GIN**

**Achado** — Queries "todos eventos do request_id X" fazem seq scan.

**Correção** —

```sql
CREATE INDEX CONCURRENTLY idx_audit_logs_metadata_gin
  ON public.audit_logs USING GIN (metadata jsonb_path_ops);

-- query patterns:
-- WHERE metadata @> '{"request_id": "..."}'
```

---

### 🟠 [19.7] **`pg_stat_statements` não referenciado** em tuning

**Achado** — Sem evidência de análise de top-N slow queries. Operações financeiras podem ter queries subótimas silenciosamente.

**Correção** — `CREATE EXTENSION pg_stat_statements` + runbook `DBA_QUERY_TUNING.md` com:

```sql
SELECT query, calls, total_exec_time, mean_exec_time, stddev_exec_time
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY total_exec_time DESC LIMIT 20;
```

Revisão mensal.

---

### 🟠 [19.8] Constraints `CHECK` sem name padronizado

**Achado** — Algumas tabelas têm `chk_peg_1_to_1`, outras usam nome auto-gerado `custody_accounts_total_deposited_usd_check`. Em erros, frontend mostra nome feio.

**Correção** — Convenção: `chk_<table>_<regra>`. Alterar constraints não-nomeadas com `ALTER TABLE … RENAME CONSTRAINT`.

---

### 🟡 [19.9] **Connection pooling** não documentado

**Achado** — Supabase oferece PgBouncer transacional/session. Portal usa `@supabase/ssr` (ephemeral); Edge Functions criam client por request. Em burst alto, conexões saturam.

**Correção** — Documentar: Portal usa pool **transaction mode**; Edge Functions também. Configurar `poolSize` no client.

---

### 🟡 [19.10] **Sem autovacuum tuning** para tabelas hot

**Achado** — `sessions`, `coin_ledger`, `product_events` crescem rápido. Autovacuum default pode não acompanhar.

**Correção** —

```sql
ALTER TABLE coin_ledger SET (
  autovacuum_vacuum_scale_factor = 0.05,  -- default 0.2
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_vacuum_cost_delay = 10
);
```

---

## LENTE 20 — SRE: Observability, Incident, SLO, Reliability

### 🔴 [20.1] **Sem dashboard** consolidado de operações financeiras

**Achado** — Nenhum Grafana/Datadog dashboard encontrado com painéis:

- Depósitos por minuto
- Latência `execute_burn_atomic` p50/p99
- Taxa de falha de webhooks
- Invariant violations count
- Queue backlog

**Risco** — Incident response é reativo (Sentry alerta) ao invés de proativo.

**Correção** — Dashboard IaC em `observability/grafana/dashboards/financial-ops.json` (versionado no repo, deploy via Terraform/Grafana API).

Painéis mínimos:

1. **Depositos/min (last 1h)** - `custody_deposits.created_at` rate
2. **p99 burn latency** - duração do RPC
3. **Invariant violations** - contagem de `check_custody_invariants()`
4. **Webhook success rate** - matriz por gateway × status
5. **Wallet drift** - diff entre ledger sum e wallet balance

---

### 🔴 [20.2] **Sem SLO/SLI definidos** → impossível ter alert policy razoável

**Achado** — Correlacionado a [6.10]. Alertas hoje são thresholds absolutos chutados. Nenhum "burn 2% error budget in 1h" style.

**Correção** —

```yaml
# observability/slo.yaml
slos:
  - name: api_distribute_coins_availability
    target: 99.9
    window: 30d
    sli: "rate(api_requests{route='/api/distribute-coins',status<500})"
  - name: api_withdraw_latency
    target: 95  # 95% of requests < 500ms
    window: 30d
    sli: "rate(api_requests{route='/api/custody/withdraw',latency<500ms})"
  - name: webhook_processing_p99
    target: 99  # 99% processed in 30s
    window: 7d
```

Burn rate alerts (Google SRE book): alert quando burn rate > 14× (burns 1h budget em 1h).

---

### 🔴 [20.3] Sem **tracing distribuído** (OpenTelemetry)

**Achado** — Request do mobile → Portal `/api/distribute-coins` → Supabase RPC → possivelmente edge function → webhook → banco. Não há trace_id correlacionado end-to-end.

**Risco** — "Pagamento demorou 15 segundos" — impossível saber onde (mobile? portal? RPC? network?).

**Correção** —

```typescript
// portal/src/instrumentation.ts
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: "https://otel.omnirunner.com/v1/traces" }),
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

Supabase client: wrap em `span`. Mobile Flutter: `sentry_flutter` já captura; habilitar tracing + propagar `sentry-trace` header para API.

---

### 🟠 [20.4] **Sentry sem `tracesSampleRate`** tuning documentado

**Achado** — Configs Sentry não auditadas aqui, mas padrão SDK costuma ser `tracesSampleRate: 1.0` (tudo) em dev e undefined em prod.

**Correção** — Sample adaptativo:

```typescript
Sentry.init({
  dsn, tracesSampler: (samplingContext) => {
    if (samplingContext.name?.includes("/api/health")) return 0.0;
    if (samplingContext.name?.includes("/api/custody") ||
        samplingContext.name?.includes("/api/swap")) return 1.0;
    return 0.1;
  },
});
```

Custódia/swap = 100% trace; resto 10%.

---

### 🟠 [20.5] **Alerts** sem canal de severidade

**Achado** — Sentry envia email para catch-all. Incidents P1 (financial) chegam com mesmo weight que P4 (console.warn).

**Correção** — Roteamento:

- **P1** (invariant violation, webhook failure > 10%, RPC error rate > 1%) → PagerDuty → SMS + phone call ao on-call.
- **P2** (latency degradation, single webhook fail) → Slack #incidents-p2.
- **P3+** (deprecation warning, non-critical error) → Email daily digest.

---

### 🟠 [20.6] **Status page** pública inexistente

**Achado** — Usuário não tem onde ver "Omni Runner está operacional?". Em outage, support tickets inundam.

**Correção** — `status.omnirunner.com` via Atlassian Statuspage, Better Stack, ou self-hosted Cachet. Feeds consumem Vercel + Supabase + Stripe status APIs + `/api/health`.

---

### 🟠 [20.7] **Backup testado** — zero evidence

**Achado** — Supabase PITR habilitado por default (verificar!), mas **processo de restore nunca testado** em game-day.

**Risco** — "Temos backup" é crença não-validada até o dia do disaster.

**Correção** — Quarterly restore drill:

1. Provisionar novo Supabase project (sandbox).
2. Restore PITR de T-24h.
3. Validar tabela-chave: `SELECT COUNT(*) FROM coin_ledger` == snapshot esperado.
4. Runbook `DR_PROCEDURE.md` atualizado após cada drill.

---

### 🟠 [20.8] **Post-mortem template** ausente

**Achado** — `docs/` não tem template de post-mortem blameless. Depois de incidente, aprendizado se perde.

**Correção** — `docs/postmortems/TEMPLATE.md` + diretório com PMs históricos. Estrutura Google SRE:

- Incident summary
- Timeline
- Root cause
- Trigger
- Resolution
- Action items (owner + deadline)
- Lessons learned

---

### 🟡 [20.9] **Chaos engineering** inexistente

**Achado** — Nenhum teste de caos (desligar Redis, matar worker, forcar lag DB).

**Correção** — Rodar mensalmente:

- Desabilitar Upstash Redis → confirmar rate-limit degrada graciosamente (mas ver [2.x] sobre fail-open).
- Matar Supabase Edge Function → verificar retries.

---

### 🟡 [20.10] **Logs de produção não-searchable**

**Achado** — Logs vão para Vercel Functions logs (3 dias retention) + Sentry. Não há Loki/CloudWatch/Datadog Logs com retention > 30 dias.

**Correção** — Vercel Log Drains → Datadog ou Axiom. Retention 30 dias para compliance, 1 ano para financeiros.

---

### 🟡 [20.11] **Cost observability** inexistente

**Achado** — Vercel + Supabase + Sentry + Upstash + Firebase + Resend/Postmark + outros — custos crescem invisível.

**Correção** — Mensal: CSV de invoice via APIs; planilha com cost-per-user-active; alertar quando cost/MAU cresce > 20% MoM.

---

### 🟡 [20.12] **Capacity planning** sem modelo

**Achado** — Quando escalar Supabase (db.micro → db.small)? Quando atingir quantos usuários? Sem projeção documentada.

**Correção** — `docs/CAPACITY_PLANNING.md` com curva: MAU × requests/MAU/mo × queries/request × cost/query → recomendação de tier Supabase para MAU = 10k, 50k, 200k.

---

### 🟡 [20.13] **Error budget policy** ausente

**Achado** — Sem policy "se consumiu 80% error budget, pausa deploys de features até restaurar".

**Correção** — `docs/ERROR_BUDGET_POLICY.md`. Automation: GitHub check bloqueia merge para main se error budget consumed > 80%.

---

## RESUMO PARTE 7 (40 itens)

| Severidade | Quantidade | IDs |
|---|---|---|
| 🔴 CRÍTICO | 8 | 17.1, 17.2, 18.1, 18.2, 18.3, 18.4, 19.1, 19.2, 19.3, 20.1, 20.2, 20.3 |
| 🟠 ALTO | 14 | 17.3–17.6, 18.5–18.8, 19.4–19.8, 20.4–20.8 |
| 🟡 MÉDIO | 13 | 17.7–17.9, 18.9, 18.10, 19.9, 19.10, 20.9–20.13 |

### Débitos arquiteturais estratégicos (ordem recomendada de ataque):

1. **[18.1] Two sources of truth** — resolve ou aceita. Com [12.1] (reconcile cron não agendado) é bomba-relógio. **Trimestre 1**.
2. **[18.2] Idempotency padronizada** — elimina classe inteira de bugs financeiros. **Trimestre 1**.
3. **[19.1]+[19.2] Partitioning de `coin_ledger`** — antes de atingir 50M rows; window de manutenção manejável. **Trimestre 2**.
4. **[20.1]+[20.2]+[20.3] Observabilidade completa** — dashboard + SLO + tracing. Sem isso, engineering vai às cegas. **Trimestre 1-2 em paralelo**.
5. **[18.3] Search-path hardening** — migration única, horas de trabalho, alto impacto de security. **Sprint atual**.
6. **[17.2] Bounded contexts** — conforme cresce time. **Contínuo**.

---

**CONTINUA NA PARTE 8 (FINAL)** — Lentes 21 (Atleta Profissional), 22 (Atleta Amador), 23 (Treinador de Corrida) — as três personas **explicitamente solicitadas** pelo usuário original, totalizando ~60 itens.

Digite **"continue"** para prosseguir para a PARTE 8 e fechar a auditoria.

 So the real issue is that `coin_ledger` uses a crude archive strategy—plain DELETE operations that leave behind bloat—rather than proper partitioning, and the table is constantly growing from new INSERTs. Now I can frame this for different stakeholder perspectives: VP Eng cares about operational risk and cost, Principal/DBA focuses on the technical debt and query performance implications, and SRE needs to understand the maintenance burden and failure modes.