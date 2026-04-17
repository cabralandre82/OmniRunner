---
id: L01-40
audit_ref: "1.40"
lens: 1
title: "Google services — google-services.json commitado"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["mobile", "reliability"]
files:
  - omni_runner/android/app/google-services.json
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
# [L01-40] Google services — google-services.json commitado
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** APP (Android)
**Personas impactadas:** Android
## Achado
`omni_runner/android/app/google-services.json` existe no repo. Firebase considera esse arquivo público (tem apenas client IDs e Firebase project config, não secrets). Porém revela **project number + API keys restritas por package name** — se o restriction SHA não estiver configurado no console Firebase, a key é abusável.
## Correção proposta

Verificar Firebase Console → Project Settings → API restrictions → "Android apps" com fingerprint SHA-1 do signing key. Adicionar warning no `CONTRIBUTING.md` sobre isso.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.40]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.40).