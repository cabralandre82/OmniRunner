---
id: L22-04
audit_ref: "22.4"
lens: 22
title: "Feedback de ritmo só pós-corrida"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "personas", "athlete-amateur"]
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
note: null
---
# [L22-04] Feedback de ritmo só pós-corrida
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Amador iniciante começa muito rápido ("burned out" em 5 min). Produto não fala durante.
## Correção proposta

— TTS em tempo real:

- "Você está 20 s mais rápido que alvo. Desacelere um pouco."
- "FC zona 3, ideal. Mantenha."
- A cada km: "1 km em 6:15, você está bem."

Customizável em `settings_screen.dart`: frequência, idioma, voz.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.4).