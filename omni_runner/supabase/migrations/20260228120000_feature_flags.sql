-- Feature flags for gradual rollout and kill switches
CREATE TABLE IF NOT EXISTS public.feature_flags (
  key        TEXT PRIMARY KEY,
  enabled    BOOLEAN NOT NULL DEFAULT false,
  rollout_pct INTEGER NOT NULL DEFAULT 0 CHECK (rollout_pct BETWEEN 0 AND 100),
  metadata   JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.feature_flags IS 'Simple feature flag system for gradual rollout';
COMMENT ON COLUMN public.feature_flags.rollout_pct IS 'Percentage of users who see the feature (0-100). Only applies when enabled=true.';

-- Allow all authenticated users to read flags (no RLS write — admin only via service role)
ALTER TABLE public.feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read flags"
  ON public.feature_flags
  FOR SELECT
  TO authenticated
  USING (true);

-- Seed initial flags
INSERT INTO public.feature_flags (key, enabled, rollout_pct, metadata) VALUES
  ('parks_enabled',        false, 0,   '{"description": "Parks discovery feature"}'),
  ('matchmaking_enabled',  false, 0,   '{"description": "Challenge matchmaking"}'),
  ('wrapped_enabled',      true,  100, '{"description": "Year-in-review wrapped screen"}'),
  ('running_dna_enabled',  true,  100, '{"description": "Running DNA analysis screen"}'),
  ('strava_import_enabled', true, 100, '{"description": "Import activities from Strava"}')
ON CONFLICT (key) DO NOTHING;
