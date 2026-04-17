---
id: L01-31
audit_ref: "1.31"
lens: 1
title: "Android — Release assina com debug key se key.properties não existir"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "reliability"]
files: []
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
# [L01-31] Android — Release assina com debug key se key.properties não existir
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** APP (Flutter/Android)
**Personas impactadas:** CI/CD, stores
## Achado
`build.gradle:89-93` fallback silencioso para `signingConfigs.debug` se `keystorePropertiesFile` não existir. Se CI perde o secret, builds release são gerados com debug key — **rejeitados pela Play Store** ou, pior, aceitos mas com upload key errada bloqueando updates futuros.
## Correção proposta

```groovy
  buildTypes {
    release {
      if (!keystorePropertiesFile.exists()) {
        throw new GradleException("Release build requires key.properties")
      }
      signingConfig signingConfigs.release
      ...
    }
  }
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.31]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.31).