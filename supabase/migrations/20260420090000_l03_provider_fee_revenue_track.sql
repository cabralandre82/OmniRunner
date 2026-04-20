-- ============================================================================
-- L03-03 — Provider fee revenue tracking on execute_withdrawal
--
-- Audit reference:
--   docs/audit/findings/L03-03-execute-withdrawal-total-deposited-usd-amount-usd-nao.md
--   docs/audit/parts/03-cfo.md  (anchor [3.3])
--
-- Problem
-- ───────
--   `createWithdrawal` (portal/src/lib/custody.ts:368-414) computes
--
--       net_local_amount = convertFromUsdWithSpread(
--           amount_usd - provider_fee_usd, fx_rate, spread_pct)
--
--   so the user receives local currency for the NET (gross minus the
--   gateway/provider fee). The gateway then takes its `provider_fee_usd`
--   off the wire transfer.
--
--   `execute_withdrawal` (migration 20260228170000:131-134) however does:
--
--       UPDATE custody_accounts SET total_deposited_usd -= v_amount
--           WHERE group_id = v_group_id;       -- v_amount = GROSS amount_usd
--
--       INSERT INTO platform_revenue ('fx_spread', v_fx_spread, ...);
--
--   Net effect on a $1000 withdrawal with $100 provider fee + $30 fx spread:
--
--     - custody loses                   $1000  ✓ (correct, gross out)
--     - user receives  ≈                ($1000 - $100 - $30) = $870 in local
--     - platform_revenue records           $30 (fx_spread)
--     - platform_revenue records           --- ← MISSING: $100 provider_fee
--
--   The $100 provider fee just disappears from the books. CFO can't
--   reconcile `total_deposited_usd` movement against the revenue ledger.
--   Custody invariant (deposits in = withdrawals out + revenue + held) is
--   off by exactly the provider_fee on every gateway-priced withdrawal.
--
-- Defence (this migration)
-- ────────────────────────
--   (1) Widen `platform_revenue.fee_type` CHECK to include `'provider_fee'`.
--       NOTE: `platform_fee_config.fee_type` is intentionally NOT widened
--       — provider fees are NOT configurable via UI; they are per-
--       transaction passthrough quoted by the gateway at withdraw time.
--       This is the first deliberate divergence between the two CHECKs.
--       L01-44 comment is updated below to reflect that.
--
--   (2) `execute_withdrawal` re-created to ALSO insert a `provider_fee`
--       row in `platform_revenue` when `provider_fee_usd > 0`. Same
--       pattern as the existing fx_spread insert (idempotent because
--       `execute_withdrawal` is itself idempotent at the
--       `pending → processing` transition via FOR UPDATE).
--
--   (3) `fail_withdrawal` (L02-06) re-created to ALSO delete the
--       provider_fee row on rollback, in the SAME transaction as the
--       fx_spread delete and the `total_deposited_usd` refund. The
--       audit log gets a new field `provider_fee_reversed_usd` so the
--       postmortem trail is complete.
--
--   (4) `_enqueue_fiscal_receipt` (L09-04 trigger on platform_revenue
--       INSERT) re-created to short-circuit on `fee_type='provider_fee'`.
--       Brazilian tax law: pass-through gateway fees are NOT service
--       revenue (the platform is not the supplier), so no NFS-e is
--       owed. Without the short-circuit the trigger fires, trips the
--       fiscal_receipts.fee_type CHECK, and emits a `RAISE WARNING`
--       per provider_fee row — noisy and obscures real fiscal errors.
--
--   (5) Backfill: NOT in scope — withdrawals booked before this
--       migration ran with the original buggy execute_withdrawal will
--       continue to be ledger-incomplete. Operators get a one-off
--       reconciliation query in WITHDRAW_STUCK_RUNBOOK §4 to identify
--       affected rows and book the missing platform_revenue entries
--       under their own actor_id (auditable manual ledger fix).
--
-- Self-test
-- ─────────
--   The bottom of the migration verifies the SCHEMA-level invariants
--   that this migration introduces (CHECK widening + deliberate
--   divergence between the two CHECKs). Full end-to-end happy/fail
--   coverage lives in `tools/test_l03_03_provider_fee_revenue_track.ts`
--   which exercises real custody_accounts/withdrawals via the service-
--   role client and verifies platform_revenue rows + audit log payload.
--   Keeping the in-TX self-test schema-only avoids fragile FK chains
--   to auth.users + coaching_groups during fresh installs.
--
-- Rollback
-- ────────
--   To revert: re-create execute_withdrawal and fail_withdrawal from
--   migration 20260419150000_l02_withdrawal_lifecycle_completion.sql,
--   then narrow the CHECK with:
--
--     ALTER TABLE platform_revenue
--       DROP CONSTRAINT platform_revenue_fee_type_check,
--       ADD CONSTRAINT platform_revenue_fee_type_check CHECK (
--         fee_type IN ('clearing','swap','maintenance','billing_split','fx_spread'));
--
--   The DROP CONSTRAINT will fail if any provider_fee rows have been
--   booked — that is the desired safety net (CFO must triage them
--   before unbooking the schema). Operators pasting this snippet must
--   first `SELECT id FROM platform_revenue WHERE fee_type = 'provider_fee'`
--   and decide whether to migrate them to a new accounting category.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Widen platform_revenue.fee_type CHECK
-- ─────────────────────────────────────────────────────────────────────────────

