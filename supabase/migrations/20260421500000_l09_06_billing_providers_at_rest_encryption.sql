-- L09-06 — Per-assessoria billing-provider credential storage
-- with at-rest encryption.
--
-- Today, the only Asaas credential lives in `ASAAS_API_KEY` env
-- var — a single platform-wide key. As we introduce per-
-- assessoria gateway credentials (Asaas sub-accounts, MP OAuth
-- tokens, Stripe Connect IDs, etc.) we need a storage primitive
-- that:
--
--   1. never has plaintext credentials at rest;
--   2. never lets a plain SELECT on the row expose the
--      credential, not even to platform_admins;
--   3. gates every decrypt call through a SECURITY DEFINER
--      helper that writes an access audit row.
--
-- The master key ("KEK") is expected to be loaded into the GUC
-- `app.settings.kms_key` by each edge-function invocation — the
-- edge function fetches it from Supabase Vault / AWS KMS at
-- warm-up and calls `set_config('app.settings.kms_key', key,
-- true)` once per transaction. If the GUC is missing,
-- fn_get_billing_provider_key raises KMS_UNAVAILABLE.
--
-- Rotation strategy (documented in
-- docs/runbooks/SECRET_ROTATION_RUNBOOK.md): the master key is
-- versioned; each encrypted blob stores the key_version, and
-- rotation is implemented as decrypt-with-old + encrypt-with-new
-- in a single service-role transaction.
--
-- Note: `pgcrypto` must be available. Supabase provisions it by
-- default on all projects.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- ── 1. billing_providers table ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.billing_providers (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id       uuid NOT NULL REFERENCES public.coaching_groups(id)
                   ON DELETE CASCADE,
  provider       text NOT NULL CHECK (
                   provider IN ('asaas','mercadopago','stripe')
                 ),
  api_key_enc    bytea,
  key_version    int NOT NULL DEFAULT 1
                   CHECK (key_version BETWEEN 1 AND 1000),
  last_rotated_at timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT billing_providers_unique UNIQUE (group_id, provider)
);

COMMENT ON TABLE public.billing_providers IS
  'L09-06 — per-assessoria gateway credentials. api_key_enc is ' ||
  'pgp_sym_encrypt(plain, current_setting(app.settings.kms_key)). ' ||
  'Never SELECT api_key_enc directly — use fn_get_billing_provider_key.';

COMMENT ON COLUMN public.billing_providers.api_key_enc IS
  'AT REST ENCRYPTION — pgp_sym_encrypt bytea. RLS denies all ' ||
  'non-service_role reads of this column.';

CREATE INDEX IF NOT EXISTS idx_billing_providers_group
  ON public.billing_providers(group_id, provider);

ALTER TABLE public.billing_providers ENABLE ROW LEVEL SECURITY;

-- Staff reads see only the NON-secret metadata. No policy may
-- expose the raw api_key_enc; we therefore revoke SELECT on that
-- column for non-service_role roles.
DROP POLICY IF EXISTS billing_providers_staff_read
  ON public.billing_providers;
CREATE POLICY billing_providers_staff_read
  ON public.billing_providers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_providers.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach')
    )
  );

REVOKE ALL ON TABLE public.billing_providers FROM anon, authenticated;
GRANT SELECT (
  id, group_id, provider, key_version, last_rotated_at,
  created_at, updated_at
) ON public.billing_providers TO authenticated;
GRANT ALL ON TABLE public.billing_providers TO service_role;

