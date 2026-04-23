---
id: L04-07
audit_ref: "4.7"
lens: 4
title: "coin_ledger retém reason com PII embutida"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "atomicity", "lgpd", "migration", "rls"]
files:
  - "supabase/migrations/20260421220000_l04_07_ledger_reason_pii_guard.sql"
  - "tools/audit/check-ledger-reason-safety.ts"
  - "tools/test_l04_07_ledger_reason_pii.ts"
  - "docs/runbooks/LEDGER_PII_REDACTION_RUNBOOK.md"
correction_type: migration
test_required: true
tests:
  - "tools/test_l04_07_ledger_reason_pii.ts"
  - "supabase/migrations/20260421220000_l04_07_ledger_reason_pii_guard.sql"
linked_issues: []
linked_prs:
  - "be5e962"
owner: clo
runbook: "docs/runbooks/LEDGER_PII_REDACTION_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L04-07] coin_ledger retém reason com PII embutida
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `execute_burn_atomic` e várias funções usam `format('Burn of %s coins from %s by user %s', …)`. Se o `%s` inclui nome do atleta ou email (em outras funções), um `SELECT * FROM coin_ledger WHERE user_id = '00...0'` após a anonimização ainda expõe o nome.
## Risco / Impacto

— "Right to be forgotten" parcial.

## Correção proposta

— Revisar todos os `reason` para conter apenas IDs + tipos; ao anonimizar, também fazer:

```sql
UPDATE coin_ledger
SET reason = regexp_replace(reason, 'user \S+', 'user [redacted]')
WHERE user_id = '00000000-0000-0000-0000-000000000000'::uuid;
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.7]`.

## Correção implementada (2026-04-21, commit `be5e962`)

Fix em **5 camadas** defensivas, descritas em detalhe no runbook
`docs/runbooks/LEDGER_PII_REDACTION_RUNBOOK.md`:

1. **CHECK constraints preventivos** em `public.coin_ledger`:
   - `coin_ledger_reason_length_guard` — reason ≤ 64 chars.
   - `coin_ledger_reason_pii_guard` — proíbe `@`, padrão `by user <uuid>`
     e `from <Nome> <Sobrenome>`.
   - `coin_ledger_note_pii_guard` (se coluna presente) — note ≤ 200 chars,
     sem `@`, sem `name=|email=|cpf=|phone=`.
   - Espelhos em `coin_ledger_archive`.
2. **Backfill one-shot** (no próprio DO-block da migration, antes dos
   `ADD CONSTRAINT`) que redige linhas históricas violando os guards —
   sem o backfill o `ADD CONSTRAINT` falharia em bases com PII residual.
3. **`public.coin_ledger_pii_redactions`** — tabela de trilha LGPD
   (RLS `service_role_only`) que guarda MD5 do valor original,
   valor pós-redação, fonte da ação (migration backfill / helper RPC /
   trigger safety-net / ops manual).
4. **`public.fn_redact_ledger_pii_for_user(p_user_id, p_actor)`** —
   helper SECURITY DEFINER, idempotente, invocável pelo fluxo LGPD de
   erasure ou por ops. Retorna jsonb com contadores por tabela/coluna.
5. **Trigger safety-net** `trg_ledger_pii_redact_on_erasure` em
   `audit_logs` que dispara o redator automaticamente quando
   `user.self_delete.completed` é registrado — cobre erasures antigas
   pré-L04-07.
6. **CI lint** `npm run audit:ledger-reason`
   (`tools/audit/check-ledger-reason-safety.ts`) — escaneia migrations
   posteriores à 20260421220000 buscando `format(...)`, concat `||`, ou
   literais fora da whitelist canônica em `INSERT INTO coin_ledger`.
   Opt-out explícito via `-- L04-07-OK: <motivo>` (usado apenas pelo
   self-test da própria migration).

**Testes** — 11 casos em `tools/test_l04_07_ledger_reason_pii.ts` +
self-test DO-block na migration (7 invariantes). Lint + audit:verify
ambos verdes.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.7).
- `2026-04-21` — Fix implementado (commit `be5e962`).