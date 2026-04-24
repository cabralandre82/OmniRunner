---
id: L03-19
audit_ref: "3.19"
lens: 3
title: "NFS-e / fiscal — Não observado"
severity: na
status: duplicate
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["finance", "fiscal", "compliance"]
files:
  - "supabase/migrations/20260417240000_fiscal_receipts_queue.sql"
correction_type: migration
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: L09-04
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: item cross-ref com L09-04 (CRO) já está fixed via migration 20260417240000_fiscal_receipts_queue.sql. Cabeçalho da migration explicitamente cita L03-19."
---
# [L03-19] NFS-e / fiscal — Não observado
> **Lente:** 3 — CFO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** 🔗 duplicate
**Camada:** N/A
**Personas impactadas:** —

## Achado original
Não encontrei integração com Nuvem Fiscal ou qualquer provedor de NFS-e. Receita da plataforma (`platform_revenue`) é sujeita a PIS/COFINS/ISS. Não ver código de emissão fiscal é não-conformidade operacional.

## Re-auditoria 2026-04-24

A infraestrutura completa de emissão fiscal foi implementada na lente CRO ([L09-04](./L09-04-nota-fiscal-recibo-fiscal-nao-emitida-em-withdrawals.md) — **critical, fixed**) via migration `supabase/migrations/20260417240000_fiscal_receipts_queue.sql`.

O próprio cabeçalho da migration declara cross-reference com este finding (linha 7): `docs/audit/findings/L03-19-nfs-e-fiscal-nao-observado.md (cross-ref)`.

### O que foi entregue (resumo)
1. **Tabela `fiscal_receipts`** — fila canônica de emissões, uma row por evento tributável (`platform_revenue` INSERT). Idempotência via `UNIQUE(source_type, source_ref_id, fee_type)`.
2. **Snapshot fiscal do cliente** no momento do fato gerador (`customer_document`, `customer_legal_name`, `customer_email`, `customer_address`) — atende Art. 195 CTN (retenção 5 anos).
3. **Conversão FX** (`fx_rate_used`, `fx_quote_id`) na data do serviço (exigência RFB).
4. **Trigger `_enqueue_fiscal_receipt`** em `AFTER INSERT ON platform_revenue` — auto-enqueue sem falhar a operação financeira (EXCEPTION handler).
5. **RPCs de ciclo de vida** (`SECURITY DEFINER`, worker pattern): `fn_fiscal_receipt_reserve_batch`, `fn_fiscal_receipt_mark_issued`, `fn_fiscal_receipt_mark_error` (com backoff exponencial), `fn_fiscal_receipt_cancel`.
6. **Estados blocked_missing_data / blocked_missing_fx** para ops descobrir gaps (cliente sem CNPJ; cotação BRL indisponível).
7. **RLS** — platform admin full read; assessoria admin_master lê só as suas receipts.
8. **View `v_fiscal_receipts_needing_attention`** — dashboard operacional para ação do finance team.
9. **Backfill** idempotente para `platform_revenue` pré-existente.
10. **Append-only log `fiscal_receipt_events`** (trilha LGPD Art. 37 + fiscal Art. 195 CTN).

### Follow-ups operacionais (NÃO bloqueantes — fora de scope desta re-auditoria)
- Contratação do emissor real (Nuvem Fiscal / Focus NFe / eNotas).
- Worker de produção que invoca API do provedor via `fn_fiscal_receipt_reserve_batch`.
- Configuração tributária por município (LC 116 service code, ISS rate) — delegado ao SaaS fiscal.

Até o worker entrar em produção, a fila serve de evidência LGPD Art. 37 "registro de operações" + finance team pode emitir manualmente a partir da view de atenção.

### Conclusão
**Gap técnico fechado.** Data model + auto-enqueue + RPCs + RLS + backfill estão em produção. O follow-up é puramente operacional (contratar provedor, subir worker) e foge do escopo desta auditoria de código.

Marcado como `duplicate_of: L09-04` (lente CRO, que entregou toda a implementação).

## Referência narrativa
Contexto completo em [`docs/audit/parts/02-cto-cfo.md`](../parts/02-cto-cfo.md) — anchor `[3.19]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.19).
- `2026-04-24` — Re-auditoria verificou que L09-04 entregou toda a infraestrutura (`fiscal_receipts` queue + trigger + RPCs + RLS + backfill). Consolidado como duplicate.
