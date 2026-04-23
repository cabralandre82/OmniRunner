-- ============================================================================
-- L16-02 — Custom domain per coaching_group
-- Date: 2026-04-21
-- ============================================================================
-- Finding: a large club wants `portal.corredoresmorumbi.com.br` routed to the
-- same portal instance that normally serves `portal.omnirunner.app`. Today
-- there is zero server-side primitive for this — we can't map Host → group
-- in middleware, we can't prove a club owns a domain before routing traffic
-- to them, and we have no audit trail if an operator swaps a domain.
--
-- This migration ships the canonical primitives. Vercel (or any CDN)
-- still owns certificate issuance; the schema only owns the mapping,
-- verification state, and actor audit trail.
--
--   1. `public.coaching_group_domains` — canonical host → group_id mapping.
--      - `host text` is normalised lower-case via a BEFORE INSERT/UPDATE
--        trigger, globally UNIQUE, validated by
--        `fn_validate_custom_host(text)` (public hostname, no protocol,
--        max 253 chars, RFC 1035 label regex, no underscores, forbids
--        `omnirunner.app` / `omnirunner.com.br` / `*.omnirunner.*` to
--        prevent accidental self-rebind).
--      - Verification state machine: `pending` → `verifying` → `verified`
--        | `failed` | `revoked`.
--      - `verification_token text` — random 32-hex string the operator
--        places in a DNS TXT record at `_omni-challenge.<host>` so we can
--        prove control before Vercel is asked to add the domain.
--      - `primary boolean` — per-group at most one row with
--        `primary = true AND status = 'verified'`. Enforced via partial
--        UNIQUE index.
--      - `issued_at / verified_at / failed_at / revoked_at / last_checked_at`
--        audit timestamps.
--   2. `fn_generate_custom_domain_token()` — IMMUTABLE-safe wrapper over
--      `gen_random_bytes(16)` returning a 32-hex string.
--   3. `fn_custom_domain_register(host, make_primary)` — admin-only RPC
--      that (a) validates the host, (b) ensures no other group owns the
--      same host, (c) inserts the row in `pending`, (d) returns the
--      challenge payload so the operator can configure DNS.
--   4. `fn_custom_domain_mark_verified(host)` — service_role target
--      (invoked by the verifier job once DNS TXT matches) that flips
--      the row to `verified` + stamps `verified_at`.
--   5. `fn_custom_domain_mark_failed(host, reason)` — same, for the
--      failure path; stamps `failed_at` and `last_error`.
--   6. `fn_custom_domain_revoke(host)` — admin-only; flips to `revoked`
--      and clears `primary`.
--   7. `fn_custom_domain_resolve(host)` — SECURITY DEFINER STABLE that
--      the Next.js middleware calls to map a Host header to a
--      `{group_id, branding_enabled}` payload (null when not
--      verified/primary). Granted to anon/authenticated/service_role so
--      edge middleware can hit it.
--
-- All writes go through SECURITY DEFINER RPCs; the table has RLS
-- admin-only SELECT. No PUBLIC access to the table directly. Audit rows
-- are emitted to `portal_audit_log` (fail-open) from each state transition
-- trigger.

BEGIN;

