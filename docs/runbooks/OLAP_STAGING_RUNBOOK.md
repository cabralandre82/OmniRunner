# OLAP staging runbook — L08-06

> **Escopo:** camada de staging analítica (`public_olap.*`) que isola
> dashboards `/platform/*` dos OLTPs críticos (`sessions`, `coin_ledger`,
> `custody_accounts`).
>
> **Finding:** [`docs/audit/findings/L08-06-sem-staging-de-data-warehouse-queries-olap-contra.md`](../audit/findings/L08-06-sem-staging-de-data-warehouse-queries-olap-contra.md)
>
> **Guard CI:** `npm run audit:olap-staging`
>
> **Migration:** `supabase/migrations/20260421410000_l08_06_olap_staging.sql`

---

## 1. Por que essa camada existe

Antes desta entrega, `/platform/page.tsx` (dashboard da plataforma)
executava consultas do tipo `count(*)` e agregações contra `public.sessions`,
`public.coin_ledger` e `public.custody_accounts` diretamente, no mesmo
cluster onde as RPCs transacionais (`execute_burn_atomic`,
`reverse_coin_emission_atomic`, `settle_challenge_atomic`) correm.

Isso causou pelo menos um incidente de produção — BI pesado em hora de pico
segurou lock em `coin_ledger`, fazendo RPCs críticos bloquearem e pedidos
de clientes voltarem com timeout. A correção "de verdade" é uma réplica OLAP
dedicada (pg_logical, FDW ou export para DuckDB/BigQuery), mas isso é
trabalho de infra com janela de manutenção.

Esta entrega é a camada mínima viável que **já elimina o risco** sem
depender de infra:

- Um schema dedicado `public_olap` com **materialized views** pré-agregadas.
- Refresh periódico (a cada 15 minutos por padrão) via `pg_cron`, usando
  `REFRESH MATERIALIZED VIEW CONCURRENTLY` — leitores não bloqueiam durante
  o refresh.
- `statement_timeout` por MV — um refresh que degenere não consegue
  segurar lock em OLTP por minutos.
- Consumidores `/platform/*` passam a ler **da MV**, não do OLTP. Isso
  é migração incremental, PR a PR. A camada já está no ar e nenhum
  consumidor precisa usá-la imediatamente.

Quando a réplica dedicada for shippada (follow-up `L08-06-read-replica`),
esta camada fica como cache rápido local — complementar, não conflitante.

---

## 2. Arquitetura (invariantes enforced em CI)

O guard `npm run audit:olap-staging` falha fechado se qualquer um destes
invariantes regredir (66 checks):

### Grants (nunca expor agregado plataforma-inteiro)

- `public_olap` recusa USAGE para `PUBLIC`, `anon`, `authenticated`.
- Somente `service_role` tem USAGE no schema e SELECT nas MVs.
- `ALTER DEFAULT PRIVILEGES` protege MVs futuras — qualquer CREATE
  MATERIALIZED VIEW nova no schema herda a trava.

### MVs obrigatórias

| MV                                   | Chave única             | OLTP origem         | Refresh   |
|--------------------------------------|-------------------------|---------------------|-----------|
| `mv_sessions_completed_daily`        | `(day_utc_epoch)`       | `sessions` (status≥3) | 15 min |
| `mv_coin_ledger_daily_by_reason`     | `(day_utc_epoch, reason)` | `coin_ledger`     | 15 min |
| `mv_custody_accounts_snapshot`       | `(group_id)`            | `custody_accounts`  | 15 min    |

Cada MV **precisa** ter `UNIQUE INDEX` — o guard falha se o índice sumir.
Sem UNIQUE INDEX, `REFRESH MATERIALIZED VIEW CONCURRENTLY` degenera para
refresh bloqueante (exclusive lock), que é exatamente o que L08-06
previne.

### Helper `fn_refresh_mv(mv_name)`

- `SECURITY DEFINER` com `SET search_path` explícito.
- `set_config('statement_timeout', …, true)` — txn-local, nunca session.
- Advisory lock por MV (`pg_try_advisory_xact_lock` com hash de
  `olap:<mv_name>`) — duas instâncias simultâneas não podem tentar
  o mesmo refresh.
