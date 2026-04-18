---
id: L09-04
audit_ref: "9.4"
lens: 9
title: "Nota fiscal / recibo fiscal não emitida em withdrawals"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "migration", "reliability", "fiscal", "lgpd"]
files:
  - supabase/migrations/20260417240000_fiscal_receipts_queue.sql
  - tools/integration_tests.ts
correction_type: code
test_required: true
tests:
  - tools/integration_tests.ts::"L09-04:*"
linked_issues: []
linked_prs: []
owner: unassigned
runbook: docs/audit/runbooks/L09-04-fiscal-receipts.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Queue + auto-enqueue trigger + RPC lifecycle entregues (stop-the-bleeding). Worker real (Nuvem Fiscal / Focus NFe / eNotas) fica como follow-up operacional — depende de contratação do emissor NFS-e e calibração ISS por município."
---
# [L09-04] Nota fiscal / recibo fiscal não emitida em withdrawals
> **Lente:** 9 — CRO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟡 in-progress
**Camada:** Banco (PostgreSQL) · Fisco · B2B assessorias
**Personas impactadas:** Platform Admin, Finance, Assessoria (CNPJ)

## Achado
Toda vez que `public.platform_revenue` recebia uma linha nova (fee de `fx_spread`
em withdrawals, `clearing`, `swap`, `maintenance`, `billing_split`), isso
representava **receita de serviço tributável** (PIS/COFINS/ISS no Brasil).
Busca por `nota_fiscal|nfe|nfs|rps|emissor_fiscal` no repo: **zero matches**.
Nem registro do fato gerador, nem fila de emissão, nem integração de provedor.

## Risco / Impacto
- Receita Federal autua a plataforma por **omissão de receita** (multa 75 % + Selic).
- Cliente CNPJ (assessoria) não recebe NFS-e → perde dedutibilidade, autua a plataforma.
- Sem registro do fato gerador, não é possível reconstruir histórico pós-auditoria
  (LGPD Art. 37 + Art. 195 CTN exigem trilha de operações por 5 anos).

## Correção aplicada (stop-the-bleeding — Onda 0)

Migration `supabase/migrations/20260417240000_fiscal_receipts_queue.sql`:

### 1. Fila canônica `public.fiscal_receipts`
Uma row por evento tributável. Idempotente via
`UNIQUE(source_type, source_ref_id, fee_type)`. Armazena **snapshot fiscal do
cliente** (legal_name, tax_id, email, address de `billing_customers` no momento)
e **snapshot financeiro** (gross USD, fx_rate_used, gross BRL calculado na hora).
Columns relevantes:

- `source_type` ∈ `custody_withdrawal | clearing_settlement | swap_order | maintenance_fee | billing_split | manual_adjustment`
- `status` ∈ `pending | issuing | issued | error | canceled | blocked_missing_data | blocked_missing_fx`
- `attempts`, `next_retry_at`, `reserved_at`, `reserved_by` — worker state.
- `provider`, `provider_ref`, `provider_response`, `nfs_pdf_url`, `nfs_xml_url` — resposta do emissor.
- `taxes_brl`, `service_code` — preenchidos pelo worker após emissão.

### 2. Log append-only `public.fiscal_receipt_events`
Transições de estado auditáveis. Trigger `_fiscal_events_append_only` bloqueia
UPDATE/DELETE (permite apenas anonymize → zero-UUID do `actor_id`).

### 3. Trigger `_fiscal_receipt_enqueue`
`AFTER INSERT ON platform_revenue` → enfileira automaticamente. Handler com
`EXCEPTION WHEN others` garante que falha da fila **nunca bloqueia o insert na
revenue** (revenue é source-of-truth, fiscal é consequência). Estado inicial:
- `pending` → tem customer + tem FX quote.
- `blocked_missing_data` → customer ausente em `billing_customers`.
- `blocked_missing_fx` → sem cotação BRL ativa.

