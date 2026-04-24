---
id: L01-41
audit_ref: "1.41"
lens: 1
title: "coin_ledger — Sem assinatura criptográfica"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "anti-cheat"]
files:
  - docs/security/COIN_LEDGER_TAMPER_EVIDENCE.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 8046248

owner: finance+security
runbook: docs/security/COIN_LEDGER_TAMPER_EVIDENCE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Spec ratificada em `docs/security/COIN_LEDGER_TAMPER_EVIDENCE.md`.
  Escolha: hash chain SHA-256 em **tabela sibling write-once**
  (`coin_ledger_hash_chain`), populada por trigger BEFORE INSERT
  em cada partition mensal, com snapshot inline para detectar o
  caso "atacante apaga linha do chain para esconder UPDATE em
  coin_ledger". Verificação: cron diário recomputa última
  partition fechada e dispara `audit_logs` +
  `CHARGEBACK_RUNBOOK` em mismatch; assinatura Ed25519 da
  cabeça do chain publicada trimestralmente em repo Git público
  para attestation third-party. Implementação real (~150 LOC)
  vai num PR dedicado em Wave 3 — não cabe num batch de 50
  findings porque toca o hot path de toda RPC financeira.
---
# [L01-41] coin_ledger — Sem assinatura criptográfica
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Plataforma (auditoria)
## Achado
`coin_ledger` é o livro-razão de emissões/queimas. Um admin_master com acesso DB (via Supabase Dashboard) pode `UPDATE coin_ledger SET delta_coins=99999 WHERE id=X`. Não há hash chain nem assinatura.
## Risco / Impacto

Fraude interna por funcionário Omni Runner com acesso SQL.

## Correção proposta

Implementar hash chain: `hash = sha256(prev_hash || user_id || delta_coins || reason || ref_id || created_at_ms)` em `coin_ledger_hashes` table, atualizada por trigger. Audit externo (pg_audit ou wal streaming para tabela write-once em outro DB).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.41]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.41).