- Too-soon guard: se o último `started_at` com `status='ok'` é mais
  recente que `refresh_interval_seconds`, retorna `skipped_too_soon`
  sem fazer refresh. Isso neutraliza loops ou botões "atualizar" mal
  comportados.
- Primeiro refresh (`pg_matviews.ispopulated = false`) é **sempre**
  não-concurrent, porque `REFRESH … CONCURRENTLY` não funciona em MV
  sem dados. Subsequentes são concurrent.
- Todo desfecho (ok, skipped_*, error) é registrado em `mv_refresh_runs`.
- Execução concedida apenas a `service_role`.

### Dispatcher `fn_refresh_all()`

- `SECURITY DEFINER`, advisory lock global — duas `fn_refresh_all`
  simultâneas não existem.
- Itera apenas `enabled = true`.
- Exceção em uma MV é isolada: o dispatcher continua com as outras e
  registra a falha como `status='error'` em `mv_refresh_runs`.

### Trilha `mv_refresh_runs`

- Registrada em `public.audit_append_only_config` (L10-08).
- Trigger `trg_*_append_only_*` bloqueia DELETE/UPDATE/TRUNCATE com
  SQLSTATE `P0010`.
- Índice `(mv_name, started_at DESC)` — queries operacionais rápidas.
- **Retention não configurada em L08-08 por default** (keep forever).
  Se o volume passar a incomodar, adicionar linha em
  `public.audit_logs_retention_config` (requer ADR, porque troca a
  postura de "forever" para "n dias").

### pg_cron

- Schedule `olap-refresh-all` a cada 15 minutos (`*/15 * * * *`).
- Invoca `public_olap.fn_refresh_all()`.
- Migration é idempotente (faz `cron.unschedule` antes de
  `cron.schedule`).

### Self-test na migration

- `fn_olap_assert_shape()` executado após COMMIT.
- Refresh de MV inexistente → `skipped_no_config`.
- Dois refreshes consecutivos → segundo é `skipped_too_soon`.
- DELETE em `mv_refresh_runs` bloqueado com `P0010`.
- Dispatcher retorna `status='ok'` ou `'skipped_locked'`.

---

## 3. Como usar (consumidores `/platform/*`)

O padrão de migração incremental:

**Antes (OLTP hit):**

```ts
const { count: weekSessions } = await supabase
  .from("sessions")
  .select("id", { count: "exact", head: true })
  .gte("start_time_ms", weekStart)
  .gte("status", 3);
```

**Depois (MV hit):**

```ts
const weekStartEpoch = Math.floor(weekStart / 86_400_000);
const { data } = await supabase
  .from("mv_sessions_completed_daily")
  .select("sessions_count")
  .gte("day_utc_epoch", weekStartEpoch);

const weekSessions = (data ?? []).reduce((s, r) => s + (r.sessions_count ?? 0), 0);
```

> Atenção: a MV é um snapshot com até 15 minutos de latência. Isso é
> aceitável para BI; **não é aceitável** para telas transacionais
> (checkout, saldo em tempo real, etc). Se dúvida, não migre.

Schema da tabela via Supabase: configure um tipo gerado apontando para
`public_olap.mv_*`. Como o schema é `public_olap` (não `public`), o
client precisa usar `supabase.schema('public_olap').from('mv_*')`.

---

## 4. Como operar

### 4.1 Forçar um refresh ad-hoc (sem esperar o cron)

```sql
SELECT public_olap.fn_refresh_mv('mv_sessions_completed_daily');
```

Resposta típica:

```json
{
  "mv_name": "mv_sessions_completed_daily",
  "status": "ok",
  "duration_ms": 1240,
  "rows_in_mv": 342,
  "error_message": null
}
```

Se retornar `skipped_too_soon`, o guard interno está funcionando — ainda
não passou a janela de `refresh_interval_seconds`. Para ignorar o guard,
atualize a config:

```sql
UPDATE public_olap.mv_refresh_config
   SET refresh_interval_seconds = 60
 WHERE mv_name = 'mv_sessions_completed_daily';
-- depois do trabalho, restaure o default:
UPDATE public_olap.mv_refresh_config
   SET refresh_interval_seconds = 900
 WHERE mv_name = 'mv_sessions_completed_daily';
```

