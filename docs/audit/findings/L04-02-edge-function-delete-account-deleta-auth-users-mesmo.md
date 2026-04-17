---
id: L04-02
audit_ref: "4.2"
lens: 4
title: "Edge Function delete-account deleta auth.users mesmo quando fn_delete_user_data falha"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "edge-function", "performance", "testing"]
files:
  - supabase/functions/delete-account/index.ts
correction_type: code
test_required: true
tests: []
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