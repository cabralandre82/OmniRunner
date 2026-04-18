-- ──────────────────────────────────────────────────────────────────────────
-- L02-02 — Correção: execute_burn_atomic engole exceções em
--           custody_release_committed e settle_clearing
--
-- Referência auditoria:
--   docs/audit/findings/L02-02-execute-burn-atomic-excecoes-engolidas-em-custody-release.md
--   docs/audit/parts/02-cto-cfo.md [2.2]
--
-- Histórico do achado:
--   - 20260228160001_burn_plan_atomic.sql: versão original com
--     `EXCEPTION WHEN OTHERS THEN NULL` (silent swallow) em ambos os blocos.
--   - 20260322300000_clearing_exception_logging.sql: substituiu NULL por
--     `RAISE NOTICE` — porém NOTICE é volátil (log Postgres apenas) e NÃO
--     corrige a invariante: custody_release_committed falhar silenciosamente
--     ainda quebra `R_i = M_i` (total_committed inflado após burn).
--
-- Problema remanescente:
--   (A) custody_release_committed: se falha (deadlock, check_custody_invariants
--       violation, connection_exception, etc), o atleta é debitado mas
--       `total_committed` não é decrementado. Invariante R vs M quebra
--       permanentemente — check_custody_invariants eventualmente flagueia e
--       bloqueia operações futuras.
--   (B) settle_clearing: se falha, NOTICE some do histórico após truncate do
--       log. Sem tabela queryable, observability não consegue alertar.
--       Também não há contador de tentativas para cron de retry.
--
-- Correção:
--   (1) Nova tabela `clearing_failure_log` — registro durável de exceções
--       engolidas, com SQLSTATE, SQLERRM, contexto JSONB, timestamps.
--       Índices para monitoring: por failure_type, por resolved, por data.
--   (2) execute_burn_atomic refatorada:
--       (A) custody_release_committed: catch específico em
--           `undefined_function` (safety net para ambientes pré-deploy da RPC).
--           Qualquer outro erro → RE-RAISE → rollback de todo o burn.
--           Justificativa: invariante R vs M é mais importante que
--           completar o burn. Se custody está inconsistente, bloqueie.
--       (B) settle_clearing: mantém best-effort (settlement row já foi
--           INSERTada com status='pending' → cron de netting retenta).
--           Porém loga a falha em clearing_failure_log com contexto
--           completo para observability + SLO tracking.
--   (3) View `clearing_failures_unresolved` para dashboards/alertas.
-- ──────────────────────────────────────────────────────────────────────────

