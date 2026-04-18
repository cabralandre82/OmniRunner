-- ══════════════════════════════════════════════════════════════════════════
-- L09-04 — Emissão fiscal (NFS-e) para receita de serviço B2B
--
-- Referência auditoria:
--   docs/audit/findings/L09-04-nota-fiscal-recibo-fiscal-nao-emitida-em-withdrawals.md
--   docs/audit/parts/05-cro-cso-supply-cron.md [9.4]
--   docs/audit/findings/L03-19-nfs-e-fiscal-nao-observado.md (cross-ref)
--
-- Problema:
--   Toda vez que a plataforma credita fee em `public.platform_revenue`
--   (fx_spread, clearing, swap, maintenance, billing_split) gera RECEITA DE
--   SERVIÇO tributável (PIS/COFINS/ISS no Brasil). Grep por
--   `nota_fiscal|nfe|nfs|rps|emissor_fiscal` retorna zero — não existia
--   nem registro do evento tributável, nem fila de emissão, nem provider
--   integration. Receita Federal autua por omissão de receita (multa 75 %
--   + Selic) e o cliente CNPJ não recebe NFS-e para deduzir.
--
-- Correção (stop-the-bleeding, Onda 0):
--   1. `fiscal_receipts` — fila canônica de emissões, uma row por evento
--      tributável. Idempotência via UNIQUE(source_type, source_ref_id,
--      fee_type). Snapshot fiscal-relevant do cliente no momento do evento
--      (legal_name, tax_id, address, email) para dar consistência mesmo se
--      billing_customers mudar depois. Armazena bruto em BRL convertido
--      pela cotação FX autoritativa da época.
--   2. Trigger `_enqueue_fiscal_receipt()` em `platform_revenue` AFTER
--      INSERT — enfileira automaticamente. Sem dado de cliente → status
--      `blocked_missing_data` (não falha a operação financeira, mas cria
--      alerta). Sem cotação FX → status `blocked_missing_fx`.
--   3. `fiscal_receipt_events` — log append-only de state transitions
--      (pending → issuing → issued | error | canceled) para auditoria.
--   4. RPCs `SECURITY DEFINER` com SET search_path/lock_timeout:
--        - `fn_fiscal_receipt_reserve_batch(p_limit, p_worker_id)` — worker
--          reclama um batch de receipts pendentes com FOR UPDATE SKIP
--          LOCKED. Move status para `issuing`, cravando reserved_at e
--          reserved_by (worker id).
--        - `fn_fiscal_receipt_mark_issued(p_id, p_provider, p_provider_ref,
--          p_provider_response, p_nfs_pdf_url, p_nfs_xml_url, p_taxes_brl)`
--          — finaliza sucesso.
--        - `fn_fiscal_receipt_mark_error(p_id, p_error_code, p_error_msg,
--          p_retryable)` — retryable: volta para `pending` com next_retry_at
--          = now + backoff(attempt); else: `error` terminal.
--        - `fn_fiscal_receipt_cancel(p_id, p_reason)` — admin only, para
--          casos de estorno / duplicação detectada manualmente.
--   5. Backfill: para todo `platform_revenue` pré-existente sem receipt,
--      enfileira com `source='backfill'`. Drift-safe (idempotente).
--   6. View `v_fiscal_receipts_needing_attention` — receipts em estados
--      que exigem ação operacional (blocked_*, error, pending > 24h, ou
--      retries exhausted).
--   7. RLS: service_role full; platform admin lê tudo; assessoria
--      admin_master lê receipts do próprio group_id.
--   8. lgpd_deletion_strategy: `issued_by_actor` → anonymize (preserva
--      trilha); `customer_*`/`tax_id_snapshot`/`legal_name_snapshot` →
--      keep (retenção fiscal 5 anos Art. 195 CTN supera LGPD 18 VI).
--
-- Escopo do que NÃO muda aqui (follow-up operacional):
--   - Contratação do emissor NFS-e (Nuvem Fiscal / Focus NFe / eNotas).
--   - Worker real que chama API do emissor — nesta PR, apenas contract da
--     RPC + fila populada. Até o worker entrar, a fila serve de evidência
--     LGPD Art. 37 "registro de operações" + fin team emite manualmente.
--   - Cálculo tributário (service_code LC 116, ISS por município, PIS/
--     COFINS) — fica a cargo do provider SaaS.
--
-- Compat / invariants:
--   - Insert em `platform_revenue` NUNCA falha por erro da fila fiscal
--     (trigger é AFTER INSERT + EXCEPTION handler que loga em
--     fiscal_receipt_events.notes). Revenue é source-of-truth, fiscal é
--     consequência.
--   - Worker pode rodar múltiplas instâncias em paralelo (SKIP LOCKED).
--   - UNIQUE(source_type, source_ref_id, fee_type) torna enqueue
--     idempotente frente a re-execuções.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

