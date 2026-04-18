# Runbook — L09-04 · Emissão fiscal (fiscal_receipts queue)

> **Escopo:** gerenciar a fila de emissão de NFS-e para receita de serviço B2B
> (fees em `platform_revenue`). Complementa L03-19 (NFS-e observability) e
> L04-01 (erasure LGPD).

## Arquitetura

- `public.fiscal_receipts` — fila canônica. Uma row por evento tributável.
  Idempotente via `UNIQUE(source_type, source_ref_id, fee_type)`.
- `public.fiscal_receipt_events` — log append-only de transições de estado.
  Trigger `_fiscal_events_append_only` bloqueia UPDATE/DELETE (exceto
  anonymize → zero-UUID do actor).
- Trigger `_fiscal_receipt_enqueue` em `platform_revenue AFTER INSERT` —
  enfileira automaticamente, snapshot de `billing_customers` + cotação FX
  atual. Falha da fila nunca bloqueia o insert na revenue (EXCEPTION → WARNING).
- RPCs `SECURITY DEFINER` (SET search_path, lock_timeout):
  - `fn_fiscal_receipt_reserve_batch(p_limit, p_worker_id)` — worker
    pattern com `FOR UPDATE SKIP LOCKED`.
  - `fn_fiscal_receipt_mark_issued(p_id, p_provider, p_provider_ref,
    p_provider_response?, p_nfs_pdf_url?, p_nfs_xml_url?, p_taxes_brl?,
    p_service_code?)` — sucesso.
  - `fn_fiscal_receipt_mark_error(p_id, p_error_code, p_error_message,
    p_retryable?)` — retryable: backoff exponencial (2^attempt min, cap
    60 min), max 5 tentativas; não-retryable ou exhausted: `error` terminal.
  - `fn_fiscal_receipt_cancel(p_id, p_reason)` — platform admin only.
- RLS: service_role full; platform admin SELECT tudo; assessoria admin_master
  SELECT do próprio `group_id`.
- View `v_fiscal_receipts_needing_attention` — dashboard de atenção.

## Estados (state machine)

```
                 ┌── blocked_missing_data ─┐
  platform_      │     (falta customer)    │
  revenue  ──► pending ────── issuing ────► issued
  INSERT    │  ▲ (retry,      ▲    │
            │  │  backoff)    │    │
            │  └──── error ◄──┘    │
            │      (retry)         │
            └── blocked_missing_fx │
                (falta FX quote)   │
                                   │
                      canceled  ◄──┘  (admin manual)
```

## Operações rotineiras

### 1. Worker de emissão (stub manual — até integrar provider real)

Enquanto o emissor (Nuvem Fiscal / Focus NFe / eNotas) não estiver contratado,
a Finance Team emite manualmente:

```sql
-- 1. Reservar lote para processamento manual
SELECT * FROM public.fn_fiscal_receipt_reserve_batch(
  p_limit     => 20,
  p_worker_id => 'finance-manual-' || current_date::text
);

-- 2. Para cada row retornada, emitir NFS-e no portal municipal /
--    sistema externo. Depois registrar:
SELECT public.fn_fiscal_receipt_mark_issued(
  p_id                => '<uuid>',
  p_provider          => 'manual',
  p_provider_ref      => 'NFS-2026-00042',           -- número da NFS-e
  p_provider_response => jsonb_build_object(
    'issued_by', 'finance-ops',
    'portal',    'municipal-sp'
  ),
  p_nfs_pdf_url       => 'https://storage/nfse/2026/00042.pdf',
  p_nfs_xml_url       => 'https://storage/nfse/2026/00042.xml',
  p_taxes_brl         => 12.50,
  p_service_code      => '17.01'   -- LC 116 — serviços de administração
);
```

Quando o emissor real entrar, basta trocar o worker por uma Edge Function que
chama a API do provider e aciona os mesmos RPCs.

### 2. Receipt bloqueado por falta de customer data

Sintoma: `status='blocked_missing_data'` (view
`v_fiscal_receipts_needing_attention` sinaliza).

Causa: `billing_customers` não tem row para o `group_id`, ou `tax_id`/
`legal_name` estão null.

