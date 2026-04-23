# Ledger PII Redaction Runbook (L04-07)

> **Escopo:** `public.coin_ledger`, `public.coin_ledger_archive`,
> `public.coin_ledger_pii_redactions` · **Persona:** LGPD Officer / Ops CFO /
> DBA · **Onda:** 1 · **Severidade:** 🟠 High · **Última revisão:**
> 2026-04-21

## 0. O que essa migration (L04-07) protege

A tabela `public.coin_ledger` é **imutável contábil** — linhas jamais são
deletadas, mesmo após o usuário exercer o direito ao esquecimento (LGPD
Art. 18 VI). O que fazemos é anonimizar `user_id → zero-UUID` via
`fn_delete_user_data` (Category B).

O problema original: colunas `reason` e `note` permitiam free-form text e
**funções históricas** (`execute_burn_atomic` pré-L03-02, reconcilers,
corretores manuais) podiam inserir nome/email/CPF via `format(...)`.
Resultado: após anonimização, um `SELECT * FROM coin_ledger WHERE user_id =
'00000000-…'::uuid` ainda exibia o nome do atleta.

A L04-07 fecha o problema em **4 camadas**:

1. **CHECK constraints preventivos**
   - `coin_ledger_reason_length_guard`  — reason ≤ 64 chars.
   - `coin_ledger_reason_pii_guard`     — sem `@`, sem `by user <uuid>`,
     sem `from <Nome> <Sobrenome>`.
   - `coin_ledger_note_pii_guard` (se coluna existir) — note ≤ 200 chars,
     sem `@`, sem `name=|email=|cpf=|phone=`.
   - Espelhos em `coin_ledger_archive`.
2. **Backfill defensivo** aplicado one-shot na própria migration: toda
   linha que violar os guards é redigida para `admin_adjustment` /
   `[redacted-pii]` com trilha em `public.coin_ledger_pii_redactions`.
3. **Helper reutilizável** `public.fn_redact_ledger_pii_for_user(p_user_id,
   p_actor)` — chamada pelo fluxo LGPD de erasure ou por ops em
   investigação de vazamento. Idempotente.
4. **Trigger safety-net** `trg_ledger_pii_redact_on_erasure` em
   `audit_logs`: dispara a redação automaticamente quando uma
   `user.self_delete.completed` é registrada (cobre erasures parciais
   herdadas de v1.x).
5. **CI lint** `npm run audit:ledger-reason`: bloqueia migrations novas
   que tentem inserir `reason` via `format(…)`, `||` ou literais fora da
   whitelist canônica.

## 1. Whitelist canônica de `reason`

A fonte canônica é `supabase/migrations/20260421130000_l03_reverse_coin_flows.sql`
(constraint `coin_ledger_reason_check`) espelhada em
`tools/audit/check-ledger-reason-safety.ts` (const `CANONICAL_REASONS`).
Atualizar os dois em **lockstep** no mesmo commit — o CI valida drift.

Ao adicionar uma nova reason-class:

1. Adicione o literal a **ambos** arquivos.
2. Descreva no finding/commit porque é semanticamente diferente das
   existentes.
3. Cubra com teste em `tools/test_*.ts` que exercita o INSERT.
4. Execute `npm run audit:ledger-reason` localmente → esperar
   `[L04-07 lint] OK`.

## 2. Quando uma CHECK bloquear um INSERT em produção

**Sintoma:** função financeira retorna erro SQLSTATE `23514`, mensagem
"violates check constraint coin_ledger_reason_\*_guard" ou
"coin_ledger_reason_check".

**Causa comum:**
- Código novo tentando inserir `reason` fora da whitelist.
- Código legacy usando `format('... %s by %s', …)` com nome/email.
- Campo `note` recebendo dump acidental de `row_to_json(NEW)`.

**Resposta:**
1. Capturar a stack completa no Sentry (inclui SQL + bind values).
2. Identificar o caller e **não tentar** afrouxar o CHECK — abra um
   finding/ticket dedicado.
