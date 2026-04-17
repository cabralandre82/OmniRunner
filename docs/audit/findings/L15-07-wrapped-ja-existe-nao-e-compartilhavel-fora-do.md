---
id: L15-07
audit_ref: "15.7"
lens: 15
title: "Wrapped (já existe) não é compartilhável fora do app"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "edge-function", "seo"]
files:
  - supabase/functions/generate-wrapped/
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L15-07] Wrapped (já existe) não é compartilhável fora do app
> **Lente:** 15 — CMO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
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