-- ============================================================================
-- L03-13 hotfix — ambiguous column references in reverse_*_atomic functions
--
-- Audit reference:
--   docs/audit/findings/L03-13-reembolso-estorno-nao-ha-funcao-reverse-burn-ou.md
--   (surfaced during L03-20 build; see migration 20260421160000)
--
-- Problem
-- ───────
--   As três funções introduzidas em 20260421130000_l03_reverse_coin_flows.sql
--   têm ambiguidades entre colunas de `RETURNS TABLE` e colunas de tabelas
--   físicas / funções chamadas. PostgreSQL 17 com
--   `plpgsql.variable_conflict = error` (padrão em Supabase) recusa em
--   runtime com:
--
--     42702: column reference "<col>" is ambiguous.
--     It could refer to either a PL/pgSQL variable or a table column.
--
--   Tabela de conflitos detectados ao rodar
--   `tools/test_l03_13_reverse_coins.ts` contra a instância local (todos
--   surgem em RUNTIME — CREATE FUNCTION valida sintaxe mas não resolve
--   nomes):
--
--   ┌─────────────────────────────────────┬───────────────────────────────┐
--   │ função                              │ coluna ambígua                │
--   ├─────────────────────────────────────┼───────────────────────────────┤
--   │ reverse_coin_emission_atomic        │ `new_balance` (retorno de     │
--   │                                     │  fn_mutate_wallet vs RETURNS  │
--   │                                     │  TABLE output)                │
--   │ reverse_burn_atomic                 │ `athlete_user_id`,            │
--   │                                     │  `new_balance`,               │
--   │                                     │  `clearing_event_id` (todos   │
--   │                                     │  presentes em RETURNS TABLE)  │
--   │ reverse_custody_deposit_atomic      │ `group_id`, `deposit_id`      │
--   │                                     │  (custody_deposits +          │
--   │                                     │  custody_accounts vs RETURNS  │
--   │                                     │  TABLE output)                │
--   └─────────────────────────────────────┴───────────────────────────────┘
--
--   Bugs secundários descobertos no mesmo ciclo de teste:
--
--     • `reverse_burn_atomic` seta `clearing_settlements.status = 'cancelled'`
--       mas a CHECK original (20260228150001) só permite
--       `('pending','settled','insufficient','failed')`. Em produção o
--       UPDATE falharia com `23514 check_violation`. Esta migration
--       estende a CHECK para incluir `'cancelled'`.
--
--     • `reverse_burn_atomic` NÃO captura `check_violation` ao chamar
--       `fn_mutate_wallet` — o path "athlete already spent the coins"
--       vaza 23514 em vez do esperado `INSUFFICIENT_BALANCE (P0003)`.
--       reverse_coin_emission_atomic tem o catch; reverse_burn_atomic
--       não tinha. Alinhamos o comportamento.
--
-- Fix (this migration)
-- ────────────────────
--   CREATE OR REPLACE nas três funções com table aliases nos SELECTs que
--   colidem. Assinaturas e comportamento observável ficam IDÊNTICOS; só
--   a implementação interna muda. Também:
--     • `#variable_conflict use_variable` no topo de cada função — se
--       algum SELECT nativo passar por revisão futura e criar nova
--       ambiguidade, o PL/pgSQL resolverá para a variável (mais seguro
--       para o nosso estilo v_…) em vez de falhar em runtime.
--     • CHECK constraint de `clearing_settlements.status` estendida.
--     • Catch de `check_violation` adicionado em reverse_burn_atomic.
-- ============================================================================

BEGIN;

SET lock_timeout = '2s';

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Extend clearing_settlements.status CHECK to allow 'cancelled'
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.clearing_settlements
  DROP CONSTRAINT IF EXISTS clearing_settlements_status_check;

ALTER TABLE public.clearing_settlements
  ADD CONSTRAINT clearing_settlements_status_check
  CHECK (status IN ('pending', 'settled', 'insufficient', 'failed', 'cancelled'));

