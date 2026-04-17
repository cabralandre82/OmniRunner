---
id: L22-08
audit_ref: "22.8"
lens: 22
title: "Desafio de grupo (viralização entre amigos)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "ux", "seo", "reliability", "personas", "athlete-amateur"]
files: []
correction_type: code
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
# [L22-08] Desafio de grupo (viralização entre amigos)
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `challenge-create` existe. UX para convidar amigos via WhatsApp (deep link pré-preenchido) fraca.
## Correção proposta

— Tela "Criar desafio" tem botão **"Convidar via WhatsApp"** que gera imagem card + deep link `omnirunner.app/challenge/XYZ`. Usa Universal Links iOS + App Links Android + `share_plus` (já no pubspec).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.8).