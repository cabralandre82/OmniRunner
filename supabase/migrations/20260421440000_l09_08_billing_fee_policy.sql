-- ============================================================================
-- L09-08 — Billing fee policy (ADR-0001)
-- ============================================================================
--
-- Finding (docs/audit/findings/L09-08-provider-fee-usd-2-12-onus-ao-cliente.md):
--   Deposit path ambiguous: assessoria deposits US$1000, Stripe
--   bills US$38, we do not declare whether the buyer sees 962 or
--   1000 coins. Creates CDC Art. 6 III exposure and hurts unit
--   economics at scale.
--
-- Decision (ADR-0001, docs/adr/ADR-0001-provider-fee-ownership.md):
--   Pass-through by default. One row drives the math; per-group
--   override is a future ADR, not implemented here.
--
-- Scope of this migration:
--   (1) Singleton table `public.billing_fee_policy` (id=1 only)
--       carrying the boolean toggle + disclosure_template string.
--   (2) CHECK pinning id=1 so the table can never grow a second
--       row (every caller reads the single policy).
--   (3) RLS policy allowing authenticated users to SELECT (they
--       need to render disclosure at checkout) but no mutation.
--   (4) Helper fn_billing_fee_policy() STABLE SECURITY DEFINER
--       that reads the policy without RLS round-trip.
--   (5) Seed row with gateway_passthrough=true, effective now.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.billing_fee_policy (
  id                    smallint PRIMARY KEY CHECK (id = 1),
  gateway_passthrough   boolean NOT NULL DEFAULT true,
  disclosure_template   text NOT NULL DEFAULT
    'Sua operadora de pagamento (Stripe/Asaas) aplica uma taxa de processamento '
    'que será deduzida do valor creditado. O valor final em créditos será '
    'exibido no momento da confirmação.',
  effective_at          timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid REFERENCES auth.users(id),
  adr_reference         text NOT NULL DEFAULT 'ADR-0001',
  note                  text
);

COMMENT ON TABLE public.billing_fee_policy IS
  'L09-08 / ADR-0001: singleton policy driving gateway-fee ownership. '
  'See docs/adr/ADR-0001-provider-fee-ownership.md.';

COMMENT ON COLUMN public.billing_fee_policy.gateway_passthrough IS
  'true → buyer sees credits after fee deduction (pass-through). '
  'false → platform absorbs; buyer sees credits = deposited amount.';

COMMENT ON COLUMN public.billing_fee_policy.disclosure_template IS
  'Localised (pt-BR) paragraph that the checkout UI must render '
  'verbatim when gateway_passthrough=true. Portal + mobile read this '
  'string; never hardcode the copy in the client.';

ALTER TABLE public.billing_fee_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_fee_policy FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS billing_fee_policy_read
  ON public.billing_fee_policy;
CREATE POLICY billing_fee_policy_read
  ON public.billing_fee_policy
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS billing_fee_policy_service
  ON public.billing_fee_policy;
CREATE POLICY billing_fee_policy_service
  ON public.billing_fee_policy
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Seed row with the ADR-0001 default.
INSERT INTO public.billing_fee_policy (id, gateway_passthrough, note)
VALUES (1, true,
        'Seeded by 20260421440000_l09_08_billing_fee_policy.sql — see ADR-0001.')
ON CONFLICT (id) DO NOTHING;

-- Helper returning the policy row (no RLS trip, STABLE for caching).
CREATE OR REPLACE FUNCTION public.fn_billing_fee_policy()
RETURNS public.billing_fee_policy
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
  SELECT * FROM public.billing_fee_policy WHERE id = 1
$$;

COMMENT ON FUNCTION public.fn_billing_fee_policy() IS
  'L09-08: returns the singleton billing_fee_policy row.';

REVOKE ALL ON FUNCTION public.fn_billing_fee_policy() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_billing_fee_policy() TO authenticated, service_role;

-- Update trigger for audit trail / updated_at.
CREATE OR REPLACE FUNCTION public.fn_billing_fee_policy_touch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_billing_fee_policy_touch
  ON public.billing_fee_policy;
CREATE TRIGGER trg_billing_fee_policy_touch
  BEFORE UPDATE ON public.billing_fee_policy
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_billing_fee_policy_touch();

COMMIT;

-- ============================================================================
-- Self-test
-- ============================================================================
DO $L09_08_selftest$
DECLARE
  v_policy public.billing_fee_policy;
  v_violated boolean := false;
BEGIN
  -- (a) Seed row exists.
  SELECT * INTO v_policy FROM public.billing_fee_policy WHERE id = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L09-08 selftest: singleton row missing after seed';
  END IF;
  IF v_policy.gateway_passthrough IS NOT true THEN
    RAISE EXCEPTION 'L09-08 selftest: default gateway_passthrough must be true';
  END IF;
  IF v_policy.adr_reference <> 'ADR-0001' THEN
    RAISE EXCEPTION 'L09-08 selftest: adr_reference must be ADR-0001';
  END IF;
  IF v_policy.disclosure_template IS NULL
     OR length(v_policy.disclosure_template) < 40 THEN
    RAISE EXCEPTION 'L09-08 selftest: disclosure_template missing or too short';
  END IF;

  -- (b) Helper returns the same row.
  v_policy := public.fn_billing_fee_policy();
  IF v_policy.id IS NULL OR v_policy.id <> 1 THEN
    RAISE EXCEPTION 'L09-08 selftest: fn_billing_fee_policy returned wrong id';
  END IF;

  -- (c) CHECK prevents a second row.
  BEGIN
    INSERT INTO public.billing_fee_policy (id) VALUES (2);
    RAISE EXCEPTION 'L09-08 selftest: CHECK on id=1 should have rejected insert';
  EXCEPTION WHEN check_violation THEN
    v_violated := true;
  END;
  IF NOT v_violated THEN
    RAISE EXCEPTION 'L09-08 selftest: second-row insert was not blocked';
  END IF;

  -- (d) Touch trigger bumps updated_at.
  UPDATE public.billing_fee_policy
     SET note = 'selftest touch ' || now()::text
   WHERE id = 1;
  IF (SELECT updated_at FROM public.billing_fee_policy WHERE id = 1)
     <= v_policy.updated_at THEN
    RAISE EXCEPTION 'L09-08 selftest: updated_at did not advance';
  END IF;

  RAISE NOTICE '[L09-08.selftest] OK — billing_fee_policy singleton + helper + CHECK + touch';
END
$L09_08_selftest$;
