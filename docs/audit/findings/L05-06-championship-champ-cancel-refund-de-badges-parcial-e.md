---
id: L05-06
audit_ref: "5.6"
lens: 5
title: "Championship champ-cancel: refund de badges parcial e silencioso"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["atomicity", "mobile", "edge-function", "performance"]
files:
  - supabase/functions/champ-cancel/index.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-06] Championship champ-cancel: refund de badges parcial e silencioso
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
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