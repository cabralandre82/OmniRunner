# AUDIT_LOGS Retention & Partitioning Runbook

> **Finding:** [L08-08](../audit/findings/L08-08-audit-logs-sem-retencao-particionamento.md) — `audit_logs` sem retenção / particionamento.
>
> **Escopo operacional:** retenção temporal (DELETE batched + pg_cron) e primitives de particionamento mensal para todas as tabelas de auditoria (`public.audit_logs`, `public.portal_audit_log`, `public.cron_edge_retry_attempts`, `public.wallet_drift_events`, `public.custody_daily_cap_changes`, `public.coin_ledger_pii_redactions`, `public.consent_events`).
>
> **CI guard:** `npm run audit:audit-logs-retention` (30+ invariantes estáticos).
>
> **Migração:** `supabase/migrations/20260421400000_l08_08_audit_logs_retention.sql`.

---

## 1. Por que este runbook existe

`audit_logs` é uma tabela de crescimento monotônico — cada ação do usuário, cada webhook, cada chamada admin insere uma linha. Sem um limite explícito, três problemas se acumulam:

- **Backup incha**: o dump diário cresce proporcionalmente. Depois de ~2 anos, `pg_dump` pode dobrar de duração.
- **Compliance fica lenta**: uma query de LGPD do tipo "todos os acessos ao registro do usuário X nos últimos 90 dias" faz seq scan numa tabela de 100M+ rows. Um _data subject access request_ que hoje leva 200 ms começa a levar minutos.
- **LGPD Art. 16 é violado**: a lei obriga retenção **limitada à finalidade**. "Guardamos para sempre" não é uma finalidade legítima — precisamos declarar janela.

A migração de L08-08 entrega os _primitives_ para retenção temporal hoje (config + cron + helper batched) e deixa pronto o pipeline para particionamento mensal amanhã (follow-up `L08-08-partition-audit-logs`, janela de manutenção).

Decisão deliberada: **retenção agora, particionamento depois**. Retenção reclama espaço imediatamente e não precisa de lock exclusivo. Conversão para `PARTITION BY RANGE (created_at)` precisa de um swap atomico de tabela (requer janela e coordenação); não queremos amarrar os dois.

---

## 2. Invariantes enforçados por CI

`npm run audit:audit-logs-retention` roda 30+ checks estáticos que falham se qualquer item abaixo regredir.

| # | Invariante | Por quê |
|---|---|---|
| 1 | Migração existe em `supabase/migrations/20260421400000_l08_08_audit_logs_retention.sql` | Rename silencioso perde o trail |
| 2 | `audit_logs_retention_config` tem `FORCE ROW LEVEL SECURITY` + policy service-role-only | Config com retention_days=1 em PR malicioso = DoS do audit trail |
| 3 | `retention_days` CHECK aceita NULL **ou** 30..3650 | Piso evita "keep 1 day" acidental; teto (~10 anos) prevenção anti-fat-finger |
| 4 | `batch_limit` CHECK 100..100000 | Batch pequeno demais = infinitos round-trips; grande demais = lock longo |
| 5 | `max_iterations` CHECK 1..200 | Teto evita cron que gira 1h numa tabela gigante |
| 6 | `audit_logs_retention_runs` é append-only (registrado em `audit_append_only_config`) | O próprio trail de retenção precisa ser inviolável |
| 7 | `fn_audit_reject_mutation` lê `audit.retention_pass` | Bypass existe somente dentro do helper |
| 8 | Bypass aceita **somente** literal `'on'` (não `'true'`, não `'1'`) | Reduz surface de fat-finger e remove ambiguidade de tipo |
| 9 | Bypass aplica **somente a DELETE** | UPDATE = falsificação do conteúdo, TRUNCATE = perda catastrófica; nenhum caminho legítimo de retenção precisa disso |
| 10 | Helper usa `set_config(..., true)` (txn-local) | `false` seria session-wide — bypass vazaria entre requisições |
| 11 | Helper escreve em `audit_logs_retention_runs` em todas as branches (ok, skipped_*, error) | Sem trail o operador vira cego |
| 12 | Seed cobre as 7 tabelas canônicas de auditoria | Drift de seed = nova tabela de auditoria entra em prod sem retenção |
| 13 | `consent_events` tem `retention_days IS NULL` | LGPD Art. 8 §6 obriga manter prova de consentimento enquanto o dado é tratado |
| 14 | Cron `audit-logs-retention-daily` agendado | Retenção precisa rodar sem intervenção humana |
| 15 | Cron `audit-logs-retention-next-month` agendado | Quando particionarmos, partição do mês seguinte tem que existir antes do mês virar |
| 16 | Helper é `SECURITY DEFINER` com `SET search_path` explícito | L18-03 hardening |
| 17 | Self-test prova que UPDATE nunca bypass-a | Guardrail contra regressão silenciosa do trigger |
| 18 | Self-test prova que DELETE sem bypass é bloqueado | Idem |
| 19 | Self-test prova que `consent_events` retorna `skipped_no_retention` | LGPD: não podemos deletar consent proof |
| 20 | Partition helper rejeita dates fora do primeiro dia do mês | Prevenção contra partições com boundaries esquisitos |
| 21 | Partition helper é no-op em tabela heap | Roda amanhã sem quebrar hoje |
| 22 | Partition helper exige `partstrat = 'r'` (RANGE) | LIST/HASH para audit_logs faria menos sentido e não é o caminho planejado |

