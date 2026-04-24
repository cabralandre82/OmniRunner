---
id: L10-13
audit_ref: "10.13"
lens: 10
title: "Sem DPI (Device Posture) no Flutter"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "mobile", "anti-cheat", "security"]
files:
  - docs/security/MOBILE_DEVICE_POSTURE_POLICY.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: mobile+security
runbook: docs/security/MOBILE_DEVICE_POSTURE_POLICY.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Política ratificada em
  `docs/security/MOBILE_DEVICE_POSTURE_POLICY.md`. **2-tier
  posture**: SOFT em uso geral / HARD em ações financeiras.
  v1 free (`flutter_jailbreak_detection` + `device_info_plus`,
  composer `DevicePosture` com `healthy/suspicious/
  compromised`); v2 billable (Play Integrity API + iOS App
  Attest) quando withdraw fraud > BRL 5k/mês. Matriz de
  enforcement por surface (login=allow, distribute/withdraw=
  block em compromised, withdraw em suspicious=2FA challenge).
  Servidor NUNCA bloqueia só por claim do client; usa
  `X-Device-Posture` em `audit_logs` para correlação e daily
  `posture-suspicious-actors` report. JWT revogation por
  posture rejeitada (atacante poderia spoofar para mass-logout).
---
# [L10-13] Sem DPI (Device Posture) no Flutter
> **Lente:** 10 — CSO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— App não verifica: root/jailbreak, debugger attached, Frida hook, emulador em produção, integridade do APK.
## Correção proposta

— `flutter_jailbreak_detection` + Play Integrity API + bloqueio "soft" (warning) ou "hard" (bloquear transações financeiras em device comprometido).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.13).