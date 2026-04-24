-- L01-42 — platform_fee_config RLS hardening
--
-- Antes: SELECT USING (true) → qualquer authenticated lia rate_pct
-- de TODAS as taxas (clearing/swap/maintenance), o que vaza
-- estratégia comercial caso a empresa adote pricing diferenciado.
--
-- Depois: SELECT permitido apenas para platform_admin OU para a
-- taxa específica que afeta o usuário (clearing/swap aplicáveis a
-- todos os autenticados; maintenance fica admin-only).
--
-- OmniCoin policy: zero writes a coin_ledger ou wallets.
-- L04-07-OK

BEGIN;

DROP POLICY IF EXISTS "platform_fee_config_read" ON public.platform_fee_config;

CREATE POLICY "platform_fee_config_read_self_facing"
  ON public.platform_fee_config
  FOR SELECT
  USING (
    is_active
    AND fee_type IN ('clearing', 'swap')
  );

CREATE POLICY "platform_fee_config_read_admin"
  ON public.platform_fee_config
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

COMMENT ON POLICY "platform_fee_config_read_self_facing"
  ON public.platform_fee_config IS
  'L01-42: athletes/coaches need clearing+swap rates to display in UI; '
  'maintenance rate is internal-only and gated by admin policy.';

COMMENT ON POLICY "platform_fee_config_read_admin"
  ON public.platform_fee_config IS
  'L01-42: platform admins read everything (including maintenance) and '
  'write via the existing admin_write policy.';

DO $self$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'platform_fee_config'
      AND policyname = 'platform_fee_config_read_self_facing'
  ) THEN
    RAISE EXCEPTION 'L01-42 self-test: read_self_facing policy missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'platform_fee_config'
      AND policyname = 'platform_fee_config_read_admin'
  ) THEN
    RAISE EXCEPTION 'L01-42 self-test: read_admin policy missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'platform_fee_config'
      AND policyname = 'platform_fee_config_read'
  ) THEN
    RAISE EXCEPTION 'L01-42 self-test: legacy USING(true) policy still present';
  END IF;
  RAISE NOTICE 'L01-42 self-test PASSED';
END;
$self$;

COMMIT;
