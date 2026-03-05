-- Platform fee configuration table
-- Configurable by platform admin via portal /platform/fees

CREATE TABLE IF NOT EXISTS public.platform_fee_config (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fee_type    text NOT NULL CHECK (fee_type IN ('clearing', 'swap', 'maintenance')),
  rate_pct    numeric(5,2) NOT NULL DEFAULT 3.00 CHECK (rate_pct >= 0 AND rate_pct <= 100),
  is_active   boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES auth.users(id),
  UNIQUE(fee_type)
);

ALTER TABLE public.platform_fee_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform_fee_config_read" ON public.platform_fee_config;
CREATE POLICY "platform_fee_config_read" ON public.platform_fee_config
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "platform_fee_config_admin_write" ON public.platform_fee_config;
CREATE POLICY "platform_fee_config_admin_write" ON public.platform_fee_config
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- Seed default fee configuration
INSERT INTO public.platform_fee_config (fee_type, rate_pct, is_active) VALUES
  ('clearing',    3.00, true),
  ('swap',        1.00, true),
  ('maintenance', 0.00, true)
ON CONFLICT (fee_type) DO NOTHING;

GRANT ALL ON TABLE public.platform_fee_config TO authenticated;
GRANT ALL ON TABLE public.platform_fee_config TO service_role;
