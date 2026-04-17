---
id: L18-04
audit_ref: "18.4"
lens: 18
title: "Architecture: Flutter viola Clean Arch em vários pontos"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "observability", "seo", "testing", "reliability"]
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
# [L18-04] Architecture: Flutter viola Clean Arch em vários pontos
> **Lente:** 18 — Principal Eng · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Conforme resumo conversacional prévio, `omni_runner/lib` tem:

- `drift_database.dart` (data layer) sendo importado diretamente de `presentation/screens/*`
- `product_event_tracker.dart` chama `sl<SupabaseClient>()` direto (não via repository)
- Use cases misturando domain + data responsibilities
## Risco / Impacto

— Inability to migrate backend (se algum dia sair do Supabase), testing painful (Supabase client precisa ser mockado em 50 lugares).

## Correção proposta

— Estabelecer fence arquitetural com `dart_code_metrics` rules:

```yaml
# analysis_options.yaml
dart_code_metrics:
  rules:
    - avoid-direct-imports:
        source: "presentation"
        forbidden: ["data/datasources/*"]
```

Refactor prioritário: `secure_storage`, `deep_links`, `auth_repository` — camadas core com mais impacto.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.4).