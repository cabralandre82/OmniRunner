-- ============================================================================
-- L03-02 — Congelamento da taxa de clearing no MOMENTO DA EMISSÃO
--
-- Referência auditoria:
--   docs/audit/findings/L03-02-congelamento-de-precos-taxas.md
--   docs/audit/parts/03-cfo.md  [3.2]
--
-- Problema (pré-fix)
-- ──────────────────
-- `execute_burn_atomic` (cadeia de migrations 20260228160001 → 20260417140000
-- → 20260419130000) lê `platform_fee_config.rate_pct` NO MOMENTO DO BURN:
--
--   SELECT rate_pct INTO v_fee_rate
--     FROM public.platform_fee_config
--    WHERE fee_type = 'clearing' AND is_active = true;
--   v_fee_rate := COALESCE(v_fee_rate, 3.0);
--
-- Isso significa que se a plataforma ajustar `clearing` de 3.0% para 5.0%
-- entre a emissão da coin (T=0) e o burn dela (T=6 meses depois), a
-- assessoria emissora paga 5% ao invés dos 3% que constavam quando ela
-- emitiu. O inverso também é verdade (drop de 3% → 1%): a plataforma perde
-- receita prometida.
--
-- Impacto por trilha:
--   • CFO — não consegue justificar a rate usada em cada settlement para
--     assessorias que contestam. O `clearing_settlements.fee_rate_pct` já
--     existia mas armazenava o rate AT BURN TIME, não emission time.
--   • Compliance — histórico de fees inconsistente em auditoria: um
--     `platform_fee_config.rate_pct` é `UPDATE`d (sem tabela de histórico)
--     e reescreve a verdade para todos os burns futuros.
--   • Assessorias emissoras — risco regulatório/contratual: a plataforma
--     pode unilateralmente elevar a taxa e afetar coins já em trânsito.
--
-- Solução (esta migration)
-- ────────────────────────
-- (1) Nova coluna `coin_ledger.clearing_fee_rate_pct_snapshot` (numeric(5,2),
--     nullable). Cada linha `institution_token_issue` escrita por
--     `emit_coins_atomic` passa a carregar uma CÓPIA IMUTÁVEL da rate
--     vigente no momento da emissão. Linhas não-emissão (burns, session
--     rewards, etc.) ficam NULL por design.
--
-- (2) Backfill one-shot: todas as emissões históricas recebem o valor
--     ATUAL de `platform_fee_config.clearing` como snapshot. É a melhor
--     aproximação possível sem tabela de histórico de rates e é
--     explicitamente documentada. Após este deploy qualquer mudança futura
--     de rate NÃO afeta retroativamente emissões pré-existentes.
--
-- (3) `emit_coins_atomic` recebe um SELECT do `platform_fee_config` antes
--     do INSERT no ledger e grava o snapshot na nova coluna. Toda a lógica
--     L02-01 + L19-01 + L05-03 anterior preservada.
--
-- (4) `execute_burn_atomic` deixa de consultar `platform_fee_config` e
--     passa a computar um WEIGHTED AVERAGE por `issuer_group_id` sobre as
--     linhas `institution_token_issue` do atleta para aquele issuer.
--     Fórmula:
--
--       fee_rate = ROUND(
--         SUM(delta_coins * clearing_fee_rate_pct_snapshot)
--         / NULLIF(SUM(delta_coins), 0),
--         2
--       )
--
--     Se TODAS as linhas do issuer têm o MESMO snapshot (cenário normal:
--     rate não mudou), o resultado bate exatamente com o snapshot. Se o
--     admin alterou a rate entre duas emissões do mesmo issuer, o
--     resultado é uma MÉDIA PONDERADA pelo volume emitido a cada rate —
--     defensavelmente "aproximadamente FIFO" sem precisar tracking
--     per-coin. Fallback para `platform_fee_config.rate_pct` continua
--     ativo caso todas as linhas do issuer sejam pré-migration (snapshot
--     NULL) — cenário que só acontece em ambientes onde esta migration
--     rodou mas o backfill da seção (2) foi pulado.
--
-- (5) Nova coluna `clearing_settlements.fee_rate_source` (text CHECK)
--     distingue:
--       • 'snapshot_weighted_avg' (caminho normal pós-L03-02)
--       • 'live_config_fallback'   (todas as linhas do issuer são
--          pré-migration OR a tabela está vazia — defensivo)
--     CFO filtra por essa coluna no dashboard de reconciliação para ver
--     qual fração das settlements está na trilha "frozen" versus "legacy
--     live" — a fração `live_config_fallback` deve convergir a 0% após
--     ciclo de archive/rotation do ledger.
--
-- (6) Helper read-only `fn_compute_clearing_fee_rate_for_issuer(user, issuer)`
--     expõe a mesma fórmula (4) para tooling de CFO/QA/testes, retornando
--     `(rate_pct, source, sample_count, total_coins_emitted)`. Útil para
--     estimar o fee ANTES do burn, debug de disputas e o contract test.
--
-- Compatibilidade
-- ───────────────
-- • Schema additive: nova coluna nullable + CHECK que aceita os dois
--   valores. Nenhum código lendo `coin_ledger` precisa mudar.
-- • Assinatura de `emit_coins_atomic` / `execute_burn_atomic` inalterada —
--   apenas o corpo muda.
-- • GUC `app.wallet_mutation_authorized` continua sendo setado pelo
--   `execute_burn_atomic` antes do UPDATE de wallets (L18 hardening).
-- • `#variable_conflict use_variable` para evitar conflitos de nome
--   (aprendizado do hotfix L03-13 20260421150000).
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema: coin_ledger.clearing_fee_rate_pct_snapshot
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.coin_ledger
  ADD COLUMN IF NOT EXISTS clearing_fee_rate_pct_snapshot numeric(5,2)
  CHECK (
    clearing_fee_rate_pct_snapshot IS NULL
    OR (clearing_fee_rate_pct_snapshot >= 0
        AND clearing_fee_rate_pct_snapshot <= 100)
  );

