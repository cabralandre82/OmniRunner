-- ============================================================================
-- L03-20 — Disputa / chargeback Stripe (+ MercadoPago refund)
--
-- Audit reference:
--   docs/audit/findings/L03-20-disputa-chargeback-stripe.md
--   docs/audit/parts/02-cto-cfo.md  (anchor [3.20])
--
-- Problem
-- ───────
--   O receiver `POST /api/custody/webhook` aceitava apenas
--   `payment_intent.succeeded` (Stripe) / `payment.updated` com status
--   `approved` (MercadoPago) e chamava `confirmDepositByReference`. Eventos
--   de disputa ou reembolso — `charge.dispute.created`,
--   `charge.dispute.funds_withdrawn`, `charge.refunded` (Stripe) e
--   `payment.updated` com status `refunded` / `charged_back`
--   (MercadoPago) — CAÍAM na mesma branch que um pagamento bem-sucedido,
--   inflando o audit log com "confirmação" de um depósito que na verdade
--   está sendo EXTORNADO pelo gateway. Pior: NENHUM caminho invocava
--   `reverse_custody_deposit_atomic` para devolver o lastro.
--
--   Consequência operacional: 60-120 dias após um depósito legítimo, um
--   chargeback chegava silenciosamente, o dinheiro voltava ao cliente
--   via Stripe, mas as coins JÁ distribuídas permaneciam no ar — ops
--   só descobria semanas depois quando a invariante mensal reclamava
--   `deposited < committed`, e o CHARGEBACK_RUNBOOK §3.3 era executado
--   a mão com SQL colado direto no psql de produção.
--
-- Defence (this migration)
-- ────────────────────────
--   (1) `public.platform_webhook_system_user_id()` — retorna a uuid
--       constante `11111111-1111-1111-1111-111111111111` usada como
--       `actor_user_id` nas reversões disparadas por webhook. O
--       auth.users row correspondente é seedado IDEMPOTENTEMENTE por esta
--       migration (ON CONFLICT DO NOTHING).
--
--       Racional: `reverse_custody_deposit_atomic` (L03-13) exige
--       `p_actor_user_id NOT NULL` com FK para `auth.users`. Webhooks
--       não têm user context. Ao invés de relaxar o invariante da
--       função canônica (que foi cuidadosamente desenhada para CFO/ops
--       humano), modelamos o "sistema" como um ator explícito,
--       identificável em auditoria. O email `platform-webhook-system@…`
--       é sintético e tem `encrypted_password=''` — ninguém faz login
--       como esse usuário.
--
--   (2) `public.custody_dispute_cases` — fila auditável de incidentes
--       de disputa/chargeback/refund. UNIQUE `(gateway, gateway_event_id)`
--       é o primitivo de idempotência — um retry do MESMO webhook cai
--       no branch `was_idempotent=true` sem gerar duplicata.
--
--       State machine:
--         OPEN                — caso criado, reversão ainda não tentada
--                               (só usado se a reversão for async, hoje
--                               não é — mantido por simetria e para
--                               facilitar adicionar um worker depois).
--         RESOLVED_REVERSED   — `reverse_custody_deposit_atomic` teve
--                               sucesso; lastro devolvido, status do
--                               deposit → `refunded`.
--         ESCALATED_CFO       — reversão rejeitou `INVARIANT_VIOLATION`
--                               (coins já emitidas contra o lastro);
--                               ops precisa acionar o path
--                               "dívida do grupo" (CHARGEBACK_RUNBOOK
--                               §3.3) manualmente.
--         DEPOSIT_NOT_FOUND   — webhook para um payment_reference sem
--                               deposit correspondente (ruído: ex. um
--                               chargeback de venda que nunca virou
--                               custody_deposit); registrado para
--                               forensics e fechado automaticamente.
--         DISMISSED           — fechado por ops sem ação (ex. chargeback
--                               recusado pelo gateway antes de funds
--                               serem retirados).
--
--   (3) `public.fn_handle_custody_dispute_atomic` — orquestrador
--       atômico chamado pelo route handler do custody webhook. Em UMA
--       transação:
--         a) UPSERT custody_dispute_cases (ou short-circuit em replay).
--         b) Resolve deposit por `payment_reference`.
--         c) Tenta `reverse_custody_deposit_atomic` COM
--            `idempotency_key = gateway:gateway_event_id`.
--         d) Atualiza custody_dispute_cases.state com o resultado.
--         e) Retorna summary (`outcome`, `case_id`, `case_state`,
--            `reversal_id`, `deposit_id`, `was_idempotent`).
--
--       Nota: o handler NÃO re-raise exceções de invariante — elas são
--       convertidas em ESCALATED_CFO e retornadas como `outcome`.
--       Re-raise quebraria a dedup do webhook; preferimos 200 OK com
--       case_id para o gateway não retry infinitamente, e ops pega no
--       dashboard.
--
-- Rollback
-- ────────
--   DROP TABLE public.custody_dispute_cases CASCADE;
--   DROP FUNCTION public.fn_handle_custody_dispute_atomic(...);
--   DROP FUNCTION public.platform_webhook_system_user_id();
--   O auth.users row seedado pode permanecer — é inerte.
-- ============================================================================