---

## 3. Matriz de retenção (e de onde vem cada número)

| Tabela | Dias | Base legal / operacional |
|---|---:|---|
| `public.audit_logs` | 730 (~2 anos) | LGPD Art. 37 — janela de _accountability_ para ANPD. ISO 27001 5.28 exige trail ≥ 6 meses; o dobro de conforto sem incharmos demais. |
| `public.portal_audit_log` | 730 | Ações admin — mesma janela para parear incident forensics. |
| `public.cron_edge_retry_attempts` | 90 | Ops-only — cobre ciclo trimestral de SLO review. 90 dias é suficiente para investigar um pico de retry e jogar fora. |
| `public.wallet_drift_events` | 365 | Reconciliação anual de wallets (`reconcile-wallets-daily`) cruza contra dados do ano fiscal; 1 ano garante ao menos um ciclo completo. |
| `public.custody_daily_cap_changes` | 1825 (5 anos) | Lei 9.430/96 (IRPJ) — obrigação fiscal de 5 anos. Custódia envolve depósitos fiat, então o piso legal dita. |
| `public.coin_ledger_pii_redactions` | 1825 | Espelha `coin_ledger` (imutável por 5 anos). Redações têm que durar tanto quanto o que elas redigem. |
| `public.consent_events` | **NULL** (forever) | LGPD Art. 8 §6 — controlador tem ônus de provar que consentimento foi obtido **enquanto o dado for tratado**. Não temos janela fechada; só podemos deletar quando o usuário for totalmente removido via `fn_delete_user_data` (L04-01), e aí a linha cai junto do usuário. |

Trocar qualquer número acima: editar a config (via `UPDATE public.audit_logs_retention_config`) ou editar o seed no PR que move a constante. Qualquer valor fora de 30..3650 dias é rejeitado pelo CHECK (ou NULL); fat-finger impossível por construção.

---

## 4. Contratos das funções públicas

### `public.fn_audit_retention_delete_batch(p_schema text, p_table text) → jsonb`

Deleta linhas de `<schema>.<table>` onde `created_at < now() - retention_days` em batches de `batch_limit` (default 10k) até `max_iterations` (default 20) ou até não sobrar nada.

**Retorno:**
```json
{
  "status":       "ok|skipped_*|error",
  "rows_deleted": 12345,
  "iterations":   3,
  "cutoff_at":    "2024-04-21T00:00:00Z",
  "error":        null
}
```

**Statuses:**
- `ok` — deletou (inclusive 0 rows se nada era velho);
- `skipped_no_retention` — sem config, ou `retention_days IS NULL` (forever);
- `skipped_disabled` — config existe mas `enabled=false` (freeze);
- `skipped_no_table` — tabela não existe neste env;
- `skipped_no_column` — tabela existe mas não tem `timestamp_column`;
- `error` — algo estourou; ver `error_message` em `audit_logs_retention_runs`.

