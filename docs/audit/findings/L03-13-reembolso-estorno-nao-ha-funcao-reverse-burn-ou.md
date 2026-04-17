---
id: L03-13
audit_ref: "3.13"
lens: 3
title: "Reembolso / Estorno — Não há função reverse_burn ou refund_deposit"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "reliability"]
files: []
correction_type: process
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
# [L03-13] Reembolso / Estorno — Não há função reverse_burn ou refund_deposit
> **Lente:** 3 — CFO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Atleta, Assessoria, Plataforma
## Achado
Grepping por `refund`, `reverse`, `chargeback` em `supabase/migrations/` não encontra funções de reversão de: (a) emissão de coins após chargeback do gateway; (b) burn (coins queimadas por engano); (c) withdrawal falha externamente.
## Risco / Impacto

Chargeback Stripe/MP deixa coins emitidas sem lastro ↔ invariante quebra. Sem função de reversão, admin precisa fazer SQL manual — erro humano catastrófico.

## Correção proposta

Criar funções:
```sql
CREATE FUNCTION reverse_custody_deposit(p_deposit_id uuid, p_reason text)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Lock deposit, verify status='confirmed'
  -- 2. Set status='refunded'
  -- 3. UPDATE custody_accounts SET total_deposited_usd -= amount_usd (with FOR UPDATE)
  -- 4. If total_committed > total_deposited, raise exception (can't refund what's already circulating)
  -- 5. INSERT INTO audit_log
END; $$;

CREATE FUNCTION reverse_burn(p_ref_id uuid, p_reason text) ...
CREATE FUNCTION reverse_withdrawal(p_withdrawal_id uuid, p_reason text) ...
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.13).