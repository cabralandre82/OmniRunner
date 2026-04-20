-- ──────────────────────────────────────────────────────────────────────────
-- L05-03 — POST /api/distribute-coins: amount max 1000 conflita com clubes
--           grandes (e o cliente precisa fazer N chamadas sequenciais para
--           distribuir bônus semanal a 200+ atletas, multiplicando o risco
--           de atomicidade já tratado em L02-01).
--
-- Referência:
--   docs/audit/findings/L05-03-post-api-distribute-coins-amount-max-1000-conflita.md
--   docs/audit/parts/05-cpo-cmo-cao.md  [5.3]
--   docs/audit/findings/L02-01-distribute-coins-orquestracao-nao-atomica-entre-4-rpcs.md (cross-ref)
--
-- Estratégia:
--   1. Mantemos `emit_coins_atomic` intacto (já é a primitiva atômica de 1
--      crédito). O batch APENAS o invoca em loop dentro de uma única
--      transação SECURITY DEFINER — qualquer falha de qualquer item rola
--      back o batch inteiro (custódia + inventário + wallet + ledger).
--   2. Cada item recebe um `ref_id` derivado do `p_batch_ref_id` mais o
--      índice (`<batch_ref>__<idx>`), permitindo replay idempotente do
--      batch inteiro: reentrar com o mesmo `p_batch_ref_id` devolve o
--      estado existente sem reprocessar (cada `emit_coins_atomic` já
--      curto-circuita via UNIQUE INDEX em coin_ledger.ref_id).
--   3. O cap superior de itens (`p_items` jsonb array) é validado em
--      runtime para defesa em profundidade, mesmo que o handler já
--      bloqueie via Zod (DISTRIBUTE_COINS_BATCH_MAX_ITEMS=200).
-- ──────────────────────────────────────────────────────────────────────────

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Drive-by fix: emit_coins_atomic ledger_id ambiguity (L19-01 follow-up)
--
-- The L19-01 partitioning migration (20260417200000_coin_ledger_partitioning.sql)
-- replaced emit_coins_atomic with a version that has a latent ambiguity bug:
--
--     RETURNS TABLE (ledger_id uuid, ...)  -- OUT param named ledger_id
--     ...
--     SELECT ledger_id INTO v_existing_id  -- ambiguous: OUT param vs
--       FROM public.coin_ledger_idempotency -- column of same name
--      WHERE ref_id = p_ref_id ...;
--
-- Postgres raises 42702 "column reference 'ledger_id' is ambiguous" the
-- first time the function is called from any non-REST SQL context (DO
-- blocks, CTE, another PL/pgSQL function — including this batch). The
-- supabase REST call path happened to dodge it because it materialises
-- via the function's TABLE shape with explicit column projection, but
-- the bug is still latent there. We fix it here by qualifying the
-- column with the table alias and shipping the same logic body.
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.emit_coins_atomic(
  p_group_id         uuid,
  p_athlete_user_id  uuid,
  p_amount           integer,
  p_ref_id           text
)
RETURNS TABLE (
  ledger_id       uuid,
  new_balance     integer,
  was_idempotent  boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_ledger_id      uuid;
  v_existing_id    uuid;
  v_new_balance    integer;
  v_now_ms         bigint := (extract(epoch from now()) * 1000)::bigint;
  v_claimed        boolean;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: amount must be > 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_ref_id IS NULL OR length(p_ref_id) = 0 THEN
    RAISE EXCEPTION 'MISSING_REF_ID: ref_id is required for idempotency' USING ERRCODE = 'P0001';
  END IF;

  v_ledger_id := gen_random_uuid();
  INSERT INTO public.coin_ledger_idempotency (ref_id, reason, ledger_id)
    VALUES (p_ref_id, 'institution_token_issue', v_ledger_id)
  ON CONFLICT (ref_id, reason) DO NOTHING;

  -- L05-03 fix: qualify column with table alias to disambiguate from the
  -- OUT parameter named `ledger_id`.
  SELECT cli.ledger_id INTO v_existing_id
    FROM public.coin_ledger_idempotency AS cli
   WHERE cli.ref_id = p_ref_id AND cli.reason = 'institution_token_issue';

  v_claimed := (v_existing_id = v_ledger_id);

  IF NOT v_claimed THEN
    SELECT balance_coins INTO v_new_balance FROM public.wallets
      WHERE user_id = p_athlete_user_id;
    RETURN QUERY SELECT v_existing_id, COALESCE(v_new_balance, 0), true;
    RETURN;
  END IF;

  INSERT INTO public.coin_ledger
    (id, user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
  VALUES
    (v_ledger_id, p_athlete_user_id, p_amount, 'institution_token_issue',
     p_ref_id, p_group_id, v_now_ms);

  BEGIN
    PERFORM public.custody_commit_coins(p_group_id, p_amount);
  EXCEPTION
    WHEN undefined_function THEN
      NULL;
    WHEN OTHERS THEN
      RAISE EXCEPTION 'CUSTODY_FAILED: %', SQLERRM USING ERRCODE = 'P0002';
  END;

  BEGIN
    PERFORM public.decrement_token_inventory(p_group_id, p_amount);
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'INVENTORY_INSUFFICIENT' USING ERRCODE = 'P0003';
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%INVENTORY_NOT_FOUND%' THEN
        RAISE EXCEPTION 'INVENTORY_INSUFFICIENT' USING ERRCODE = 'P0003';
      END IF;
      RAISE;
  END;

  PERFORM public.increment_wallet_balance(p_athlete_user_id, p_amount);

  SELECT balance_coins INTO v_new_balance FROM public.wallets
    WHERE user_id = p_athlete_user_id;

  RETURN QUERY SELECT v_ledger_id, COALESCE(v_new_balance, 0), false;
END;
$$;

COMMENT ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) IS
  'L02-01 + L19-01 + L05-03: emissão atômica de OmniCoins com idempotência via '
  'coin_ledger_idempotency. Retorna was_idempotent=true quando ref_id já foi '
  'processado. Erros: INVALID_AMOUNT, MISSING_REF_ID (P0001); CUSTODY_FAILED (P0002); '
  'INVENTORY_INSUFFICIENT (P0003). L05-03: ledger_id column reference qualified '
  'with table alias to fix ambiguity with OUT parameter that broke SQL invocation.';

REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM anon;
REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) TO service_role;