3. Se urgente (prod-block), substituir a reason pelo valor canônico mais
   próximo (tipicamente `admin_adjustment`) e mover o contexto para
   `audit_logs.metadata` (jsonb) ou para o campo semanticamente correto
   (ex. `ref_id` para IDs).

## 3. Quando executar `fn_redact_ledger_pii_for_user` manualmente

**Cenário A — investigação de vazamento LGPD:**
```sql
-- DBA com service_role. Substitua p_user_id pelo alvo.
SELECT public.fn_redact_ledger_pii_for_user(
  'uuid-do-usuario'::uuid,
  'uuid-do-operador'::uuid
);
```

O retorno é um `jsonb` com contadores:
```json
{
  "user_id": "...",
  "started_at": "...",
  "function_version": "1.0.0",
  "coin_ledger_reason_redacted": 3,
  "coin_ledger_note_redacted": 1,
  "coin_ledger_archive_reason_redacted": 0,
  "completed_at": "..."
}
```

**Cenário B — after-the-fact erasure:** um erasure antigo (pré-L04-07)
anonimizou `user_id` mas deixou PII em `reason`/`note`. Depois do deploy,
rode a função para todos os usuários anonimizados:

```sql
-- 1. Captura usuários anonimizados que ainda têm PII residual
WITH residual AS (
  SELECT DISTINCT user_id FROM public.coin_ledger
   WHERE user_id = '00000000-0000-0000-0000-000000000000'::uuid
     AND (position('@' in reason) > 0
          OR reason ~* '\mby user [0-9a-f]{8,}'
          OR reason ~* '\mfrom [A-Z][a-z]+ [A-Z][a-z]+')
)
SELECT count(*) FROM residual;  -- deve ser 0 após redação ativa.

-- 2. Aplica em lote (para cada user_id real conhecido no audit_logs)
DO $$
DECLARE r uuid;
BEGIN
  FOR r IN
    SELECT DISTINCT target_user_id FROM public.audit_logs
     WHERE action IN ('user.self_delete.completed',
                      'user.deleted_by_admin')
       AND target_user_id IS NOT NULL
  LOOP
    PERFORM public.fn_redact_ledger_pii_for_user(r, NULL);
  END LOOP;
END $$;
```

**Cenário C — integração com novo fluxo de erasure:** se você está
adicionando um novo caminho de deleção (ex. GDPR via parceiro EU), garanta
que ele emite `audit_logs.action = 'user.self_delete.completed'` — o
trigger `trg_ledger_pii_redact_on_erasure` cobre automaticamente.

## 4. Auditoria — `coin_ledger_pii_redactions`

Toda redação gera uma linha em
`public.coin_ledger_pii_redactions`:

| coluna            | conteúdo                                           |
|-------------------|----------------------------------------------------|
| `ledger_id`       | FK para `coin_ledger.id` (NULL se trigger-error)   |
| `table_name`      | `coin_ledger` ou `coin_ledger_archive`             |
| `column_name`     | `reason` ou `note`                                 |
| `redacted_value`  | valor pós-redação (`admin_adjustment`/`[redacted-pii]`) |
| `original_hash`   | MD5 do valor original — **não** permite recuperação, só fingerprint |
| `trigger_source`  | `migration_backfill_20260421` / `fn_redact_ledger_pii_for_user` / `fn_delete_user_data` / `ops_manual` |
| `user_id`         | usuário alvo (pode ser o anon UUID)               |
| `redacted_by`     | operador (NULL em triggers automáticos)           |
| `note`            | free-form, uso interno ops                        |

**Consultas úteis:**

```sql
-- Por operador (últimas 30 dias)
SELECT redacted_by, count(*) AS qtd
  FROM public.coin_ledger_pii_redactions
 WHERE redacted_at > now() - interval '30 days'
 GROUP BY 1 ORDER BY 2 DESC;

-- Pico de redações (spike = incidente?)
SELECT date_trunc('day', redacted_at) AS dia, count(*) AS qtd
  FROM public.coin_ledger_pii_redactions
 WHERE redacted_at > now() - interval '90 days'
 GROUP BY 1 ORDER BY 1 DESC;

-- Verificar trigger-errors (note LIKE 'TRIGGER_ERROR:%')
SELECT redacted_at, user_id, note
  FROM public.coin_ledger_pii_redactions
 WHERE note LIKE 'TRIGGER_ERROR:%'
 ORDER BY redacted_at DESC
 LIMIT 50;
```

