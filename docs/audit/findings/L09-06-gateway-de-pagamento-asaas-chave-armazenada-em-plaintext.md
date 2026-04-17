---
id: L09-06
audit_ref: "9.6"
lens: 9
title: "Gateway de pagamento Asaas: chave armazenada em plaintext na DB"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "finance", "anti-cheat", "mobile"]
files: []
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
# [L09-06] Gateway de pagamento Asaas: chave armazenada em plaintext na DB
> **Lente:** 9 — CRO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
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