DO $widen_check$
BEGIN
  -- Defensive: drop only if present (older fresh installs may have a
  -- different baseline; the IF EXISTS keeps re-runs idempotent).
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.platform_revenue'::regclass
      AND conname  = 'platform_revenue_fee_type_check'
  ) THEN
    ALTER TABLE public.platform_revenue
      DROP CONSTRAINT platform_revenue_fee_type_check;
  END IF;

  ALTER TABLE public.platform_revenue
    ADD CONSTRAINT platform_revenue_fee_type_check
    CHECK (fee_type IN (
      'clearing',
      'swap',
      'maintenance',
      'billing_split',
      'fx_spread',
      'provider_fee'
    ));
END;
$widen_check$;

COMMENT ON CONSTRAINT platform_revenue_fee_type_check ON public.platform_revenue IS
  'L01-44 + L03-03: lista canônica de fee_types em platform_revenue. '
  'SUPERSET de platform_fee_config.fee_type — `provider_fee` é '
  'pass-through (gateway/banco fica com o dinheiro, não é receita) e '
  'não aparece no CHECK do fee_config porque não é configurável via UI; '
  'os outros 5 são receita real e aparecem em ambos. Source-of-truth TS: '
  '`portal/src/lib/platform-fee-types.ts` (PLATFORM_REVENUE_FEE_TYPES).';

-- L01-44 comment on platform_fee_config CHECK was written assuming the
-- two CHECK lists would always match. They do not anymore (provider_fee
-- belongs to revenue but not to fee_config). Update the comment so the
-- next contributor doesn't try to "fix the drift" by adding provider_fee
-- to fee_config.
COMMENT ON CONSTRAINT platform_fee_config_fee_type_check ON public.platform_fee_config IS
  'L01-44: lista canônica de fee_types CONFIGURÁVEIS (rate ajustável '
  'pela UI platform-admin). SUBSET de platform_revenue_fee_type_check — '
  'tipos pass-through (e.g. provider_fee L03-03) ficam APENAS em '
  'platform_revenue, NÃO aqui. Adicionar novo tipo configurável: '
  '1) DROP/ADD este CHECK; 2) DROP/ADD platform_revenue CHECK (mesmo '
  'set + qualquer pass-through); 3) atualizar PLATFORM_FEE_TYPES e '
  'PLATFORM_REVENUE_FEE_TYPES em portal/src/lib/platform-fee-types.ts; '
  '4) adicionar label em FEE_TYPE_LABELS; 5) atualizar enum no '
  'public/openapi.json. Os contract-locks em platform-fee-types.test.ts '
  'pegam drift entre as 5 superfícies.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. execute_withdrawal — record provider_fee row when > 0