COMMENT ON COLUMN public.coin_ledger.clearing_fee_rate_pct_snapshot IS
  'L03-02: snapshot imutável de platform_fee_config.rate_pct (fee_type=clearing) '
  'capturado em emit_coins_atomic no momento exato da emissão. '
  'NOT NULL apenas para linhas com reason=institution_token_issue escritas '
  'pós-deploy L03-02 — emissões anteriores são backfilled com a rate ativa '
  'em 2026-04-21 (melhor aproximação sem histórico de rates). '
  'Linhas de outros reasons (burn, rewards, etc.) ficam NULL por design. '
  'execute_burn_atomic usa WEIGHTED AVERAGE dessa coluna por (user, issuer) '
  'para computar clearing_settlements.fee_rate_pct — congelando a taxa que '
  'a assessoria emissora paga no momento em que ela emitiu. Nunca UPDATE '
  'esta coluna; para corrigir histórico use uma linha de ajuste separada '
  '(reason=admin_adjustment) para deixar a trilha de auditoria intacta.';

-- Index parcial em emissões para acelerar o weighted-avg per-issuer.
-- Só indexa linhas relevantes → barato e mantém os índices existentes
-- (idx_ledger_user, idx_ledger_issuer, idx_ledger_reason) intactos.
CREATE INDEX IF NOT EXISTS idx_ledger_issue_snapshot
  ON public.coin_ledger (user_id, issuer_group_id)
  INCLUDE (delta_coins, clearing_fee_rate_pct_snapshot)
  WHERE reason = 'institution_token_issue'
    AND issuer_group_id IS NOT NULL;

COMMENT ON INDEX public.idx_ledger_issue_snapshot IS
  'L03-02: index de cobertura (INCLUDE) para fn_compute_clearing_fee_rate_for_issuer '
  'e para o bloco de weighted-avg dentro de execute_burn_atomic. '
  'Partial WHERE reason=institution_token_issue mantém o índice pequeno.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Backfill de emissões históricas (one-shot)
-- ─────────────────────────────────────────────────────────────────────────────

DO $backfill$
DECLARE
  v_current_rate numeric(5,2);
  v_updated      bigint;
