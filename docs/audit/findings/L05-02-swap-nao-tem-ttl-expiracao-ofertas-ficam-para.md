---
id: L05-02
audit_ref: "5.2"
lens: 5
title: "Swap não tem TTL/expiração — ofertas ficam para sempre"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "cron", "performance"]
files: []
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
# [L05-02] Swap não tem TTL/expiração — ofertas ficam para sempre
> **Lente:** 5 — CPO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Não há `expires_at` nem job `pg_cron` que cancele ofertas com mais de 7/30 dias. Ofertas velhas continuam ocupando `total_committed` da custódia do vendedor.
## Risco / Impacto

— Vendedor "esquece" uma oferta de US$ 500k, fica sem poder operar esse valor por meses.

## Correção proposta

—

```sql
ALTER TABLE swap_orders ADD COLUMN expires_at timestamptz NOT NULL
  DEFAULT (now() + interval '7 days');
CREATE INDEX idx_swap_orders_expires ON swap_orders(expires_at) WHERE status = 'open';

-- pg_cron job every 10 min
SELECT cron.schedule('swap_expire', '*/10 * * * *', $$
  UPDATE swap_orders SET status='expired' WHERE status='open' AND expires_at < now();
$$);
```

Client cria oferta com `expires_in_days` obrigatório (1/7/30/90).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.2).