**Propriedades de segurança:**
- Usa `set_config('audit.retention_pass', 'on', true)` → txn-local. Bypass evapora no COMMIT.
- Bypass é honrado só por DELETE; UPDATE/TRUNCATE ainda explodem com P0010.
- SECURITY DEFINER com `search_path = public, pg_catalog, pg_temp`. Função é owned por `postgres`; roda como ele para poder emitir DELETE ignorando RLS.

### `public.fn_audit_retention_run_all() → jsonb`

Dispatcher chamado por `cron 15 5 * * *`. Itera `audit_logs_retention_config WHERE enabled=true AND retention_days IS NOT NULL`, chama o helper por linha. Uma tabela falhando não bloqueia as outras.

Protegido por `pg_try_advisory_xact_lock(8082408808::bigint)` — dois workers concorrentes não processam a mesma tabela.

### `public.fn_audit_ensure_monthly_partition(p_schema text, p_table text, p_month_start date) → jsonb`

Idempotente. Cria partição filha `<table>_yYYYYmMM` cobrindo `[p_month_start, p_month_start + 1 month)` **se** `<schema>.<table>` for RANGE partitioned. Caso contrário: `skipped_not_partitioned` (no-op benigno).

Usado dentro de `fn_audit_retention_ensure_next_month_all`, que pg_cron chama dia 25 de cada mês às 02:00 UTC — garante que a partição do mês seguinte exista com ~6 dias de folga.

### `public.fn_audit_retention_assert_shape() → void`

Levanta P0010 se: config tem <7 rows, alguma das 7 canônicas sumiu, `consent_events` deixou de ser `NULL`, ou `audit_logs_retention_runs` perdeu o guard append-only. Chamada pelo CI via psql; versão estática roda em `check-audit-logs-retention.ts` sem precisar de DB.

---

## 5. How-to

### 5.1 Adicionar uma nova tabela de auditoria ao regime de retenção

1. **Registrar append-only** (se ainda não):
   ```sql
   SELECT public.fn_audit_install_append_only_guard('public', 'minha_tabela_audit',
     'Added 2026-05-01 for feature X — see ADR-123');
   ```
2. **Inserir config**:
   ```sql
   INSERT INTO public.audit_logs_retention_config
     (schema_name, table_name, retention_days, note)
   VALUES
     ('public', 'minha_tabela_audit', 730,
      'LGPD accountability — 2 anos, alinhado com audit_logs');
   ```
3. **Atualizar o seed** da migração L08-08 (adicionar no `INSERT ... ON CONFLICT`) e o array `v_known` de `fn_audit_assert_append_only_shape` na migração L10-08 (ou re-declarar em uma nova migration).
4. **Rodar** `npm run audit:audit-logs-retention` — o guard força seed coerente com a migration.
5. **Runbook**: adicionar linha na §3 com a base legal.

### 5.2 Mudar a janela de retenção de uma tabela

```sql
UPDATE public.audit_logs_retention_config
   SET retention_days = 1095,      -- 3 years
       note = note || E'\n- 2026-07-14 bumped para 3 anos por parecer DPO'
 WHERE schema_name = 'public' AND table_name = 'audit_logs';
```

O CHECK constraint rejeita valores fora de `[30, 3650]`. Para `consent_events`: qualquer `UPDATE ... SET retention_days = <n>` onde n≠NULL será rejeitado pelo CI guard (que roda em todo PR).

### 5.3 Pausar retenção de uma tabela temporariamente (forensic freeze)

```sql
UPDATE public.audit_logs_retention_config
   SET enabled = false,
       note = note || E'\n- FROZEN 2026-07-14 incident #INC-4231'
 WHERE schema_name = 'public' AND table_name = 'audit_logs';
```

Próximo cron vai registrar `status=skipped_disabled` — visível no dashboard.

### 5.4 Rodar uma limpeza manual (fora do cron)

```sql
SELECT public.fn_audit_retention_delete_batch('public', 'cron_edge_retry_attempts');
```

Log sai em `audit_logs_retention_runs`. Segurança: usa mesmo bypass txn-local.

### 5.5 Ensaiar a próxima partição (antes da conversão da tabela live)

```sql
SELECT public.fn_audit_ensure_monthly_partition(
  'public', 'audit_logs_retention_runs',
  date_trunc('month', now() + interval '1 month')::date
);
```