-- ──────────────────────────────────────────────────────────────────────────
-- 2. Função batch atômica (L05-03 main)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.distribute_coins_batch_atomic(
  p_group_id        uuid,
  p_caller_user_id  uuid,
  p_items           jsonb,
  p_batch_ref_id    text
)
RETURNS TABLE (
  total_amount         integer,
  total_distributions  integer,
  batch_was_idempotent boolean,
  items                jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '5s'
AS $$
DECLARE
  v_caller_role        text;
  v_count              integer;
  v_total_amount       integer := 0;
  v_total_dist         integer := 0;
  v_idempotent_count   integer := 0;
  v_results            jsonb := '[]'::jsonb;
  v_item               jsonb;
  v_idx                integer := 0;
  v_athlete_id         uuid;
  v_amount             integer;
  v_item_ref_id        text;
  v_emit_row           record;
  -- L05-03 — runtime cap mirrors DISTRIBUTE_COINS_BATCH_MAX_ITEMS / _MAX_TOTAL
  -- (portal/src/lib/schemas.ts). Defense in depth: even if a future client
  -- bypasses the Zod layer, the DB still refuses payloads that risk
  -- statement_timeout or absurd totals.
  c_max_items          integer := 200;
  c_max_total          integer := 1000000;
  c_max_per_item       integer := 100000;
BEGIN
  -- 1. Caller authz: only admin_master de coaching_members do group pode emitir
  IF p_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'MISSING_CALLER' USING ERRCODE = 'P0001';
  END IF;

  SELECT role INTO v_caller_role
  FROM public.coaching_members
  WHERE group_id = p_group_id AND user_id = p_caller_user_id;

  IF v_caller_role IS NULL OR v_caller_role <> 'admin_master' THEN
    RAISE EXCEPTION 'FORBIDDEN: caller is not admin_master of group %', p_group_id
      USING ERRCODE = 'P0001';
  END IF;

  -- 2. Payload sanity
  IF p_batch_ref_id IS NULL OR length(p_batch_ref_id) < 8 THEN
    RAISE EXCEPTION 'MISSING_REF_ID: batch ref_id is required (>=8 chars)' USING ERRCODE = 'P0001';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_ITEMS: p_items must be a JSON array' USING ERRCODE = 'P0001';
  END IF;

  v_count := jsonb_array_length(p_items);
  IF v_count = 0 THEN
    RAISE EXCEPTION 'EMPTY_BATCH: items must contain at least 1 entry' USING ERRCODE = 'P0001';
  END IF;
  IF v_count > c_max_items THEN
    RAISE EXCEPTION 'BATCH_TOO_LARGE: % items > limit %', v_count, c_max_items
      USING ERRCODE = 'P0001';
  END IF;

  -- 3. Loop: cada item vira chamada para emit_coins_atomic com ref derivado.
  --    Toda a function é uma única transação implícita; qualquer RAISE em
  --    emit_coins_atomic (CUSTODY_FAILED / INVENTORY_INSUFFICIENT / etc.)
  --    aborta o lote inteiro.
  FOR v_idx IN 0 .. v_count - 1 LOOP
    v_item := p_items -> v_idx;

    IF jsonb_typeof(v_item) <> 'object' THEN
      RAISE EXCEPTION 'INVALID_ITEM at index %: not an object', v_idx
        USING ERRCODE = 'P0001';
    END IF;

    BEGIN
      v_athlete_id := (v_item ->> 'athlete_user_id')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'INVALID_ITEM at index %: athlete_user_id not a UUID', v_idx
          USING ERRCODE = 'P0001';
    END;

    v_amount := (v_item ->> 'amount')::integer;

    IF v_athlete_id IS NULL THEN
      RAISE EXCEPTION 'INVALID_ITEM at index %: missing athlete_user_id', v_idx
        USING ERRCODE = 'P0001';
    END IF;
    IF v_amount IS NULL OR v_amount <= 0 THEN
      RAISE EXCEPTION 'INVALID_ITEM at index %: amount must be > 0', v_idx
        USING ERRCODE = 'P0001';
    END IF;
    IF v_amount > c_max_per_item THEN
      RAISE EXCEPTION 'INVALID_ITEM at index %: amount % > per-item limit %',
        v_idx, v_amount, c_max_per_item USING ERRCODE = 'P0001';
    END IF;

    v_total_amount := v_total_amount + v_amount;
    IF v_total_amount > c_max_total THEN
      RAISE EXCEPTION 'BATCH_TOTAL_EXCEEDED: running total % > limit %',
        v_total_amount, c_max_total USING ERRCODE = 'P0001';
    END IF;

    -- ref_id determinístico: replay de qualquer item devolve o ledger
    -- existente via UNIQUE INDEX (L02-01) sem mexer em wallet/inventário.
    v_item_ref_id := p_batch_ref_id || '__' || v_idx::text;

    SELECT * INTO v_emit_row
    FROM public.emit_coins_atomic(
      p_group_id,
      v_athlete_id,
      v_amount,
      v_item_ref_id
    );

    v_total_dist := v_total_dist + 1;
    IF v_emit_row.was_idempotent THEN
      v_idempotent_count := v_idempotent_count + 1;
    END IF;

    v_results := v_results || jsonb_build_object(
      'athlete_user_id', v_athlete_id,
      'amount',          v_amount,
      'new_balance',     v_emit_row.new_balance,
      'was_idempotent',  v_emit_row.was_idempotent,
      'ledger_id',       v_emit_row.ledger_id
    );
  END LOOP;

  RETURN QUERY SELECT
    v_total_amount,
    v_total_dist,
    -- batch_was_idempotent é TRUE somente se TODOS os itens já existiam
    -- (replay completo); um único item novo já marca o batch como
    -- "execução nova" para fins de auditoria.
    (v_idempotent_count = v_total_dist),
    v_results;
END;
$$;

COMMENT ON FUNCTION public.distribute_coins_batch_atomic(uuid, uuid, jsonb, text) IS
  'L05-03: distribuição em lote (até 200 atletas, total 1MM coins) executada '
  'em transação única, delegando cada item ao emit_coins_atomic (L02-01). '
  'Qualquer falha (CUSTODY_FAILED, INVENTORY_INSUFFICIENT, INVALID_ITEM) aborta '
  'o lote inteiro. Idempotência por ref_id derivado: reentrar com o mesmo '
  'p_batch_ref_id devolve estado existente sem reprocessar.';

REVOKE ALL ON FUNCTION public.distribute_coins_batch_atomic(uuid, uuid, jsonb, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.distribute_coins_batch_atomic(uuid, uuid, jsonb, text) FROM anon;
REVOKE ALL ON FUNCTION public.distribute_coins_batch_atomic(uuid, uuid, jsonb, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.distribute_coins_batch_atomic(uuid, uuid, jsonb, text) TO service_role;

-- 2. Self-check: a função existe e aceita o tipo certo de p_items.
--    Não tentamos rodar com dados reais aqui (depende de coaching_members /
--    wallets / custódia, que variam entre ambientes). O sandbox runner
--    `tools/test_l05_03_distribute_coins_batch.ts` cobre o caminho ponta a ponta.
DO $$
DECLARE
  v_proname text;
BEGIN
  SELECT proname INTO v_proname
  FROM pg_proc
  WHERE proname = 'distribute_coins_batch_atomic'
    AND pronamespace = 'public'::regnamespace
  LIMIT 1;

  IF v_proname IS NULL THEN
    RAISE EXCEPTION 'L05-03 self-check: distribute_coins_batch_atomic not registered';
  END IF;
END;
$$;
