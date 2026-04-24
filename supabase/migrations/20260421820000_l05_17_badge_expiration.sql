-- L05-17 — badge_awards.valid_until (optional expiration)
--
-- Antes: badge_awards é imutável e permanente. "Atleta de bronze
-- 2024" continua para sempre, sem distinção de safra.
--
-- Depois:
--   • valid_until timestamptz NULL    — quando NULL, badge é permanente
--                                       (comportamento legado preservado)
--   • view active_badge_awards filtra automaticamente expirados
--   • índice parcial p/ leitura rápida
--
-- OmniCoin policy: zero writes a coin_ledger ou wallets.
-- L04-07-OK

BEGIN;

ALTER TABLE public.badge_awards
  ADD COLUMN IF NOT EXISTS valid_until timestamptz;

DO $cnstr$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'badge_awards_valid_until_after_unlock'
  ) THEN
    ALTER TABLE public.badge_awards
      ADD CONSTRAINT badge_awards_valid_until_after_unlock
      CHECK (
        valid_until IS NULL
          OR (extract(epoch FROM valid_until) * 1000)::bigint > unlocked_at_ms
      );
  END IF;
END;
$cnstr$;

CREATE INDEX IF NOT EXISTS idx_badge_awards_active
  ON public.badge_awards (user_id, unlocked_at_ms DESC)
  WHERE valid_until IS NULL OR valid_until > now();

CREATE OR REPLACE VIEW public.active_badge_awards AS
SELECT *
FROM public.badge_awards
WHERE valid_until IS NULL OR valid_until > now();

COMMENT ON COLUMN public.badge_awards.valid_until IS
  'L05-17: optional expiration timestamp. NULL = permanent (legacy). '
  'Annual/seasonal badges should set this to the end of the season.';

COMMENT ON VIEW public.active_badge_awards IS
  'L05-17: badge_awards filtered to only currently-valid entries.';

GRANT SELECT ON public.active_badge_awards TO authenticated;

DO $self$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='badge_awards'
      AND column_name='valid_until'
  ) THEN
    RAISE EXCEPTION 'L05-17 self-test: valid_until column missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema='public' AND table_name='active_badge_awards'
  ) THEN
    RAISE EXCEPTION 'L05-17 self-test: active_badge_awards view missing';
  END IF;

  RAISE NOTICE 'L05-17 self-test PASSED';
END;
$self$;

COMMIT;
