---
id: L21-02
audit_ref: "21.2"
lens: 21
title: "MAX_HR_BPM = 220 inferior à realidade de atletas jovens"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["personas", "athlete-pro", "anti-cheat", "edge-function"]
files:
  - supabase/functions/_shared/anti_cheat.ts
  - supabase/functions/verify-session/index.ts
  - supabase/functions/strava-webhook/index.ts
  - supabase/migrations/20260421110000_l21_athlete_anti_cheat_profile.sql
correction_type: code
test_required: true
tests:
  - supabase/functions/_shared/anti_cheat.test.ts
  - tools/test_l21_01_02_anti_cheat_profile.ts
linked_issues: []
linked_prs:
  - "903738c"
owner: unassigned
runbook: docs/runbooks/ANTI_CHEAT_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Resolved jointly with L21-01 in commit 903738c. Teto max_hr_bpm passa a respeitar (a) base do bracket, (b) Tanaka 225-age via profiles.birth_date, (c) measured chest-strap (profiles.measured_max_hr_bpm) com janela de 6 meses, clamp final em [185,250]."
---
# [L21-02] MAX_HR_BPM = 220 inferior à realidade de atletas jovens
> **Lente:** 21 — Atleta Pro · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linha 73: cap 220 BPM. Estudos modernos (Robergs & Landwehr 2002, Tanaka 2001) mostram que `220 − idade` subestima max HR para atletas jovens em até 20 BPM. Elite sub-25 pode atingir 210-225 BPM em VO2max. Cap = 220 marca corridas legítimas como suspeitas.
## Correção proposta

— Usar `max(220, measured_max_hr_last_6_months + 5)` ou simplesmente elevar para 230. Validar com heart-rate strap (chest BLE) tem menos ruído que optical.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.2).