### 4.2 Pausar uma MV

```sql
UPDATE public_olap.mv_refresh_config
   SET enabled = false,
       note = note || ' [PAUSED: <motivo> em <data>]'
 WHERE mv_name = 'mv_sessions_completed_daily';
```

A trilha `mv_refresh_runs` continuará registrando `skipped_disabled` nas
invocações do dispatcher.

### 4.3 Adicionar uma nova MV

1. Numa nova migration (`YYYYMMDDHHMMSS_l08_06_mv_foo.sql`):
   - `CREATE MATERIALIZED VIEW IF NOT EXISTS public_olap.mv_foo AS …
     WITH NO DATA;`
   - `CREATE UNIQUE INDEX IF NOT EXISTS mv_foo_pk ON public_olap.mv_foo (…);`
   - `INSERT INTO public_olap.mv_refresh_config
       (mv_name, enabled, refresh_interval_seconds, statement_timeout_ms, concurrent, note)
       VALUES ('mv_foo', true, 900, 30000, true, 'L08-06: descrição');`
2. Atualize `fn_olap_assert_shape()` para incluir `mv_foo` em `v_known`.
3. Atualize `tools/audit/check-olap-staging.ts` — adicione `mv_foo` na
   lista de MVs canônicas e um check específico de seed.
4. Atualize a seção §2 deste runbook.

### 4.4 Rodar o dispatcher manualmente

```sql
SELECT public_olap.fn_refresh_all();
```

### 4.5 Inspecionar trilha

```sql
SELECT mv_name, started_at, duration_ms, status, rows_in_mv, error_message
  FROM public_olap.mv_refresh_runs
 ORDER BY started_at DESC
 LIMIT 50;
```

### 4.6 Ver quando será o próximo refresh elegível

```sql
SELECT c.mv_name,
       max(r.started_at)                                            AS last_ok,
       max(r.started_at) + make_interval(secs => c.refresh_interval_seconds)
         AS next_eligible_at
  FROM public_olap.mv_refresh_config c
  LEFT JOIN public_olap.mv_refresh_runs r
    ON r.mv_name = c.mv_name AND r.status = 'ok'
 GROUP BY c.mv_name, c.refresh_interval_seconds;
```

---

## 5. Playbooks

### 5.1 "Dashboard `/platform` está lento de novo"

1. Conferir se o consumidor migrou para a MV:
   ```bash
   rg "from\((coin_ledger|custody_accounts|sessions)" portal/src/app/platform
   ```
   Se ainda há acesso direto, abrir PR para migrar.
2. Conferir saúde do refresh:
   ```sql
   SELECT mv_name, status, duration_ms, error_message
     FROM public_olap.mv_refresh_runs
    WHERE started_at > now() - interval '2 hours'
    ORDER BY started_at DESC;
   ```
   Muito `status='error'`? Veja §5.2.
3. Conferir se cron está executando:
   ```sql
   SELECT jobname, schedule, active, last_start_at
     FROM cron.job
    WHERE jobname = 'olap-refresh-all';
   ```

### 5.2 "`mv_refresh_runs` com status=error"

1. Ler `error_message` da linha mais recente.
2. Casos comuns:
   - `canceling statement due to statement timeout` → aumentar
     `statement_timeout_ms` da config, **ou** (melhor) investigar por
     que o `SELECT` da MV ficou lento. Índice faltando no OLTP? Tabela
     inchada precisando de `VACUUM`?
   - `could not obtain lock on materialized view` → outro refresh em
     andamento; espera. Se persistir, veja §5.3.
3. Uma MV em erro não afeta as outras (dispatcher isola). Mas se ela
   nunca atualiza, os consumidores começam a ver dados stale. Priorize.

### 5.3 "Refresh trava / não termina"

1. `SELECT pid, state, query_start, query FROM pg_stat_activity
      WHERE query LIKE 'REFRESH MATERIALIZED VIEW%';`
2. Confirme se está segurando lock em alguma OLTP:
   `SELECT * FROM pg_locks WHERE pid = <pid>;`
3. Se estiver segurando OLTP em horário de pico, **cancele**:
   `SELECT pg_cancel_backend(<pid>);` (não use `pg_terminate_backend`
   a menos que `pg_cancel` não resolva).
