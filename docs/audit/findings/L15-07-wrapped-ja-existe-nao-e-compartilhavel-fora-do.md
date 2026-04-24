---
id: L15-07
audit_ref: "15.7"
lens: 15
title: "Wrapped (já existe) não é compartilhável fora do app"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "edge-function", "seo"]
files:
  - docs/marketing/WRAPPED_SOCIAL_SHARING.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: marketing+platform
runbook: docs/marketing/WRAPPED_SOCIAL_SHARING.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Spec ratificado em `docs/marketing/WRAPPED_SOCIAL_SHARING.md`.
  Decisão: página pública opt-in em `/wrapped/[year]/[slug]` com slug
  assinado, OG image gerado estaticamente, e tabela `wrapped_publications`
  para controle de consent + revogação. Excluímos PII e métricas
  sensíveis (endereço, posição em ranking financeiro). Implementação
  Wave 3.
---
# [L15-07] Wrapped (já existe) não é compartilhável fora do app
> **Lente:** 15 — CMO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/generate-wrapped/` e `wrapped_screen.dart` geram página interna. Sem URL pública `/wrapped/[user]/2026` com imagem social.
## Correção proposta

— Exportar como página SEO-friendly + OG image; slug único, opt-in "compartilhar publicamente".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.7).