---
id: L12-05
audit_ref: "12.5"
lens: 12
title: "auto-topup-hourly — cobrança automática sem cap diário"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["edge-function", "migration"]
files: []
correction_type: config
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
# [L12-05] auto-topup-hourly — cobrança automática sem cap diário
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Roda de hora em hora. Se settings do atleta mal-configurado (bug ou ataque), pode cobrar 24×/dia.
## Correção proposta

—

```sql
ALTER TABLE auto_topup_settings ADD COLUMN daily_charge_cap_brl numeric(10,2) DEFAULT 500;
ALTER TABLE auto_topup_settings ADD COLUMN charges_today integer DEFAULT 0;
ALTER TABLE auto_topup_settings ADD COLUMN last_charge_reset_at date DEFAULT current_date;
-- Edge function refuses if charges_today >= 3 OR total_today > cap
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.5).