BEGIN;

SET lock_timeout = '2s';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Platform webhook system user
-- ─────────────────────────────────────────────────────────────────────────────
--
-- O id é constante e bem conhecido; nunca deve ser login válido porque
-- `encrypted_password` é string vazia. O registro existe só para satisfazer
-- o FK `coin_reversal_log.actor_user_id → auth.users(id)` quando a origem
-- da reversão é o próprio gateway (chargeback).

INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'platform-webhook-system@internal.omnirunner.app',
  '',
  now(),
  '{"provider":"internal","providers":["internal"],"kind":"platform_webhook_system"}'::jsonb,
  '{"display_name":"Platform Webhook System","note":"Used only as actor for gateway-triggered reversals (L03-20)."}'::jsonb,
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

-- NOTE: we don't COMMENT ON COLUMN auth.users.id because `postgres`
-- doesn't own the auth schema — ownership lives with
-- `supabase_auth_admin`. The sentinel id conventions are documented
-- in this migration header instead:
--   00000000-…-000  → LGPD anonimizado (migration 20260417190000, L04-01)
--   11111111-…-111  → platform_webhook_system (this migration, L03-20)

CREATE OR REPLACE FUNCTION public.platform_webhook_system_user_id()
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT '11111111-1111-1111-1111-111111111111'::uuid
$$;

COMMENT ON FUNCTION public.platform_webhook_system_user_id() IS
  'L03-20: uuid constante do ator sintético usado como '
  'reverse_custody_deposit_atomic.p_actor_user_id quando a reversão '
  'é disparada pelo webhook de disputa (Stripe/MP).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. custody_dispute_cases
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.custody_dispute_cases (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Gateway origin. `asaas` kept for future use (today Asaas drives
  -- subscription billing, not custody, but a refund on an Asaas payment
  -- tied to a custody deposit would go through the same flow).
  gateway               text NOT NULL
                        CHECK (gateway IN ('stripe', 'mercadopago', 'asaas')),

  -- Gateway's own event id (Stripe `evt_…`, MP numeric id, Asaas hash).
  -- UNIQUE with gateway is the dedup primitive — webhook replays hit
  -- the same row and return `was_idempotent=true`.
  gateway_event_id      text NOT NULL
                        CHECK (length(gateway_event_id) BETWEEN 1 AND 255),

  -- The underlying dispute / refund resource id (Stripe dispute `du_…`
  -- or refund `re_…`; MP refund id). Nullable because some MP payloads
  -- only carry the payment id (dispute id must be fetched later).
  gateway_dispute_ref   text,

  -- Resolved deposit. Nullable because we create the case BEFORE
  -- resolving the deposit; if resolution fails we store state
  -- DEPOSIT_NOT_FOUND with deposit_id = NULL.
  deposit_id            uuid REFERENCES public.custody_deposits(id)
                        ON DELETE RESTRICT,

  -- Denormalized so ops can triage without JOIN. Filled when
  -- deposit_id is resolved.
  group_id              uuid REFERENCES public.coaching_groups(id)
                        ON DELETE SET NULL,

  -- Amount at stake (USD). Taken from the deposit row when we resolve
  -- it; useful for "top N cases by $" ops queries.
  amount_usd            numeric(14,2),

  -- Gateway-reported reason (Stripe `reason` field on dispute:
  -- fraudulent, product_not_received, duplicate, etc.) OR our own
  -- code when the gateway doesn't provide one (e.g. MP's blank status).
  reason_code           text NOT NULL CHECK (length(trim(reason_code)) > 0),

  kind                  text NOT NULL
                        CHECK (kind IN ('dispute', 'refund', 'chargeback')),

  state                 text NOT NULL
                        CHECK (state IN (
                          'OPEN',
                          'RESOLVED_REVERSED',
                          'ESCALATED_CFO',
                          'DEPOSIT_NOT_FOUND',
                          'DISMISSED'
                        )) DEFAULT 'OPEN',

  -- FK to coin_reversal_log when the auto-reversal succeeded.
  reversal_id           uuid REFERENCES public.coin_reversal_log(id)
                        ON DELETE SET NULL,

  -- Free-form note set when ops transitions to RESOLVED_* / DISMISSED.
  resolution_note       text,

  -- User that closed the case (ops / CFO). NULL while state=OPEN or
  -- when resolution was automatic (system closes DEPOSIT_NOT_FOUND
  -- and RESOLVED_REVERSED with resolved_by = platform_webhook_system).
  resolved_by           uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved_at           timestamptz,

  -- Full raw event kept for forensics. 64 KiB cap enforced at the
  -- webhook receiver layer; jsonb storage is cheap.
  raw_event             jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT custody_dispute_cases_event_uniq
    UNIQUE (gateway, gateway_event_id)
);

