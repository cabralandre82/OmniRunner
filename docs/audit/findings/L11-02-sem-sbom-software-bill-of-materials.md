---
id: L11-02
audit_ref: "11.2"
lens: 11
title: "Sem SBOM (Software Bill of Materials)"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal"]
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
# [L11-02] Sem SBOM (Software Bill of Materials)
> **Lente:** 11 — Supply Chain · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Requisito cresceu regulatoriamente (NIST SSDF, EO 14028 US, BACEN resol. 4.893/21 brasileiro sobre gerenciamento de risco de fornecedor).
## Correção proposta

—

```yaml
- uses: anchore/sbom-action@v0
  with:
    path: ./portal
    format: cyclonedx-json
    output-file: sbom-portal.cdx.json
- uses: actions/upload-artifact@v4
  with:
    name: sbom-portal
    path: sbom-portal.cdx.json
```

Armazenar versionado. Opcionalmente assinar com Sigstore (`cosign`).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.2).