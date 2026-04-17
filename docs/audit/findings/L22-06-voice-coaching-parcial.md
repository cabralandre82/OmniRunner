---
id: L22-06
audit_ref: "22.6"
lens: 22
title: "Voice coaching parcial"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "reliability", "personas", "athlete-amateur"]
files: []
correction_type: config
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
# [L22-06] Voice coaching parcial
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `flutter_tts` nos deps. Uso real: talvez só "pace alert". Faltam:

- Countdown "3, 2, 1, GO"
- Motivação periódica ("Você está indo bem!")
- Avisos de hidratação em corrida longa
## Correção proposta

— `AudioCuesService` configurável. Multi-idioma (pt-BR, en, es).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.6).