COMMENT ON TABLE public.custody_dispute_cases IS
  'L03-20: fila de incidentes de disputa / chargeback / refund vindos de '
  'Stripe / MercadoPago / Asaas. UNIQUE (gateway, gateway_event_id) é o '
  'primitivo de idempotência. Populada pelo route handler via '
  'fn_handle_custody_dispute_atomic; ops transiciona estado via '
  'painel /platform/disputes ou SQL ad-hoc.';

CREATE INDEX IF NOT EXISTS idx_custody_dispute_cases_state_open
  ON public.custody_dispute_cases (state, created_at DESC)
  WHERE state IN ('OPEN', 'ESCALATED_CFO');

CREATE INDEX IF NOT EXISTS idx_custody_dispute_cases_group
  ON public.custody_dispute_cases (group_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_custody_dispute_cases_deposit
  ON public.custody_dispute_cases (deposit_id);

CREATE INDEX IF NOT EXISTS idx_custody_dispute_cases_created_at
  ON public.custody_dispute_cases (created_at DESC);

ALTER TABLE public.custody_dispute_cases ENABLE ROW LEVEL SECURITY;

-- Policies use DROP IF EXISTS + CREATE for idempotent reapply (no
-- CREATE POLICY IF NOT EXISTS in PostgreSQL 17).
DROP POLICY IF EXISTS custody_dispute_cases_platform_admin_read
  ON public.custody_dispute_cases;
CREATE POLICY custody_dispute_cases_platform_admin_read
  ON public.custody_dispute_cases
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- Staff do grupo impactado também pode VER (nunca UPDATE) o caso.
-- Justificativa: admin_master precisa explicar ao atleta "seu depósito
-- foi estornado pelo banco"; bloquear leitura seria um bug de UX.
DROP POLICY IF EXISTS custody_dispute_cases_group_staff_read
  ON public.custody_dispute_cases;
CREATE POLICY custody_dispute_cases_group_staff_read
  ON public.custody_dispute_cases
  FOR SELECT USING (
    group_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.group_id = custody_dispute_cases.group_id
        AND cm.role IN ('admin_master', 'professor', 'assistente')
    )
  );

