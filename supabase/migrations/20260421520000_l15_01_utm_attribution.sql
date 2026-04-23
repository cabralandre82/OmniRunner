-- L15-01 — Marketing attribution (UTM) capture pipeline.
--
-- Today the product has zero attribution signal: `grep utm_source`
-- across portal + omni_runner returns zero matches, which means
-- every campaign spend is unattributable and CAC is unknowable.
--
-- This migration introduces two primitives:
--
--   1. `public.marketing_attribution_events` — append-only log of
--      every UTM-bearing visit / signup / first-touch event.
--      Capture happens client-side (cookie) and is written
--      server-side by a dedicated API route so we never let the
--      browser write to user rows.
--
--   2. `public.profiles.attribution jsonb` — first-touch snapshot
--      (source / medium / campaign / term / content / landing /
--      referrer / first_seen_at). Set only once by a trigger.
--
-- Retention: events are raw data with PII (IP truncated /24 or
-- /48, UA hashed). We keep 180 days by default and rely on
-- `audit_logs_retention` policy to enforce it.
--
-- LGPD: no first/last name, no precise geo, no email in this
-- table. IP is stored truncated and UA is sha256'd — consent to
-- marketing cookies is captured separately at the app layer.

BEGIN;

-- ── 1. Events log ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.marketing_attribution_events (
  id             bigserial PRIMARY KEY,
  user_id        uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  anonymous_id   text,
  event_type     text NOT NULL CHECK (
                   event_type IN ('visit','signup','activation','conversion')
                 ),
  source         text,
  medium         text,
  campaign       text,
  term           text,
  content        text,
  referrer_host  text,
  landing_path   text,
  ip_prefix      text,
  user_agent_sha text,
  metadata       jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_attribution_has_identity CHECK (
    user_id IS NOT NULL OR anonymous_id IS NOT NULL
  ),
  CONSTRAINT chk_attribution_source_length CHECK (
    source IS NULL OR length(source) <= 128
  ),
  CONSTRAINT chk_attribution_campaign_length CHECK (
    campaign IS NULL OR length(campaign) <= 200
  ),
  CONSTRAINT chk_attribution_landing_length CHECK (
    landing_path IS NULL OR length(landing_path) <= 1024
  )
);

COMMENT ON TABLE public.marketing_attribution_events IS
  'L15-01 — append-only UTM capture log. ' ||
  'PII-minimized: IP truncated, UA hashed.';

CREATE INDEX IF NOT EXISTS idx_attribution_user
  ON public.marketing_attribution_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_attribution_campaign
  ON public.marketing_attribution_events(campaign, created_at DESC)
  WHERE campaign IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_attribution_event_type
  ON public.marketing_attribution_events(event_type, created_at DESC);

ALTER TABLE public.marketing_attribution_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS attribution_own_read
  ON public.marketing_attribution_events;
CREATE POLICY attribution_own_read
  ON public.marketing_attribution_events
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

GRANT SELECT ON public.marketing_attribution_events TO authenticated;
GRANT ALL ON public.marketing_attribution_events TO service_role;
GRANT USAGE ON SEQUENCE marketing_attribution_events_id_seq TO service_role;

-- ── 2. First-touch snapshot on profiles ────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS attribution jsonb;

COMMENT ON COLUMN public.profiles.attribution IS
  'L15-01 — first-touch attribution snapshot (source / medium / ' ||
  'campaign / term / content / landing / referrer / first_seen_at).';

CREATE OR REPLACE FUNCTION public.fn_attribution_first_touch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_snapshot jsonb;
BEGIN
  IF NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT attribution INTO v_snapshot
    FROM public.profiles
   WHERE id = NEW.user_id;

  IF v_snapshot IS NOT NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.profiles
     SET attribution = jsonb_build_object(
       'source',        NEW.source,
       'medium',        NEW.medium,
       'campaign',      NEW.campaign,
       'term',          NEW.term,
       'content',       NEW.content,
       'landing',       NEW.landing_path,
       'referrer',      NEW.referrer_host,
       'first_seen_at', NEW.created_at,
       'event_id',      NEW.id
     )
   WHERE id = NEW.user_id
     AND attribution IS NULL;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_attribution_first_touch
  ON public.marketing_attribution_events;
CREATE TRIGGER trg_attribution_first_touch
  AFTER INSERT ON public.marketing_attribution_events
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_attribution_first_touch();

-- ── 3. Register retention (180 days) ───────────────────────────────────────

INSERT INTO public.audit_logs_retention_config (
  schema_name, table_name, retention_days, enabled, batch_limit,
  timestamp_column, note
) VALUES (
  'public',
  'marketing_attribution_events',
  180,
  true,
  10000,
  'created_at',
  'L15-01 — UTM events are marketing telemetry with some PII; 6 months default.'
)
ON CONFLICT DO NOTHING;

-- ── 4. Self-test ───────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'attribution'
      AND data_type = 'jsonb'
  ) THEN
    RAISE EXCEPTION
      'L15-01 self-test: profiles.attribution column missing or wrong type';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_attribution_first_touch'
  ) THEN
    RAISE EXCEPTION 'L15-01 self-test: first-touch trigger missing';
  END IF;

  -- (a) CHECK enforces identity
  BEGIN
    INSERT INTO public.marketing_attribution_events (event_type)
      VALUES ('visit');
    RAISE EXCEPTION
      'L15-01 self-test: identity CHECK should have blocked identity-less row';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- (b) Too-long source rejected
  BEGIN
    INSERT INTO public.marketing_attribution_events (
      event_type, anonymous_id, source
    ) VALUES (
      'visit',
      'anon-self-test',
      repeat('x', 200)
    );
    RAISE EXCEPTION
      'L15-01 self-test: source length CHECK should have fired';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- Cleanup self-test rows
  DELETE FROM public.marketing_attribution_events
   WHERE anonymous_id = 'anon-self-test';

  RAISE NOTICE 'L15-01 self-test: OK';
END
$$;

COMMIT;
