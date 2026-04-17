---
id: L09-04
audit_ref: "9.4"
lens: 9
title: "Nota fiscal / recibo fiscal não emitida em withdrawals"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "migration", "reliability"]
files: []
correction_type: code
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
# [L09-04] Nota fiscal / recibo fiscal não emitida em withdrawals
> **Lente:** 9 — CRO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Quando Assessoria (CNPJ) recebe withdrawal de moedas reconvertidas em BRL, a plataforma cobra `fx_spread` + taxa de clearing + taxa de swap. Isso é **receita de serviço** (tributável). Busca por `nota_fiscal|nfe|nfs|rps|emissor_fiscal` → zero matches.
## Risco / Impacto

— Receita auditada pela Receita Federal → autuação por omissão de receita + multa 75 % + juros Selic. Cliente B2B não recebe NFS-e e também autua a plataforma.

## Correção proposta

— Integrar emissor (Focus NFe, Enotas, NFE.io):

```sql
CREATE TABLE public.fiscal_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text NOT NULL CHECK (source_type IN
    ('custody_withdrawal','clearing_settlement','swap_order','platform_fee')),
  source_ref_id text NOT NULL,
  customer_document text NOT NULL,
  customer_name text NOT NULL,
  service_code text NOT NULL,  -- código CNAE / Lei Comp. 116
  gross_amount_brl numeric(14,2) NOT NULL,
  taxes_brl numeric(14,2) NOT NULL,
  provider_response jsonb,
  nfs_pdf_url text,
  nfs_xml_url text,
  status text DEFAULT 'pending' CHECK (status IN ('pending','issued','canceled','error')),
  issued_at timestamptz,
  created_at timestamptz DEFAULT now()
);
```

Chamar após `platform_revenue` receber nova linha.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.4).