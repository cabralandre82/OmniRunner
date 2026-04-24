---
id: L05-14
audit_ref: "5.14"
lens: 5
title: "Feed social: sem \"report\" / moderação"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["migration", "ux", "trust-safety", "marco-civil"]
files:
  - docs/policies/SOCIAL_MODERATION_POLICY.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 9b5eb71

owner: product+legal+trust-safety
runbook: docs/policies/SOCIAL_MODERATION_POLICY.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Política ratificada em
  `docs/policies/SOCIAL_MODERATION_POLICY.md`. Tabela
  `social_reports` (RLS forçada, UNIQUE per reporter+content)
  + trigger auto-hide a 3 reports distintos + queue admin em
  `/platform/moderation` + SLA cron 72h alinhado com Marco
  Civil Art. 19. AI moderation rejeitada em v1 (escala atual,
  PII LGPD, false-positives em PT-BR). Re-avaliação quando MAU
  > 50k ou p95 review time > 24h. Implementação Wave 3.
---
# [L05-14] Feed social: sem "report" / moderação
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Posts, comments, reactions existem mas não há tabela `reports` nem fluxo de moderação.
## Risco / Impacto

— Cyberbullying entre atletas. Marco Civil Art. 19 + novas regras de plataformas.

## Correção proposta

— `CREATE TABLE social_reports(...)` + tela `/platform/moderation` + hide automático após 3 reports distintos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.14).