BEGIN
  SELECT COALESCE(pfc.rate_pct, 3.00)
    INTO v_current_rate
    FROM public.platform_fee_config pfc
   WHERE pfc.fee_type = 'clearing'
     AND pfc.is_active = true
   LIMIT 1;

  v_current_rate := COALESCE(v_current_rate, 3.00);

  UPDATE public.coin_ledger
     SET clearing_fee_rate_pct_snapshot = v_current_rate
   WHERE reason = 'institution_token_issue'
     AND clearing_fee_rate_pct_snapshot IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  RAISE NOTICE 'L03-02 backfill: % emission rows updated with snapshot %',
    v_updated, v_current_rate;
END
$backfill$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Schema: clearing_settlements.fee_rate_source
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.clearing_settlements
  ADD COLUMN IF NOT EXISTS fee_rate_source text NOT NULL
  DEFAULT 'snapshot_weighted_avg';

DO $add_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.clearing_settlements'::regclass
       AND conname  = 'clearing_settlements_fee_rate_source_check'
  ) THEN
    ALTER TABLE public.clearing_settlements
      ADD CONSTRAINT clearing_settlements_fee_rate_source_check
      CHECK (fee_rate_source IN (
        'snapshot_weighted_avg',
        'live_config_fallback'
      ));
  END IF;
END
$add_check$;

COMMENT ON COLUMN public.clearing_settlements.fee_rate_source IS
  'L03-02: origem do fee_rate_pct desta settlement. '
  '"snapshot_weighted_avg" = média ponderada dos '
  'coin_ledger.clearing_fee_rate_pct_snapshot do issuer (caminho normal). '
  '"live_config_fallback" = todas as linhas de emissão daquele issuer '
  'tinham snapshot NULL, então caímos em platform_fee_config.rate_pct '
  'at burn time (caminho defensivo, deve convergir a 0% após archive '
  'do ledger). CFO usa esta coluna no dashboard de reconciliação.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Helper: fn_compute_clearing_fee_rate_for_issuer
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_compute_clearing_fee_rate_for_issuer(
  p_user_id         uuid,
  p_issuer_group_id uuid
)
RETURNS TABLE (
  rate_pct              numeric(5,2),
  source                text,
  sample_count          integer,
  total_coins_emitted   integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_variable
DECLARE
  v_wavg           numeric(10,4);
  v_sum_coins      bigint;
  v_sample         integer;
  v_non_null_rows  integer;
  v_fallback       numeric(5,2);
BEGIN
  SELECT
    SUM(cl.delta_coins * cl.clearing_fee_rate_pct_snapshot)::numeric(18,4)
      / NULLIF(SUM(cl.delta_coins) FILTER (
          WHERE cl.clearing_fee_rate_pct_snapshot IS NOT NULL
        ), 0),
    SUM(cl.delta_coins)::bigint,
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE cl.clearing_fee_rate_pct_snapshot IS NOT NULL)::integer
  INTO v_wavg, v_sum_coins, v_sample, v_non_null_rows
  FROM public.coin_ledger cl
  WHERE cl.user_id = p_user_id
    AND cl.issuer_group_id = p_issuer_group_id
    AND cl.reason = 'institution_token_issue';

  IF v_sample IS NULL OR v_sample = 0 OR v_non_null_rows = 0 THEN
    SELECT COALESCE(pfc.rate_pct, 3.00)
      INTO v_fallback
      FROM public.platform_fee_config pfc
     WHERE pfc.fee_type = 'clearing'
       AND pfc.is_active = true
     LIMIT 1;
    v_fallback := COALESCE(v_fallback, 3.00);

    rate_pct            := v_fallback;
    source              := 'live_config_fallback';
    sample_count        := COALESCE(v_sample, 0);
    total_coins_emitted := COALESCE(v_sum_coins, 0)::integer;
    RETURN NEXT;
    RETURN;
  END IF;

  rate_pct            := ROUND(v_wavg, 2);
  source              := 'snapshot_weighted_avg';
  sample_count        := v_sample;
  total_coins_emitted := COALESCE(v_sum_coins, 0)::integer;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.fn_compute_clearing_fee_rate_for_issuer(uuid, uuid) IS
  'L03-02: retorna o rate_pct de clearing congelado para a dupla '
  '(athlete, issuer_group), computado como weighted average dos '
  'snapshots em coin_ledger.clearing_fee_rate_pct_snapshot. '
  'Retorna source=live_config_fallback quando não há snapshots '
  'disponíveis (caso degradado). Usado por execute_burn_atomic e por '
  'tooling de CFO que precisa estimar fee antes do burn. STABLE = '
  'mesmo resultado dentro da mesma transação.';

