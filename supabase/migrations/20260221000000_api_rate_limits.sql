-- Rate limiting table for Edge Functions (per-user, per-function, sliding window)
CREATE TABLE IF NOT EXISTS public.api_rate_limits (
  id         bigserial PRIMARY KEY,
  user_id    uuid        NOT NULL,
  fn         text        NOT NULL,
  window_start timestamptz NOT NULL,
  count      int         NOT NULL DEFAULT 0,
  UNIQUE (user_id, fn, window_start)
);

CREATE INDEX idx_api_rate_limits_user_fn
  ON public.api_rate_limits (user_id, fn);

-- Atomic increment-and-return RPC.
-- Aligns current time to a fixed window of p_window_seconds and upserts the counter.
-- Returns the new count for the current window.
CREATE OR REPLACE FUNCTION public.increment_rate_limit(
  p_user_id       uuid,
  p_fn            text,
  p_window_seconds int
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_window_start timestamptz;
  v_count        int;
BEGIN
  v_window_start := to_timestamp(
    floor(extract(epoch FROM now()) / p_window_seconds) * p_window_seconds
  );

  INSERT INTO public.api_rate_limits (user_id, fn, window_start, count)
  VALUES (p_user_id, p_fn, v_window_start, 1)
  ON CONFLICT (user_id, fn, window_start)
  DO UPDATE SET count = api_rate_limits.count + 1
  RETURNING count INTO v_count;

  RETURN v_count;
END;
$$;

-- Periodic cleanup: remove windows older than 1 hour (run via pg_cron or manual)
CREATE OR REPLACE FUNCTION public.cleanup_rate_limits()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  DELETE FROM public.api_rate_limits
  WHERE window_start < now() - interval '1 hour';
$$;
