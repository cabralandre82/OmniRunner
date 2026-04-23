---
id: L22-08
audit_ref: "22.8"
lens: 22
title: "Desafio de grupo (viralização entre amigos)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "ux", "seo", "reliability", "personas", "athlete-amateur"]
files:
  - omni_runner/lib/domain/value_objects/challenge_invite_link.dart
  - omni_runner/lib/domain/value_objects/challenge_share_channel.dart
  - omni_runner/lib/domain/services/challenge_invite_message_builder.dart
  - omni_runner/lib/domain/entities/challenge_share_intent_entity.dart
  - omni_runner/lib/domain/usecases/gamification/share_challenge_invite.dart
  - omni_runner/lib/presentation/screens/challenge_invite_screen.dart
  - portal/public/.well-known/assetlinks.json
  - portal/public/.well-known/apple-app-site-association
  - tools/audit/check-challenge-invite-deep-link.ts
  - docs/runbooks/CHALLENGE_INVITE_VIRAL_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/value_objects/challenge_invite_link_test.dart
  - omni_runner/test/domain/services/challenge_invite_message_builder_test.dart
  - omni_runner/test/domain/usecases/gamification/share_challenge_invite_test.dart
linked_issues: []
linked_prs:
  - "local:d52f941"
owner: unassigned
runbook: docs/runbooks/CHALLENGE_INVITE_VIRAL_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Domain pipeline (canonical link VO → locale-aware builder → share intent use-case) + WhatsApp-specific launch via wa.me/?text= + CI guard enforcing .well-known/* invariants."
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