REVOKE ALL ON TABLE public.custody_dispute_cases FROM PUBLIC;
REVOKE ALL ON TABLE public.custody_dispute_cases FROM anon;
GRANT SELECT ON TABLE public.custody_dispute_cases TO authenticated;
GRANT ALL    ON TABLE public.custody_dispute_cases TO service_role;

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.tg_custody_dispute_cases_touch()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS custody_dispute_cases_touch ON public.custody_dispute_cases;
CREATE TRIGGER custody_dispute_cases_touch
  BEFORE UPDATE ON public.custody_dispute_cases
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_custody_dispute_cases_touch();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. fn_handle_custody_dispute_atomic
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Orquestra: create-or-reuse dispute case → resolve deposit → attempt
-- reverse_custody_deposit_atomic → update case state.
--
-- Exit codes for the caller (`outcome` column in the return row):
--   'idempotent_replay' — case already existed, no mutation this call.
--   'reversed'          — dispute caused a successful refund; state
--                         RESOLVED_REVERSED; reversal_id populated.
--   'escalated'         — INVARIANT_VIOLATION: coins already spent.
--                         state ESCALATED_CFO; reversal_id NULL.
--   'deposit_not_found' — no custody_deposits row for p_payment_reference.
--                         state DEPOSIT_NOT_FOUND; reversal_id NULL.
--   'dismissed'         — deposit exists but status ≠ confirmed
--                         (e.g. already refunded, or pending/failed);
--                         state DISMISSED; no-op.
--
-- Design note: we INTENTIONALLY catch the invariant violation from
-- reverse_custody_deposit_atomic and turn it into a bookkeeping row.
-- Re-raising would cause the webhook to return 5xx, which causes
-- gateway retries, which pile up duplicate dispute_cases rows — the
-- UNIQUE protects us but ops gets noise. Returning 200 with an
-- `escalated` outcome is the cleaner contract.

