---
id: L04-08
audit_ref: "4.8"
lens: 4
title: "Backups Supabase — sem política de retenção documentada"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["lgpd", "rls", "migration", "reliability"]
files:
  - docs/compliance/BACKUP_POLICY.md
  - docs/runbooks/BACKUP_RESTORE_RUNBOOK.md
  - tools/audit/check-backup-policy.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-backup-policy.ts
linked_issues: []
linked_prs:
  - local:b8f0380
owner: platform
runbook: docs/runbooks/BACKUP_RESTORE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Published BACKUP_POLICY.md with retention matrix (PITR 7d, daily 14d,
  weekly 30d, monthly 180d), LGPD erasure alignment (30-day restore
  block after confirmed erasure, 180-day residual exposure ceiling),
  staging obfuscation rules, quarterly restore-drill cadence, and
  sa-east-1 region declaration. Paired with BACKUP_RESTORE_RUNBOOK.md
  that ships the operational SQL for PITR restore, snapshot restore,
  post-restore PII scrubbing (DPO-gated), and staging obfuscation.
  CI guard audit:backup-policy (26 invariants) enforces the retention
  matrix, erasure rules, cross-links to L04-09 / L04-10 / L08-08 / L10-08.
  Follow-up: drill-log enforcement (L04-08-drill-log) once enough
  quarterly drills exist to feed a cadence check.
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