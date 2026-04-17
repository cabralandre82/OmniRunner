---
id: L21-04
audit_ref: "21.4"
lens: 21
title: "Ausência de \"training load\" / TSS / CTL / ATL"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["integration", "mobile", "migration", "performance", "personas", "athlete-pro"]
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
# [L21-04] Ausência de "training load" / TSS / CTL / ATL
> **Lente:** 21 — Atleta Pro · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `coaching_athlete_kpis_daily` tem distance/duration/frequency. Não calcula:
## Risco / Impacto

— Elite migra para TrainingPeaks, usa Omni Runner apenas para checklist social → atrito, perda da persona alvo.

## Correção proposta

—

```sql
ALTER TABLE sessions ADD COLUMN tss numeric(6,1);
ALTER TABLE sessions ADD COLUMN if_intensity_factor numeric(3,2);
-- IF = NP / FTP (running: NGP / rFTP or custom pace zone model)

-- Daily rollup
CREATE MATERIALIZED VIEW mv_athlete_load_daily AS
SELECT user_id, date_trunc('day', to_timestamp(start_time_ms/1000))::date AS day,
  SUM(tss) AS daily_tss,
  -- EWMA for CTL and ATL
  exp_avg(tss, 42) OVER w AS ctl,
  exp_avg(tss, 7)  OVER w AS atl
FROM sessions
WINDOW w AS (PARTITION BY user_id ORDER BY start_time_ms)
GROUP BY user_id, day;
```

UI: `athlete_evolution_screen.dart` + `athlete_my_evolution_screen.dart` ganham tab "Performance Management Chart".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.4).