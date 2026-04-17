---
id: L20-02
audit_ref: "20.2"
lens: 20
title: "Sem SLO/SLI definidos → impossível ter alert policy razoável"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "observability", "reliability"]
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
# [L20-02] Sem SLO/SLI definidos → impossível ter alert policy razoável
> **Lente:** 20 — SRE · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Correlacionado a [6.10]. Alertas hoje são thresholds absolutos chutados. Nenhum "burn 2% error budget in 1h" style.
## Correção proposta

—

```yaml
# observability/slo.yaml
slos:
  - name: api_distribute_coins_availability
    target: 99.9
    window: 30d
    sli: "rate(api_requests{route='/api/distribute-coins',status<500})"
  - name: api_withdraw_latency
    target: 95  # 95% of requests < 500ms
    window: 30d
    sli: "rate(api_requests{route='/api/custody/withdraw',latency<500ms})"
  - name: webhook_processing_p99
    target: 99  # 99% processed in 30s
    window: 7d
```

Burn rate alerts (Google SRE book): alert quando burn rate > 14× (burns 1h budget em 1h).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.2).