-- ── 0. Validation helper ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_validate_custom_host(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_len INT;
  v_lower TEXT;
BEGIN
  IF p_value IS NULL THEN
    RETURN FALSE;
  END IF;
  v_len := length(p_value);
  IF v_len < 4 OR v_len > 253 THEN
    RETURN FALSE;
  END IF;
  v_lower := lower(p_value);

  IF v_lower ~ '(^|[.])omnirunner[.]' THEN
    RETURN FALSE;
  END IF;

  IF v_lower ~ '^https?://' THEN
    RETURN FALSE;
  END IF;

  RETURN v_lower ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$';
END;
$$;

COMMENT ON FUNCTION public.fn_validate_custom_host(TEXT) IS
  'Returns true when input is a bare public hostname (RFC 1035 labels, no protocol, 4-253 chars) and is NOT inside the omnirunner.* apex. Used by coaching_group_domains CHECK and RPCs.';

GRANT EXECUTE ON FUNCTION public.fn_validate_custom_host(TEXT) TO PUBLIC;

-- ── 1. Token generator ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_generate_custom_domain_token()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  RETURN encode(gen_random_bytes(16), 'hex');
END;
$$;

COMMENT ON FUNCTION public.fn_generate_custom_domain_token() IS
  '32-hex random token used as the DNS TXT challenge value under _omni-challenge.<host>. Each custom domain row gets a distinct token.';

-- ── 2. Canonical table ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.coaching_group_domains (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id            UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  host                TEXT NOT NULL,
  status              TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','verifying','verified','failed','revoked')),
  is_primary          BOOLEAN NOT NULL DEFAULT FALSE,
  verification_token  TEXT NOT NULL DEFAULT public.fn_generate_custom_domain_token(),
  last_error          TEXT,
  issued_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  verified_at         TIMESTAMPTZ,
  failed_at           TIMESTAMPTZ,
  revoked_at          TIMESTAMPTZ,
  last_checked_at     TIMESTAMPTZ,
  created_by          UUID REFERENCES auth.users(id),
  CONSTRAINT coaching_group_domains_host_shape CHECK (public.fn_validate_custom_host(host)),
  CONSTRAINT coaching_group_domains_token_shape CHECK (verification_token ~ '^[0-9a-f]{32}$'),
  CONSTRAINT coaching_group_domains_last_error_len CHECK (last_error IS NULL OR length(last_error) <= 500),
  CONSTRAINT coaching_group_domains_status_stamps CHECK (
    (status = 'verified' AND verified_at IS NOT NULL) OR status <> 'verified'
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS coaching_group_domains_host_unique
  ON public.coaching_group_domains (host);

CREATE UNIQUE INDEX IF NOT EXISTS coaching_group_domains_one_primary_per_group
  ON public.coaching_group_domains (group_id)
  WHERE is_primary = TRUE AND status = 'verified';

CREATE INDEX IF NOT EXISTS coaching_group_domains_group_idx
  ON public.coaching_group_domains (group_id);

CREATE INDEX IF NOT EXISTS coaching_group_domains_status_idx
  ON public.coaching_group_domains (status)
  WHERE status IN ('pending','verifying');

COMMENT ON TABLE public.coaching_group_domains IS
  'L16-02: Host → coaching_group mapping. Populated via admin RPCs; resolved at edge middleware via fn_custom_domain_resolve.';

-- ── 3. RLS ───────────────────────────────────────────────────────────────

ALTER TABLE public.coaching_group_domains ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS coaching_group_domains_admin_read ON public.coaching_group_domains;
CREATE POLICY coaching_group_domains_admin_read ON public.coaching_group_domains
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_group_domains.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- No INSERT/UPDATE/DELETE policy — mutation goes through SECURITY DEFINER
-- RPCs only.

-- ── 4. Host normalisation + audit triggers ───────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_coaching_group_domains_normalize()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.host := lower(trim(NEW.host));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS coaching_group_domains_normalize ON public.coaching_group_domains;
CREATE TRIGGER coaching_group_domains_normalize
  BEFORE INSERT OR UPDATE OF host ON public.coaching_group_domains
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_coaching_group_domains_normalize();

CREATE OR REPLACE FUNCTION public.fn_coaching_group_domains_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  BEGIN
    IF to_regclass('public.portal_audit_log') IS NOT NULL THEN
      INSERT INTO public.portal_audit_log (
        actor_id,
        group_id,
        action,
        metadata,
        created_at
      ) VALUES (
        COALESCE(NEW.created_by, auth.uid()),
        NEW.group_id,
        CASE TG_OP
          WHEN 'INSERT' THEN 'group.custom_domain.registered'
          WHEN 'UPDATE' THEN 'group.custom_domain.' || COALESCE(NEW.status, 'updated')
        END,
        jsonb_build_object(
          'host', NEW.host,
          'status', NEW.status,
          'is_primary', NEW.is_primary,
          'last_error', NEW.last_error
        ),
        now()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'coaching_group_domains audit failed: %', SQLERRM;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS coaching_group_domains_audit_insert ON public.coaching_group_domains;
CREATE TRIGGER coaching_group_domains_audit_insert
  AFTER INSERT ON public.coaching_group_domains
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_coaching_group_domains_audit();

DROP TRIGGER IF EXISTS coaching_group_domains_audit_update ON public.coaching_group_domains
;
CREATE TRIGGER coaching_group_domains_audit_update
  AFTER UPDATE OF status, is_primary, last_error ON public.coaching_group_domains
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_coaching_group_domains_audit();

-- ── 5. RPCs ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_custom_domain_register(
  p_group_id UUID,
  p_host TEXT,
  p_make_primary BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_is_admin BOOLEAN := FALSE;
  v_host TEXT := lower(trim(p_host));
  v_row public.coaching_group_domains;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_GROUP' USING ERRCODE = 'P0001';
  END IF;
  IF NOT public.fn_validate_custom_host(v_host) THEN
    RAISE EXCEPTION 'INVALID_HOST' USING ERRCODE = 'P0001';
  END IF;

  IF current_setting('role', true) = 'service_role' THEN
    v_is_admin := TRUE;
  ELSIF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  ELSE
    SELECT TRUE INTO v_is_admin
    FROM public.profiles
    WHERE id = v_actor AND platform_role = 'admin';
    IF NOT v_is_admin THEN
      SELECT TRUE INTO v_is_admin
      FROM public.coaching_members
      WHERE group_id = p_group_id
        AND user_id = v_actor
        AND role = 'admin_master';
    END IF;
  END IF;

  IF NOT COALESCE(v_is_admin, FALSE) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.coaching_group_domains (
    group_id, host, status, is_primary, created_by
  ) VALUES (
    p_group_id, v_host, 'pending', COALESCE(p_make_primary, FALSE), v_actor
  )
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'host', v_row.host,
    'status', v_row.status,
    'verification_token', v_row.verification_token,
    'challenge_record', '_omni-challenge.' || v_row.host,
    'issued_at', v_row.issued_at
  );
END;
$$;

COMMENT ON FUNCTION public.fn_custom_domain_register(UUID, TEXT, BOOLEAN) IS
  'Admin-only RPC to register a host. Returns challenge payload so the operator can create the DNS TXT record.';

REVOKE ALL ON FUNCTION public.fn_custom_domain_register(UUID, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_custom_domain_register(UUID, TEXT, BOOLEAN) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_custom_domain_mark_verified(p_host TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.coaching_group_domains;
BEGIN
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_ONLY' USING ERRCODE = '42501';
  END IF;

  UPDATE public.coaching_group_domains
  SET status = 'verified',
      verified_at = now(),
      last_checked_at = now(),
      last_error = NULL
  WHERE host = lower(trim(p_host))
    AND status IN ('pending','verifying','failed')
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'DOMAIN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'host', v_row.host,
    'status', v_row.status,
    'verified_at', v_row.verified_at
  );
END;
$$;

COMMENT ON FUNCTION public.fn_custom_domain_mark_verified(TEXT) IS
  'Service-role-only RPC invoked by the DNS-verifier job after _omni-challenge TXT matches.';

REVOKE ALL ON FUNCTION public.fn_custom_domain_mark_verified(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_custom_domain_mark_verified(TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_custom_domain_mark_failed(
  p_host TEXT,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.coaching_group_domains;
BEGIN
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_ONLY' USING ERRCODE = '42501';
  END IF;

  UPDATE public.coaching_group_domains
  SET status = 'failed',
      failed_at = now(),
      last_checked_at = now(),
      last_error = LEFT(COALESCE(p_reason, ''), 500)
  WHERE host = lower(trim(p_host))
    AND status IN ('pending','verifying')
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'DOMAIN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'host', v_row.host,
    'status', v_row.status,
    'last_error', v_row.last_error
  );
END;
$$;

COMMENT ON FUNCTION public.fn_custom_domain_mark_failed(TEXT, TEXT) IS
  'Service-role-only RPC to flip a pending/verifying domain to failed with a reason blurb (≤500 chars).';

REVOKE ALL ON FUNCTION public.fn_custom_domain_mark_failed(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_custom_domain_mark_failed(TEXT, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_custom_domain_revoke(p_host TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_is_admin BOOLEAN := FALSE;
  v_row public.coaching_group_domains;
  v_host TEXT := lower(trim(p_host));
BEGIN
  SELECT * INTO v_row FROM public.coaching_group_domains WHERE host = v_host;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DOMAIN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF current_setting('role', true) = 'service_role' THEN
    v_is_admin := TRUE;
  ELSIF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  ELSE
    SELECT TRUE INTO v_is_admin
    FROM public.profiles
    WHERE id = v_actor AND platform_role = 'admin';
    IF NOT v_is_admin THEN
      SELECT TRUE INTO v_is_admin
      FROM public.coaching_members
      WHERE group_id = v_row.group_id
        AND user_id = v_actor
        AND role = 'admin_master';
    END IF;
  END IF;

  IF NOT COALESCE(v_is_admin, FALSE) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.coaching_group_domains
  SET status = 'revoked',
      revoked_at = now(),
      is_primary = FALSE
  WHERE host = v_host
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'host', v_row.host,
    'status', v_row.status,
    'revoked_at', v_row.revoked_at
  );
END;
$$;

COMMENT ON FUNCTION public.fn_custom_domain_revoke(TEXT) IS
  'Admin-only RPC to revoke a host (any current status). Clears is_primary and stamps revoked_at.';

REVOKE ALL ON FUNCTION public.fn_custom_domain_revoke(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_custom_domain_revoke(TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_custom_domain_resolve(p_host TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.coaching_group_domains;
  v_branding_enabled BOOLEAN;
BEGIN
  IF p_host IS NULL OR length(p_host) < 4 THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_row
  FROM public.coaching_group_domains
  WHERE host = lower(trim(p_host))
    AND status = 'verified';

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT branding_enabled INTO v_branding_enabled
  FROM public.portal_branding
  WHERE group_id = v_row.group_id;

  RETURN jsonb_build_object(
    'group_id', v_row.group_id,
    'host', v_row.host,
    'is_primary', v_row.is_primary,
    'branding_enabled', COALESCE(v_branding_enabled, FALSE)
  );
END;
$$;

COMMENT ON FUNCTION public.fn_custom_domain_resolve(TEXT) IS
  'Edge-middleware accessor: maps a verified Host header to a group. Returns NULL when host is not verified. Safe to call from anon context; the hostname is already public.';

REVOKE ALL ON FUNCTION public.fn_custom_domain_resolve(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_custom_domain_resolve(TEXT) TO anon, authenticated, service_role;

-- ── 6. Self-test ─────────────────────────────────────────────────────────

DO $self_test$
BEGIN
  IF NOT public.fn_validate_custom_host('portal.corredoresmorumbi.com.br') THEN
    RAISE EXCEPTION 'self-test: fn_validate_custom_host rejected valid hostname';
  END IF;
  IF public.fn_validate_custom_host('omnirunner.app') THEN
    RAISE EXCEPTION 'self-test: fn_validate_custom_host accepted omnirunner apex';
  END IF;
  IF public.fn_validate_custom_host('portal.omnirunner.com.br') THEN
    RAISE EXCEPTION 'self-test: fn_validate_custom_host accepted omnirunner subdomain';
  END IF;
  IF public.fn_validate_custom_host('https://foo.com') THEN
    RAISE EXCEPTION 'self-test: fn_validate_custom_host accepted URL-with-scheme';
  END IF;
  IF public.fn_validate_custom_host('bad_host.com') THEN
    RAISE EXCEPTION 'self-test: fn_validate_custom_host accepted underscore';
  END IF;
  IF public.fn_validate_custom_host('a.b') THEN
    RAISE EXCEPTION 'self-test: fn_validate_custom_host accepted short tld';
  END IF;

  IF length(public.fn_generate_custom_domain_token()) <> 32 THEN
    RAISE EXCEPTION 'self-test: token length must be 32 hex chars';
  END IF;
  IF public.fn_generate_custom_domain_token() !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'self-test: token must be hex';
  END IF;

  RAISE NOTICE 'L16-02 self-test OK';
END;
$self_test$;

COMMIT;
