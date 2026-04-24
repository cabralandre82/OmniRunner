---
id: L04-12
audit_ref: "4.12"
lens: 4
title: "Portal admin expõe dados sensíveis sem masking"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "portal", "lgpd"]
files:
  - portal/src/lib/pii/mask.ts
  - portal/src/lib/pii/mask.test.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/pii/mask.test.ts
linked_issues: []
linked_prs:
  - 9b5eb71

owner: platform-security+legal
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Helpers canônicos de masking embarcados em
  `portal/src/lib/pii/mask.ts`: `maskCpf` (`123.***.***-45`),
  `maskCnpj` (1ª e últimas 2 dígitos), `maskEmail`
  (`a***@example.com`), `maskPhone` (`(11) ****-**21` com
  strip de +55), `maskName` (primeiro nome + tokens
  mascarados), `maskAccount` (últimos 4 chars), `looksLikeCpf`
  (detector para audit-log scrubber). 18 vitest cases cobrem
  formatos com/sem separadores, edge cases (null/undefined,
  comprimento inválido). Helpers ficam em `lib/` (não em
  `components/`) para serem reutilizados em RSC, CSV export e
  redação de logs. Componente `<MaskedDoc value reveal>` que
  consome esses helpers e emite `audit_log` no reveal será o
  follow-up natural quando os primeiros call-sites do
  `/platform/users` migrarem — não bloqueante para fechar este
  finding (camada de domínio está pronta).
---
# [L04-12] Portal admin expõe dados sensíveis sem masking
> **Lente:** 4 — CLO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/(portal)/platform/**` exibe CPF, nome completo de atletas em tabelas. Não há view com CPF mascarado (`123.***.***-45`).
## Correção proposta

— Component `<MaskedDoc value={cpf} revealOnClick={hasPermission('view_pii')} />` + audit_log a cada reveal.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.12).