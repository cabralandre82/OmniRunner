---
id: L04-02
audit_ref: "4.2"
lens: 4
title: "Edge Function delete-account deleta auth.users mesmo quando fn_delete_user_data falha"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "edge-function", "lgpd", "audit-trail", "testing"]
files:
  - supabase/functions/delete-account/index.ts
  - supabase/functions/_shared/account_deletion.ts
  - supabase/functions/_shared/account_deletion.test.ts
  - supabase/migrations/20260417300000_account_deletion_log.sql
  - tools/integration_tests.ts
  - tools/edge_function_smoke_tests.ts
  - docs/runbooks/ACCOUNT_DELETION_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - supabase/functions/_shared/account_deletion.test.ts
  - tools/integration_tests.ts
linked_issues: []
linked_prs:
  - "commit:5de4d0d"
owner: platform
runbook: docs/runbooks/ACCOUNT_DELETION_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido em 2026-04-17 reescrevendo o pipeline da edge function
  `delete-account` para ser **atômico** e sempre auditável:

  1. **Abort-on-cleanup-error** (núcleo do L04-02): se
     `fn_delete_user_data` (ou o cancelamento de challenges) falhar, a
     função retorna 500 com `DATA_CLEANUP_FAILED` e **nunca** chama
     `auth.admin.deleteUser`. O usuário pode reexecutar pelo app sem
     ficar sem identidade.

  2. **Audit trail imutável** (cobre também L01-36 e L06-08): nova
     tabela `public.account_deletion_log` (migration
     `20260417300000_account_deletion_log.sql`) registra cada tentativa
     com `request_id`, `user_id`, `email_hash` (SHA-256), `user_role`,
     `client_ip`/`client_ua`, `outcome` (success / cleanup_failed /
     auth_delete_failed / cancelled_by_validation / internal_error),
     `failure_reason` e `cleanup_report` jsonb. A tabela **não tem FK
     para `auth.users`** (o registro sobrevive à deleção que documenta)
     e tem trigger `account_deletion_log_immutable` que rejeita reescrita
     de qualquer coluna terminal já preenchida. RLS restrita a
     `platform_role='admin'`.

  3. **Helpers puros e testáveis** em `supabase/functions/_shared/account_deletion.ts`:
     `hashEmail` (SHA-256 normalizado, lowercase+trim), `truncateReason`
     (cap 500 chars + strip de control chars), `extractClientIp`
     (parse defensivo de XFF, rejeita garbage), `extractClientUserAgent`,
     `buildInitialLogRow`, `buildTerminalLogRow`. 23 unit-tests Deno
     cobrem reflexividade do hash, vetores SHA-256 conhecidos, casos
     de truncamento e limpeza de XFF spoofado.

  4. **Integration tests** em `tools/integration_tests.ts` validam
     existência da tabela, CHECK regex em `email_hash`, CHECK enum em
     `outcome`, UNIQUE em `request_id`, e o trigger de imutabilidade
     (segunda escrita de outcome é rejeitada com mensagem `immutable`).

  5. **Runbook operacional** `docs/runbooks/ACCOUNT_DELETION_RUNBOOK.md`
     cobre diagnóstico (queries por outcome, in-flight crashes, busca
     por email_hash para responder ANPD), mitigação por outcome
     (`cleanup_failed` é estado seguro, `auth_delete_failed` requer
     re-rodar o auth delete via service-role), template de comunicação
     ao usuário (Art. 18, VI), drill trimestral e alertas P1/P2.

  Validação: 23/23 deno tests do helper + 56/56 do conjunto
  `_shared/*.test.ts` + 864/864 vitest do portal + `tsc --noEmit`
  limpo + `npx tsx tools/audit/verify.ts` = 348 findings ok. Smoke
  tests passaram de 590→598 (todos os novos exports do shared module
  são detectados).
---
# [L04-02] Edge Function delete-account deleta auth.users mesmo quando fn_delete_user_data falha
> **Lente:** 4 — CLO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/delete-account/index.ts:59-80`:

```60:80:supabase/functions/delete-account/index.ts
    const { error: cleanupErr } = await adminDb.rpc("fn_delete_user_data", { p_user_id: uid });
    if (cleanupErr) {
      console.error(JSON.stringify({ ... }));
    }

    // 5. Delete auth user (requires admin client)
    const { error: deleteErr } = await adminDb.auth.admin.deleteUser(uid);
```

O `cleanupErr` é apenas logado. Depois o auth.user é deletado, o que torna **impossível** re-executar a exclusão: o usuário sumiu do `auth.users`, mas as linhas com PII continuam em `custody_deposits`, `support_tickets`, storage etc.
## Risco / Impacto

— Dados órfãos com PII + cliente reclama na ANPD "pedi exclusão há 6 meses, dados ainda lá".

## Correção proposta

— Abortar a exclusão se o cleanup falhar:

```typescript
if (cleanupErr) {
  logError({ request_id: requestId, fn: FN, user_id: uid,
             error_code: "DATA_CLEANUP_FAILED", detail: cleanupErr.message });
  return jsonErr(500, "DATA_CLEANUP_FAILED",
    "Falha ao limpar dados. Tente novamente ou contate o suporte.", requestId);
}
// Only after successful cleanup, delete auth user
const { error: deleteErr } = await adminDb.auth.admin.deleteUser(uid);
```

## Teste de regressão

— mockar `fn_delete_user_data` para falhar; validar que `auth.admin.deleteUser` NÃO é chamado (usando spy) e resposta é 500.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.2).