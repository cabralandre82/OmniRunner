-- ══════════════════════════════════════════════════════════════════════════
-- L01-17 — Asaas API Key / webhook_token em texto puro → supabase_vault
--
-- Referência auditoria:
--   docs/audit/findings/L01-17-post-api-billing-asaas-armazenamento-de-api-key.md
--   docs/audit/parts/01-ciso.md [1.17]
--
-- Problema:
--   `payment_provider_config.api_key TEXT NOT NULL` armazena a API Key
--   do Asaas (permite emitir cobranças, consultar clientes, iniciar
--   transferências) em texto puro. Dump/backup/leak do banco → TODAS as
--   keys das assessorias vazam. Mesmo problema com `webhook_token`
--   (HMAC secret que autentica payloads do Asaas).
--
-- Correção:
--   1. Extensão `supabase_vault` (já instalada) provê `vault.secrets`
--      (AEAD encryption via pgsodium, key rotacionável).
--   2. Novas colunas `api_key_secret_id uuid`, `webhook_token_secret_id uuid`
--      armazenam apenas referências ao vault (FK lógica para vault.secrets.id).
--   3. Helpers SECURITY DEFINER (hardened com search_path + lock_timeout):
--        - fn_ppc_save_api_key:        admin_master/coach do grupo
--        - fn_ppc_get_api_key:         service_role only (Edge Functions)
--        - fn_ppc_save_webhook_token:  service_role only (asaas-sync)
--        - fn_ppc_get_webhook_token:   service_role only (asaas-webhook)
--        - fn_ppc_has_api_key:         admin_master/coach do grupo (UI flag)
--   4. Audit log `payment_provider_secret_access_log` — cada leitura
--      de secret é registrada com actor + request-id + kind.
--   5. Backfill: para cada row existente com `api_key IS NOT NULL`,
--      cria vault.secret, preenche secret_id, zera a coluna plaintext.
--   6. DROP das colunas `api_key` e `webhook_token` ao fim — secret
--      material nunca mais transita por dump/replica.
--
-- Compat:
--   - Edge Functions e portal route refatorados no mesmo commit para
--     chamar as RPCs. Deploy atômico.
--   - Rotação de key é simples: re-chamar fn_ppc_save_api_key com o
--     novo valor → vault.update_secret() preserva o UUID da referência.
--
-- Linked:
--   - L01-18 (Asaas webhook sem HMAC) — reaproveita fn_ppc_get_webhook_token
--     para validar signature com o secret correto.
-- ══════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Pré-requisito: supabase_vault
-- ──────────────────────────────────────────────────────────────────────────
--
-- Extensão criada pelo Supabase no bootstrap. Validamos presença.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'supabase_vault') THEN
    RAISE EXCEPTION '[L01-17] extensão supabase_vault ausente — ambiente inválido';
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Audit log de acessos a secrets
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_provider_secret_access_log (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id       uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  secret_kind    text NOT NULL CHECK (secret_kind IN ('api_key', 'webhook_token')),
  action         text NOT NULL CHECK (action IN ('create', 'rotate', 'read', 'delete')),
  actor_user_id  uuid,
  actor_role     text,
  request_id     text,
  accessed_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ppsal_group_accessed
  ON public.payment_provider_secret_access_log (group_id, accessed_at DESC);

CREATE INDEX IF NOT EXISTS idx_ppsal_kind_action
  ON public.payment_provider_secret_access_log (secret_kind, action, accessed_at DESC);

COMMENT ON TABLE public.payment_provider_secret_access_log IS
  'L01-17: audit trail de operações em secrets Asaas (create/rotate/read/delete). '
  'Service_role writes; admin_master lê apenas do próprio grupo.';

ALTER TABLE public.payment_provider_secret_access_log ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.payment_provider_secret_access_log FROM PUBLIC;
REVOKE ALL ON public.payment_provider_secret_access_log FROM anon;

GRANT SELECT ON public.payment_provider_secret_access_log TO authenticated;
GRANT ALL    ON public.payment_provider_secret_access_log TO service_role;

DROP POLICY IF EXISTS "ppsal_admin_own_group_read" ON public.payment_provider_secret_access_log;
CREATE POLICY "ppsal_admin_own_group_read"
  ON public.payment_provider_secret_access_log FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = payment_provider_secret_access_log.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Colunas de referência ao vault
-- ──────────────────────────────────────────────────────────────────────────
ALTER TABLE public.payment_provider_config
  ADD COLUMN IF NOT EXISTS api_key_secret_id       uuid,
  ADD COLUMN IF NOT EXISTS webhook_token_secret_id uuid;

COMMENT ON COLUMN public.payment_provider_config.api_key_secret_id IS
  'L01-17: referência para vault.secrets.id (Asaas API Key encrypted at rest).';
COMMENT ON COLUMN public.payment_provider_config.webhook_token_secret_id IS
  'L01-17: referência para vault.secrets.id (Asaas webhook HMAC token).';

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Helper interno: nome determinístico de secret por (group_id, kind)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._ppc_secret_name(p_group_id uuid, p_kind text)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path = public, pg_temp
AS $$
  SELECT 'asaas:' || p_kind || ':' || p_group_id::text;
$$;

REVOKE ALL ON FUNCTION public._ppc_secret_name(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ppc_secret_name(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public._ppc_secret_name(uuid, text) FROM authenticated;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. RPC: fn_ppc_save_api_key (admin_master/coach do grupo)
-- ──────────────────────────────────────────────────────────────────────────
--
-- Cria a config (se ausente) ou rotaciona o secret (se presente).
-- Authz: caller deve ser admin_master ou coach de p_group_id.
-- Retorna jsonb com { config_id, secret_id, rotated: boolean }.
-- Nunca retorna a api_key em si.
CREATE OR REPLACE FUNCTION public.fn_ppc_save_api_key(
  p_group_id     uuid,
  p_api_key      text,
  p_environment  text DEFAULT 'sandbox',
  p_request_id   text DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_caller_role  text;
  v_config_id    uuid;
  v_secret_id    uuid;
  v_existing     uuid;
  v_secret_name  text := public._ppc_secret_name(p_group_id, 'api_key');
  v_rotated      boolean := false;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'MISSING_GROUP_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_api_key IS NULL OR length(trim(p_api_key)) < 8 THEN
    RAISE EXCEPTION 'INVALID_API_KEY' USING ERRCODE = 'P0001';
  END IF;
  IF p_environment IS NULL OR p_environment NOT IN ('sandbox', 'production') THEN
    RAISE EXCEPTION 'INVALID_ENVIRONMENT' USING ERRCODE = 'P0001';
  END IF;

  -- Authz: caller precisa ser admin_master/coach do grupo (via JWT user)
  -- OU chamado com service_role (Edge Function trusted).
  -- Importante: `NULL NOT IN (...)` avalia para NULL em SQL trivalent,
  -- então testamos IS NULL explicitamente para fail-closed.
  IF auth.role() = 'service_role' THEN
    v_caller_role := 'service_role';
  ELSE
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0004';
    END IF;

    SELECT cm.role INTO v_caller_role
      FROM public.coaching_members cm
     WHERE cm.group_id = p_group_id
       AND cm.user_id  = auth.uid();

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0004';
    END IF;
  END IF;

  -- Upsert vault secret — se já existe, rotaciona; senão, cria.
  SELECT ppc.api_key_secret_id, ppc.id
    INTO v_secret_id, v_config_id
    FROM public.payment_provider_config ppc
   WHERE ppc.group_id = p_group_id
     AND ppc.provider = 'asaas';

  IF v_secret_id IS NOT NULL THEN
    -- Rotação
    PERFORM vault.update_secret(v_secret_id, p_api_key, v_secret_name,
                                'Asaas API Key (L01-17)');
    v_rotated := true;
  ELSE
    -- Create — se alguém já criou um secret com o mesmo nome (rollback parcial),
    -- pegamos o existente para evitar UNIQUE violation em vault.secrets.name
    SELECT id INTO v_existing FROM vault.secrets WHERE name = v_secret_name;
    IF v_existing IS NOT NULL THEN
      PERFORM vault.update_secret(v_existing, p_api_key, v_secret_name,
                                  'Asaas API Key (L01-17)');
      v_secret_id := v_existing;
    ELSE
      v_secret_id := vault.create_secret(p_api_key, v_secret_name,
                                          'Asaas API Key (L01-17)');
    END IF;
  END IF;

  -- Upsert config row com referência
  INSERT INTO public.payment_provider_config (
    group_id, provider, api_key_secret_id, environment, is_active, updated_at
  ) VALUES (
    p_group_id, 'asaas', v_secret_id, p_environment, false, now()
  )
  ON CONFLICT (group_id, provider) DO UPDATE
    SET api_key_secret_id = EXCLUDED.api_key_secret_id,
        environment       = EXCLUDED.environment,
        updated_at        = now()
  RETURNING id INTO v_config_id;

  -- Audit
  INSERT INTO public.payment_provider_secret_access_log (
    group_id, secret_kind, action, actor_user_id, actor_role, request_id
  ) VALUES (
    p_group_id, 'api_key',
    CASE WHEN v_rotated THEN 'rotate' ELSE 'create' END,
    auth.uid(), v_caller_role, p_request_id
  );

  RETURN jsonb_build_object(
    'config_id', v_config_id,
    'secret_id', v_secret_id,
    'rotated',   v_rotated
  );
END;
$$;

COMMENT ON FUNCTION public.fn_ppc_save_api_key(uuid, text, text, text) IS
  'L01-17: salva/rotaciona Asaas API Key no vault. Authz admin_master/coach. '
  'Erros: MISSING_GROUP_ID/INVALID_API_KEY/INVALID_ENVIRONMENT (P0001), '
  'FORBIDDEN (P0004).';

REVOKE ALL ON FUNCTION public.fn_ppc_save_api_key(uuid, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_ppc_save_api_key(uuid, text, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.fn_ppc_save_api_key(uuid, text, text, text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_ppc_save_api_key(uuid, text, text, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 6. RPC: fn_ppc_get_api_key (service_role only — Edge Functions)
-- ──────────────────────────────────────────────────────────────────────────
--
-- Retorna a chave decriptada. SÓ deve ser chamada por Edge Functions
-- via service_role. Cada leitura é auditada.
CREATE OR REPLACE FUNCTION public.fn_ppc_get_api_key(
  p_group_id    uuid,
  p_request_id  text DEFAULT NULL
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_secret_id uuid;
  v_secret    text;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'MISSING_GROUP_ID' USING ERRCODE = 'P0001';
  END IF;

  SELECT api_key_secret_id INTO v_secret_id
    FROM public.payment_provider_config
   WHERE group_id = p_group_id AND provider = 'asaas';

  IF v_secret_id IS NULL THEN
    RAISE EXCEPTION 'NO_CONFIG' USING ERRCODE = 'P0002';
  END IF;

  SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
   WHERE id = v_secret_id;

  IF v_secret IS NULL THEN
    RAISE EXCEPTION 'VAULT_MISS' USING ERRCODE = 'P0003';
  END IF;

  INSERT INTO public.payment_provider_secret_access_log (
    group_id, secret_kind, action, actor_user_id, actor_role, request_id
  ) VALUES (
    p_group_id, 'api_key', 'read', auth.uid(), 'service_role', p_request_id
  );

  RETURN v_secret;
END;
$$;

COMMENT ON FUNCTION public.fn_ppc_get_api_key(uuid, text) IS
  'L01-17: retorna Asaas API Key decriptada. Service_role only. Auditada.';

REVOKE ALL ON FUNCTION public.fn_ppc_get_api_key(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_ppc_get_api_key(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_ppc_get_api_key(uuid, text) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_ppc_get_api_key(uuid, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 7. RPC: fn_ppc_save_webhook_token (service_role only — asaas-sync)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ppc_save_webhook_token(
  p_group_id     uuid,
  p_webhook_id   text,
  p_token        text,
  p_request_id   text DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_secret_id    uuid;
  v_existing     uuid;
  v_secret_name  text := public._ppc_secret_name(p_group_id, 'webhook_token');
  v_rotated      boolean := false;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'MISSING_GROUP_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_token IS NULL OR length(trim(p_token)) < 16 THEN
    RAISE EXCEPTION 'INVALID_TOKEN' USING ERRCODE = 'P0001';
  END IF;

  SELECT webhook_token_secret_id INTO v_secret_id
    FROM public.payment_provider_config
   WHERE group_id = p_group_id AND provider = 'asaas';

  IF v_secret_id IS NOT NULL THEN
    PERFORM vault.update_secret(v_secret_id, p_token, v_secret_name,
                                'Asaas webhook HMAC token (L01-17)');
    v_rotated := true;
  ELSE
    SELECT id INTO v_existing FROM vault.secrets WHERE name = v_secret_name;
    IF v_existing IS NOT NULL THEN
      PERFORM vault.update_secret(v_existing, p_token, v_secret_name,
                                  'Asaas webhook HMAC token (L01-17)');
      v_secret_id := v_existing;
    ELSE
      v_secret_id := vault.create_secret(p_token, v_secret_name,
                                          'Asaas webhook HMAC token (L01-17)');
    END IF;
  END IF;

  UPDATE public.payment_provider_config
     SET webhook_id                = p_webhook_id,
         webhook_token_secret_id   = v_secret_id,
         is_active                 = true,
         connected_at              = now(),
         updated_at                = now()
   WHERE group_id = p_group_id AND provider = 'asaas';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_CONFIG' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.payment_provider_secret_access_log (
    group_id, secret_kind, action, actor_user_id, actor_role, request_id
  ) VALUES (
    p_group_id, 'webhook_token',
    CASE WHEN v_rotated THEN 'rotate' ELSE 'create' END,
    auth.uid(), 'service_role', p_request_id
  );

  RETURN jsonb_build_object(
    'secret_id', v_secret_id,
    'rotated',   v_rotated
  );
END;
$$;

COMMENT ON FUNCTION public.fn_ppc_save_webhook_token(uuid, text, text, text) IS
  'L01-17: salva/rotaciona Asaas webhook HMAC token no vault. Service_role only.';

REVOKE ALL ON FUNCTION public.fn_ppc_save_webhook_token(uuid, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_ppc_save_webhook_token(uuid, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_ppc_save_webhook_token(uuid, text, text, text) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_ppc_save_webhook_token(uuid, text, text, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 8. RPC: fn_ppc_get_webhook_token (service_role only — asaas-webhook)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ppc_get_webhook_token(
  p_group_id    uuid,
  p_request_id  text DEFAULT NULL
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_secret_id uuid;
  v_secret    text;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'MISSING_GROUP_ID' USING ERRCODE = 'P0001';
  END IF;

  SELECT webhook_token_secret_id INTO v_secret_id
    FROM public.payment_provider_config
   WHERE group_id = p_group_id AND provider = 'asaas';

  IF v_secret_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
   WHERE id = v_secret_id;

  INSERT INTO public.payment_provider_secret_access_log (
    group_id, secret_kind, action, actor_user_id, actor_role, request_id
  ) VALUES (
    p_group_id, 'webhook_token', 'read', auth.uid(), 'service_role', p_request_id
  );

  RETURN v_secret;
END;
$$;

COMMENT ON FUNCTION public.fn_ppc_get_webhook_token(uuid, text) IS
  'L01-17: retorna Asaas webhook token decriptado. Service_role only. Auditada.';

REVOKE ALL ON FUNCTION public.fn_ppc_get_webhook_token(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_ppc_get_webhook_token(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_ppc_get_webhook_token(uuid, text) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_ppc_get_webhook_token(uuid, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 9. RPC: fn_ppc_has_api_key (UI flag — admin_master/coach)
-- ──────────────────────────────────────────────────────────────────────────
--
-- Retorna { connected, environment, last_connected_at } — NUNCA retorna
-- o valor da key. Útil para UI mostrar "Asaas configurado" sem expor secret.
CREATE OR REPLACE FUNCTION public.fn_ppc_has_api_key(p_group_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_role text;
  v_row         record;
BEGIN
  IF auth.role() <> 'service_role' THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0004';
    END IF;

    SELECT cm.role INTO v_caller_role
      FROM public.coaching_members cm
     WHERE cm.group_id = p_group_id AND cm.user_id = auth.uid();

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0004';
    END IF;
  END IF;

  SELECT
    (api_key_secret_id IS NOT NULL) AS has_key,
    environment,
    is_active,
    connected_at
    INTO v_row
    FROM public.payment_provider_config
   WHERE group_id = p_group_id AND provider = 'asaas';

  IF v_row IS NULL THEN
    RETURN jsonb_build_object(
      'has_key', false,
      'environment', null,
      'is_active', false,
      'connected_at', null
    );
  END IF;

  RETURN jsonb_build_object(
    'has_key',      v_row.has_key,
    'environment',  v_row.environment,
    'is_active',    v_row.is_active,
    'connected_at', v_row.connected_at
  );
END;
$$;

COMMENT ON FUNCTION public.fn_ppc_has_api_key(uuid) IS
  'L01-17: flag UI (connected/environment/is_active) sem expor secret. '
  'Authz admin_master/coach.';

REVOKE ALL ON FUNCTION public.fn_ppc_has_api_key(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_ppc_has_api_key(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.fn_ppc_has_api_key(uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_ppc_has_api_key(uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 10. Backfill: migrar api_key/webhook_token plaintext → vault
-- ──────────────────────────────────────────────────────────────────────────
--
-- Para cada row existente que ainda tenha api_key/webhook_token em texto,
-- cria o secret no vault e preenche a referência. Idempotente.

DO $$
DECLARE
  r                record;
  v_secret_id      uuid;
  v_secret_name    text;
  v_has_api_key    boolean;
  v_has_webhook    boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'payment_provider_config'
      AND column_name = 'api_key'
  ) INTO v_has_api_key;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'payment_provider_config'
      AND column_name = 'webhook_token'
  ) INTO v_has_webhook;

  IF NOT v_has_api_key AND NOT v_has_webhook THEN
    RAISE NOTICE '[L01-17] backfill: colunas plaintext já removidas, pulando';
    RETURN;
  END IF;

  FOR r IN
    EXECUTE format(
      'SELECT id, group_id, %s AS legacy_api_key, %s AS legacy_webhook_token, '
      '       api_key_secret_id, webhook_token_secret_id '
      'FROM public.payment_provider_config WHERE provider = ''asaas''',
      CASE WHEN v_has_api_key THEN 'api_key' ELSE 'NULL::text' END,
      CASE WHEN v_has_webhook THEN 'webhook_token' ELSE 'NULL::text' END
    )
  LOOP
    -- API Key
    IF r.api_key_secret_id IS NULL
       AND r.legacy_api_key IS NOT NULL
       AND length(trim(r.legacy_api_key)) > 0
    THEN
      v_secret_name := public._ppc_secret_name(r.group_id, 'api_key');
      SELECT id INTO v_secret_id FROM vault.secrets WHERE name = v_secret_name;
      IF v_secret_id IS NULL THEN
        v_secret_id := vault.create_secret(r.legacy_api_key, v_secret_name,
                                            'Asaas API Key (L01-17 backfill)');
      ELSE
        PERFORM vault.update_secret(v_secret_id, r.legacy_api_key, v_secret_name,
                                    'Asaas API Key (L01-17 backfill)');
      END IF;
      UPDATE public.payment_provider_config
         SET api_key_secret_id = v_secret_id
       WHERE id = r.id;
      INSERT INTO public.payment_provider_secret_access_log (
        group_id, secret_kind, action, actor_user_id, actor_role, request_id
      ) VALUES (r.group_id, 'api_key', 'create', NULL, 'migration', 'L01-17-backfill');
    END IF;

    -- Webhook token
    IF r.webhook_token_secret_id IS NULL
       AND r.legacy_webhook_token IS NOT NULL
       AND length(trim(r.legacy_webhook_token)) > 0
    THEN
      v_secret_name := public._ppc_secret_name(r.group_id, 'webhook_token');
      SELECT id INTO v_secret_id FROM vault.secrets WHERE name = v_secret_name;
      IF v_secret_id IS NULL THEN
        v_secret_id := vault.create_secret(r.legacy_webhook_token, v_secret_name,
                                            'Asaas webhook token (L01-17 backfill)');
      ELSE
        PERFORM vault.update_secret(v_secret_id, r.legacy_webhook_token, v_secret_name,
                                    'Asaas webhook token (L01-17 backfill)');
      END IF;
      UPDATE public.payment_provider_config
         SET webhook_token_secret_id = v_secret_id
       WHERE id = r.id;
      INSERT INTO public.payment_provider_secret_access_log (
        group_id, secret_kind, action, actor_user_id, actor_role, request_id
      ) VALUES (r.group_id, 'webhook_token', 'create', NULL, 'migration', 'L01-17-backfill');
    END IF;
  END LOOP;

  RAISE NOTICE '[L01-17] backfill vault completo';
END $$;

-- ──────────────────────────────────────────────────────────────────────────
-- 11. DROP colunas plaintext (defense-in-depth)
-- ──────────────────────────────────────────────────────────────────────────
--
-- Após backfill, remove o material secreto do schema para sempre — nenhum
-- dump/replica/logical backup captura texto-puro a partir desta migration.

ALTER TABLE public.payment_provider_config
  DROP COLUMN IF EXISTS api_key,
  DROP COLUMN IF EXISTS webhook_token;

-- ──────────────────────────────────────────────────────────────────────────
-- 12. Invariantes de saída
-- ──────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_has_api_key_col boolean;
  v_has_wh_col      boolean;
  v_fn_count        integer;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'payment_provider_config'
      AND column_name = 'api_key'
  ) INTO v_has_api_key_col;
  IF v_has_api_key_col THEN
    RAISE EXCEPTION '[L01-17] invariant failed: api_key plaintext column ainda existe';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'payment_provider_config'
      AND column_name = 'webhook_token'
  ) INTO v_has_wh_col;
  IF v_has_wh_col THEN
    RAISE EXCEPTION '[L01-17] invariant failed: webhook_token plaintext column ainda existe';
  END IF;

  SELECT count(*) INTO v_fn_count
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('fn_ppc_save_api_key', 'fn_ppc_get_api_key',
                       'fn_ppc_save_webhook_token', 'fn_ppc_get_webhook_token',
                       'fn_ppc_has_api_key');
  IF v_fn_count < 5 THEN
    RAISE EXCEPTION '[L01-17] invariant failed: esperado 5 RPCs, got %', v_fn_count;
  END IF;
END $$;
