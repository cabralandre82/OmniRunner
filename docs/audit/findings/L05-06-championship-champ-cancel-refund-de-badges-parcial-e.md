---
id: L05-06
audit_ref: "5.6"
lens: 5
title: "Championship champ-cancel: refund de badges parcial e silencioso"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["atomicity", "mobile", "edge-function", "performance"]
files:
  - supabase/functions/champ-cancel/index.ts
  - supabase/migrations/20260421480000_l05_06_champ_cancel_atomic.sql
  - tools/audit/check-champ-cancel-atomic.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:a564d3c
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  All four writes (withdraw participants, revoke invites, refund
  badges, flip championship status) are now wrapped in a single
  SECURITY DEFINER RPC `fn_champ_cancel_atomic(uuid, uuid)` that
  owns authorization (admin_master/coach of host_group), status
  precondition (draft/open/active), and row lock (FOR UPDATE).
  No silent catch — any failure raises and rolls back the whole
  transaction. Idempotent on retry via noop branch when the
  championship is already cancelled. Ships with
  audit:champ-cancel-atomic guard (35 invariants).
---
# [L05-06] Championship champ-cancel: refund de badges parcial e silencioso
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/champ-cancel/index.ts:149-161`:

```149:161:supabase/functions/champ-cancel/index.ts
        await db.rpc("fn_credit_badge_inventory", {
          p_group_id: champ.host_group_id,
          p_amount: badgeCount,
          p_source_ref: `champ_cancel_refund:${championship_id}`,
        });
      }
    } catch (e) {
      console.warn(JSON.stringify({
        request_id: requestId, fn: FN,
        msg: `Badge refund failed: ${e instanceof Error ? e.message : String(e)}`,
        championship_id,
      }));
    }
```

Se `fn_credit_badge_inventory` falhar, a operação continua — o championship é marcado `canceled` mas os badges do host somem.
## Correção proposta

— Igual [2.2]: remover catch silencioso e envolver cancelamento + refund em RPC atômica `champ_cancel_atomic(p_id)`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.6).