-- ══════════════════════════════════════════════════════════════════════════
-- 1. fiscal_receipts (fila canônica)
-- ══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.fiscal_receipts (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Origem (chave idempotente)
  source_type              text NOT NULL
    CHECK (source_type IN ('custody_withdrawal', 'clearing_settlement',
                           'swap_order', 'maintenance_fee', 'billing_split',
                           'manual_adjustment')),
  source_ref_id            text NOT NULL,
  fee_type                 text NOT NULL
    CHECK (fee_type IN ('clearing', 'swap', 'fx_spread', 'maintenance',
                        'billing_split')),
  group_id                 uuid REFERENCES public.coaching_groups(id)
                             ON DELETE SET NULL,
  platform_revenue_id      uuid REFERENCES public.platform_revenue(id)
                             ON DELETE SET NULL,
  -- Snapshot do cliente no momento do fato gerador
  customer_document        text,       -- CNPJ/CPF; null=missing_data
  customer_legal_name      text,
  customer_email           text,
  customer_address         jsonb,      -- {line,city,state,zip}
  -- Snapshot financeiro no momento do fato gerador
  currency_code            text NOT NULL DEFAULT 'BRL'
    CHECK (currency_code IN ('BRL', 'USD')),
  gross_amount_usd         numeric(14,2) NOT NULL CHECK (gross_amount_usd > 0),
  fx_rate_used             numeric(18,8),                    -- BRL per USD na hora
  fx_quote_id              uuid REFERENCES public.platform_fx_quotes(id)
                             ON DELETE SET NULL,
  gross_amount_brl         numeric(14,2),                    -- null até ter FX
  taxes_brl                numeric(14,2),                    -- preenchido após emissão
  service_code             text,                             -- LC 116 — determinado pelo provider
  -- Estado da fila
  status                   text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'issuing', 'issued', 'error',
                      'canceled', 'blocked_missing_data', 'blocked_missing_fx')),
  attempts                 integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_retry_at            timestamptz,
  reserved_at              timestamptz,
  reserved_by              text,       -- worker identifier
  -- Provedor
  provider                 text,       -- 'nuvem_fiscal' | 'focus_nfe' | 'enotas' | 'manual'
  provider_ref             text,       -- id externo do RPS/NFS-e
  provider_response        jsonb,      -- snapshot do body da resposta
  nfs_pdf_url              text,
  nfs_xml_url              text,
  -- Erro (se houver)
  last_error_code          text,
  last_error_message       text,
  -- Auditoria
  issued_by_actor          uuid REFERENCES auth.users(id) ON DELETE SET DEFAULT,
  issued_at                timestamptz,
  canceled_reason          text,
  canceled_at              timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  -- Idempotência: uma única nota por (source, ref, fee_type)
  CONSTRAINT fiscal_receipts_idempotent
    UNIQUE (source_type, source_ref_id, fee_type)
);

ALTER TABLE public.fiscal_receipts
  ALTER COLUMN issued_by_actor SET DEFAULT '00000000-0000-0000-0000-000000000000';

COMMENT ON TABLE public.fiscal_receipts IS
  'L09-04: fila canônica de emissões fiscais (NFS-e) para receita de serviço '
  'B2B. Uma row por evento tributável (cada insert em platform_revenue). '
  'Idempotente via UNIQUE(source_type, source_ref_id, fee_type).';