REVOKE ALL ON FUNCTION public.fn_compute_clearing_fee_rate_for_issuer(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_compute_clearing_fee_rate_for_issuer(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.fn_compute_clearing_fee_rate_for_issuer(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_compute_clearing_fee_rate_for_issuer(uuid, uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. emit_coins_atomic — snapshot da rate no INSERT
-- ─────────────────────────────────────────────────────────────────────────────

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
#variable_conflict use_variable
DECLARE
  v_ledger_id      uuid;
  v_existing_id    uuid;
  v_new_balance    integer;
  v_now_ms         bigint := (extract(epoch from now()) * 1000)::bigint;
  v_claimed        boolean;
  v_fee_snapshot   numeric(5,2);
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: amount must be > 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_ref_id IS NULL OR length(p_ref_id) = 0 THEN
    RAISE EXCEPTION 'MISSING_REF_ID: ref_id is required for idempotency' USING ERRCODE = 'P0001';
  END IF;

  -- L03-02: snapshot da rate de clearing ANTES de qualquer mutação.
  -- Lê a configuração ativa; se a tabela estiver vazia ou clearing desativado,
  -- cai em 3.00 (default histórico). O snapshot fica imutável na linha do ledger.
  SELECT COALESCE(pfc.rate_pct, 3.00)
    INTO v_fee_snapshot
    FROM public.platform_fee_config pfc
   WHERE pfc.fee_type = 'clearing'
     AND pfc.is_active = true
   LIMIT 1;
  v_fee_snapshot := COALESCE(v_fee_snapshot, 3.00);

  v_ledger_id := gen_random_uuid();
  INSERT INTO public.coin_ledger_idempotency (ref_id, reason, ledger_id)
    VALUES (p_ref_id, 'institution_token_issue', v_ledger_id)
  ON CONFLICT (ref_id, reason) DO NOTHING;

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
    (id, user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms,
     clearing_fee_rate_pct_snapshot)
  VALUES
    (v_ledger_id, p_athlete_user_id, p_amount, 'institution_token_issue',
     p_ref_id, p_group_id, v_now_ms, v_fee_snapshot);

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
  'L02-01 + L19-01 + L05-03 + L03-02: emissão atômica de OmniCoins com '
  'idempotência via coin_ledger_idempotency. Retorna was_idempotent=true '
  'quando ref_id já foi processado. Erros: INVALID_AMOUNT, MISSING_REF_ID '
  '(P0001); CUSTODY_FAILED (P0002); INVENTORY_INSUFFICIENT (P0003). '
  'L03-02: captura clearing_fee_rate_pct_snapshot para congelar a taxa '
  'da assessoria emissora no momento da emissão.';

REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM anon;
REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. execute_burn_atomic — weighted-avg snapshot por issuer
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.execute_burn_atomic(
  p_user_id           uuid,
  p_redeemer_group_id uuid,
  p_amount            integer,
  p_ref_id            uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
#variable_conflict use_variable
DECLARE
  v_wallet_balance integer;
  v_breakdown      jsonb := '[]'::jsonb;
  v_issuer         uuid;
  v_issuer_balance integer;
  v_now_ms         bigint := (extract(epoch from now()) * 1000)::bigint;
  v_event_id       uuid;
  v_fee_rate       numeric(5,2);
  v_fee_source     text;
  v_gross          numeric(14,2);
  v_fee            numeric(14,2);
  v_net            numeric(14,2);
  v_settlement_id  uuid;
  v_has_custody    boolean;
  v_sqlstate       text;
  v_sqlerrm        text;
  v_rate_row       record;
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  -- 1. Lock wallet and verify balance
  SELECT w.balance_coins INTO v_wallet_balance
  FROM public.wallets w
  WHERE w.user_id = p_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL OR v_wallet_balance < p_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE: balance=%, requested=%',
      COALESCE(v_wallet_balance, 0), p_amount;
  END IF;

  -- 2. Compute burn plan and insert per-issuer ledger entries
  FOR v_issuer, v_issuer_balance IN
    SELECT bp.issuer_group_id, bp.amount
    FROM public.compute_burn_plan(p_user_id, p_redeemer_group_id, p_amount) bp
  LOOP
    v_breakdown := v_breakdown || jsonb_build_object(
      'issuer_group_id', v_issuer,
      'amount', v_issuer_balance
    );

    INSERT INTO public.coin_ledger
      (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
    VALUES
      (p_user_id, -v_issuer_balance, 'institution_token_burn',
       p_ref_id, v_issuer, v_now_ms);
  END LOOP;

  -- 3. Debit wallet (total)
  UPDATE public.wallets w
     SET balance_coins = w.balance_coins - p_amount
   WHERE w.user_id = p_user_id;

  -- 4. Create clearing event
  INSERT INTO public.clearing_events
    (burn_ref_id, athlete_user_id, redeemer_group_id, total_coins, breakdown)
  VALUES
    (p_ref_id, p_user_id, p_redeemer_group_id, p_amount, v_breakdown)
  RETURNING id INTO v_event_id;

  -- 5. Per-issuer custody + settlement.
  -- L03-02: fee_rate é computada per-issuer a partir do SNAPSHOT congelado
  -- em coin_ledger.clearing_fee_rate_pct_snapshot (caminho normal). Fallback
  -- para platform_fee_config.rate_pct (caminho legacy) quando não há snapshot.
  FOR v_issuer, v_issuer_balance IN
    SELECT
      (entry->>'issuer_group_id')::uuid,
      (entry->>'amount')::integer
    FROM jsonb_array_elements(v_breakdown) AS entry
    WHERE entry->>'issuer_group_id' IS NOT NULL
  LOOP
    IF v_issuer = p_redeemer_group_id THEN
      -- Intra-club: no fee, no settlement row.
      SELECT EXISTS(
        SELECT 1 FROM public.custody_accounts ca WHERE ca.group_id = v_issuer
      ) INTO v_has_custody;

      IF v_has_custody THEN
        BEGIN
          PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
        EXCEPTION
          WHEN undefined_function THEN
            INSERT INTO public.clearing_failure_log
              (failure_type, burn_ref_id, clearing_event_id,
               issuer_group_id, amount, sqlstate, sqlerrm, context)
            VALUES
              ('custody_release', p_ref_id, v_event_id,
               v_issuer, v_issuer_balance, 'P0004',
               'custody_release_committed RPC not deployed',
               jsonb_build_object('note', 'undefined_function — pre-deploy environment'));
          WHEN OTHERS THEN
            v_sqlstate := SQLSTATE;
            v_sqlerrm  := SQLERRM;
            RAISE EXCEPTION
              'CUSTODY_RELEASE_FAILED: group=% amount=% sqlstate=% err=%',
              v_issuer, v_issuer_balance, v_sqlstate, v_sqlerrm
              USING ERRCODE = 'P0005';
        END;
      END IF;
    ELSE
      -- Interclub: compute frozen rate from ledger snapshots
      SELECT * INTO v_rate_row
      FROM public.fn_compute_clearing_fee_rate_for_issuer(p_user_id, v_issuer);

      v_fee_rate   := v_rate_row.rate_pct;
      v_fee_source := v_rate_row.source;

      v_gross := v_issuer_balance::numeric;
      v_fee   := ROUND(v_gross * v_fee_rate / 100, 2);
      v_net   := v_gross - v_fee;

      INSERT INTO public.clearing_settlements
        (clearing_event_id, creditor_group_id, debtor_group_id,
         coin_amount, gross_amount_usd, fee_rate_pct, fee_rate_source,
         fee_amount_usd, net_amount_usd, status)
      VALUES
        (v_event_id, p_redeemer_group_id, v_issuer,
         v_issuer_balance, v_gross, v_fee_rate, v_fee_source,
         v_fee, v_net, 'pending')
      RETURNING id INTO v_settlement_id;

      BEGIN
        PERFORM public.settle_clearing(v_settlement_id);
      EXCEPTION WHEN OTHERS THEN
        v_sqlstate := SQLSTATE;
        v_sqlerrm  := SQLERRM;
        INSERT INTO public.clearing_failure_log
          (failure_type, burn_ref_id, clearing_event_id, settlement_id,
           issuer_group_id, amount, sqlstate, sqlerrm, context)
        VALUES
          ('settle_clearing', p_ref_id, v_event_id, v_settlement_id,
           v_issuer, v_issuer_balance, v_sqlstate, v_sqlerrm,
           jsonb_build_object(
             'creditor_group_id', p_redeemer_group_id,
             'debtor_group_id',   v_issuer,
             'gross',             v_gross,
             'fee',               v_fee,
             'fee_rate_pct',      v_fee_rate,
             'fee_rate_source',   v_fee_source,
             'net',               v_net
           ));
        RAISE NOTICE 'settle_clearing failed (logged): settlement=% sqlstate=% err=%',
          v_settlement_id, v_sqlstate, v_sqlerrm;
      END;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'event_id',     v_event_id,
    'breakdown',    v_breakdown,
    'total_burned', p_amount
  );
END;
$$;

COMMENT ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) IS
  'L02-02 + L18-01 + L03-02: burn atômico por issuer. L03-02: fee_rate de '
  'clearing_settlements é WEIGHTED AVERAGE dos clearing_fee_rate_pct_snapshot '
  'das emissões (user, issuer), congelando a taxa que a assessoria emissora '
  'paga no momento em que ela emitiu. fee_rate_source distingue caminho '
  'normal (snapshot_weighted_avg) do defensivo (live_config_fallback). '
  'Erros: INSUFFICIENT_BALANCE, CUSTODY_RELEASE_FAILED (P0005). '
  'Preserva GUC app.wallet_mutation_authorized=yes (L18 guard).';

REVOKE ALL ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Self-test com rollback sentinela (não contamina o schema)
-- ─────────────────────────────────────────────────────────────────────────────

DO $self_test$
DECLARE
  v_admin      uuid;
  v_athlete    uuid;
  v_issuer_a   uuid;
  v_redeemer   uuid;
  v_fresh_rate numeric(5,2);
  v_rate       numeric(5,2);
  v_source     text;
  v_count      integer;
  v_now_ms     bigint := (extract(epoch from now()) * 1000)::bigint;
BEGIN
  -- (a) função registrada com a assinatura esperada
  PERFORM 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'fn_compute_clearing_fee_rate_for_issuer'
     AND pg_get_function_arguments(p.oid) = 'p_user_id uuid, p_issuer_group_id uuid';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L03-02 self-test: fn_compute_clearing_fee_rate_for_issuer not registered';
  END IF;

  -- (b) coluna snapshot existe
  PERFORM 1
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'coin_ledger'
     AND column_name = 'clearing_fee_rate_pct_snapshot';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L03-02 self-test: coin_ledger.clearing_fee_rate_pct_snapshot missing';
  END IF;

  -- (c) coluna fee_rate_source existe
  PERFORM 1
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'clearing_settlements'
     AND column_name = 'fee_rate_source';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L03-02 self-test: clearing_settlements.fee_rate_source missing';
  END IF;

  -- (d) helper devolve live_config_fallback quando não há emissão
  v_athlete  := gen_random_uuid();
  v_issuer_a := gen_random_uuid();
  SELECT rate_pct, source, sample_count
    INTO v_rate, v_source, v_count
    FROM public.fn_compute_clearing_fee_rate_for_issuer(v_athlete, v_issuer_a);

  IF v_source <> 'live_config_fallback' THEN
    RAISE EXCEPTION
      'L03-02 self-test (d): expected live_config_fallback with no emissions, got source=%',
      v_source;
  END IF;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'L03-02 self-test (d): expected sample_count=0, got %', v_count;
  END IF;

  RAISE NOTICE 'L03-02 self-test passed: function registered, columns present, fallback path OK';
END
$self_test$;

COMMIT;