-- 1. Tabela de log durável de falhas engolidas
CREATE TABLE IF NOT EXISTS public.clearing_failure_log (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  failure_type      text NOT NULL
    CHECK (failure_type IN ('custody_release', 'settle_clearing')),
  burn_ref_id       uuid,
  clearing_event_id uuid REFERENCES public.clearing_events(id) ON DELETE SET NULL,
  settlement_id     uuid REFERENCES public.clearing_settlements(id) ON DELETE SET NULL,
  issuer_group_id   uuid,
  amount            integer,
  sqlstate          text,
  sqlerrm           text,
  context           jsonb,
  resolved          boolean NOT NULL DEFAULT false,
  resolved_at       timestamptz,
  resolved_by       uuid,
  retry_count       integer NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.clearing_failure_log IS
  'L02-02: registro durável de exceções engolidas em execute_burn_atomic. '
  'failure_type=custody_release jamais deveria aparecer (qualquer falha em '
  'custody_release_committed agora aborta a transação). Entradas com '
  'failure_type=settle_clearing indicam settlements que caíram no cron de '
  'retry — se retry_count alto ou created_at antigo, investigar.';

CREATE INDEX IF NOT EXISTS idx_clearing_failure_log_type_resolved
  ON public.clearing_failure_log (failure_type, resolved, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_clearing_failure_log_settlement
  ON public.clearing_failure_log (settlement_id)
  WHERE settlement_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_clearing_failure_log_unresolved
  ON public.clearing_failure_log (created_at DESC)
  WHERE resolved = false;

-- RLS: apenas service_role acessa (sem policy → default deny para outros roles)
ALTER TABLE public.clearing_failure_log ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.clearing_failure_log TO service_role;


-- 2. View para dashboards/alertas
CREATE OR REPLACE VIEW public.clearing_failures_unresolved AS
SELECT
  failure_type,
  count(*)                                                          AS total,
  count(*) FILTER (WHERE created_at > now() - interval '1 hour')    AS last_1h,
  count(*) FILTER (WHERE created_at > now() - interval '24 hours')  AS last_24h,
  count(*) FILTER (WHERE retry_count >= 3)                          AS retry_exhausted,
  min(created_at)                                                   AS oldest,
  max(created_at)                                                   AS newest
FROM public.clearing_failure_log
WHERE resolved = false
GROUP BY failure_type;

COMMENT ON VIEW public.clearing_failures_unresolved IS
  'L02-02: dashboard-friendly view de falhas de clearing pendentes. '
  'SLO: zero entries em failure_type=custody_release. '
  'failure_type=settle_clearing com retry_count >= 3 requer intervenção manual.';

GRANT SELECT ON public.clearing_failures_unresolved TO service_role;


-- 3. execute_burn_atomic — versão hardenizada
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
AS $$
DECLARE
  v_wallet_balance integer;
  v_breakdown      jsonb := '[]'::jsonb;
  v_issuer         uuid;
  v_issuer_balance integer;
  v_now_ms         bigint := (extract(epoch from now()) * 1000)::bigint;
  v_event_id       uuid;
  v_fee_rate       numeric(5,2);
  v_gross          numeric(14,2);
  v_fee            numeric(14,2);
  v_net            numeric(14,2);
  v_settlement_id  uuid;
  v_has_custody    boolean;
  v_sqlstate       text;
  v_sqlerrm        text;
BEGIN
  -- 1. Lock wallet and verify balance
  SELECT balance_coins INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = p_user_id
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
  UPDATE public.wallets
  SET balance_coins = balance_coins - p_amount
  WHERE user_id = p_user_id;

  -- 4. Create clearing event
  INSERT INTO public.clearing_events
    (burn_ref_id, athlete_user_id, redeemer_group_id, total_coins, breakdown)
  VALUES
    (p_ref_id, p_user_id, p_redeemer_group_id, p_amount, v_breakdown)
  RETURNING id INTO v_event_id;

  -- 5. Get clearing fee rate
  SELECT rate_pct INTO v_fee_rate
  FROM public.platform_fee_config
  WHERE fee_type = 'clearing' AND is_active = true;
  v_fee_rate := COALESCE(v_fee_rate, 3.0);

  -- 6. Process each issuer in breakdown
  FOR v_issuer, v_issuer_balance IN
    SELECT
      (entry->>'issuer_group_id')::uuid,
      (entry->>'amount')::integer
    FROM jsonb_array_elements(v_breakdown) AS entry
    WHERE entry->>'issuer_group_id' IS NOT NULL
  LOOP
    IF v_issuer = p_redeemer_group_id THEN
      -- Intra-club: release committed (R -= b, A += b)
      SELECT EXISTS(
        SELECT 1 FROM public.custody_accounts WHERE group_id = v_issuer
      ) INTO v_has_custody;

      IF v_has_custody THEN
        -- ── L02-02 fix (A): custody_release_committed NUNCA engole erros.
        -- Apenas tolera RPC inexistente (ambiente pré-deploy).
        BEGIN
          PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
        EXCEPTION
          WHEN undefined_function THEN
            -- RPC não deployada; logamos e seguimos (invariante preservada
            -- porque custody_accounts ainda não tracka total_committed).
            INSERT INTO public.clearing_failure_log
              (failure_type, burn_ref_id, clearing_event_id,
               issuer_group_id, amount, sqlstate, sqlerrm, context)
            VALUES
              ('custody_release', p_ref_id, v_event_id,
               v_issuer, v_issuer_balance, 'P0004',
               'custody_release_committed RPC not deployed',
               jsonb_build_object('note', 'undefined_function — pre-deploy environment'));
          WHEN OTHERS THEN
            -- Deadlock, connection error, check_custody_invariants, OUT OF MEMORY…
            -- Re-raise: rollback completo do burn. Invariante R vs M preservada.
            v_sqlstate := SQLSTATE;
            v_sqlerrm  := SQLERRM;
            RAISE EXCEPTION
              'CUSTODY_RELEASE_FAILED: group=% amount=% sqlstate=% err=%',
              v_issuer, v_issuer_balance, v_sqlstate, v_sqlerrm
              USING ERRCODE = 'P0005';
        END;
      END IF;
    ELSE
      -- Interclub: create settlement
      v_gross := v_issuer_balance::numeric;
      v_fee := ROUND(v_gross * v_fee_rate / 100, 2);
      v_net := v_gross - v_fee;

      INSERT INTO public.clearing_settlements
        (clearing_event_id, creditor_group_id, debtor_group_id,
         coin_amount, gross_amount_usd, fee_rate_pct,
         fee_amount_usd, net_amount_usd, status)
      VALUES
        (v_event_id, p_redeemer_group_id, v_issuer,
         v_issuer_balance, v_gross, v_fee_rate,
         v_fee, v_net, 'pending')
      RETURNING id INTO v_settlement_id;

      -- ── L02-02 fix (B): settle_clearing mantém best-effort, porém loga
      -- durável em clearing_failure_log. Settlement row permanece 'pending'
      -- e cron de netting retenta.
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
             'net',               v_net
           ));
        RAISE NOTICE 'settle_clearing failed (logged to clearing_failure_log): settlement=% sqlstate=% err=%',
          v_settlement_id, v_sqlstate, v_sqlerrm;
      END;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'breakdown', v_breakdown,
    'total_burned', p_amount
  );
END;
$$;

COMMENT ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) IS
  'L02-02 hardenizado: custody_release_committed falhas re-raise (abortam burn); '
  'settle_clearing falhas logam em clearing_failure_log e seguem (settlement '
  'pending → cron de retry). Invariante R vs M preservada em todo cenário. '
  'Erros: CUSTODY_RELEASE_FAILED (P0005).';

GRANT EXECUTE ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) TO service_role;