COMMENT ON CONSTRAINT clearing_settlements_status_check
  ON public.clearing_settlements IS
  'L03-13 hotfix: adicionado ''cancelled'' — usado por reverse_burn_atomic '
  'para marcar settlements não-settled que foram desfeitos pela reversão.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. reverse_coin_emission_atomic — `new_balance` ambiguity
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reverse_coin_emission_atomic(
  p_original_ledger_id  uuid,
  p_reason              text,
  p_actor_user_id       uuid,
  p_idempotency_key     text
)
RETURNS TABLE (
  reversal_id        uuid,
  reversal_ledger_id uuid,
  athlete_user_id    uuid,
  reversed_amount    integer,
  new_balance        integer,
  was_idempotent     boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
#variable_conflict use_variable
DECLARE
  v_existing_rev   uuid;
  v_existing_meta  jsonb;
  v_rev_id         uuid;
  v_orig_user      uuid;
  v_orig_group     uuid;
  v_orig_amount    integer;
  v_orig_reason    text;
  v_orig_ref       text;
  v_mut_row        record;
  v_new_balance    integer;
  v_has_custody    boolean;
BEGIN
  IF p_original_ledger_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_LEDGER_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'pass the platform_admin auth.uid() so audit log is attributable';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'REASON_REQUIRED: postmortem reason must be >= 10 chars'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'MISSING_IDEMPOTENCY_KEY: key must be >= 8 chars'
      USING ERRCODE = 'P0001';
  END IF;

  -- (a) Idempotência.
  SELECT crl.id, crl.metadata
    INTO v_existing_rev, v_existing_meta
    FROM public.coin_reversal_log crl
   WHERE crl.kind = 'emission'
     AND crl.idempotency_key = p_idempotency_key;

  IF v_existing_rev IS NOT NULL THEN
    RETURN QUERY
      SELECT
        v_existing_rev,
        (v_existing_meta ->> 'reversal_ledger_id')::uuid,
        (v_existing_meta ->> 'athlete_user_id')::uuid,
        (v_existing_meta ->> 'reversed_amount')::integer,
        (v_existing_meta ->> 'new_balance')::integer,
        true;
    RETURN;
  END IF;

  -- (b) Lock ledger row + validate it is an emission.
  SELECT cl.user_id, cl.issuer_group_id, cl.delta_coins, cl.reason, cl.ref_id
    INTO v_orig_user, v_orig_group, v_orig_amount, v_orig_reason, v_orig_ref
    FROM public.coin_ledger cl
   WHERE cl.id = p_original_ledger_id
   FOR UPDATE;

  IF v_orig_user IS NULL THEN
    RAISE EXCEPTION 'LEDGER_NOT_FOUND: id=%', p_original_ledger_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_orig_reason <> 'institution_token_issue' THEN
    RAISE EXCEPTION
      'INVALID_TARGET_REASON: expected institution_token_issue, got %',
      v_orig_reason
      USING ERRCODE = 'P0008',
            HINT = 'use reverse_burn_atomic for institution_token_burn or the appropriate domain-specific flow';
  END IF;

  IF v_orig_amount IS NULL OR v_orig_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_TARGET_AMOUNT: original delta_coins=% (must be >0)',
      v_orig_amount USING ERRCODE = 'P0008';
  END IF;

  -- (c) Debita wallet + insere ledger negativo em UMA operação.
  BEGIN
    SELECT fm.ledger_id, fm.new_balance INTO v_mut_row
      FROM public.fn_mutate_wallet(
        v_orig_user,
        -v_orig_amount,
        'institution_token_reverse_emission',
        'reverse_emission:' || p_original_ledger_id::text,
        v_orig_group
      ) fm;
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'INSUFFICIENT_BALANCE: athlete already spent the coins'
        USING ERRCODE = 'P0003',
              HINT = 'user spent the tokens; chase the debt-of-group path (CHARGEBACK_RUNBOOK §3.3) instead';
  END;

  v_new_balance := v_mut_row.new_balance;

  -- (d) Restaura inventário.
  IF v_orig_group IS NOT NULL THEN
    BEGIN
      PERFORM public.reverse_token_inventory_issuance(v_orig_group, v_orig_amount);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM LIKE '%INVENTORY_NOT_FOUND%' THEN
          RAISE NOTICE '[L03-13] inventory missing for group % — reversal proceeding', v_orig_group;
        ELSE
          RAISE;
        END IF;
    END;
  END IF;

  -- (e) Libera custódia committed.
  IF v_orig_group IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.custody_accounts ca WHERE ca.group_id = v_orig_group
    ) INTO v_has_custody;
    IF v_has_custody THEN
      BEGIN
        PERFORM public.custody_release_committed(v_orig_group, v_orig_amount);
      EXCEPTION
        WHEN OTHERS THEN
          RAISE NOTICE '[L03-13] custody_release_committed failed for group % (%): %',
            v_orig_group, SQLSTATE, SQLERRM;
      END;
    END IF;
  END IF;

  -- (f) coin_reversal_log + audit
  v_rev_id := gen_random_uuid();
  INSERT INTO public.coin_reversal_log
    (id, kind, idempotency_key, target_ref, actor_user_id, reason,
     metadata, reversed_coins, reversed_usd)
  VALUES
    (v_rev_id, 'emission', p_idempotency_key,
     p_original_ledger_id::text, p_actor_user_id, p_reason,
     jsonb_build_object(
       'reversal_ledger_id', v_mut_row.ledger_id,
       'athlete_user_id',    v_orig_user,
       'reversed_amount',    v_orig_amount,
       'new_balance',        v_new_balance,
       'original_ref_id',    v_orig_ref,
       'issuer_group_id',    v_orig_group
     ),
     v_orig_amount,
     NULL);

  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  VALUES
    (p_actor_user_id, v_orig_group, 'coins.reverse.emission',
     'coin_ledger', p_original_ledger_id::text,
     jsonb_build_object(
       'reversal_id',        v_rev_id,
       'reversal_ledger_id', v_mut_row.ledger_id,
       'amount',             v_orig_amount,
       'athlete_user_id',    v_orig_user,
       'reason',             p_reason,
       'runbook',            'REVERSE_COINS_RUNBOOK#emission'
     ));

  RETURN QUERY SELECT
    v_rev_id,
    v_mut_row.ledger_id,
    v_orig_user,
    v_orig_amount,
    v_new_balance,
    false;
