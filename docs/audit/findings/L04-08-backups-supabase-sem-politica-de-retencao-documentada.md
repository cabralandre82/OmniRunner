---
id: L04-08
audit_ref: "4.8"
lens: 4
title: "Backups Supabase — sem política de retenção documentada"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "rls", "migration", "reliability"]
files:
  - docs/compliance/BACKUP_POLICY.md
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
# [L04-08] Backups Supabase — sem política de retenção documentada
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Não há documento/migration especificando: tempo de retenção de PITR, ofuscação em staging, procedimento de deletar usuário nos backups.
## Risco / Impacto

— Após delete-account, o atleta ainda está em 4 backups (7, 14, 21, 28 dias). LGPD não exige apagar backups, mas exige documentar.

## Correção proposta

— Publicar `docs/compliance/BACKUP_POLICY.md` com: PITR = 7 dias, snapshots semanais mantidos 30 dias, requests de eliminação bloqueiam restauração do backup até 30 dias decorridos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.8).