## 5. CI Lint — `npm run audit:ledger-reason`

Executa em cada PR via CI. Escaneia **apenas** migrations criadas a
partir de `20260421220000` (cutoff = a própria migration L04-07, pois
antes dela o backfill já rodou). Para cada `INSERT INTO coin_ledger`:

- ✅ Aceita literal canônico da whitelist.
- ✅ Aceita variável plpgsql (`v_reason`, `_reason`).
- ❌ Rejeita `format(...)` salvo comentário `-- L04-07-OK: <motivo>` nas
  5 linhas acima do INSERT (útil apenas para self-tests deliberados).
- ❌ Rejeita concatenação `||`.
- ❌ Rejeita literal com `@` ou fora da whitelist.

**Se o lint falhar:** abra o arquivo no editor, leia a mensagem, ajuste a
reason para um literal canônico, OU (se genuinamente novo) adicione o
novo literal a **ambos**:

1. `supabase/migrations/20260421130000_l03_reverse_coin_flows.sql`
   (CHECK array).
2. `tools/audit/check-ledger-reason-safety.ts` (`CANONICAL_REASONS` Set).

## 6. Manutenção — rotacionar CHECK constraints

Se descobrirmos novos padrões PII (ex. "CPF: 000.000.000-00"):

1. Adicionar regex ao `coin_ledger_reason_pii_guard` (nova migration, NÃO
   alterar a existente — DDL imutável).
2. Atualizar `fn_redact_ledger_pii_for_user` (CREATE OR REPLACE) com a
   mesma regex para scrubbing ativo.
3. Atualizar `tools/audit/check-ledger-reason-safety.ts`.
4. Rodar backfill: `SELECT public.fn_redact_ledger_pii_for_user(…)` para
   usuários já anonimizados.

## 7. Integração com fluxos existentes

| Fluxo                              | Integração L04-07                                      |
|------------------------------------|-------------------------------------------------------|
| `fn_delete_user_data` (L04-01)     | Trigger em audit_logs dispara redator safety-net.      |
| `execute_burn_atomic` (L03-14)     | Já usa `'institution_token_burn'` canônico. OK.       |
| `reverse_coin_emission_atomic`     | Inserts via `fn_mutate_wallet` → sempre literal OK.   |
| `fn_settle_challenge_atomic`       | Usa `challenge_team_won`/etc canônicos. OK.           |
| `wallet_reconcile` (L08-02)        | Usa `admin_correction` + note numérica. OK (números). |
| Mobile Flutter                     | N/A — mobile não escreve em coin_ledger diretamente.  |
| Edge Function `auto-topup-check`   | Não insere em coin_ledger (Stripe → webhook → RPC).   |

## 8. Rollback

Se L04-07 causar regressão (improvável dado o backfill pré-CHECK):

```sql
-- NOT ideal em produção LGPD — só use se um finding sério for descoberto.
ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_reason_length_guard;
ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_reason_pii_guard;
ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_note_pii_guard;
DROP TRIGGER IF EXISTS trg_ledger_pii_redact_on_erasure ON public.audit_logs;
DROP FUNCTION IF EXISTS public.fn_ledger_pii_redact_on_erasure();
DROP FUNCTION IF EXISTS public.fn_redact_ledger_pii_for_user(uuid, uuid);
-- coin_ledger_pii_redactions pode ser preservado (auditoria retroativa).
```

**NÃO** apague `coin_ledger_pii_redactions` — esse é o audit trail
exigido por LGPD Art. 37 para demonstrar accountability.

## 9. Contato

- **DPO (LGPD):** dpo@running.app
- **DBA on-call:** #dba-oncall (Slack)
- **CFO ops:** #finance-ops
- **Finding:** `docs/audit/findings/L04-07-coin-ledger-retem-reason-com-pii-embutida.md`
