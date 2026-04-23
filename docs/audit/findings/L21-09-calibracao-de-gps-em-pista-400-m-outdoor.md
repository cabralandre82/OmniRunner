---
id: L21-09
audit_ref: "21.9"
lens: 21
title: "Calibração de GPS em pista (400 m outdoor)"
severity: high
status: wont-fix
wave: 1
discovered_at: 2026-04-17
closed_at: 2026-04-21
tags: ["gps", "personas", "athlete-pro", "strava-only-scope"]
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
note: |
  **wont-fix (2026-04-21).** O app não faz tracking GPS
  in-app desde a Sprint 25.0.0 (`docs/ARCHITECTURE.md`
  §7 — Strava é fonte única). A correção sobre GPS de
  pista pertence ao dispositivo do atleta (modo "track
  run" do Garmin/Coros) e vem pronta via Strava; não há
  ponto de calibração no pipeline Omni. Se o produto
  mudar de direção e voltar a gravar GPS nativo, este
  finding é reaberto.
---
# [L21-09] Calibração de GPS em pista (400 m outdoor)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🚫 wont-fix (Sprint 25.0.0 — Strava-only)
**Camada:** —
**Personas impactadas:** —
## Achado
— Em pista de atletismo, GPS tem erro lateral 3-5 m → 200 m medidos viram 195 ou 212. Elite rodando 1500m em tartan quer distância exata.
## Correção proposta

— Modo "pista 400m" com auto-lap a cada volta por GPS fit + correção determinística (cada lap = 400 m). Ou BLE sensor de passos/cadência mais preciso que GPS em pista fechada.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.9).
- `2026-04-21` — **Fechado como `wont-fix`**. Não fazemos mais tracking GPS in-app (`docs/ARCHITECTURE.md` §7 — Strava-only); calibração de pista é responsabilidade do device.