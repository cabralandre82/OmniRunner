-- L03-08 — check_custody_invariants: add global conservation check
--
-- Antes: 2 checks (basic + R_i = M_i por emissor).
-- Faltava: invariante global de USD em depósito,
--   SUM(custody_accounts.total_deposited_usd)
--     = SUM(confirmed deposits) - SUM(completed withdrawals) - SUM(platform_revenue)
-- sem isso, drift acumulativo passa despercebido por meses.
--
-- Depois: terceira UNION com 'global_deposit_mismatch' quando houver
-- divergência entre o saldo agregado e o histórico de depósitos vs.
-- saídas. Tolerância: 0.01 USD (1 centavo) para ruído de arredondamento.
--
-- OmniCoin policy: nenhuma escrita; SQL puro de leitura.
-- L04-07-OK

BEGIN;

CREATE OR REPLACE FUNCTION public.check_custody_invariants()
  RETURNS TABLE(
    group_id            uuid,
    total_deposited     numeric,
    total_committed     numeric,
    computed_available  numeric,
    violation           text
  )
  LANGUAGE sql STABLE
AS $$
  -- Check 1: basic accounting invariants per group
  SELECT
    ca.group_id,
    ca.total_deposited_usd,
    ca.total_committed,
    ca.total_deposited_usd - ca.total_committed,
    CASE
      WHEN ca.total_committed     < 0                        THEN 'committed_negative'
      WHEN ca.total_deposited_usd < 0                        THEN 'deposited_negative'
      WHEN ca.total_deposited_usd < ca.total_committed       THEN 'deposited_less_than_committed'
    END
  FROM public.custody_accounts ca
  WHERE ca.total_committed     < 0
     OR ca.total_deposited_usd < 0
     OR ca.total_deposited_usd < ca.total_committed

  UNION ALL

  -- Check 2: R_i = M_i (reserved == coins alive per issuer)
  SELECT
    COALESCE(ca.group_id, cl_agg.issuer_group_id),
    ca.total_deposited_usd,
    ca.total_committed,
    COALESCE(cl_agg.coins_alive, 0),
    format('committed_mismatch: reserved=%s coins_alive=%s diff=%s',
           COALESCE(ca.total_committed, 0),
           COALESCE(cl_agg.coins_alive, 0),
           COALESCE(ca.total_committed, 0) - COALESCE(cl_agg.coins_alive, 0))
  FROM (
    SELECT issuer_group_id, SUM(delta_coins)::numeric AS coins_alive
    FROM public.coin_ledger
    WHERE issuer_group_id IS NOT NULL
    GROUP BY issuer_group_id
    HAVING SUM(delta_coins) <> 0
  ) cl_agg
  FULL OUTER JOIN public.custody_accounts ca
    ON ca.group_id = cl_agg.issuer_group_id
  WHERE COALESCE(ca.total_committed, 0) <> COALESCE(cl_agg.coins_alive, 0)

  UNION ALL

  -- Check 3 (L03-08): global USD conservation
  --   SUM(custody_accounts.total_deposited_usd)
  --     = SUM(confirmed deposits)
  --     - SUM(completed withdrawals)
  --     - SUM(platform_revenue)   -- revenue is funded from depositor balances
  -- Tolerância: 0.01 USD (1 centavo) — ruído de ROUND no settlement.
  SELECT
    NULL::uuid,
    (SELECT COALESCE(SUM(total_deposited_usd), 0) FROM public.custody_accounts),
    NULL::numeric,
    (SELECT COALESCE(SUM(amount_usd), 0)
       FROM public.custody_deposits
      WHERE status = 'confirmed')
    - (SELECT COALESCE(SUM(amount_usd), 0)
         FROM public.custody_withdrawals
        WHERE status = 'completed')
    - (SELECT COALESCE(SUM(amount_usd), 0)
         FROM public.platform_revenue),
    'global_deposit_mismatch: '
    || format('aggregated=%s expected=%s diff=%s',
              (SELECT COALESCE(SUM(total_deposited_usd), 0)
                 FROM public.custody_accounts),
              (SELECT COALESCE(SUM(amount_usd), 0)
                 FROM public.custody_deposits
                WHERE status = 'confirmed')
              - (SELECT COALESCE(SUM(amount_usd), 0)
                   FROM public.custody_withdrawals
                  WHERE status = 'completed')
              - (SELECT COALESCE(SUM(amount_usd), 0)
                   FROM public.platform_revenue),
              (SELECT COALESCE(SUM(total_deposited_usd), 0)
                 FROM public.custody_accounts)
              - ((SELECT COALESCE(SUM(amount_usd), 0)
                    FROM public.custody_deposits
                   WHERE status = 'confirmed')
                 - (SELECT COALESCE(SUM(amount_usd), 0)
                      FROM public.custody_withdrawals
                     WHERE status = 'completed')
                 - (SELECT COALESCE(SUM(amount_usd), 0)
                      FROM public.platform_revenue)))
  WHERE abs(
    (SELECT COALESCE(SUM(total_deposited_usd), 0) FROM public.custody_accounts)
    - ((SELECT COALESCE(SUM(amount_usd), 0)
          FROM public.custody_deposits WHERE status = 'confirmed')
       - (SELECT COALESCE(SUM(amount_usd), 0)
            FROM public.custody_withdrawals WHERE status = 'completed')
       - (SELECT COALESCE(SUM(amount_usd), 0)
            FROM public.platform_revenue))
  ) > 0.01;
$$;

COMMENT ON FUNCTION public.check_custody_invariants() IS
  'L03-08: 3 invariants now checked: (1) per-group accounting; '
  '(2) per-issuer reserved == coins-alive; (3) GLOBAL USD conservation. '
  'Tolerance for global check: 0.01 USD. Returning rows = violations.';

DO $self$
DECLARE
  v_check3_present boolean;
BEGIN
  SELECT pg_get_functiondef(p.oid) ILIKE '%global_deposit_mismatch%'
  INTO v_check3_present
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'check_custody_invariants';

  IF NOT COALESCE(v_check3_present, false) THEN
    RAISE EXCEPTION 'L03-08 self-test: check 3 (global_deposit_mismatch) not in function body';
  END IF;
  RAISE NOTICE 'L03-08 self-test PASSED';
END;
$self$;

COMMIT;