Correção:
```sql
-- 1. Preencher billing_customers
INSERT INTO public.billing_customers (
  group_id, legal_name, tax_id, email, address_line,
  address_city, address_state, address_zip
) VALUES (
  '<group_uuid>', 'Assessoria XYZ LTDA', '12.345.678/0001-90',
  'fin@xyz.com.br', 'Rua Tal, 100', 'São Paulo', 'SP', '01310-000'
)
ON CONFLICT (group_id) DO UPDATE
  SET legal_name = EXCLUDED.legal_name, tax_id = EXCLUDED.tax_id;

-- 2. Voltar o receipt para pending (re-snapshot ocorre no worker)
UPDATE public.fiscal_receipts
SET status = 'pending',
    customer_document   = '12.345.678/0001-90',
    customer_legal_name = 'Assessoria XYZ LTDA',
    customer_email      = 'fin@xyz.com.br',
    customer_address    = jsonb_build_object(
      'line', 'Rua Tal, 100', 'city', 'São Paulo',
      'state', 'SP', 'zip', '01310-000'
    ),
    next_retry_at = now()
WHERE status = 'blocked_missing_data'
  AND group_id = '<group_uuid>';
```

### 3. Receipt bloqueado por falta de FX quote

Sintoma: `status='blocked_missing_fx'`.

Correção: refresh de cotação no portal (`/platform/fx`). Depois:
```sql
UPDATE public.fiscal_receipts fr
SET status = 'pending',
    fx_rate_used = q.rate_per_usd,
    fx_quote_id  = q.id,
    gross_amount_brl = round(fr.gross_amount_usd * q.rate_per_usd, 2),
    next_retry_at = now()
FROM (SELECT id, rate_per_usd FROM public.platform_fx_quotes
      WHERE currency_code='BRL' AND is_active) q
WHERE fr.status = 'blocked_missing_fx';
```

### 4. Cancel de uma receipt duplicada / estorno

```sql
SELECT public.fn_fiscal_receipt_cancel(
  p_id     => '<uuid>',
  p_reason => 'Duplicata detectada em reconciliação — emissão original NFS-XXX'
);
```

Nota: `fn_fiscal_receipt_cancel` exige `platform_role = 'admin'`.

### 5. Investigar histórico de um receipt

```sql
SELECT from_status, to_status, worker_id, actor_id, notes, payload, occurred_at
FROM public.fiscal_receipt_events
WHERE receipt_id = '<uuid>'
ORDER BY occurred_at;
```

### 6. Dashboard de atenção

```sql
SELECT status,
       count(*) AS qty,
       sum(gross_amount_usd) AS total_usd,
       sum(gross_amount_brl) AS total_brl
FROM public.v_fiscal_receipts_needing_attention
GROUP BY status
ORDER BY qty DESC;
```

## Invariantes que **NUNCA** podem cair

1. `fiscal_receipt_events` é append-only. Qualquer migration que tente
   alterar este comportamento é erro crítico — retenção Art. 195 CTN.
2. Trigger `_fiscal_receipt_enqueue` NÃO pode RAISE EXCEPTION — revenue
   é source-of-truth; se a fila falhar, fica o WARNING no log mas o
   insert em `platform_revenue` vai em frente.
3. UNIQUE(source_type, source_ref_id, fee_type) é o ancoramento de
   idempotência. Qualquer mudança deste índice quebra o contrato.
4. `fn_fiscal_receipt_cancel` não cancela receipt já `issued` (isso seria
   NFS-e cancelada no emissor, processo diferente — fora de escopo).
5. `attempts` máximo = 5 antes de `error` terminal. Ajuste requer
   revisão de SLA com Finance.

## Métricas (SLO candidates)

- `pending_over_24h_count`: quantos receipts > 24h sem ser issued.
- `error_rate`: `count(error) / count(total)` nos últimos 7 dias.
- `blocked_missing_data_count`: sinaliza billing_customers incompleto.
- `avg_time_to_issue`: `avg(issued_at - created_at)` — SLO candidato 4h.

## Referências
- Finding: [`docs/audit/findings/L09-04-nota-fiscal-recibo-fiscal-nao-emitida-em-withdrawals.md`](../findings/L09-04-nota-fiscal-recibo-fiscal-nao-emitida-em-withdrawals.md)
- Cross-ref: [`L03-19`](../findings/L03-19-nfs-e-fiscal-nao-observado.md) (observability do fiscal)
- Migration: `supabase/migrations/20260417240000_fiscal_receipts_queue.sql`
- Testes: `tools/integration_tests.ts` (grep `L09-04:`)
