---
id: L09-06
audit_ref: "9.6"
lens: 9
title: "Gateway de pagamento Asaas: chave armazenada em plaintext na DB"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "finance", "anti-cheat", "mobile"]
files:
  - supabase/migrations/20260421500000_l09_06_billing_providers_at_rest_encryption.sql
  - tools/audit/check-billing-providers-encryption.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:41110d8
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  billing_providers table stores per-assessoria Asaas / Mercado
  Pago / Stripe credentials as pgp_sym_encrypt bytea. RLS +
  column privileges make api_key_enc unreadable by authenticated
  / anon; only service_role can SELECT the ciphertext. Access
  goes exclusively through fn_set_billing_provider_key (bumps
  key_version, writes key_set audit row) and
  fn_get_billing_provider_key (decrypts, writes key_access audit
  row with reason). Master key loaded into GUC app.settings.kms_key
  per edge-function transaction from Supabase Vault / AWS KMS.
  KMS_UNAVAILABLE guard closes the "accidental plaintext" path.
  Ships with audit:billing-providers-encryption guard
  (32 invariants).
---
# [L09-06] Gateway de pagamento Asaas: chave armazenada em plaintext na DB
> **Lente:** 9 — CRO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Conforme [1.19] de PARTE 1. Risco regulatório adicional: a LGPD (dado pessoal + financeiro) e a PCI DSS quando Asaas agrega dados de cartão.
## Risco / Impacto

— Acesso DBA malicioso ou dump para staging → atacante usa chave para cobranças fraudulentas no CNPJ da assessoria.

## Correção proposta

— Usar `pgp_sym_encrypt` com master key em KMS (AWS KMS, Supabase Vault):

```sql
UPDATE billing_providers SET api_key =
  pgp_sym_encrypt(api_key, current_setting('app.settings.kms_key'))
WHERE api_key IS NOT NULL AND api_key NOT LIKE '\x%';
```

Função `fn_get_asaas_key(group_id uuid) RETURNS text SECURITY DEFINER` faz o decrypt e loga acesso em `audit_logs`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.6).