CREATE OR REPLACE FUNCTION public.fn_handle_custody_dispute_atomic(
  p_gateway             text,
  p_gateway_event_id    text,
  p_gateway_dispute_ref text,
  p_payment_reference   text,
  p_kind                text,
  p_reason_code         text,
  p_raw_event           jsonb
)
RETURNS TABLE (
  outcome         text,
  case_id         uuid,
  case_state      text,
  deposit_id      uuid,
  group_id        uuid,
  amount_usd      numeric,
  reversal_id     uuid,
  refunded_usd    numeric,
  was_idempotent  boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_existing_case  public.custody_dispute_cases;
  v_case_id        uuid;
  v_deposit_id     uuid;
  v_group_id       uuid;
  v_amount_usd     numeric(14,2);
  v_deposit_status text;
  v_idem_key       text;
  v_rev_row        record;
  v_actor          uuid := public.platform_webhook_system_user_id();
  v_reason_full    text;
BEGIN
  -- ── Validation ──────────────────────────────────────────────────────
  IF p_gateway IS NULL OR p_gateway NOT IN ('stripe', 'mercadopago', 'asaas') THEN
    RAISE EXCEPTION 'INVALID_GATEWAY: %', COALESCE(p_gateway, '<null>')
      USING ERRCODE = 'P0001';
  END IF;

  IF p_gateway_event_id IS NULL OR length(trim(p_gateway_event_id)) = 0 THEN
    RAISE EXCEPTION 'EVENT_ID_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  IF p_kind IS NULL OR p_kind NOT IN ('dispute', 'refund', 'chargeback') THEN
    RAISE EXCEPTION 'INVALID_KIND: %', COALESCE(p_kind, '<null>')
      USING ERRCODE = 'P0001';
  END IF;

  IF p_reason_code IS NULL OR length(trim(p_reason_code)) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  -- ── (a) Idempotency: short-circuit on replay ────────────────────────
  SELECT c.*
    INTO v_existing_case
    FROM public.custody_dispute_cases c
   WHERE c.gateway = p_gateway
     AND c.gateway_event_id = p_gateway_event_id
   FOR UPDATE;

  IF v_existing_case.id IS NOT NULL THEN
    RETURN QUERY SELECT
      'idempotent_replay'::text,
      v_existing_case.id,
      v_existing_case.state,
      v_existing_case.deposit_id,
      v_existing_case.group_id,
      v_existing_case.amount_usd,
      v_existing_case.reversal_id,
      NULL::numeric,
      true;
    RETURN;
  END IF;

  -- ── (b) Resolve deposit by payment_reference ────────────────────────
  -- Table aliases are required here: the RETURNS TABLE definition
  -- declares output columns named `deposit_id`, `group_id`, `amount_usd`
  -- which collide with custody_deposits column names.
  IF p_payment_reference IS NOT NULL AND length(trim(p_payment_reference)) > 0 THEN
    SELECT d.id, d.group_id, d.amount_usd, d.status
      INTO v_deposit_id, v_group_id, v_amount_usd, v_deposit_status
      FROM public.custody_deposits d
     WHERE d.payment_reference = p_payment_reference
     LIMIT 1;
  END IF;

  -- ── (c) DEPOSIT_NOT_FOUND path: record forensics and close ──────────
  IF v_deposit_id IS NULL THEN
    INSERT INTO public.custody_dispute_cases (
      gateway, gateway_event_id, gateway_dispute_ref,
      deposit_id, group_id, amount_usd,
      reason_code, kind,
      state, resolution_note, resolved_by, resolved_at,
      raw_event
    ) VALUES (
      p_gateway, p_gateway_event_id, p_gateway_dispute_ref,
      NULL, NULL, NULL,
      p_reason_code, p_kind,
      'DEPOSIT_NOT_FOUND',
      format('no custody_deposits row for payment_reference=%s',
             COALESCE(p_payment_reference, '<null>')),
      v_actor, now(),
      COALESCE(p_raw_event, '{}'::jsonb)
    )
    RETURNING id INTO v_case_id;

    INSERT INTO public.portal_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      v_actor, 'custody.dispute.deposit_not_found', 'custody_dispute_case',
      v_case_id::text,
      jsonb_build_object(
        'gateway', p_gateway,
        'event_id', p_gateway_event_id,
        'payment_reference', p_payment_reference,
        'kind', p_kind,
        'reason_code', p_reason_code
      )
    );

    RETURN QUERY SELECT
      'deposit_not_found'::text,
      v_case_id,
      'DEPOSIT_NOT_FOUND'::text,
      NULL::uuid, NULL::uuid, NULL::numeric,
      NULL::uuid, NULL::numeric, false;
    RETURN;
  END IF;

  -- ── (d) DISMISSED path: deposit exists but isn't confirmed ──────────
  --
  -- Covers (i) depósito já estornado (status=refunded) — dispute veio
  -- depois da resolução manual; (ii) status=pending/failed — o gateway
  -- disputou antes de confirmar (raro mas possível). Em ambos os casos
  -- NÃO tentamos reverse_custody_deposit_atomic: ele recusaria e o
  -- ops ganharia barulho inútil.
  IF v_deposit_status <> 'confirmed' THEN
    INSERT INTO public.custody_dispute_cases (
      gateway, gateway_event_id, gateway_dispute_ref,
      deposit_id, group_id, amount_usd,
      reason_code, kind,
      state, resolution_note, resolved_by, resolved_at,
      raw_event
    ) VALUES (
      p_gateway, p_gateway_event_id, p_gateway_dispute_ref,
      v_deposit_id, v_group_id, v_amount_usd,
      p_reason_code, p_kind,
      'DISMISSED',
      format('deposit status=%s (nothing to reverse)', v_deposit_status),
      v_actor, now(),
      COALESCE(p_raw_event, '{}'::jsonb)
    )
    RETURNING id INTO v_case_id;

    RETURN QUERY SELECT
      'dismissed'::text,
      v_case_id,
      'DISMISSED'::text,
      v_deposit_id, v_group_id, v_amount_usd,
      NULL::uuid, NULL::numeric, false;
    RETURN;
  END IF;

  -- ── (e) Create the OPEN case BEFORE attempting reversal ─────────────
  --
  -- If the reversal throws an unexpected error (not INVARIANT_VIOLATION),
  -- the INSERT above is rolled back — but that's fine because the retry
  -- will re-enter the idempotency branch with a clean slate. We DO NOT
  -- want a half-updated case sitting in OPEN state forever.
  INSERT INTO public.custody_dispute_cases (
    gateway, gateway_event_id, gateway_dispute_ref,
    deposit_id, group_id, amount_usd,
    reason_code, kind,
    state, raw_event
  ) VALUES (
    p_gateway, p_gateway_event_id, p_gateway_dispute_ref,
    v_deposit_id, v_group_id, v_amount_usd,
    p_reason_code, p_kind,
    'OPEN', COALESCE(p_raw_event, '{}'::jsonb)
  )
  RETURNING id INTO v_case_id;

  -- Deterministic idempotency key for reverse_custody_deposit_atomic.
  -- Length is guaranteed ≥ 8 because gateway + ':' has 7+ chars and
  -- event_ids are non-empty.
  v_idem_key := p_gateway || ':' || p_gateway_event_id;

  v_reason_full := format(
    '[L03-20] %s chargeback/refund from %s (event=%s, reason=%s). '
    'Auto-reversal triggered by fn_handle_custody_dispute_atomic.',
    p_kind, p_gateway, p_gateway_event_id, p_reason_code
  );

  -- ── (f) Attempt reversal — catch invariant violation ────────────────
  BEGIN
    SELECT *
      INTO v_rev_row
      FROM public.reverse_custody_deposit_atomic(
        p_deposit_id      => v_deposit_id,
        p_reason          => v_reason_full,
        p_actor_user_id   => v_actor,
        p_idempotency_key => v_idem_key
      );

    -- Success: close case as RESOLVED_REVERSED.
    UPDATE public.custody_dispute_cases
       SET state           = 'RESOLVED_REVERSED',
           reversal_id     = v_rev_row.reversal_id,
           resolved_by     = v_actor,
           resolved_at     = now(),
           resolution_note = format(
             'auto-reversed: refunded_usd=%s (reverse_custody_deposit_atomic)',
             v_rev_row.refunded_usd::text
           )
     WHERE id = v_case_id;

    INSERT INTO public.portal_audit_log (
      actor_id, group_id, action, target_type, target_id, metadata
    )
    VALUES (
      v_actor, v_group_id,
      'custody.dispute.reversed', 'custody_dispute_case', v_case_id::text,
      jsonb_build_object(
        'gateway', p_gateway,
        'event_id', p_gateway_event_id,
        'deposit_id', v_deposit_id,
        'reversal_id', v_rev_row.reversal_id,
        'refunded_usd', v_rev_row.refunded_usd,
        'reason_code', p_reason_code,
        'kind', p_kind
      )
    );

    RETURN QUERY SELECT
      'reversed'::text,
      v_case_id,
      'RESOLVED_REVERSED'::text,
      v_deposit_id, v_group_id, v_amount_usd,
      v_rev_row.reversal_id, v_rev_row.refunded_usd, false;
    RETURN;

  EXCEPTION WHEN SQLSTATE 'P0008' THEN
    -- INVARIANT_VIOLATION (reverse_custody_deposit_atomic raises P0008
    -- when `total_deposited - amount < total_committed` — coins já
    -- emitidas contra o lastro). Escalate to CFO; ops runs the
    -- CHARGEBACK_RUNBOOK §3.3 "dívida do grupo" path manually.
    UPDATE public.custody_dispute_cases
       SET state           = 'ESCALATED_CFO',
           resolution_note = format(
             'invariant violation on auto-reversal: %s. '
             'Coins already spent — route to debt-of-group workflow.',
             SQLERRM
           )
     WHERE id = v_case_id;

    INSERT INTO public.portal_audit_log (
      actor_id, group_id, action, target_type, target_id, metadata
    )
    VALUES (
      v_actor, v_group_id,
      'custody.dispute.escalated_cfo', 'custody_dispute_case',
      v_case_id::text,
      jsonb_build_object(
        'gateway', p_gateway,
        'event_id', p_gateway_event_id,
        'deposit_id', v_deposit_id,
        'amount_usd', v_amount_usd,
        'reason_code', p_reason_code,
        'kind', p_kind,
        'sqlerrm', SQLERRM
      )
    );

    RETURN QUERY SELECT
      'escalated'::text,
      v_case_id,
      'ESCALATED_CFO'::text,
      v_deposit_id, v_group_id, v_amount_usd,
      NULL::uuid, NULL::numeric, false;
    RETURN;
  END;