### 4. RPCs `SECURITY DEFINER` hardened (`search_path` + `lock_timeout`)
- `fn_fiscal_receipt_reserve_batch(p_limit, p_worker_id)` — worker pattern com
  `FOR UPDATE SKIP LOCKED`. Múltiplos workers em paralelo sem colisão.
  Incrementa `attempts`, move para `issuing`.
- `fn_fiscal_receipt_mark_issued(p_id, p_provider, p_provider_ref, p_provider_response?, p_nfs_pdf_url?, p_nfs_xml_url?, p_taxes_brl?, p_service_code?)` —
  finaliza sucesso.
- `fn_fiscal_receipt_mark_error(p_id, p_error_code, p_error_message, p_retryable?)` —
  retryable → volta para `pending` com `next_retry_at = now + min(2^attempt min, 60 min)`;
  attempts ≥ 5 OR não-retryable → `error` terminal.
- `fn_fiscal_receipt_cancel(p_id, p_reason)` — só platform admin. Impede cancel
  de receipts já `issued`.

### 5. RLS
- `service_role`: full write.
- `platform admin` (via `profiles.platform_role = 'admin'`): SELECT tudo.
- `admin_master` da assessoria: SELECT do próprio `group_id`.

### 6. View operacional `v_fiscal_receipts_needing_attention`
Lista receipts em `blocked_*`, `error`, ou `pending > 24h` com `action_required`
legível. Base para dashboard + alerta periódico.

### 7. Backfill
Bloco `DO $$` idempotente cria receipts para todo `platform_revenue` legado que
ainda não tem linha em `fiscal_receipts` (match por `platform_revenue_id`).
Status inicial segue as mesmas regras do trigger.

### 8. LGPD
`fiscal_receipts.issued_by_actor` e `fiscal_receipt_events.actor_id` →
`strategy='anonymize'` em `lgpd_deletion_strategy`. Snapshots fiscais
(`customer_document`, `customer_legal_name`) não entram no registry — não são FK
para `auth.users` e são retidos por obrigação fiscal (Art. 195 CTN 5 anos /
LGPD Art. 16 II).

## Escopo NÃO coberto (follow-up operacional — deferred)

Estes items dependem de **contratação de emissor NFS-e** e não são código puro:

1. Worker real (Edge Function) que chama API do provedor (Nuvem Fiscal /
   Focus NFe / eNotas). Nesta PR fica apenas o contract dos RPCs — worker stub
   manual: Finance team reserva batches e marca issued via SQL direto até o
   provider estar integrado. Runbook documenta o procedimento.
2. Cálculo tributário (service_code LC 116, ISS por município, PIS/COFINS) —
   fica a cargo do SaaS emissor.
3. Portal UI para `v_fiscal_receipts_needing_attention` — next wave.

## Teste de regressão
8 testes em `tools/integration_tests.ts` (`L09-04:*`):
1. Tabela + trigger append-only instalados + RPC reachable.
2. Trigger `platform_revenue INSERT → fiscal_receipts` com FX snapshot correto.
3. Sem `billing_customers` → `blocked_missing_data` + entra em alerta view.
4. UNIQUE(source_type, source_ref_id, fee_type) idempotente (insert duplicado → 1 receipt).
5. Lifecycle completo `reserve_batch → mark_issued` com event trail 3-estados.
6. `mark_error` retryable volta para `pending` com backoff + last_error persiste.
7. `fiscal_receipt_events` é append-only (UPDATE falha com mensagem L09-04).
8. `lgpd_deletion_strategy` registra `issued_by_actor` + `actor_id` como `anonymize`.

Dry-run SQL em DB local validou adicionalmente:
- Retry exhaustion (attempts 1→2→3→4→5 terminal `error`).
- Inserção duplicada em `platform_revenue` com mesmo `source_ref_id`+`fee_type`
  não duplica receipt (idempotência).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.4]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.4).
- `2026-04-18` — Correção aplicada: fila canônica + trigger auto-enqueue + RPC lifecycle + append-only + RLS + backfill + LGPD registry + 8 testes. Worker real fica como follow-up operacional.