COMMENT ON COLUMN public.fiscal_receipts.customer_document IS
  'Snapshot de billing_customers.tax_id no momento do fato gerador. Mantém '
  'consistência fiscal mesmo se cliente mudar CNPJ depois.';
COMMENT ON COLUMN public.fiscal_receipts.fx_rate_used IS
  'Cotação platform_fx_quotes.rate_per_usd (BRL per USD) no momento do '
  'enqueue. Exigido pela Receita Federal: fato gerador na data do serviço.';
COMMENT ON COLUMN public.fiscal_receipts.status IS
  'pending (aguarda emissão) → issuing (worker reservou) → issued (sucesso) '
  '| error (retries esgotados) | canceled (admin). '
  'blocked_missing_data=sem customer_document; blocked_missing_fx=sem FX ativa.';

CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_status_retry
  ON public.fiscal_receipts (status, next_retry_at NULLS FIRST)
  WHERE status IN ('pending', 'blocked_missing_data', 'blocked_missing_fx');

CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_group
  ON public.fiscal_receipts (group_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_provider_ref
  ON public.fiscal_receipts (provider, provider_ref)
  WHERE provider_ref IS NOT NULL;

-- ══════════════════════════════════════════════════════════════════════════
-- 2. fiscal_receipt_events (log append-only de transições)
-- ══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.fiscal_receipt_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id    uuid NOT NULL REFERENCES public.fiscal_receipts(id) ON DELETE CASCADE,
  from_status   text,
  to_status     text NOT NULL,
  actor_id      uuid REFERENCES auth.users(id) ON DELETE SET DEFAULT,
  worker_id     text,
  notes         text,
  payload       jsonb,
  occurred_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.fiscal_receipt_events
  ALTER COLUMN actor_id SET DEFAULT '00000000-0000-0000-0000-000000000000';

CREATE INDEX IF NOT EXISTS idx_fiscal_events_receipt
  ON public.fiscal_receipt_events (receipt_id, occurred_at DESC);

COMMENT ON TABLE public.fiscal_receipt_events IS
  'L09-04: log append-only de transições de estado em fiscal_receipts. '
  'Serve de evidência Art. 37 LGPD + Art. 195 CTN (retenção fiscal 5 anos).';

-- Append-only: bloqueia UPDATE / DELETE (exceto anonimização)
CREATE OR REPLACE FUNCTION public._fiscal_events_append_only()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '[L09-04] fiscal_receipt_events é append-only: DELETE bloqueado';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    -- permite apenas transição para zero-UUID (erasure)
    IF NEW.actor_id IS NOT DISTINCT FROM OLD.actor_id
       OR NEW.actor_id <> '00000000-0000-0000-0000-000000000000'::uuid THEN
      RAISE EXCEPTION '[L09-04] fiscal_receipt_events é append-only';
    END IF;
    IF (NEW.from_status, NEW.to_status, NEW.receipt_id, NEW.occurred_at,
        NEW.worker_id, NEW.notes, NEW.payload)
       IS DISTINCT FROM
       (OLD.from_status, OLD.to_status, OLD.receipt_id, OLD.occurred_at,
        OLD.worker_id, OLD.notes, OLD.payload) THEN
      RAISE EXCEPTION '[L09-04] fiscal_receipt_events é append-only';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS _fiscal_events_append_only ON public.fiscal_receipt_events;
CREATE TRIGGER _fiscal_events_append_only
  BEFORE UPDATE OR DELETE ON public.fiscal_receipt_events
  FOR EACH ROW EXECUTE FUNCTION public._fiscal_events_append_only();

-- ══════════════════════════════════════════════════════════════════════════
-- 3. Trigger: auto-enqueue a partir de platform_revenue INSERT
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._enqueue_fiscal_receipt()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_source_type    text;
  v_customer       record;
  v_fx             record;
  v_rate           numeric(18,8);
  v_gross_brl      numeric(14,2);
  v_status         text;
  v_receipt_id     uuid;
BEGIN
  -- Mapeia fee_type → source_type (nomenclatura fiscal)
  v_source_type := CASE NEW.fee_type
    WHEN 'fx_spread'     THEN 'custody_withdrawal'
    WHEN 'clearing'      THEN 'clearing_settlement'
    WHEN 'swap'          THEN 'swap_order'
    WHEN 'maintenance'   THEN 'maintenance_fee'
    WHEN 'billing_split' THEN 'billing_split'
    ELSE 'manual_adjustment'
  END;

  -- Snapshot do cliente (se existe)
  SELECT bc.legal_name, bc.tax_id, bc.email, bc.address_line, bc.address_city,
         bc.address_state, bc.address_zip
  INTO v_customer
  FROM public.billing_customers bc
  WHERE bc.group_id = NEW.group_id;

  -- Cotação FX ativa para BRL no momento
  SELECT q.id, q.rate_per_usd
  INTO v_fx
  FROM public.platform_fx_quotes q
  WHERE q.currency_code = 'BRL' AND q.is_active = true
  ORDER BY q.fetched_at DESC
  LIMIT 1;

  v_rate := v_fx.rate_per_usd;
  v_gross_brl := CASE WHEN v_rate IS NOT NULL
                      THEN round(NEW.amount_usd * v_rate, 2)
                      ELSE NULL END;

  -- Status inicial
  v_status := CASE
    WHEN v_customer.tax_id IS NULL OR v_customer.legal_name IS NULL
      THEN 'blocked_missing_data'
    WHEN v_rate IS NULL
      THEN 'blocked_missing_fx'
    ELSE 'pending'
  END;

  -- Enqueue (idempotente: ON CONFLICT não explode, só ignora)
  INSERT INTO public.fiscal_receipts (
    source_type, source_ref_id, fee_type, group_id, platform_revenue_id,
    customer_document, customer_legal_name, customer_email, customer_address,
    gross_amount_usd, fx_rate_used, fx_quote_id, gross_amount_brl,
    status, next_retry_at
  ) VALUES (
    v_source_type,
    COALESCE(NEW.source_ref_id, NEW.id::text),
    NEW.fee_type,
    NEW.group_id,
    NEW.id,
    v_customer.tax_id,
    v_customer.legal_name,
    v_customer.email,
    CASE WHEN v_customer.legal_name IS NOT NULL THEN jsonb_build_object(
      'line',  v_customer.address_line,
      'city',  v_customer.address_city,
      'state', v_customer.address_state,
      'zip',   v_customer.address_zip
    ) END,
    NEW.amount_usd,
    v_rate,
    v_fx.id,
    v_gross_brl,
    v_status,
    CASE WHEN v_status = 'pending' THEN now() ELSE now() + interval '1 hour' END
  )
  ON CONFLICT (source_type, source_ref_id, fee_type) DO NOTHING
  RETURNING id INTO v_receipt_id;

  IF v_receipt_id IS NOT NULL THEN
    INSERT INTO public.fiscal_receipt_events (
      receipt_id, from_status, to_status, notes, payload
    ) VALUES (
      v_receipt_id, NULL, v_status,
      'Enqueued via platform_revenue trigger',
      jsonb_build_object(
        'platform_revenue_id', NEW.id,
        'fee_type', NEW.fee_type,
        'amount_usd', NEW.amount_usd,
        'has_customer', v_customer.tax_id IS NOT NULL,
        'has_fx', v_rate IS NOT NULL
      )
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN others THEN
  -- NUNCA falha o INSERT em platform_revenue por causa da fila fiscal.
  -- Log o erro num canal simples (via RAISE WARNING) — operador monitora.
  RAISE WARNING '[L09-04] Falha ao enfileirar fiscal_receipt para platform_revenue %: % (%)',
    NEW.id, SQLERRM, SQLSTATE;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._enqueue_fiscal_receipt() FROM PUBLIC;

DROP TRIGGER IF EXISTS _fiscal_receipt_enqueue ON public.platform_revenue;
CREATE TRIGGER _fiscal_receipt_enqueue
  AFTER INSERT ON public.platform_revenue
  FOR EACH ROW EXECUTE FUNCTION public._enqueue_fiscal_receipt();

-- ══════════════════════════════════════════════════════════════════════════
-- 4. RPCs de ciclo de vida (SECURITY DEFINER hardened)
-- ══════════════════════════════════════════════════════════════════════════

-- Reserva de batch — worker pattern com FOR UPDATE SKIP LOCKED
CREATE OR REPLACE FUNCTION public.fn_fiscal_receipt_reserve_batch(
  p_limit     integer DEFAULT 10,
  p_worker_id text    DEFAULT 'anonymous'
)
  RETURNS SETOF public.fiscal_receipts
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_row public.fiscal_receipts;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 200 THEN
    RAISE EXCEPTION '[L09-04] p_limit deve estar entre 1 e 200';
  END IF;
  IF p_worker_id IS NULL OR length(p_worker_id) < 3 THEN
    RAISE EXCEPTION '[L09-04] p_worker_id inválido';
  END IF;

  FOR v_row IN
    WITH claimed AS (
      SELECT id
      FROM public.fiscal_receipts
      WHERE status = 'pending'
        AND (next_retry_at IS NULL OR next_retry_at <= now())
      ORDER BY created_at
      FOR UPDATE SKIP LOCKED
      LIMIT p_limit
    )
    UPDATE public.fiscal_receipts fr
    SET status = 'issuing',
        attempts = fr.attempts + 1,
        reserved_at = now(),
        reserved_by = p_worker_id,
        updated_at = now()
    FROM claimed
    WHERE fr.id = claimed.id
    RETURNING fr.*
  LOOP
    INSERT INTO public.fiscal_receipt_events (
      receipt_id, from_status, to_status, worker_id, notes
    ) VALUES (
      v_row.id, 'pending', 'issuing', p_worker_id, 'Reserved by worker'
    );
    RETURN NEXT v_row;
  END LOOP;

  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fiscal_receipt_reserve_batch(integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_fiscal_receipt_reserve_batch(integer, text) TO service_role;

-- Marca emissão bem-sucedida
CREATE OR REPLACE FUNCTION public.fn_fiscal_receipt_mark_issued(
  p_id                 uuid,
  p_provider           text,
  p_provider_ref       text,
  p_provider_response  jsonb DEFAULT NULL,
  p_nfs_pdf_url        text  DEFAULT NULL,
  p_nfs_xml_url        text  DEFAULT NULL,
  p_taxes_brl          numeric(14,2) DEFAULT NULL,
  p_service_code       text  DEFAULT NULL
)
  RETURNS public.fiscal_receipts
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_row public.fiscal_receipts;
BEGIN
  IF p_id IS NULL OR p_provider IS NULL OR p_provider_ref IS NULL THEN
    RAISE EXCEPTION '[L09-04] parâmetros obrigatórios ausentes';
  END IF;

  UPDATE public.fiscal_receipts
  SET status             = 'issued',
      provider           = p_provider,
      provider_ref       = p_provider_ref,
      provider_response  = COALESCE(p_provider_response, provider_response),
      nfs_pdf_url        = COALESCE(p_nfs_pdf_url, nfs_pdf_url),
      nfs_xml_url        = COALESCE(p_nfs_xml_url, nfs_xml_url),
      taxes_brl          = COALESCE(p_taxes_brl, taxes_brl),
      service_code       = COALESCE(p_service_code, service_code),
      issued_at          = now(),
      issued_by_actor    = auth.uid(),
      last_error_code    = NULL,
      last_error_message = NULL,
      updated_at         = now()
  WHERE id = p_id AND status = 'issuing'
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION '[L09-04] receipt % não está em status issuing', p_id;
  END IF;

  INSERT INTO public.fiscal_receipt_events (
    receipt_id, from_status, to_status, actor_id, notes, payload
  ) VALUES (
    v_row.id, 'issuing', 'issued', auth.uid(), 'Issued by worker',
    jsonb_build_object('provider', p_provider, 'provider_ref', p_provider_ref)
  );

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fiscal_receipt_mark_issued(
  uuid, text, text, jsonb, text, text, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_fiscal_receipt_mark_issued(
  uuid, text, text, jsonb, text, text, numeric, text) TO service_role;

-- Marca erro (retryable ou terminal)
CREATE OR REPLACE FUNCTION public.fn_fiscal_receipt_mark_error(
  p_id             uuid,
  p_error_code     text,
  p_error_message  text,
  p_retryable      boolean DEFAULT true
)
  RETURNS public.fiscal_receipts
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_row public.fiscal_receipts;
  v_max_attempts constant integer := 5;
  v_next_status  text;
  v_next_retry   timestamptz;
BEGIN
  IF p_id IS NULL OR p_error_code IS NULL THEN
    RAISE EXCEPTION '[L09-04] p_id e p_error_code são obrigatórios';
  END IF;

  SELECT * INTO v_row FROM public.fiscal_receipts WHERE id = p_id FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION '[L09-04] receipt % não encontrada', p_id;
  END IF;
  IF v_row.status <> 'issuing' THEN
    RAISE EXCEPTION '[L09-04] receipt % não está em status issuing (got %)',
      p_id, v_row.status;
  END IF;

  -- Retry policy: se for retryable E attempts < max, volta a 'pending'
  -- com backoff exponencial (2^attempt minutos, cap 60min).
  IF p_retryable AND v_row.attempts < v_max_attempts THEN
    v_next_status := 'pending';
    v_next_retry := now() + least(
      interval '1 minute' * (2 ^ v_row.attempts),
      interval '60 minutes'
    );
  ELSE
    v_next_status := 'error';
    v_next_retry := NULL;
  END IF;

  UPDATE public.fiscal_receipts
  SET status             = v_next_status,
      next_retry_at      = v_next_retry,
      reserved_at        = NULL,
      reserved_by        = NULL,
      last_error_code    = p_error_code,
      last_error_message = p_error_message,
      updated_at         = now()
  WHERE id = p_id
  RETURNING * INTO v_row;

  INSERT INTO public.fiscal_receipt_events (
    receipt_id, from_status, to_status, notes, payload
  ) VALUES (
    v_row.id, 'issuing', v_next_status,
    'Provider error',
    jsonb_build_object(
      'error_code', p_error_code,
      'error_message', p_error_message,
      'retryable', p_retryable,
      'attempts', v_row.attempts,
      'next_retry_at', v_next_retry
    )
  );

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fiscal_receipt_mark_error(uuid, text, text, boolean)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_fiscal_receipt_mark_error(uuid, text, text, boolean)
  TO service_role;

-- Cancel manual (admin-only)
CREATE OR REPLACE FUNCTION public.fn_fiscal_receipt_cancel(
  p_id     uuid,
  p_reason text
)
  RETURNS public.fiscal_receipts
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_row        public.fiscal_receipts;
  v_is_admin   boolean;
BEGIN
  IF p_id IS NULL OR p_reason IS NULL OR length(trim(p_reason)) < 5 THEN
    RAISE EXCEPTION '[L09-04] p_reason obrigatório (min 5 chars)';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND platform_role = 'admin'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION '[L09-04] apenas platform admin pode cancelar receipts';
  END IF;

  UPDATE public.fiscal_receipts
  SET status          = 'canceled',
      canceled_reason = p_reason,
      canceled_at     = now(),
      next_retry_at   = NULL,
      updated_at      = now()
  WHERE id = p_id
    AND status <> 'issued'    -- não cancelar o que já foi emitido
    AND status <> 'canceled'
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION '[L09-04] receipt % não encontrada ou já issued/canceled', p_id;
  END IF;

  INSERT INTO public.fiscal_receipt_events (
    receipt_id, from_status, to_status, actor_id, notes
  ) VALUES (
    v_row.id, v_row.status, 'canceled', auth.uid(),
    format('Canceled by admin: %s', p_reason)
  );

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fiscal_receipt_cancel(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_fiscal_receipt_cancel(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_fiscal_receipt_cancel(uuid, text) TO service_role;

-- ══════════════════════════════════════════════════════════════════════════
-- 5. RLS
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.fiscal_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_receipt_events ENABLE ROW LEVEL SECURITY;

-- fiscal_receipts: platform admin full read; assessoria admin_master lê o seu
DROP POLICY IF EXISTS fiscal_receipts_admin_read ON public.fiscal_receipts;
CREATE POLICY fiscal_receipts_admin_read
  ON public.fiscal_receipts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = fiscal_receipts.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- fiscal_receipt_events idem
DROP POLICY IF EXISTS fiscal_events_admin_read ON public.fiscal_receipt_events;
CREATE POLICY fiscal_events_admin_read
  ON public.fiscal_receipt_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.fiscal_receipts fr
      JOIN public.coaching_members cm ON cm.group_id = fr.group_id
      WHERE fr.id = fiscal_receipt_events.receipt_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

REVOKE ALL ON TABLE public.fiscal_receipts FROM PUBLIC;
REVOKE ALL ON TABLE public.fiscal_receipts FROM anon;
GRANT SELECT ON TABLE public.fiscal_receipts TO authenticated;
GRANT ALL    ON TABLE public.fiscal_receipts TO service_role;

REVOKE ALL ON TABLE public.fiscal_receipt_events FROM PUBLIC;
REVOKE ALL ON TABLE public.fiscal_receipt_events FROM anon;
GRANT SELECT ON TABLE public.fiscal_receipt_events TO authenticated;
GRANT ALL    ON TABLE public.fiscal_receipt_events TO service_role;

-- ══════════════════════════════════════════════════════════════════════════
-- 6. View de alertas operacionais
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.v_fiscal_receipts_needing_attention AS
SELECT
  fr.id,
  fr.source_type,
  fr.source_ref_id,
  fr.fee_type,
  fr.group_id,
  fr.gross_amount_usd,
  fr.gross_amount_brl,
  fr.status,
  fr.attempts,
  fr.last_error_code,
  fr.last_error_message,
  fr.next_retry_at,
  fr.created_at,
  CASE
    WHEN fr.status = 'blocked_missing_data' THEN
      'Sem customer_document em billing_customers — preencher tax_id/legal_name'
    WHEN fr.status = 'blocked_missing_fx' THEN
      'Sem cotação BRL ativa em platform_fx_quotes — refrescar em /platform/fx'
    WHEN fr.status = 'error' THEN
      'Retries esgotados — revisar last_error_* e cancel ou reset manual'
    WHEN fr.status = 'pending' AND fr.created_at < now() - interval '24 hours' THEN
      'Pendente > 24h — worker parado? provider degradado?'
    ELSE
      'Needs attention'
  END AS action_required
FROM public.fiscal_receipts fr
WHERE fr.status IN ('blocked_missing_data', 'blocked_missing_fx', 'error')
   OR (fr.status = 'pending' AND fr.created_at < now() - interval '24 hours');

COMMENT ON VIEW public.v_fiscal_receipts_needing_attention IS
  'L09-04: receipts em estado que exige ação do platform admin ou do finance '
  'team. Expor em dashboard + alerta periódico.';

GRANT SELECT ON public.v_fiscal_receipts_needing_attention TO authenticated;
GRANT SELECT ON public.v_fiscal_receipts_needing_attention TO service_role;

-- ══════════════════════════════════════════════════════════════════════════
-- 7. Backfill: platform_revenue pré-existente sem receipt
-- ══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_count integer := 0;
BEGIN
  WITH missing AS (
    SELECT pr.*
    FROM public.platform_revenue pr
    LEFT JOIN public.fiscal_receipts fr ON fr.platform_revenue_id = pr.id
    WHERE fr.id IS NULL
  ),
  fx AS (
    SELECT id, rate_per_usd
    FROM public.platform_fx_quotes
    WHERE currency_code = 'BRL' AND is_active = true
    ORDER BY fetched_at DESC
    LIMIT 1
  ),
  inserted AS (
    INSERT INTO public.fiscal_receipts (
      source_type, source_ref_id, fee_type, group_id, platform_revenue_id,
      customer_document, customer_legal_name, customer_email, customer_address,
      gross_amount_usd, fx_rate_used, fx_quote_id, gross_amount_brl,
      status, next_retry_at, created_at
    )
    SELECT
      CASE m.fee_type
        WHEN 'fx_spread'     THEN 'custody_withdrawal'
        WHEN 'clearing'      THEN 'clearing_settlement'
        WHEN 'swap'          THEN 'swap_order'
        WHEN 'maintenance'   THEN 'maintenance_fee'
        WHEN 'billing_split' THEN 'billing_split'
        ELSE 'manual_adjustment'
      END,
      COALESCE(m.source_ref_id, m.id::text),
      m.fee_type,
      m.group_id,
      m.id,
      bc.tax_id,
      bc.legal_name,
      bc.email,
      CASE WHEN bc.legal_name IS NOT NULL THEN jsonb_build_object(
        'line',  bc.address_line,
        'city',  bc.address_city,
        'state', bc.address_state,
        'zip',   bc.address_zip
      ) END,
      m.amount_usd,
      fx.rate_per_usd,
      fx.id,
      CASE WHEN fx.rate_per_usd IS NOT NULL
           THEN round(m.amount_usd * fx.rate_per_usd, 2) END,
      CASE
        WHEN bc.tax_id IS NULL OR bc.legal_name IS NULL THEN 'blocked_missing_data'
        WHEN fx.rate_per_usd IS NULL                   THEN 'blocked_missing_fx'
        ELSE 'pending'
      END,
      m.created_at + interval '1 minute',
      m.created_at
    FROM missing m
    LEFT JOIN public.billing_customers bc ON bc.group_id = m.group_id
    LEFT JOIN fx ON true
    ON CONFLICT (source_type, source_ref_id, fee_type) DO NOTHING
    RETURNING id, status
  )
  SELECT count(*) INTO v_count FROM inserted;

  IF v_count > 0 THEN
    RAISE NOTICE '[L09-04] Backfill: % receipts criados', v_count;
  END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 8. Registrar colunas no lgpd_deletion_strategy
-- ══════════════════════════════════════════════════════════════════════════
-- Apenas colunas que referenciam auth.users(id) precisam entrar no registry
-- (o integration test valida cobertura de FKs → auth.users).
-- customer_document / customer_legal_name NÃO são FK para auth.users; são
-- dados do cliente B2B (assessoria/CNPJ) retidos por obrigação fiscal
-- (Art. 195 CTN, 5 anos) — LGPD Art. 16 II excepciona obrigação legal.
-- O ator (quem marcou como issued) vira zero-UUID preservando trilha.

INSERT INTO public.lgpd_deletion_strategy (table_name, column_name, strategy, rationale) VALUES
  ('fiscal_receipts',        'issued_by_actor',
   'anonymize',  'L09-04: preserva trilha fiscal (retenção Art. 195 CTN 5a > LGPD 18 VI); actor vira zero-UUID.'),
  ('fiscal_receipt_events',  'actor_id',
   'anonymize',  'L09-04: trilha de auditoria preservada com zero-UUID no ator.')
ON CONFLICT (table_name, column_name) DO UPDATE
  SET strategy = EXCLUDED.strategy,
      rationale = EXCLUDED.rationale;

-- Documentar via COMMENT a retenção fiscal dos snapshots B2B
COMMENT ON COLUMN public.fiscal_receipts.customer_legal_name IS
  'L09-04: snapshot legal_name da assessoria (B2B) no fato gerador. '
  'Retido por 5 anos — Art. 195 CTN / LGPD Art. 16 II (obrigação legal).';
COMMENT ON COLUMN public.fiscal_receipts.customer_document IS
  'L09-04: snapshot CNPJ/CPF no fato gerador. Retido por 5 anos — '
  'Art. 195 CTN / LGPD Art. 16 II (obrigação legal).';

-- ══════════════════════════════════════════════════════════════════════════
-- 9. Invariantes finais
-- ══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_trigger_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = '_fiscal_receipt_enqueue'
      AND tgrelid = 'public.platform_revenue'::regclass
  ) INTO v_trigger_exists;

  IF NOT v_trigger_exists THEN
    RAISE EXCEPTION '[L09-04] trigger _fiscal_receipt_enqueue NÃO foi instalado';
  END IF;
END $$;

COMMIT;
