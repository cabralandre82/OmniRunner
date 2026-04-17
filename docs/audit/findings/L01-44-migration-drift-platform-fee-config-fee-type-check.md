---
id: L01-44
audit_ref: "1.44"
lens: 1
title: "Migration drift — platform_fee_config.fee_type CHECK + INSERT 'fx_spread'"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "migration", "ux", "reliability"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L01-44] Migration drift — platform_fee_config.fee_type CHECK + INSERT 'fx_spread'
> **Lente:** 1 — CISO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** DevOps, CFO (em fresh install)
## Achado
`20260228150001_custody_clearing_model.sql:17` cria CHECK com `('clearing', 'swap', 'maintenance')`.
  - `20260228170000_custody_gaps.sql:40-42` tenta `INSERT ... ('fx_spread', 0.75)`.
  - A CHECK **REJEITA** o INSERT de 'fx_spread' → migration 170000 **FALHA** em instalação fresh.
  - Só migration `20260319000000_maintenance_fee_per_athlete.sql:18` finalmente expande CHECK para incluir `'fx_spread'`.
  - Em um banco existente que já passou 170000 antes da CHECK ser apertada, vai funcionar por acidente histórico.
## Risco / Impacto

Reprovisão de ambientes (staging, preview, onboarding novo dev) **quebra**. Disaster recovery de backup + replay de migrations desde zero **quebra**.

## Correção proposta

Criar migration de repair imediatamente:
  ```sql
  -- 20260417000001_fix_platform_fee_config_check.sql
  ALTER TABLE public.platform_fee_config DROP CONSTRAINT IF EXISTS platform_fee_config_fee_type_check;
  ALTER TABLE public.platform_fee_config ADD CONSTRAINT platform_fee_config_fee_type_check
    CHECK (fee_type IN ('clearing','swap','maintenance','billing_split','fx_spread'));
  ```
  E editar `20260228170000` para incluir o DROP/ADD CHECK antes do INSERT. Também: adicionar CI step que faz `supabase db reset && supabase db push` em cada PR.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.44]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.44).