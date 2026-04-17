---
id: L05-09
audit_ref: "5.9"
lens: 5
title: "Deposit custody_deposits — sem cap diário antifraude"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration"]
files: []
correction_type: code
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
# [L05-09] Deposit custody_deposits — sem cap diário antifraude
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Não há limite por grupo/dia de depósitos. Lavagem: atacante com grupo comprometido deposita US$ 10M de uma vez.
## Correção proposta

—

```sql
ALTER TABLE custody_accounts ADD COLUMN daily_deposit_limit_usd numeric(14,2) DEFAULT 50000;

CREATE OR REPLACE FUNCTION fn_check_daily_deposit_limit(p_group_id uuid, p_amount numeric)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_today_total numeric; v_limit numeric;
BEGIN
  SELECT COALESCE(SUM(amount_usd), 0) INTO v_today_total
  FROM custody_deposits
  WHERE group_id = p_group_id
    AND status IN ('pending','confirmed')
    AND created_at >= date_trunc('day', now());
  SELECT daily_deposit_limit_usd INTO v_limit FROM custody_accounts WHERE group_id = p_group_id;
  IF v_today_total + p_amount > v_limit THEN
    RAISE EXCEPTION 'Daily deposit limit exceeded' USING ERRCODE = 'CD001';
  END IF;
END;$$;
```

E chamar no `POST /api/custody`. Limite aumentável por platform_admin.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.9).