4. Pause a MV (§4.2) até entender a causa raiz.
5. O advisory lock por MV impede uma segunda tentativa concorrente;
   depois do cancelamento, o próximo tick do cron refaz.

### 5.4 "Quero remover uma MV"

1. `DELETE FROM public_olap.mv_refresh_config WHERE mv_name = 'mv_xxx';`
   (sem isso, o dispatcher tenta refresh em MV inexistente e registra
   `skipped_no_mv` — limpo mas confuso).
2. `DROP MATERIALIZED VIEW public_olap.mv_xxx;` em nova migration.
3. Remova `mv_xxx` de `fn_olap_assert_shape().v_known` e do CI guard.

### 5.5 "Quero cancelar o cron todo"

```sql
SELECT cron.unschedule('olap-refresh-all');
```

Consumidores passam a ver dados cada vez mais stale. Invariantes de
estrutura continuam válidos (CI não quebra). Reativar:

```sql
SELECT cron.schedule('olap-refresh-all', '*/15 * * * *',
  $$ SELECT public_olap.fn_refresh_all(); $$);
```

### 5.6 "Precisa fazer `REFRESH` blocking por algum motivo"

```sql
UPDATE public_olap.mv_refresh_config
   SET concurrent = false
 WHERE mv_name = 'mv_xxx';

SELECT public_olap.fn_refresh_mv('mv_xxx');

UPDATE public_olap.mv_refresh_config
   SET concurrent = true
 WHERE mv_name = 'mv_xxx';
```

> Blocking refresh toma AccessExclusiveLock no MV, impedindo leitores.
> Só use em janela de manutenção ou se a MV for pequena e não estiver
> no caminho quente de `/platform`.

---

## 6. Trade-offs e decisões explícitas

1. **MVs em mesmo cluster, não réplica dedicada.** Shipping uma réplica
   é trabalho de infra; MVs entregam ~80% do isolamento hoje. Follow-up:
   `L08-06-read-replica`.
2. **15 minutos de lag.** Dashboards `/platform` toleram esse atraso.
   Se algum consumidor precisar de "agora", ele deve continuar batendo
   OLTP direto (não migre esse).
3. **Só `service_role` pode ler.** MVs contêm agregados plataforma-inteira
   (ex.: receita total). Conceder a `authenticated` seria vazar dados
   de outros grupos. Qualquer necessidade de exposição passa por novo
   endpoint API com filtro por tenant.
4. **`mv_refresh_runs` keep-forever.** Trilha de observabilidade é
   pequena (~1 linha por MV por tick, 4 × 3 × 24 × 30 = ~8.640/mês).
   Se incomodar, configurar retention via L08-08.
5. **Advisory locks em vez de `LOCK TABLE`.** `REFRESH CONCURRENTLY` já
   garante non-blocking; o advisory lock só impede duas tentativas
   de refresh da mesma MV. Barato e robusto.
6. **`set_config(..., true)`** em vez de `SET` session-wide para
   `statement_timeout` — o mesmo padrão de L08-08 para `audit.retention_pass`.
   Nada vaza entre conexões.

---

## 7. Cross-links

- Finding: [`L08-06`](../audit/findings/L08-06-sem-staging-de-data-warehouse-queries-olap-contra.md)
- Migration: `supabase/migrations/20260421410000_l08_06_olap_staging.sql`
- Guard CI: `tools/audit/check-olap-staging.ts` (`npm run audit:olap-staging`)
- Sibling **L10-08** (append-only registry) —
  [`AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md`](./AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md)
  (instala trigger em `mv_refresh_runs`).
- Sibling **L08-08** (audit_logs retention/partitioning) —
  [`AUDIT_LOGS_RETENTION_RUNBOOK.md`](./AUDIT_LOGS_RETENTION_RUNBOOK.md)
  (primitivas usadas se quisermos adicionar retention em
  `mv_refresh_runs` no futuro).
- Follow-up `L08-06-read-replica` — substituir/complementar este layer
  com réplica pg_logical quando a infra permitir.
- Follow-up `L08-06-portal-migrate` — migrar consumidores `/platform/*`
  para apontar às MVs (PRs pequenos, um por dashboard).
