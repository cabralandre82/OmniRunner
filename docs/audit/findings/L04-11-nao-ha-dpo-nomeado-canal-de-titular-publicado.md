---
id: L04-11
audit_ref: "4.11"
lens: 4
title: "Não há DPO nomeado / canal de titular publicado"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["lgpd", "dpo", "process", "documentation"]
files:
  - docs/legal/DPO_AND_DATA_SUBJECT_CHANNEL.md
  - tools/audit/check-dpo-channel.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-dpo-channel.ts
linked_issues: []
linked_prs:
  - d894bbc
  - 8346a6e
owner: legal
runbook: docs/legal/DPO_AND_DATA_SUBJECT_CHANNEL.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Documento canônico `docs/legal/DPO_AND_DATA_SUBJECT_CHANNEL.md`
  v1.0 publica:

  - Email canônico do DPO `dpo@omnirunner.com.br` + backup
    `legal@omnirunner.com.br`.
  - Endereço para carta registrada (placeholder até go-live público;
    L04-11 inclui review trigger antes de Onda 3).
  - Lista dos 9 direitos LGPD (Art. 18) com endpoint self-service e
    prazo (15 dias corridos).
  - SLA interno: 24h ack, 7 dias resposta preliminar, 15 dias
    resolução.
  - Página pública `/privacy/dpo` + tela `omni_runner/lib/features/
    privacy/` que devem expor o canal.
  - Recurso para a ANPD documentado.
  - Cross-refs L04-01 (eliminação), L04-03 (consentimento),
    L04-15 (portabilidade).

  CI guard `audit:dpo-channel` (15 asserts) bloqueia regressão se
  o email canônico mudar, se algum dos 9 direitos sumir ou se o
  prazo for alterado sem revisão de versão.
---
# [L04-11] Não há DPO nomeado / canal de titular publicado
> **Lente:** 4 — CLO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed
**Camada:** Legal / docs

## Achado
Help-center menciona FAQ mas não havia endpoint/email dedicado para
exercer direitos LGPD (Art. 18 + Art. 41). Sem DPO nomeado, o
controlador descumpre Art. 41 caput.

## Correção aplicada
Documento canônico `docs/legal/DPO_AND_DATA_SUBJECT_CHANNEL.md` v1.0
fixa:

- Email canônico **`dpo@omnirunner.com.br`** + backup `legal@`.
- Lista dos 9 direitos LGPD (Art. 18 I a IX) com endpoint
  self-service e prazo de 15 dias corridos.
- SLA interno (24h ack, 7d resposta preliminar, 15d resolução).
- Operação interna: registro em `audit_logs` com `category='lgpd'`.
- Recurso para ANPD documentado.
- Cross-refs L04-01 (eliminação), L04-03 (consentimento),
  L04-15 (portabilidade).

CI guard `audit:dpo-channel` (15 asserts) impede regressão silenciosa
do email canônico, dos 9 direitos ou do prazo.

## Próximo passo (não bloqueador)
Página `/privacy/dpo` no portal e tela equivalente em
`omni_runner/lib/features/privacy/` (presenter follow-up).

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4, item 4.11).
- `2026-04-23` — Fixed via doc canônico + CI guard. Próximo: review
  no momento de abertura comercial pública (substituir placeholders
  CNPJ/endereço).
