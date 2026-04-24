---
id: L22-16
audit_ref: "22.16"
lens: 22
title: "Primeira experiência de injury sem onboarding"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["mobile", "personas", "athlete-amateur", "lgpd", "health-data"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "fce133b"

owner: product+legal+mobile
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`
  § 7 (In-app injury triage). Postura ética explícita:
  triagem (estreita e segura), não diagnóstico; todo
  output termina com "em caso de dúvida, consulte um
  profissional". Matriz de decisão conservadora por EVA +
  localização + contexto; 4 recomendações discretas
  (rest_light, rest_firm, pro_48h, pro_now). Tabelas novas
  `injury_professionals` (diretório curado manual v1) e
  `injury_reports` (LGPD Art. 11 — own-only RLS, hard
  delete em `fn_delete_user_data`). Ship last na Wave 5
  (W5-C) — carga de compliance maior da Wave.
---
# [L22-16] Primeira experiência de injury sem onboarding
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Amador machuca joelho, não sabe fazer. Abre ticket suporte (se descobre).
## Correção proposta

— Triagem in-app: "Você está com dor?" → formulário com localização + intensidade → sugestão de rest + link para profissional da região (parceria local).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.16).
- `2026-04-24` — Consolidado em `docs/product/ATHLETE_AMATEUR_BASELINE.md` § 7 (batch K12); implementação Wave 5 fase W5-C.
