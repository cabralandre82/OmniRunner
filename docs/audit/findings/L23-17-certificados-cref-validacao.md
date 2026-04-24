---
id: L23-17
audit_ref: "23.17"
lens: 23
title: "Certificados CREF validação"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["personas", "coach", "compliance", "trust"]
files:
  - docs/product/COACH_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "fce133b"

owner: product+legal+platform-admin
runbook: docs/product/COACH_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/COACH_BASELINE.md` § 3
  (CREF certificate validation). Upload PDF ≤ 5 MB +
  número CREF validado por regex `NNNNNN-[G|P]/UF`;
  storage bucket `coach-cref-docs` com RLS self +
  platform admin_master. Revisão **humana** no
  `/platform/admin/cref-queue` — NÃO consultamos a API
  pública do CREF (flaky e incompleta). Novas colunas
  em `profiles` (cref_number, _state, _kind, _doc_path,
  _verified_at, _verified_by, _rejected_at,
  _rejection_reason). Runbook dedicado
  `CREF_VERIFICATION_RUNBOOK.md` com o que admin procura
  num doc válido. Retenção LGPD Art 5º II — deletado
  via `fn_delete_user_data_lgpd_complete`. Ship Wave 5
  fase W5-E (depende de staff de platform-admin para
  operar fila).
---
# [L23-17] Certificados CREF validação
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Qualquer um vira coach criando grupo. Sem validação CREF.
## Correção proposta

— Badge "Coach certificado CREF 012345-G" com upload de PDF + validação manual admin_master (platform). Filtro opcional "apenas coaches certificados".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.17).
- `2026-04-24` — Consolidado em `docs/product/COACH_BASELINE.md` § 3 (batch K12); implementação Wave 5 fase W5-E.