-- ── 2. Write helper (service_role only) ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_set_billing_provider_key(
  p_group_id uuid,
  p_provider text,
  p_plain_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_master text;
  v_enc    bytea;
  v_id     uuid;
  v_version int;
BEGIN
  IF p_group_id IS NULL OR p_provider IS NULL OR p_plain_key IS NULL THEN
    RAISE EXCEPTION 'INVALID_ARGS' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    v_master := current_setting('app.settings.kms_key');
  EXCEPTION WHEN undefined_object THEN
    v_master := NULL;
  END;

  IF v_master IS NULL OR length(v_master) < 32 THEN
    RAISE EXCEPTION 'KMS_UNAVAILABLE: app.settings.kms_key not set or too short'
      USING ERRCODE = 'P0001';
  END IF;

  v_enc := pgp_sym_encrypt(p_plain_key, v_master);

  INSERT INTO public.billing_providers (
    group_id, provider, api_key_enc, key_version, last_rotated_at, updated_at
  ) VALUES (
    p_group_id, p_provider, v_enc, 1, now(), now()
  )
  ON CONFLICT (group_id, provider) DO UPDATE SET
    api_key_enc      = EXCLUDED.api_key_enc,
    key_version      = billing_providers.key_version + 1,
    last_rotated_at  = now(),
    updated_at       = now()
  RETURNING id, key_version INTO v_id, v_version;

  INSERT INTO public.portal_audit_log (
    actor_id, group_id, action, target_type, target_id, metadata
  ) VALUES (
    COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    p_group_id,
    'billing_provider.key_set',
    'billing_providers',
    v_id::text,
    jsonb_build_object('provider', p_provider, 'key_version', v_version)
  );

  RETURN jsonb_build_object(
    'id', v_id,
    'group_id', p_group_id,
    'provider', p_provider,
    'key_version', v_version
  );
END;
$$;

COMMENT ON FUNCTION public.fn_set_billing_provider_key(uuid, text, text) IS
  'L09-06 — encrypt + upsert billing provider credential. ' ||
  'Logs to portal_audit_log. service_role only.';

REVOKE ALL ON FUNCTION public.fn_set_billing_provider_key(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_set_billing_provider_key(uuid, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_set_billing_provider_key(uuid, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_set_billing_provider_key(uuid, text, text) TO service_role;

-- ── 3. Read helper (service_role only, logged) ─────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_get_billing_provider_key(
  p_group_id uuid,
  p_provider text,
  p_reason   text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_master  text;
  v_enc     bytea;
  v_id      uuid;
  v_version int;
  v_plain   text;
BEGIN
  IF p_group_id IS NULL OR p_provider IS NULL THEN
    RAISE EXCEPTION 'INVALID_ARGS' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    v_master := current_setting('app.settings.kms_key');
  EXCEPTION WHEN undefined_object THEN
    v_master := NULL;
  END;

  IF v_master IS NULL OR length(v_master) < 32 THEN
    RAISE EXCEPTION 'KMS_UNAVAILABLE: app.settings.kms_key not set or too short'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT id, api_key_enc, key_version
    INTO v_id, v_enc, v_version
    FROM public.billing_providers
   WHERE group_id = p_group_id
     AND provider = p_provider;

  IF NOT FOUND OR v_enc IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: no billing_provider for % / %',
      p_group_id, p_provider
      USING ERRCODE = 'P0001';
  END IF;

  v_plain := pgp_sym_decrypt(v_enc, v_master);

  INSERT INTO public.portal_audit_log (
    actor_id, group_id, action, target_type, target_id, metadata
  ) VALUES (
    COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    p_group_id,
    'billing_provider.key_access',
    'billing_providers',
    v_id::text,
    jsonb_build_object(
      'provider', p_provider,
      'key_version', v_version,
      'reason', COALESCE(p_reason, 'unspecified')
    )
  );

  RETURN v_plain;
END;
$$;

COMMENT ON FUNCTION public.fn_get_billing_provider_key(uuid, text, text) IS
  'L09-06 — decrypt billing provider credential. ' ||
  'Every call is logged to portal_audit_log. service_role only.';

REVOKE ALL ON FUNCTION public.fn_get_billing_provider_key(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_get_billing_provider_key(uuid, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_get_billing_provider_key(uuid, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_get_billing_provider_key(uuid, text, text) TO service_role;

-- ── 4. Self-test ───────────────────────────────────────────────────────────

DO $$
DECLARE
  v_raised boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto'
  ) THEN
    RAISE EXCEPTION 'L09-06 self-test: pgcrypto extension missing';
  END IF;

  -- (a) Column exists and is bytea
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'billing_providers'
      AND column_name = 'api_key_enc'
      AND data_type = 'bytea'
  ) THEN
    RAISE EXCEPTION 'L09-06 self-test: api_key_enc must be bytea';
  END IF;

  -- (b) authenticated role does NOT have SELECT on api_key_enc.
  IF EXISTS (
    SELECT 1 FROM information_schema.column_privileges
    WHERE grantee = 'authenticated'
      AND table_schema = 'public'
      AND table_name = 'billing_providers'
      AND column_name = 'api_key_enc'
      AND privilege_type = 'SELECT'
  ) THEN
    RAISE EXCEPTION
      'L09-06 self-test: authenticated must not have SELECT on api_key_enc';
  END IF;

  -- (c) Missing KMS GUC raises
  BEGIN
    PERFORM set_config('app.settings.kms_key', '', true);
    PERFORM public.fn_set_billing_provider_key(
      '00000000-0000-0000-0000-000000000000'::uuid,
      'asaas',
      'dummy'
    );
    v_raised := false;
  EXCEPTION WHEN others THEN
    v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION
      'L09-06 self-test: empty KMS key should have raised KMS_UNAVAILABLE';
  END IF;

  -- (d) Round-trip encrypt / decrypt inside same transaction when
  --     KMS is set. We can't touch real group_id rows so we do a
  --     pure cryptographic round-trip.
  PERFORM set_config(
    'app.settings.kms_key',
    'self-test-0123456789abcdef0123456789abcdef',
    true
  );
  IF pgp_sym_decrypt(
       pgp_sym_encrypt('hello', current_setting('app.settings.kms_key')),
       current_setting('app.settings.kms_key')
     ) <> 'hello'
  THEN
    RAISE EXCEPTION 'L09-06 self-test: pgp_sym round-trip failed';
  END IF;

  RAISE NOTICE 'L09-06 self-test: OK';
END
$$;

COMMIT;
