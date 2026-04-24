---
id: L15-05
audit_ref: "15.5"
lens: 15
title: "Sem landing pages SEO-otimizadas"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "marketing", "seo"]
files:
  - docs/marketing/SEO_LANDING_STRATEGY.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: marketing+frontend
runbook: docs/marketing/SEO_LANDING_STRATEGY.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Estratégia ratificada em
  `docs/marketing/SEO_LANDING_STRATEGY.md`. **MDX-driven
  marketing route group** em `app/(marketing)/[slug]` lendo
  `_content/*.mdx` com Metadata + JsonLd
  (`SportsActivity`/`Article`) + sitemap automático +
  prefetch para `/signup?utm_source=seo`. Wave-3 launch set
  de 10 páginas selecionadas por keyword research pt-BR
  (volumes 590-9.9k MoM). Lighthouse target ≥ 95. Métricas
  + retire criteria mensais. CMS rejeitado em v1 (MDX +
  GitHub PR é suficiente para < 5 edits/mês; migração para
  Sanity simples se cresce).
---
# [L15-05] Sem landing pages SEO-otimizadas
> **Lente:** 15 — CMO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Portal é "logged app first"; não tem `/running-with-coaches`, `/marathon-training-plan`, etc. Tráfego orgânico search zero.
## Correção proposta

— `/app/(marketing)/[slug]/page.tsx` com MDX + schema.org SportsActivity + sitemap.xml.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.5).