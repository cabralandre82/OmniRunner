---
id: L22-15
audit_ref: "22.15"
lens: 22
title: "Formato de exportação pessoal apenas técnico"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["mobile", "personas", "athlete-amateur"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "k12-pending"

owner: product+mobile+backend
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`
  § 6 (Monthly Wrapped PDF export). Reutiliza
  `generate-wrapped` para agregação + novo render-path
  `@react-pdf` → storage bucket `user-wrapped-pdf` com
  signed URL 24h. Render on-demand (mensal é baixo
  tráfego; pre-render desperdiça storage). Conteúdo:
  página 1 (KPIs + rota favorita + frase motivacional
  deterministicamente escolhida), página 2 opcional
  (progressão 6 meses + badges). Implementação Wave 5
  fase W5-B (após weather widget).
---
# [L22-15] Formato de exportação pessoal apenas técnico
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Export = `.fit` ([21.7]). Amador quer PDF bonito "meu resumo do mês" para compartilhar.
## Correção proposta

— `generate-wrapped` (existe) + export mensal PDF rechado de gráficos, fotos de perfil, frases motivacionais.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.15).
- `2026-04-24` — Consolidado em `docs/product/ATHLETE_AMATEUR_BASELINE.md` § 6 (batch K12); implementação Wave 5 fase W5-B.
