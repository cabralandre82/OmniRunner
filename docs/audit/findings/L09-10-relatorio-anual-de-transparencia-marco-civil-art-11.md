---
id: L09-10
audit_ref: "9.10"
lens: 9
title: "Relatório anual de transparência (Marco Civil Art. 11)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["transparency", "marco-civil", "lgpd", "process"]
files:
  - docs/legal/TRANSPARENCY_REPORT.md
  - tools/audit/check-transparency-report.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-transparency-report.ts
linked_issues: []
linked_prs: []
owner: legal
runbook: docs/legal/TRANSPARENCY_REPORT.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Template canônico `docs/legal/TRANSPARENCY_REPORT.md` v1.0
  publicado para cadência semestral (31/jan e 31/jul). Estrutura
  fixa cobre solicitações governamentais, direitos LGPD,
  incidentes, remoções de conteúdo, tentativas de acesso
  ilegítimo. CI guard `audit:transparency-report` (13 asserts)
  garante que a estrutura sobrevive future edits. Próxima
  publicação preenchida: 2026-07-31.
---
# [L09-10] Relatório anual de transparência (Marco Civil Art. 11)
> **Lente:** 9 — CRO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed
**Camada:** Legal / process

## Achado
Não havia relatório periódico de solicitações governamentais,
remoções, etc. Marco Civil Art. 11 + LGPD Art. 4 §3 sugerem
publicação periódica.

## Correção aplicada
Template canônico `docs/legal/TRANSPARENCY_REPORT.md` v1.0 com:
- Período coberto, solicitações governamentais por categoria,
  direitos LGPD por tipo, incidentes, remoções, tentativas
  ilegítimas.
- Cadência semestral (31/jan e 31/jul).
- Compromissos: notificação ao usuário sempre que possível;
  arquivo histórico em `docs/legal/transparency-archive/`.
- Cross-refs: `DPO_AND_DATA_SUBJECT_CHANNEL.md`, `DATA_TRANSFER.md`,
  `TERMO_ATLETA.md`.

CI guard `audit:transparency-report` (13 asserts) bloqueia
remoção de seção crítica ou alteração de cadência sem revisão
de versão.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via template + CI guard.