Retorno esperado hoje: `{"status": "skipped_not_partitioned"}`. Depois do follow-up de particionamento: `{"status": "created", "partition": "public.audit_logs_retention_runs_y2026m05"}`.

---

## 6. Playbooks operacionais

### 6.1 "Retenção não rodou ontem"

**Detecção:** Alerta `audit-logs-retention-daily` no `cron-health-monitor` (L06-04) acusa `last_run > 25h`.

**Triagem:**
```sql
SELECT schema_name, table_name, ran_at, status, error_message
  FROM public.audit_logs_retention_runs
 ORDER BY ran_at DESC
 LIMIT 20;
```

- Se TODAS as tabelas mostram `skipped_locked`: o advisory lock anterior não liberou (crash durante a run). Sintomas: linhas antigas em `pg_stat_activity` com `state=idle in transaction`. Remediação: `SELECT pg_terminate_backend(pid)` na sessão órfã; rodar manualmente o dispatcher.
- Se só UMA tabela falhou com `status=error`: ler `error_message`. Casos comuns:
  - `permission denied` → postgres não possui a tabela (acontece com `public.audit_logs` platform-managed em alguns envs). Solução: trocar `SECURITY DEFINER` ownership ou marcar `enabled=false` nesse env.
  - `deadlock` → colisão com outro DDL; inofensivo, próximo cron resolve.
- Se o cron nem existe (`SELECT * FROM cron.job WHERE jobname='audit-logs-retention-daily'` vazio): re-executar a migração.

### 6.2 "Tabela de auditoria está explodindo apesar da retenção"

**Sintoma:** `audit_logs` > 50 GB e crescendo. `audit_logs_retention_runs` mostra `rows_deleted > 0` todo dia.

**Diagnóstico:** Taxa de insert superou a janela de retenção × batch capacity. Opções (em ordem crescente de impacto):

1. **Aumentar `batch_limit`** para 50k → mais linhas por iteração.
2. **Aumentar `max_iterations`** para 100 → processa mais tempo.
3. **Encurtar `retention_days`** (com aprovação DPO/legal — LGPD pede justificativa).
4. **Disparar follow-up de particionamento** (`L08-08-partition-audit-logs`) — DROP PARTITION é O(1), reclama espaço instantaneamente.

Não use TRUNCATE nem VACUUM FULL em `audit_logs` sem janela de manutenção: trigger append-only bloqueia TRUNCATE (bom), e VACUUM FULL pega AccessExclusiveLock.

### 6.3 "Preciso encurtar retenção por ordem judicial / DPO urgência"

Ex.: decisão anoniminação de usuário nomeado. Não use retenção geral — use `fn_delete_user_data` (L04-01), que é cirúrgica. Mas se for _toda_ a tabela:

```sql
BEGIN;
UPDATE public.audit_logs_retention_config
   SET retention_days = 90,
       note = note || E'\n- 2026-07-14 cumprimento ordem #XYZ'
 WHERE schema_name = 'public' AND table_name = 'audit_logs';

-- Rodar imediatamente em vez de esperar 05:15 UTC:
SELECT public.fn_audit_retention_delete_batch('public', 'audit_logs');
COMMIT;
```

Deixar o `UPDATE` + `SELECT` na MESMA transação: se o helper quebrar no meio, o update é revertido e retenção volta ao anterior.

### 6.4 "Bypass GUC vazou para uma sessão normal" (nunca deve acontecer)

Sintoma: usuário admin reporta que conseguiu `DELETE FROM audit_logs` via Supabase Studio.

**Diagnóstico imediato:**
```sql
SHOW audit.retention_pass;
-- esperado: '' (empty) — qualquer outra coisa é o incidente.
```

Como pode ter acontecido:
1. Alguém mudou `set_config(..., false)` no helper (guard do CI deveria ter pego — investigar PR).
2. Alguém adicionou `ALTER DATABASE ... SET audit.retention_pass = 'on'` (revertir imediatamente com `ALTER DATABASE ... RESET audit.retention_pass`).

**Mitigação:**
```sql
ALTER DATABASE postgres RESET audit.retention_pass;
-- Revalidar trigger:
SELECT public.fn_audit_assert_append_only_shape();
```

