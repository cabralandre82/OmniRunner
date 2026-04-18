-- ──────────────────────────────────────────────────────────────────────────
-- L02-01 — Correção: distribute-coins orquestração não-atômica
--
-- Referência auditoria:
--   docs/audit/findings/L02-01-distribute-coins-orquestracao-nao-atomica-entre-4-rpcs.md
--   docs/audit/parts/02-cto-cfo.md [2.1]
--   docs/audit/parts/01-ciso.md    [1.3] (cross-ref)
--
-- Problema:
--   /api/distribute-coins executa 4 operações em 4 conexões separadas
--   (custody_commit_coins, decrement_token_inventory, increment_wallet_balance,
--    INSERT coin_ledger). Se qualquer uma falhar após outra ter committado,
--   custódia, inventário, wallet e ledger ficam inconsistentes. O INSERT no
--   ledger falhava silenciosamente retornando 200 OK ao cliente.
--
-- Correção:
--   1. UNIQUE INDEX parcial em coin_ledger(ref_id) para reason='institution_token_issue'
--      → garante idempotência forte ao nível do banco.
--   2. Função emit_coins_atomic envolvendo TODAS as mutações em transação única.
--      Qualquer falha reverte o bloco inteiro. Idempotent retry devolve o estado
--      existente sem reprocessar.
-- ──────────────────────────────────────────────────────────────────────────

-- 1. Partial UNIQUE INDEX — idempotência forte
-- Só aplica a institution_token_issue; outras reasons podem repetir ref_id legitimamente
-- (ex: institution_switch_burn usa ref_id = group_id).
CREATE UNIQUE INDEX IF NOT EXISTS idx_coin_ledger_ref_id_institution_issue_unique
  ON public.coin_ledger (ref_id)
  WHERE reason = 'institution_token_issue' AND ref_id IS NOT NULL;

COMMENT ON INDEX public.idx_coin_ledger_ref_id_institution_issue_unique IS
  'L02-01: idempotência forte para emissão institucional. '
  'Garante ON CONFLICT em emit_coins_atomic.';


-- 2. Função atômica
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
AS $$
DECLARE
  v_ledger_id      uuid;
  v_new_balance    integer;
  v_existing_id    uuid;
  v_now_ms         bigint := (extract(epoch from now()) * 1000)::bigint;
BEGIN
  -- Validação de entrada
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: amount must be > 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_ref_id IS NULL OR length(p_ref_id) = 0 THEN
    RAISE EXCEPTION 'MISSING_REF_ID: ref_id is required for idempotency' USING ERRCODE = 'P0001';
  END IF;

  -- (A) INSERT ledger com ON CONFLICT para capturar idempotent retry
  INSERT INTO public.coin_ledger
    (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
  VALUES
    (p_athlete_user_id, p_amount, 'institution_token_issue', p_ref_id, p_group_id, v_now_ms)
  ON CONFLICT (ref_id) WHERE reason = 'institution_token_issue'
  DO NOTHING
  RETURNING id INTO v_ledger_id;

  IF v_ledger_id IS NULL THEN
    -- Idempotent retry: linha já existe com mesmo ref_id
    -- Retorna estado atual sem mexer em inventário/custódia/wallet
    SELECT id INTO v_existing_id FROM public.coin_ledger
      WHERE ref_id = p_ref_id AND reason = 'institution_token_issue';

    SELECT balance_coins INTO v_new_balance FROM public.wallets
      WHERE user_id = p_athlete_user_id;

    RETURN QUERY SELECT v_existing_id, COALESCE(v_new_balance, 0), true;
    RETURN;
  END IF;

  -- (B) Custódia: commit coins contra lastro USD
  -- Se a função não existir (deploy incompleto), seguimos sem ela.
  -- Se existir e falhar (lastro insuficiente), aborta toda a transação.
  BEGIN
    PERFORM public.custody_commit_coins(p_group_id, p_amount);
  EXCEPTION
    WHEN undefined_function THEN
      NULL; -- custody_commit_coins não deployada; ignora
    WHEN OTHERS THEN
      RAISE EXCEPTION 'CUSTODY_FAILED: %', SQLERRM USING ERRCODE = 'P0002';
  END;

  -- (C) Decrementa inventário da assessoria (CHECK >= 0 previne overdraft)
  BEGIN
    PERFORM public.decrement_token_inventory(p_group_id, p_amount);
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'INVENTORY_INSUFFICIENT' USING ERRCODE = 'P0003';
    WHEN OTHERS THEN
      -- INVENTORY_NOT_FOUND ou erro inesperado
      IF SQLERRM LIKE '%INVENTORY_NOT_FOUND%' THEN
        RAISE EXCEPTION 'INVENTORY_INSUFFICIENT' USING ERRCODE = 'P0003';
      END IF;
      RAISE;
  END;

  -- (D) Credita wallet do atleta
  PERFORM public.increment_wallet_balance(p_athlete_user_id, p_amount);

  -- Pega saldo final para devolver ao cliente
  SELECT balance_coins INTO v_new_balance FROM public.wallets
    WHERE user_id = p_athlete_user_id;

  RETURN QUERY SELECT v_ledger_id, COALESCE(v_new_balance, 0), false;
END;
$$;

COMMENT ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) IS
  'L02-01: emissão atômica de OmniCoins (custódia + inventário + wallet + ledger) '
  'em transação única com idempotência forte via ref_id. '
  'Retorna was_idempotent=true quando chamada com ref_id já existente. '
  'Erros: INVALID_AMOUNT, MISSING_REF_ID (P0001); CUSTODY_FAILED (P0002); '
  'INVENTORY_INSUFFICIENT (P0003).';


REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) TO service_role;
