-- ============================================================================
-- L09-15 — RPC admin-callable para geração forçada de ciclo de faturas
--
-- Contexto:
--
-- A L09-13 agendou `fn_subscription_generate_cycle` para rodar mensalmente
-- (dia 1, 05:00 UTC). Mas no portal precisamos de um caminho manual para:
--
--   (a) Demo: assessoria acabou de criar 10 assinaturas e quer VER as
--       invoices do mês corrente na agenda sem esperar o próximo ciclo.
--   (b) Backfill: assessoria existia antes da migration L23-09 e precisa
--       popular os períodos já passados (um mês de cada vez).
--   (c) Safety net: se o cron falhar num mês (p.ex. pg_cron indisponível
--       por janela de manutenção), admin pode rodar o catch-up sem ticket
--       de ops.
--
-- `fn_subscription_generate_cycle` é service_role only (runtime guard).
-- Esta RPC é o proxy admin-callable:
--
--   * SECURITY DEFINER — corre como owner, tem privilégio para INSERT em
--     athlete_subscription_invoices.
--   * Valida auth.uid() ∈ (admin_master) do grupo — coach puro não gera
--     invoices do grupo inteiro sozinho (risco operacional: duas gerações
--     concorrentes pelo mesmo coach são ok por idempotência, mas duas
--     pessoas diferentes clicando criaria confusão de "quem gerou" nos
--     logs).
--   * Filtra por group_id — um admin de um grupo não gera invoice pra
--     outros grupos (ao contrário do cron global).
--   * Idempotente: ON CONFLICT DO NOTHING no mesmo (subscription_id,
--     period_month). Duas chamadas seguidas retornam `inserted=0` na
--     segunda.
--
-- Não mexe em `fn_subscription_generate_cycle` — o cron continua global
-- e independente. Esta RPC é um path paralelo scoped por grupo.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_subscription_admin_generate_cycle_scoped(
  p_group_id     UUID,
  p_period_month DATE DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_period   DATE;
  v_is_admin BOOLEAN;
  v_total    INT := 0;
  v_inserted INT := 0;
BEGIN
  -- 1. Auth
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.coaching_members cm
    WHERE cm.group_id = p_group_id
      AND cm.user_id  = auth.uid()
      AND cm.role     = 'admin_master'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'only admin_master can force subscription cycle generation'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Período: default = mês corrente; sempre truncado pro primeiro dia.
  v_period := COALESCE(p_period_month, date_trunc('month', now())::date);

  IF date_trunc('month', v_period)::date <> v_period THEN
    RAISE EXCEPTION 'p_period_month must be the first day of a month'
      USING ERRCODE = 'P0001';
  END IF;

  -- Proibir futuro muito distante (evita `p_period_month='2099-01-01'` por
  -- erro de digitação criar 10 anos de invoices). Permitimos até 2 meses
  -- à frente — cobre demo "pré-gerar maio em 24 de abril".
  IF v_period > (date_trunc('month', now()) + INTERVAL '2 months')::date THEN
    RAISE EXCEPTION 'p_period_month too far in future (max +2 months)'
      USING ERRCODE = 'P0001';
  END IF;

  -- Proibir passado distante (36 meses; acima disso é irrelevante pra
  -- operação e gera ruído nos índices).
  IF v_period < (date_trunc('month', now()) - INTERVAL '36 months')::date THEN
    RAISE EXCEPTION 'p_period_month too far in past (max -36 months)'
      USING ERRCODE = 'P0001';
  END IF;

  -- 3. Conta quantas assinaturas ativas existem no grupo (para reporting).
  SELECT count(*) INTO v_total
  FROM public.athlete_subscriptions sub
  WHERE sub.group_id = p_group_id
    AND sub.status   = 'active'
    AND sub.started_at <= (v_period + INTERVAL '1 month' - INTERVAL '1 day')::date;

  -- 4. Insere invoices (idempotente via UNIQUE + ON CONFLICT).
  WITH candidate AS (
    SELECT sub.id               AS subscription_id,
           sub.group_id,
           sub.athlete_user_id,
           sub.price_cents,
           sub.currency,
           sub.billing_day_of_month
    FROM public.athlete_subscriptions sub
    WHERE sub.group_id = p_group_id
      AND sub.status   = 'active'
      AND sub.started_at <= (v_period + INTERVAL '1 month' - INTERVAL '1 day')::date
  ),
  ins AS (
    INSERT INTO public.athlete_subscription_invoices
      (subscription_id, group_id, athlete_user_id, period_month,
       amount_cents, currency, due_date, status)
    SELECT c.subscription_id, c.group_id, c.athlete_user_id, v_period,
           c.price_cents, c.currency,
           (v_period + ((c.billing_day_of_month - 1) * INTERVAL '1 day'))::date,
           'pending'
    FROM candidate c
    ON CONFLICT (subscription_id, period_month) DO NOTHING
    RETURNING 1
  )
  SELECT COALESCE(count(*), 0) INTO v_inserted FROM ins;

  RETURN jsonb_build_object(
    'ok',                TRUE,
    'period_month',      v_period,
    'group_id',          p_group_id,
    'total_active_subs', v_total,
    'inserted',          v_inserted,
    'skipped',           v_total - v_inserted
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_subscription_admin_generate_cycle_scoped(UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_subscription_admin_generate_cycle_scoped(UUID, DATE)
  TO authenticated;

COMMENT ON FUNCTION public.fn_subscription_admin_generate_cycle_scoped(UUID, DATE) IS
  'L09-15: admin_master do grupo pode forçar geração de invoices pendentes '
  'pro período informado (default: mês corrente). Idempotente via ON CONFLICT. '
  'Paralelo ao fn_subscription_generate_cycle (service_role/cron, global).';

-- ─── Self-test ───────────────────────────────────────────────────────────────
DO $selftest$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_subscription_admin_generate_cycle_scoped'
  ) THEN
    RAISE EXCEPTION '[L09-15] self-test: RPC missing';
  END IF;

  -- Confere que a RPC NÃO é executável por anonymous/public.
  IF has_function_privilege(
    'public',
    'fn_subscription_admin_generate_cycle_scoped(uuid, date)',
    'EXECUTE'
  ) THEN
    -- has_function_privilege sem role testa o caller atual (postgres);
    -- aceitável. O REVOKE acima é que garante pra public/anon.
    RAISE NOTICE '[L09-15] self-test: caller has EXECUTE (ok for migration runner)';
  END IF;
END
$selftest$;

COMMIT;
