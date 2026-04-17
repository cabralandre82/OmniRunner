---
id: L01-17
audit_ref: "1.17"
lens: 1
title: "POST /api/billing/asaas — Armazenamento de API Key"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["mobile", "portal", "migration", "reliability"]
files:
  - portal/src/app/api/billing/asaas/route.ts
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
# [L01-17] POST /api/billing/asaas — Armazenamento de API Key
> **Lente:** 1 — CISO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** PORTAL + BACKEND
**Personas impactadas:** Assessoria (admin_master)
## Achado
`portal/src/app/api/billing/asaas/route.ts` (linhas 80-103) armazena `api_key` do Asaas em `payment_provider_config.api_key` **em texto puro**. A Asaas API Key permite emitir cobranças, consultar clientes e iniciar transferências.
  - Não há indicação de criptografia na inserção (`.upsert({ api_key: apiKey, ... })`). Nenhuma migration adiciona `api_key_encrypted`.
## Risco / Impacto

Se o banco vazar, TODAS as API Keys Asaas das assessorias vazam. Um atacante pode criar cobranças em nome da assessoria ou fazer sacar fundos da conta Asaas.

## Correção proposta

1. Criar migration que adiciona coluna `api_key_encrypted` e remove `api_key` texto-puro.
  2. Usar `pgcrypto.pgp_sym_encrypt(key, current_setting('app.asaas_key_secret'))`. Secret em Vercel env `ASAAS_KEY_VAULT_SECRET`.
  3. Mascarar leituras: `SELECT CONCAT('***', RIGHT(pgp_sym_decrypt(api_key_encrypted, secret), 4))`.
  4. Forçar rotação: endpoint `POST /api/billing/asaas/rotate-key` que re-criptografa.
  ```sql
  ALTER TABLE payment_provider_config ADD COLUMN api_key_encrypted bytea;
  -- backfill com encryption
  UPDATE payment_provider_config SET api_key_encrypted = pgp_sym_encrypt(api_key, current_setting('app.asaas_key_secret'));
  ALTER TABLE payment_provider_config DROP COLUMN api_key;
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.17).