---
id: L05-19
audit_ref: "5.19"
lens: 5
title: "Offline-first Flutter: sessões ficam em drift até sincronizar"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "cron", "reliability"]
files:
  - docs/runbooks/MOBILE_OFFLINE_SESSION_BACKUP.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: mobile+reliability
runbook: docs/runbooks/MOBILE_OFFLINE_SESSION_BACKUP.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Spec ratificada em
  `docs/runbooks/MOBILE_OFFLINE_SESSION_BACKUP.md`. Estratégia
  3 camadas: (1) eager-push baseline já existente, (2) email
  digest após 24h sem sync (encrypted via account-derived key,
  1 email/24h por usuário, piggyback no WorkManager de L08-12),
  (3) tela `Settings → Pending Runs` com ações manuais
  (try-sync / send-email / export-file / delete). Rejeitados
  por design: `flutter_secure_storage` (mesmo failure mode em
  factory reset, limite de 1 MB por key, two-source-of-truth)
  e iCloud/Google Drive auto-backup (sem consent explícito do
  usuário sobre GPS trajectories). Implementação Wave 3.
---
# [L05-19] Offline-first Flutter: sessões ficam em drift até sincronizar
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `drift_database.dart` salva sessões localmente. Se atleta corre, não sincroniza, troca de celular → perde treino.
## Correção proposta

— Backup local em `FlutterSecureStorage` ou botão "Enviar por email todas as corridas pendentes".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.19]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.19).