E abrir post-mortem — é um incidente de segurança (trilha de auditoria foi mutável durante a janela do vazamento).

### 6.5 "Janela de conversão: migrar audit_logs para RANGE partitioned"

Quando `audit_logs > 50M rows`, a follow-up `L08-08-partition-audit-logs` passa a valer a pena. Passos (alto nível, detalhados no PR de conversão):

1. Criar nova `public.audit_logs_partitioned` RANGE PARTITIONED BY `created_at`.
2. Criar partições filhas para os 25 meses cobertos (retention_days 730 + folga).
3. `INSERT INTO audit_logs_partitioned SELECT * FROM audit_logs` em chunks.
4. Trocar nome atomicamente em maintenance window.
5. CI guard `audit:audit-logs-retention` continua verde — nada muda do lado do config/helpers.
6. `fn_audit_retention_ensure_next_month_all` já começa a criar partição do próximo mês automaticamente no dia 25.

DROP PARTITION velha passa a ser O(1) em vez de DELETE O(N).

---

## 7. Detection signals

- **`cron.job_run_details`** — `audit-logs-retention-daily` com status `failed` ou duração crescente.
- **Alert em Logflare**: gatilho quando aparece `L08-08: retention on ... failed` em WARNING.
- **Query de saúde**:
  ```sql
  SELECT schema_name, table_name, max(ran_at) AS last_run,
         max(ran_at) FILTER (WHERE status='ok') AS last_ok,
         (now() - max(ran_at)) > interval '26 hours' AS stale
    FROM public.audit_logs_retention_runs
   GROUP BY 1, 2
   ORDER BY stale DESC, last_run;
  ```
- **PostHog:** próximo follow-up `L08-08-posthog` emite `audit.retention.run_completed` para dashboard de ops.

---

## 8. Rollback

A migração é aditiva e reversível. Para pausar 100% da retenção sem reverter:

```sql
UPDATE public.audit_logs_retention_config SET enabled = false;
-- Ou remover o cron:
SELECT cron.unschedule('audit-logs-retention-daily');
SELECT cron.unschedule('audit-logs-retention-next-month');
```

Rollback completo via migração reversa (dropar funções + tabelas + cron + reverter `fn_audit_reject_mutation` para versão L10-08 sem bypass). Consequência: retenção cessa, append-only permanece armado. Aceitável em emergência.

---

## 9. Cross-references

- **L10-08** (`AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md`) — irmão que protege UPDATE/DELETE; L08-08 cria a única exceção controlada (DELETE retention-scoped).
- **L19-06** (`check-audit-logs-gin.ts`) — índice GIN em `audit_logs.metadata`; quando particionarmos, índice precisa ser recriado por partição (callout já está no header do migration L19-06).
- **L04-07** (`ledger_reason_pii_guard.sql`) — redações de PII; `coin_ledger_pii_redactions` compartilha janela 5 anos fiscal.
- **L12-06** (`archive-old-sessions`) — mesmo padrão de cron batched, mas para dados de produto, não auditoria.
- **L04-01** (`fn_delete_user_data`) — LGPD Art. 18 "right to erasure"; retenção ≠ erasure. Usuário pedindo remoção aciona o fn_delete; retenção cuida do fluxo comum.
- **L06-04** (`cron-health-monitor`) — já alerta `audit-logs-retention-daily` se parar de rodar.
- **L18-03** (security_definer search_path hardening) — helper + dispatcher respeitam o padrão `SET search_path = public, pg_catalog, pg_temp`.

---

## 10. Follow-ups explícitos (tracked)

| ID | Descrição | Blocker |
|---|---|---|
| `L08-08-partition-audit-logs` | Converter `public.audit_logs` para RANGE partitioned by `created_at`. Requer janela de manutenção + lock swap. | Volume (hoje ~2M rows; acionamos quando passar 50M) |
| `L08-08-partition-portal-audit-log` | Idem para `portal_audit_log`. | Volume |
| `L08-08-posthog` | Emitir `audit.retention.run_completed` para dashboard ops. | Priorização do time de Observabilidade |
| `L08-08-dashboard` | View materializada `audit_retention_daily_summary` para coach/admin dashboard. | Priorização de produto |