END;
$$;

COMMENT ON FUNCTION public.fn_handle_custody_dispute_atomic(
  text, text, text, text, text, text, jsonb
) IS
  'L03-20: orquestrador de disputa / chargeback. Cria ou reusa '
  'custody_dispute_cases (idempotente por gateway+event_id), tenta '
  'reverse_custody_deposit_atomic quando o deposit está confirmado, e '
  'atualiza o state da case. Retorna outcome ∈ {idempotent_replay, '
  'reversed, escalated, deposit_not_found, dismissed}.';

REVOKE ALL ON FUNCTION public.fn_handle_custody_dispute_atomic(
  text, text, text, text, text, text, jsonb
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_handle_custody_dispute_atomic(
  text, text, text, text, text, text, jsonb
) FROM anon;
REVOKE ALL ON FUNCTION public.fn_handle_custody_dispute_atomic(
  text, text, text, text, text, text, jsonb
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_handle_custody_dispute_atomic(
  text, text, text, text, text, text, jsonb
) TO service_role;

-- platform_webhook_system_user_id() is IMMUTABLE and returns a constant;
-- safe for anon/authenticated to call (no data access). We grant EXECUTE
-- to simplify client-side audit tooling that needs to display "actor:
-- system" labels.
-- (no REVOKE — default grant is fine)

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Self-test (migration time, in-transaction — rolled back on failure)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Build confidence the orchestrator behaves per spec before the route
-- handler depends on it. We fabricate a minimal group + deposit +
-- custody_account, exercise the three outcome branches (deposit_not_found,
-- reversed, idempotent_replay), then rollback a SAVEPOINT so the
-- migration leaves production data untouched.

DO $self_test$
DECLARE
  -- Use a deterministic uuid tied to this migration timestamp so a partial
  -- run (crash after the test rows are inserted but before cleanup) can
  -- be detected + purged on next attempt.
  v_user_id          uuid := 'aaaa0320-0000-4000-8000-000000000001';
  v_group_id         uuid;
  v_deposit_id       uuid;
  v_case_replay_id   uuid;
  v_r1               record;
  v_r2               record;
  v_r3               record;
  v_r4               record;
  v_sentinel_err     constant text := 'L03-20-SELFTEST-ROLLBACK';
BEGIN
  -- ── Strategy: we run the whole thing inside a BEGIN/EXCEPTION block
  -- and at the end we RAISE a sentinel exception to force Postgres to
  -- rollback the subtransaction. PL/pgSQL does not support explicit
  -- ROLLBACK TO SAVEPOINT inside a function body, so this is the
  -- canonical idiom.
  BEGIN
  -- Seed auth.users row (may already exist from a previous partial run).
  INSERT INTO auth.users (id, instance_id, aud, role, email)
  VALUES (v_user_id, '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated',
          'l03-20-selftest@example.test')
  ON CONFLICT (id) DO NOTHING;

  -- Group + custody account with $10 deposited and $0 committed.
  INSERT INTO public.coaching_groups (id, name, coach_user_id, created_at_ms)
  VALUES (gen_random_uuid(), 'L03-20 Self-Test Group', v_user_id,
          (extract(epoch from now()) * 1000)::bigint)
  RETURNING id INTO v_group_id;

  INSERT INTO public.custody_accounts (group_id, total_deposited_usd, total_committed)
  VALUES (v_group_id, 10.00, 0)
  ON CONFLICT (group_id) DO UPDATE
    SET total_deposited_usd = 10.00, total_committed = 0;

  INSERT INTO public.custody_deposits (
    group_id, amount_usd, coins_equivalent, payment_gateway,
    payment_reference, status
  )
  VALUES (
    v_group_id, 10.00, 10, 'stripe',
    'pi_l03_20_selftest_' || substring(replace(gen_random_uuid()::text, '-', '') from 1 for 10),
    'confirmed'
  )
  RETURNING id INTO v_deposit_id;

  -- ── (a) deposit_not_found — unknown payment_reference
  SELECT * INTO v_r1 FROM public.fn_handle_custody_dispute_atomic(
    p_gateway             => 'stripe',
    p_gateway_event_id    => 'evt_l03_20_dnf_' || substring(replace(gen_random_uuid()::text, '-', '') from 1 for 10),
    p_gateway_dispute_ref => NULL,
    p_payment_reference   => 'pi_unknown_ref_xyz',
    p_kind                => 'dispute',
    p_reason_code         => 'fraudulent',
    p_raw_event           => '{"test":"dnf"}'::jsonb
  );
  IF v_r1.outcome <> 'deposit_not_found' THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (a) expected deposit_not_found, got %', v_r1.outcome;
  END IF;
  IF v_r1.case_state <> 'DEPOSIT_NOT_FOUND' THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (a) expected state DEPOSIT_NOT_FOUND, got %', v_r1.case_state;
  END IF;

  -- ── (b) reversed happy path — matching deposit, committed=0
  SELECT * INTO v_r2 FROM public.fn_handle_custody_dispute_atomic(
    p_gateway             => 'stripe',
    p_gateway_event_id    => 'evt_l03_20_rev_' || substring(replace(gen_random_uuid()::text, '-', '') from 1 for 10),
    p_gateway_dispute_ref => 'du_l03_20_selftest',
    p_payment_reference   => (SELECT payment_reference FROM public.custody_deposits WHERE id = v_deposit_id),
    p_kind                => 'chargeback',
    p_reason_code         => 'fraudulent',
    p_raw_event           => '{"test":"reversed"}'::jsonb
  );
  IF v_r2.outcome <> 'reversed' THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (b) expected reversed, got %', v_r2.outcome;
  END IF;
  IF v_r2.case_state <> 'RESOLVED_REVERSED' THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (b) expected state RESOLVED_REVERSED, got %', v_r2.case_state;
  END IF;
  IF v_r2.reversal_id IS NULL THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (b) reversal_id should not be null';
  END IF;

  -- Deposit should now be refunded.
  IF (SELECT status FROM public.custody_deposits WHERE id = v_deposit_id) <> 'refunded' THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (b) deposit status should be refunded';
  END IF;

  -- ── (c) idempotent_replay — re-sending the SAME (gateway, event_id)
  SELECT * INTO v_r3 FROM public.fn_handle_custody_dispute_atomic(
    p_gateway             => 'stripe',
    p_gateway_event_id    => (SELECT gateway_event_id FROM public.custody_dispute_cases WHERE id = v_r2.case_id),
    p_gateway_dispute_ref => 'du_l03_20_selftest',
    p_payment_reference   => (SELECT payment_reference FROM public.custody_deposits WHERE id = v_deposit_id),
    p_kind                => 'chargeback',
    p_reason_code         => 'fraudulent',
    p_raw_event           => '{"test":"replay"}'::jsonb
  );
  IF v_r3.outcome <> 'idempotent_replay' THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (c) expected idempotent_replay, got %', v_r3.outcome;
  END IF;
  IF v_r3.was_idempotent IS NOT TRUE THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (c) expected was_idempotent=true';
  END IF;
  IF v_r3.case_id <> v_r2.case_id THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (c) replay should return the ORIGINAL case_id';
  END IF;

  -- ── (d) dismissed — trying to dispute an already-refunded deposit
  SELECT * INTO v_r4 FROM public.fn_handle_custody_dispute_atomic(
    p_gateway             => 'stripe',
    p_gateway_event_id    => 'evt_l03_20_dism_' || substring(replace(gen_random_uuid()::text, '-', '') from 1 for 10),
    p_gateway_dispute_ref => 'du_l03_20_dismiss',
    p_payment_reference   => (SELECT payment_reference FROM public.custody_deposits WHERE id = v_deposit_id),
    p_kind                => 'refund',
    p_reason_code         => 'requested_by_customer',
    p_raw_event           => '{"test":"dismissed"}'::jsonb
  );
  IF v_r4.outcome <> 'dismissed' THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (d) expected dismissed, got %', v_r4.outcome;
  END IF;
  IF v_r4.case_state <> 'DISMISSED' THEN
    RAISE EXCEPTION 'L03-20 SELFTEST (d) expected state DISMISSED, got %', v_r4.case_state;
  END IF;

  -- Force rollback of the subtransaction so the migration leaves
  -- production data untouched. The sentinel RAISE is caught below.
  RAISE EXCEPTION '%', v_sentinel_err;

  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> v_sentinel_err THEN
      -- Real failure — re-raise so the migration aborts.
      RAISE;
    END IF;
  END;

  RAISE NOTICE '[L03-20] self-test PASSED: deposit_not_found, reversed, idempotent_replay, dismissed';
END
$self_test$;

COMMIT;