END;
$$;

REVOKE ALL ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. reverse_burn_atomic — `athlete_user_id` / `new_balance` ambiguity +
--    check_violation catch + 'cancelled' status allowed by hotfix above
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reverse_burn_atomic(
  p_burn_ref_id      text,
  p_reason           text,
  p_actor_user_id    uuid,
  p_idempotency_key  text
)
RETURNS TABLE (
  reversal_id        uuid,
  clearing_event_id  uuid,
  athlete_user_id    uuid,
  reversed_amount    integer,
  new_balance        integer,
  settlements_cancelled integer,
  was_idempotent     boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
#variable_conflict use_variable
DECLARE
  v_existing_rev   uuid;
  v_existing_meta  jsonb;
  v_rev_id         uuid;
  v_event_id       uuid;
  v_athlete        uuid;
  v_redeemer       uuid;
  v_total_coins    integer;
  v_breakdown      jsonb;
  v_settlements_cancelled integer := 0;
  v_has_settled    integer;
  v_issuer         uuid;
  v_issuer_amt     integer;
  v_mut_row        record;
  v_new_balance    integer;
BEGIN
  IF p_burn_ref_id IS NULL OR length(trim(p_burn_ref_id)) = 0 THEN
    RAISE EXCEPTION 'INVALID_BURN_REF' USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'MISSING_IDEMPOTENCY_KEY' USING ERRCODE = 'P0001';
  END IF;

  -- (a) Idempotência.
  SELECT crl.id, crl.metadata
    INTO v_existing_rev, v_existing_meta
    FROM public.coin_reversal_log crl
   WHERE crl.kind = 'burn' AND crl.idempotency_key = p_idempotency_key;

  IF v_existing_rev IS NOT NULL THEN
    RETURN QUERY SELECT
      v_existing_rev,
      (v_existing_meta ->> 'clearing_event_id')::uuid,
      (v_existing_meta ->> 'athlete_user_id')::uuid,
      (v_existing_meta ->> 'reversed_amount')::integer,
      (v_existing_meta ->> 'new_balance')::integer,
      (v_existing_meta ->> 'settlements_cancelled')::integer,
      true;
    RETURN;
  END IF;

  -- (b) Carrega clearing_event (lock + detalhes).
  SELECT ce.id, ce.athlete_user_id, ce.redeemer_group_id, ce.total_coins, ce.breakdown
    INTO v_event_id, v_athlete, v_redeemer, v_total_coins, v_breakdown
    FROM public.clearing_events ce
   WHERE ce.burn_ref_id = p_burn_ref_id
   FOR UPDATE;

  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'BURN_NOT_FOUND: burn_ref_id=%', p_burn_ref_id
      USING ERRCODE = 'P0002';
  END IF;

  -- (c) Bloqueia se há settlements já compensados (cross-club settled).
  SELECT COUNT(*)
    INTO v_has_settled
    FROM public.clearing_settlements cs
   WHERE cs.clearing_event_id = v_event_id
     AND cs.status = 'settled';

  IF v_has_settled > 0 THEN
    RAISE EXCEPTION
      'NOT_REVERSIBLE: % settlement(s) already settled between custodies',
      v_has_settled
      USING ERRCODE = 'P0008',
            HINT = 'see docs/runbooks/REVERSE_COINS_RUNBOOK.md §"burn with settled settlements" for manual inter-club unwind';
  END IF;

  -- (d) Cancela settlements não-settled (pending / insufficient / failed).
  UPDATE public.clearing_settlements
     SET status = 'cancelled',
         settled_at = now()
   WHERE clearing_event_id = v_event_id
     AND status IN ('pending', 'insufficient', 'failed');
  GET DIAGNOSTICS v_settlements_cancelled = ROW_COUNT;

  -- (e) Re-commit custódia intra-clube.
  FOR v_issuer, v_issuer_amt IN
    SELECT
      (entry->>'issuer_group_id')::uuid,
      (entry->>'amount')::integer
    FROM jsonb_array_elements(v_breakdown) AS entry
    WHERE entry->>'issuer_group_id' IS NOT NULL
  LOOP
    IF v_issuer = v_redeemer THEN
      BEGIN
        PERFORM public.custody_commit_coins(v_issuer, v_issuer_amt);
      EXCEPTION
        WHEN OTHERS THEN
          RAISE EXCEPTION
            'CUSTODY_RECOMMIT_FAILED: group=% amount=% err=%',
            v_issuer, v_issuer_amt, SQLERRM
            USING ERRCODE = 'P0002',
                  HINT = 'deposit more backing into the group custody before retrying';
      END;
    END IF;
  END LOOP;

  -- (f) Re-credita wallet (ledger positivo). Catch de check_violation
  -- (NÃO deveria bater: reverse_burn re-CREDITA a wallet; balance só
  -- sobe. Mantemos o catch por paridade defensiva com emission.)
  BEGIN
    SELECT fm.ledger_id, fm.new_balance INTO v_mut_row
      FROM public.fn_mutate_wallet(
        v_athlete,
        v_total_coins,
        'institution_token_reverse_burn',
        'reverse_burn:' || p_burn_ref_id,
        NULL
      ) fm;
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'WALLET_CHECK_VIOLATION during reverse_burn_atomic: %', SQLERRM
        USING ERRCODE = 'P0003';
  END;

  v_new_balance := v_mut_row.new_balance;

  -- (g) coin_reversal_log + audit.
  v_rev_id := gen_random_uuid();
  INSERT INTO public.coin_reversal_log
    (id, kind, idempotency_key, target_ref, actor_user_id, reason,
     metadata, reversed_coins, reversed_usd)
  VALUES
    (v_rev_id, 'burn', p_idempotency_key, p_burn_ref_id,
     p_actor_user_id, p_reason,
     jsonb_build_object(
       'clearing_event_id',     v_event_id,
       'athlete_user_id',       v_athlete,
       'reversed_amount',       v_total_coins,
       'new_balance',           v_new_balance,
       'settlements_cancelled', v_settlements_cancelled,
       'reversal_ledger_id',    v_mut_row.ledger_id,
       'redeemer_group_id',     v_redeemer,
       'breakdown',             v_breakdown
     ),
     v_total_coins,
     NULL);

  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  VALUES
    (p_actor_user_id, v_redeemer, 'coins.reverse.burn',
     'clearing_event', v_event_id::text,
     jsonb_build_object(
       'reversal_id',           v_rev_id,
       'burn_ref_id',           p_burn_ref_id,
       'amount',                v_total_coins,
       'settlements_cancelled', v_settlements_cancelled,
       'athlete_user_id',       v_athlete,
       'reason',                p_reason,
       'runbook',               'REVERSE_COINS_RUNBOOK#burn'
     ));

  RETURN QUERY SELECT
    v_rev_id,
    v_event_id,
    v_athlete,
    v_total_coins,
    v_new_balance,
    v_settlements_cancelled,
    false;
END;
$$;

REVOKE ALL ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. reverse_custody_deposit_atomic — `group_id` / `deposit_id` ambiguity
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reverse_custody_deposit_atomic(
  p_deposit_id       uuid,
  p_reason           text,
  p_actor_user_id    uuid,
  p_idempotency_key  text
)
RETURNS TABLE (
  reversal_id       uuid,
  deposit_id        uuid,
  group_id          uuid,
  refunded_usd      numeric,
  was_idempotent    boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
#variable_conflict use_variable
DECLARE
  v_existing_rev   uuid;
  v_existing_meta  jsonb;
  v_rev_id         uuid;
  v_group_id       uuid;
  v_amount_usd     numeric(14,2);
  v_status         text;
  v_deposited      numeric(14,2);
  v_committed      numeric(14,2);
BEGIN
  IF p_deposit_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_DEPOSIT_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'MISSING_IDEMPOTENCY_KEY' USING ERRCODE = 'P0001';
  END IF;

  -- (a) Idempotência.
  SELECT crl.id, crl.metadata
    INTO v_existing_rev, v_existing_meta
    FROM public.coin_reversal_log crl
   WHERE crl.kind = 'deposit' AND crl.idempotency_key = p_idempotency_key;

  IF v_existing_rev IS NOT NULL THEN
    RETURN QUERY SELECT
      v_existing_rev,
      (v_existing_meta ->> 'deposit_id')::uuid,
      (v_existing_meta ->> 'group_id')::uuid,
      (v_existing_meta ->> 'refunded_usd')::numeric,
      true;
    RETURN;
  END IF;

  -- (b) Lock deposit.
  SELECT cd.group_id, cd.amount_usd, cd.status
    INTO v_group_id, v_amount_usd, v_status
    FROM public.custody_deposits cd
   WHERE cd.id = p_deposit_id
   FOR UPDATE;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: id=%', p_deposit_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_status = 'refunded' THEN
    -- Replay amigável com outra idempotency_key.
    v_rev_id := gen_random_uuid();
    INSERT INTO public.coin_reversal_log
      (id, kind, idempotency_key, target_ref, actor_user_id, reason,
       metadata, reversed_coins, reversed_usd)
    VALUES
      (v_rev_id, 'deposit', p_idempotency_key, p_deposit_id::text,
       p_actor_user_id, p_reason,
       jsonb_build_object(
         'deposit_id',   p_deposit_id,
         'group_id',     v_group_id,
         'refunded_usd', 0,
         'noop_reason',  'already_refunded'
       ),
       NULL, 0);
    RETURN QUERY SELECT v_rev_id, p_deposit_id, v_group_id, 0::numeric, true;
    RETURN;
  END IF;

  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'INVALID_STATE: deposit status=% (only confirmed can be reversed)',
      v_status
      USING ERRCODE = 'P0008',
            HINT = 'use the payment-gateway-specific failure path for pending/failed deposits';
  END IF;

  -- (c) Lock custody_account.
  SELECT ca.total_deposited_usd, ca.total_committed
    INTO v_deposited, v_committed
    FROM public.custody_accounts ca
   WHERE ca.group_id = v_group_id
   FOR UPDATE;

  IF v_deposited IS NULL THEN
    RAISE EXCEPTION 'CUSTODY_ACCOUNT_NOT_FOUND: group_id=%', v_group_id
      USING ERRCODE = 'P0002';
  END IF;

  -- (d) Invariante: após subtrair, deposited >= committed.
  IF v_deposited - v_amount_usd < COALESCE(v_committed, 0) THEN
    RAISE EXCEPTION
      'INVARIANT_VIOLATION: refund would leave deposited=% < committed=% (coins already issued against this backing)',
      v_deposited - v_amount_usd, v_committed
      USING ERRCODE = 'P0008',
            HINT = 'reverse outstanding emissions first (CHARGEBACK_RUNBOOK §3.3)';
  END IF;

  -- (e) Subtrai lastro + marca deposit como refunded.
  UPDATE public.custody_accounts ca
     SET total_deposited_usd = ca.total_deposited_usd - v_amount_usd,
         updated_at = now()
   WHERE ca.group_id = v_group_id;

  UPDATE public.custody_deposits cd
     SET status = 'refunded'
   WHERE cd.id = p_deposit_id;

  -- (f) Log + audit.
  v_rev_id := gen_random_uuid();
  INSERT INTO public.coin_reversal_log
    (id, kind, idempotency_key, target_ref, actor_user_id, reason,
     metadata, reversed_coins, reversed_usd)
  VALUES
    (v_rev_id, 'deposit', p_idempotency_key, p_deposit_id::text,
     p_actor_user_id, p_reason,
     jsonb_build_object(
       'deposit_id',   p_deposit_id,
       'group_id',     v_group_id,
       'refunded_usd', v_amount_usd,
       'prev_status',  'confirmed'
     ),
     NULL,
     v_amount_usd);

  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  VALUES
    (p_actor_user_id, v_group_id, 'coins.reverse.deposit',
     'custody_deposit', p_deposit_id::text,
     jsonb_build_object(
       'reversal_id',  v_rev_id,
       'amount_usd',   v_amount_usd,
       'reason',       p_reason,
       'runbook',      'REVERSE_COINS_RUNBOOK#deposit'
     ));

  RETURN QUERY SELECT v_rev_id, p_deposit_id, v_group_id, v_amount_usd, false;
END;
$$;

COMMENT ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) IS
  'L03-13: inverte confirm_custody_deposit. Recusa o refund (P0008) '
  'se total_deposited - amount < total_committed (coins já emitidas '
  'contra o lastro); caso contrário subtrai o lastro, seta status=refunded, '
  'escreve coin_reversal_log + audit. Idempotente por '
  '(kind=deposit, idempotency_key). Hotfix L03-13 aplicado em 20260421150000 '
  'para resolver ambiguidades de referência de coluna.';

REVOKE ALL ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) TO service_role;

COMMIT;