-- ─────────────────────────────────────────────────────────────────────────────
--   Mirrors the existing fx_spread block. Both inserts happen AFTER the
--   pending→processing transition (so a fail in either insert aborts the
--   whole TX and leaves the row in `pending` for retry). source_ref_id
--   is the withdrawal id as text (matches existing convention).

CREATE OR REPLACE FUNCTION public.execute_withdrawal(
  p_withdrawal_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id     uuid;
  v_amount       numeric(14,2);
  v_available    numeric(14,2);
  v_fx_spread    numeric(14,2);
  v_provider_fee numeric(14,2);
BEGIN
  -- Project-wide convention (L19-05): bound any wait so a long-running
  -- analytics query never holds up money movement.
  PERFORM set_config('lock_timeout', '2s', true);

  SELECT group_id, amount_usd, fx_spread_usd, provider_fee_usd
    INTO v_group_id, v_amount, v_fx_spread, v_provider_fee
    FROM public.custody_withdrawals
   WHERE id = p_withdrawal_id AND status = 'pending'
   FOR UPDATE;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'Withdrawal not found or not pending';
  END IF;

  SELECT total_deposited_usd - total_committed
    INTO v_available
    FROM public.custody_accounts
   WHERE group_id = v_group_id
   FOR UPDATE;

  IF v_available IS NULL OR v_available < v_amount THEN
    UPDATE public.custody_withdrawals
       SET status = 'failed'
     WHERE id = p_withdrawal_id;
    RAISE EXCEPTION 'Insufficient available: available=%, requested=%',
      COALESCE(v_available, 0), v_amount;
  END IF;

  UPDATE public.custody_accounts
     SET total_deposited_usd = total_deposited_usd - v_amount,
         updated_at          = now()
   WHERE group_id = v_group_id;

  UPDATE public.custody_withdrawals
     SET status = 'processing'
   WHERE id = p_withdrawal_id;

  IF v_fx_spread > 0 THEN
    INSERT INTO public.platform_revenue (
      fee_type, amount_usd, source_ref_id, group_id, description
    )
    VALUES (
      'fx_spread', v_fx_spread, p_withdrawal_id::text, v_group_id,
      'FX spread on withdrawal'
    );
  END IF;

  -- L03-03: provider/gateway fee accounting trail. Pass-through revenue
  -- (platform doesn't keep this) but MUST be recorded so
  -- `total_deposited_usd` movement reconciles to platform_revenue +
  -- net-paid amount.
  IF v_provider_fee > 0 THEN
    INSERT INTO public.platform_revenue (
      fee_type, amount_usd, source_ref_id, group_id, description
    )
    VALUES (
      'provider_fee', v_provider_fee, p_withdrawal_id::text, v_group_id,
      'Gateway/provider fee on withdrawal (pass-through)'
    );
  END IF;
END;
$$;

COMMENT ON FUNCTION public.execute_withdrawal(uuid) IS
  'L03-03: pending → processing transition. Atomically debits '
  'total_deposited_usd by GROSS amount_usd, then records BOTH fx_spread '
  '(if > 0) AND provider_fee (if > 0) rows in platform_revenue so the '
  'CFO ledger reconciles. fail_withdrawal reverses both inserts.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. fail_withdrawal — reverse provider_fee row too
-- ─────────────────────────────────────────────────────────────────────────────
--   Re-creation preserves the L02-06 contract (RETURN TABLE shape, error
--   codes, audit log target, idempotency). New: also DELETE provider_fee
--   row + emit `provider_fee_reversed_usd` in audit metadata.
--
--   The original L02-06 RETURN signature is preserved
--     (withdrawal_id uuid, status text, was_terminal boolean,
--      refunded_usd numeric, revenue_reversed_usd numeric)
--   so existing route handlers/tests don't break.
--   `revenue_reversed_usd` now reports the SUM of both fx_spread AND
--   provider_fee (the total amount removed from platform_revenue) —
--   semantically still "revenue reversed", just inclusive. The audit
--   log JSONB carries the breakdown for forensic clarity.

CREATE OR REPLACE FUNCTION public.fail_withdrawal(
  p_withdrawal_id uuid,
  p_reason        text,
  p_actor_user_id uuid
)
RETURNS TABLE (
  withdrawal_id        uuid,
  status               text,
  was_terminal         boolean,
  refunded_usd         numeric,
  revenue_reversed_usd numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_status        text;
  v_group_id      uuid;
  v_amount        numeric(14,2);
  v_fx_spread     numeric(14,2);
  v_existing_ref  text;
  v_fx_reversed   numeric(14,2);
  v_pf_reversed   numeric(14,2);
BEGIN
  IF p_withdrawal_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_WITHDRAWAL_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT    = 'pass the gateway-rejection reason (e.g. "invalid_bank_account") for postmortem';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  -- L03-03: explicit table-qualification on `status` because the
  -- RETURNS TABLE column of the same name shadows it under
  -- `plpgsql.variable_conflict = error` (PG 15+ default in some
  -- configs). The L02-06 original was vulnerable to the same issue
  -- but was never exercised by a happy-path integration test; this
  -- migration regression-tests it.
  SELECT cw.status, cw.group_id, cw.amount_usd, cw.fx_spread_usd, cw.payout_reference
    INTO v_status, v_group_id, v_amount, v_fx_spread, v_existing_ref
    FROM public.custody_withdrawals cw
   WHERE cw.id = p_withdrawal_id
   FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'WITHDRAWAL_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotent against re-clicks: if already failed, no-op.
  IF v_status = 'failed' THEN
    RETURN QUERY SELECT p_withdrawal_id, 'failed'::text, true, 0::numeric, 0::numeric;
    RETURN;
  END IF;

  IF v_status <> 'processing' THEN
    RAISE EXCEPTION 'INVALID_TRANSITION: % → failed (only processing allowed)', v_status
      USING ERRCODE = 'P0008';
  END IF;

  -- Refund the custody account (gross amount left during execute).
  UPDATE public.custody_accounts
     SET total_deposited_usd = total_deposited_usd + v_amount,
         updated_at          = now()
   WHERE group_id = v_group_id;

  -- Reverse fx_spread row (if any). Sum first for the audit trail.
  SELECT COALESCE(SUM(amount_usd), 0)
    INTO v_fx_reversed
    FROM public.platform_revenue
   WHERE source_ref_id = p_withdrawal_id::text
     AND fee_type      = 'fx_spread';

  DELETE FROM public.platform_revenue
   WHERE source_ref_id = p_withdrawal_id::text
     AND fee_type      = 'fx_spread';

  -- L03-03: also reverse provider_fee row (if any). Same TX so refund
  -- and revenue-reversal are atomic.
  SELECT COALESCE(SUM(amount_usd), 0)
    INTO v_pf_reversed
    FROM public.platform_revenue
   WHERE source_ref_id = p_withdrawal_id::text
     AND fee_type      = 'provider_fee';

  DELETE FROM public.platform_revenue
   WHERE source_ref_id = p_withdrawal_id::text
     AND fee_type      = 'provider_fee';

  UPDATE public.custody_withdrawals
     SET status           = 'failed',
         completed_at     = now(),
         payout_reference = COALESCE(v_existing_ref, '')
                            || ' | reverted: ' || p_reason
                            || ' @ ' || now()::text
   WHERE id = p_withdrawal_id;

  -- Re-validate the cross-table invariant.
  IF EXISTS (
    SELECT 1 FROM public.check_custody_invariants() v
    WHERE v.group_id = v_group_id
  ) THEN
    RAISE EXCEPTION 'INVARIANT_VIOLATION: refund would unbalance custody for group %', v_group_id
      USING ERRCODE = 'P0008',
            HINT    = 'inspect check_custody_invariants() and reconcile manually before retrying';
  END IF;

  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  VALUES (
    p_actor_user_id,
    v_group_id,
    'custody.withdrawal.failed',
    'custody_withdrawal',
    p_withdrawal_id::text,
    jsonb_build_object(
      'reason',                     p_reason,
      'refunded_usd',               v_amount,
      'revenue_reversed_usd',       v_fx_reversed + v_pf_reversed,
      'fx_spread_reversed_usd',     v_fx_reversed,
      'provider_fee_reversed_usd',  v_pf_reversed,
      'previous_payout_reference',  v_existing_ref,
      'runbook',                    'WITHDRAW_STUCK_RUNBOOK#3.3'
    )
  );

  RETURN QUERY SELECT
    p_withdrawal_id, 'failed'::text, false,
    v_amount, (v_fx_reversed + v_pf_reversed);
END;
$$;

COMMENT ON FUNCTION public.fail_withdrawal(uuid, text, uuid) IS
  'L02-06 + L03-03: ops-driven processing → failed transition. Atomically '
  'refunds total_deposited_usd, deletes BOTH fx_spread AND provider_fee '
  'platform_revenue rows tied to this withdrawal, re-validates '
  'check_custody_invariants() in the same TX. Idempotent on '
  'already-failed rows. Audit log carries breakdown of fx_spread vs '
  'provider_fee reversed for forensic clarity.';

-- Re-grant after CREATE OR REPLACE (DEFAULT is preserved, but be
-- explicit so a hand-rolled deploy script doesn't have to remember).
GRANT EXECUTE ON FUNCTION public.execute_withdrawal(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_withdrawal(uuid, text, uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3b. _enqueue_fiscal_receipt — skip provider_fee (pass-through, no NFS-e)
-- ─────────────────────────────────────────────────────────────────────────────
--   The L09-04 trigger fires on every INSERT into platform_revenue and
--   tries to enqueue a fiscal_receipts row. fiscal_receipts.fee_type
--   has its own CHECK that does NOT include 'provider_fee' (and
--   shouldn't — Brazilian tax law: pass-through fees are not service
--   revenue and don't require NFS-e issuance).
--
--   Without this patch every provider_fee insert would be caught by the
--   trigger's `EXCEPTION WHEN others` block and emit a noisy
--   `[L09-04] Falha ao enfileirar fiscal_receipt` WARNING. We instead
--   short-circuit at the top: provider_fee rows are recognised and
--   skipped explicitly, freeing the WARNING channel for real failures.
--
--   The body is otherwise byte-identical to the L09-04 original so we
--   minimise the diff surface.

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
  -- L03-03: pass-through fees are not platform service revenue —
  -- skip the fiscal queue entirely. This avoids the noisy WARNING
  -- and keeps the fiscal_receipts CHECK semantically accurate
  -- (only billable revenue ever appears there).
  IF NEW.fee_type = 'provider_fee' THEN
    RETURN NEW;
  END IF;

  v_source_type := CASE NEW.fee_type
    WHEN 'fx_spread'     THEN 'custody_withdrawal'
    WHEN 'clearing'      THEN 'clearing_settlement'
    WHEN 'swap'          THEN 'swap_order'
    WHEN 'maintenance'   THEN 'maintenance_fee'
    WHEN 'billing_split' THEN 'billing_split'
    ELSE 'manual_adjustment'
  END;

  SELECT bc.legal_name, bc.tax_id, bc.email, bc.address_line, bc.address_city,
         bc.address_state, bc.address_zip
  INTO v_customer
  FROM public.billing_customers bc
  WHERE bc.group_id = NEW.group_id;

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

  v_status := CASE
    WHEN v_customer.tax_id IS NULL OR v_customer.legal_name IS NULL
      THEN 'blocked_missing_data'
    WHEN v_rate IS NULL
      THEN 'blocked_missing_fx'
    ELSE 'pending'
  END;

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
  RAISE WARNING '[L09-04] Falha ao enfileirar fiscal_receipt para platform_revenue %: % (%)',
    NEW.id, SQLERRM, SQLSTATE;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._enqueue_fiscal_receipt() FROM PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Self-test (schema-level only, FK-free)
-- ─────────────────────────────────────────────────────────────────────────────
--   Verifies the two CHECK invariants this migration establishes
--   without seeding any data that has FK chains (which would be
--   fragile during fresh installs / partial schema replays). End-to-end
--   exec→fail flow with real data lives in
--   `tools/test_l03_03_provider_fee_revenue_track.ts`.

DO $self_test$
DECLARE
  v_dummy uuid;
BEGIN
  PERFORM set_config('lock_timeout', '2s', true);

  -- (a) platform_revenue accepts provider_fee.
  --     We INSERT then immediately DELETE inside a savepoint so the
  --     migration does not leak ledger noise even if a downstream FK
  --     interferes (group_id is nullable in platform_revenue per the
  --     baseline schema, so a NULL group_id keeps the row FK-clean).
  BEGIN
    INSERT INTO public.platform_revenue (
      fee_type, amount_usd, source_ref_id, group_id, description
    )
    VALUES (
      'provider_fee', 0.01, 'l03-03-self-test-' || gen_random_uuid()::text,
      NULL, 'L03-03 self-test guard (immediately deleted)'
    )
    RETURNING id INTO v_dummy;
    DELETE FROM public.platform_revenue WHERE id = v_dummy;
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION '[L03-03.self_test] CHECK rejects provider_fee — widening did not stick';
    WHEN foreign_key_violation THEN
      -- If a future migration adds a NOT NULL FK on group_id, the test
      -- can't run here without seeding a group. Surface that as a
      -- diagnostic NOTICE instead of failing the migration — the
      -- integration test still covers the full path.
      RAISE NOTICE '[L03-03.self_test] platform_revenue.group_id became required; '
        'CHECK guard skipped (covered by integration test)';
  END;

  -- (b) platform_fee_config rejects provider_fee (deliberate divergence
  --     between the two CHECKs). If this passes, someone added
  --     provider_fee to fee_config — that breaks the L01-44 + L03-03
  --     separation between configurable and pass-through fees.
  BEGIN
    INSERT INTO public.platform_fee_config (fee_type, rate_pct, is_active)
    VALUES ('provider_fee', 0.5, false);
    DELETE FROM public.platform_fee_config WHERE fee_type = 'provider_fee';
    RAISE EXCEPTION '[L03-03.self_test] platform_fee_config accepted provider_fee — '
      'should be rejected by CHECK (provider_fee is pass-through, not configurable)';
  EXCEPTION
    WHEN check_violation THEN
      -- Expected.
      NULL;
  END;

  -- (c) fiscal_receipts trigger short-circuits on provider_fee.
  --     We INSERT a provider_fee row and verify NO fiscal_receipts row
  --     was created (the trigger should `RETURN NEW` immediately).
  DECLARE
    v_pr_id     uuid;
    v_fr_count  integer;
  BEGIN
    INSERT INTO public.platform_revenue (
      fee_type, amount_usd, source_ref_id, group_id, description
    )
    VALUES (
      'provider_fee', 0.02, 'l03-03-trigger-skip-' || gen_random_uuid()::text,
      NULL, 'L03-03 trigger short-circuit guard'
    )
    RETURNING id INTO v_pr_id;

    SELECT count(*) INTO v_fr_count
      FROM public.fiscal_receipts
     WHERE platform_revenue_id = v_pr_id;

    DELETE FROM public.platform_revenue WHERE id = v_pr_id;

    IF v_fr_count <> 0 THEN
      RAISE EXCEPTION '[L03-03.self_test] _enqueue_fiscal_receipt did not '
        'short-circuit on provider_fee — % fiscal_receipts row(s) created', v_fr_count;
    END IF;
  EXCEPTION
    WHEN foreign_key_violation THEN
      RAISE NOTICE '[L03-03.self_test] platform_revenue.group_id became required; '
        'trigger guard skipped (covered by integration test)';
  END;

  RAISE NOTICE '[L03-03.self_test] platform_revenue accepts provider_fee; '
    'platform_fee_config still rejects it; fiscal_receipts trigger '
    'short-circuits on provider_fee (deliberate divergence verified)';
END;
$self_test$;

COMMIT;
