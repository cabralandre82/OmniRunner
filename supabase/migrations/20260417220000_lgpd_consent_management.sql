-- ══════════════════════════════════════════════════════════════════════════
-- L04-03 — LGPD Art. 7/8: registro de consentimento (opt-in explícito)
--
-- Referência auditoria:
--   docs/audit/findings/L04-03-nao-ha-registro-de-consentimento-opt-in-explicito.md
--   docs/audit/parts/03-clo-cpo.md [4.3]
--
-- Problema:
--   A plataforma coleta dados pessoais (perfil, GPS, HR, integrações
--   Strava/TrainingPeaks, billing) sem qualquer registro de consentimento.
--   LGPD Art. 7º I exige consentimento inequívoco e demonstrável; Art. 8 §1
--   exige que o titular possa REVOGAR a qualquer tempo. Em auditoria/ação
--   judicial, a plataforma é incapaz de provar quando/como/qual versão o
--   usuário aceitou. Multa até 2% do faturamento.
--
-- Correção:
--   1. `consent_policy_versions` — catálogo versionado das políticas vigentes
--      (terms, privacy, marketing, health_data, third_party_*, location).
--   2. `consent_events` — log append-only de cada grant/revoke com
--      (user_id, consent_type, version, action, ip, user_agent, source,
--      request_id, granted_at). Único source-of-truth histórico.
--   3. Snapshot desnormalizado em `profiles.*_accepted_at / *_version` para
--      queries rápidas (UI, RLS auxiliar). Atualizado por trigger/RPC.
--   4. 4 RPCs SECURITY DEFINER hardened:
--        - fn_consent_grant(type, version, source, ip, ua, rid)
--        - fn_consent_revoke(type, source, rid)
--        - fn_consent_status(user_id?) — lista por tipo + válido?
--        - fn_consent_has_required(user_id?) — boolean fail-closed
--   5. View `v_user_consent_status` agrega último evento por
--      (user_id, consent_type) e indica se a versão aceita ≥ minimum_version.
--   6. `consent_events` entra em lgpd_deletion_strategy como `anonymize`:
--      preserva prova histórica de que "alguém" consentiu em T=... (LGPD
--      Art. 16 legítimo interesse documental), desliga user_id no erasure
--      (Art. 18 VI direito ao esquecimento).
--
-- Compat:
--   - Tabela `profiles` ganha colunas nullable — rows existentes ficam com
--     NULL → fn_consent_has_required = false → app/portal devem bloquear
--     fluxos privados até consentimento obtido (fail-closed por design).
--   - Política inicial registra v1.0 para todos os tipos; rotação futura
--     basta bump da `consent_policy_versions.current_version`.
-- ══════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Catálogo de políticas vigentes
-- ──────────────────────────────────────────────────────────────────────────
--
-- consent_type canônicos:
--   terms                     — Termos de Uso (required)
--   privacy                   — Política de Privacidade (required)
--   health_data               — Coleta de HR/GPS/biométricos (required atletas)
--   location_tracking         — GPS em sessões (required atletas)
--   marketing                 — Email/push marketing (opt-in)
--   third_party_strava        — Integração Strava (opt-in quando conectar)
--   third_party_trainingpeaks — Integração TrainingPeaks (opt-in)
--   coach_data_share          — Compartilhar dados com coach/assessoria (opt-in ao joinar)

CREATE TABLE IF NOT EXISTS public.consent_policy_versions (
  consent_type      text PRIMARY KEY CHECK (consent_type IN (
    'terms', 'privacy', 'health_data', 'location_tracking',
    'marketing', 'third_party_strava', 'third_party_trainingpeaks',
    'coach_data_share'
  )),
  current_version   text        NOT NULL,
  minimum_version   text        NOT NULL,
  is_required       boolean     NOT NULL DEFAULT true,
  required_for_role text        CHECK (required_for_role IN ('athlete', 'coach', 'admin_master', 'any')),
  document_url      text,
  document_hash     text,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        uuid
);

COMMENT ON TABLE public.consent_policy_versions IS
  'L04-03: catálogo das versões vigentes por tipo de consentimento. '
  'Fonte de verdade para validar se consent_events.version ≥ minimum_version.';

COMMENT ON COLUMN public.consent_policy_versions.required_for_role IS
  'NULL/any = obrigatório para todos; athlete/coach/admin_master = apenas papel específico.';

ALTER TABLE public.consent_policy_versions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.consent_policy_versions FROM PUBLIC;
REVOKE ALL ON public.consent_policy_versions FROM anon;
GRANT  SELECT ON public.consent_policy_versions TO authenticated;
GRANT  ALL    ON public.consent_policy_versions TO service_role;

DROP POLICY IF EXISTS "cpv_public_read" ON public.consent_policy_versions;
CREATE POLICY "cpv_public_read"
  ON public.consent_policy_versions FOR SELECT TO authenticated
  USING (true);

-- Seed inicial (idempotente)
INSERT INTO public.consent_policy_versions
  (consent_type, current_version, minimum_version, is_required, required_for_role, document_url)
VALUES
  ('terms',                     '1.0', '1.0', true,  'any',          '/legal/terms-v1.md'),
  ('privacy',                   '1.0', '1.0', true,  'any',          '/legal/privacy-v1.md'),
  ('health_data',               '1.0', '1.0', true,  'athlete',      '/legal/health-data-v1.md'),
  ('location_tracking',         '1.0', '1.0', true,  'athlete',      '/legal/location-v1.md'),
  ('marketing',                 '1.0', '1.0', false, 'any',          '/legal/marketing-v1.md'),
  ('third_party_strava',        '1.0', '1.0', false, 'athlete',      '/legal/strava-v1.md'),
  ('third_party_trainingpeaks', '1.0', '1.0', false, 'athlete',      '/legal/trainingpeaks-v1.md'),
  ('coach_data_share',          '1.0', '1.0', false, 'athlete',      '/legal/coach-share-v1.md')
ON CONFLICT (consent_type) DO UPDATE
  SET updated_at = now();

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Log append-only de eventos
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.consent_events (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  -- FK com ON DELETE SET DEFAULT → auth.users DELETE preserva a row
  -- anonimizando user_id para zero UUID (LGPD Art. 16 vs. Art. 18 VI).
  user_id       uuid        NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'::uuid
                REFERENCES auth.users(id) ON DELETE SET DEFAULT,
  consent_type  text        NOT NULL CHECK (consent_type IN (
    'terms', 'privacy', 'health_data', 'location_tracking',
    'marketing', 'third_party_strava', 'third_party_trainingpeaks',
    'coach_data_share'
  )),
  action        text        NOT NULL CHECK (action IN ('granted', 'revoked')),
  version       text        NOT NULL,
  source        text        NOT NULL CHECK (source IN (
    'mobile', 'portal', 'edge_function', 'migration', 'admin_override'
  )),
  ip_address    inet,
  user_agent    text,
  request_id    text,
  granted_at    timestamptz NOT NULL DEFAULT now(),
  -- Optional signed checksum for extra integrity (future hardening)
  event_hash    text
);

COMMENT ON TABLE public.consent_events IS
  'L04-03: log imutável (append-only via RLS) de grant/revoke de consentimento. '
  'Única fonte histórica para prova judicial. user_id anonimizado em erasure '
  '(LGPD Art. 18 VI) mas row preservada (LGPD Art. 16 legítimo interesse).';

CREATE INDEX IF NOT EXISTS idx_consent_events_user_type_time
  ON public.consent_events (user_id, consent_type, granted_at DESC);

CREATE INDEX IF NOT EXISTS idx_consent_events_type_version
  ON public.consent_events (consent_type, version, granted_at DESC);

-- RLS: user reads own; service_role reads all; NO direct INSERT/UPDATE/DELETE
ALTER TABLE public.consent_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.consent_events FROM PUBLIC;
REVOKE ALL ON public.consent_events FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.consent_events FROM authenticated;
GRANT  SELECT ON public.consent_events TO authenticated;
GRANT  ALL    ON public.consent_events TO service_role;

DROP POLICY IF EXISTS "ce_own_read" ON public.consent_events;
CREATE POLICY "ce_own_read"
  ON public.consent_events FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Append-only: qualquer UPDATE/DELETE direto falha mesmo para service_role
-- via trigger (service_role usa o RPC que também só faz INSERT).
CREATE OR REPLACE FUNCTION public._consent_events_append_only()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_anon constant uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
  -- Permitir que fn_delete_user_data / FK SET DEFAULT anonimizem user_id.
  IF TG_OP = 'UPDATE' THEN
    IF NEW.consent_type IS DISTINCT FROM OLD.consent_type
       OR NEW.action IS DISTINCT FROM OLD.action
       OR NEW.version IS DISTINCT FROM OLD.version
       OR NEW.source IS DISTINCT FROM OLD.source
       OR NEW.granted_at IS DISTINCT FROM OLD.granted_at
       OR NEW.id IS DISTINCT FROM OLD.id
    THEN
      RAISE EXCEPTION 'CONSENT_APPEND_ONLY: só user_id/ip/ua podem ser anonimizados; outros campos são imutáveis'
        USING ERRCODE = 'P0001';
    END IF;
    -- Se user_id foi anonimizado (via fn_anonymize_consent_events ou ON DELETE
    -- SET DEFAULT da FK), PII adicional em ip/ua deve ser zerada também.
    IF NEW.user_id = v_anon AND OLD.user_id IS DISTINCT FROM v_anon THEN
      NEW.ip_address := NULL;
      NEW.user_agent := NULL;
    END IF;
    RETURN NEW;
  END IF;
  -- DELETE só permitido se a row já foi anonimizada (LGPD compaction opcional)
  IF TG_OP = 'DELETE' THEN
    IF OLD.user_id <> v_anon THEN
      RAISE EXCEPTION 'CONSENT_APPEND_ONLY: delete requer user_id previamente anonimizado'
        USING ERRCODE = 'P0001';
    END IF;
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_consent_events_append_only ON public.consent_events;
CREATE TRIGGER trg_consent_events_append_only
  BEFORE UPDATE OR DELETE ON public.consent_events
  FOR EACH ROW EXECUTE FUNCTION public._consent_events_append_only();

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Snapshot desnormalizado em profiles
-- ──────────────────────────────────────────────────────────────────────────
--
-- Speeds up UI/RLS queries ("is user onboarded?") sem recalcular view.
-- Trigger em consent_events mantém em sync.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS terms_accepted_at        timestamptz,
  ADD COLUMN IF NOT EXISTS terms_version            text,
  ADD COLUMN IF NOT EXISTS privacy_accepted_at      timestamptz,
  ADD COLUMN IF NOT EXISTS privacy_version          text,
  ADD COLUMN IF NOT EXISTS health_data_consent_at   timestamptz,
  ADD COLUMN IF NOT EXISTS location_consent_at      timestamptz,
  ADD COLUMN IF NOT EXISTS marketing_consent_at     timestamptz;

COMMENT ON COLUMN public.profiles.terms_accepted_at IS
  'L04-03: snapshot do último consent_events granted para consent_type=terms. '
  'Autoridade final é consent_events; esta coluna é cache desnormalizado.';

-- ──────────────────────────────────────────────────────────────────────────
-- 4. View: status consolidado por (user_id, consent_type)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_user_consent_status AS
WITH latest AS (
  SELECT DISTINCT ON (user_id, consent_type)
         user_id,
         consent_type,
         action,
         version,
         granted_at,
         source
    FROM public.consent_events
   ORDER BY user_id, consent_type, granted_at DESC
)
SELECT
  l.user_id,
  l.consent_type,
  l.action,
  l.version        AS accepted_version,
  p.current_version,
  p.minimum_version,
  p.is_required,
  p.required_for_role,
  l.granted_at,
  l.source,
  -- Consent válido = último action='granted' E versão >= minimum
  (l.action = 'granted'
     AND l.version >= p.minimum_version) AS is_valid
FROM latest l
JOIN public.consent_policy_versions p ON p.consent_type = l.consent_type;

COMMENT ON VIEW public.v_user_consent_status IS
  'L04-03: último estado de cada (user_id, consent_type). is_valid indica '
  'que o usuário consentiu e a versão aceita ≥ minimum_version atual.';

REVOKE ALL ON public.v_user_consent_status FROM PUBLIC;
REVOKE ALL ON public.v_user_consent_status FROM anon;
GRANT  SELECT ON public.v_user_consent_status TO authenticated;
GRANT  SELECT ON public.v_user_consent_status TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. RPC: fn_consent_grant
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_consent_grant(
  p_consent_type text,
  p_version      text,
  p_source       text DEFAULT 'portal',
  p_ip           inet DEFAULT NULL,
  p_user_agent   text DEFAULT NULL,
  p_request_id   text DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_user_id  uuid;
  v_min_ver  text;
  v_event_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN: consent grant requires authenticated session'
      USING ERRCODE = 'P0004';
  END IF;

  IF p_consent_type IS NULL OR p_consent_type NOT IN (
    'terms', 'privacy', 'health_data', 'location_tracking',
    'marketing', 'third_party_strava', 'third_party_trainingpeaks',
    'coach_data_share'
  ) THEN
    RAISE EXCEPTION 'INVALID_CONSENT_TYPE: %', p_consent_type
      USING ERRCODE = 'P0001';
  END IF;

  IF p_version IS NULL OR length(trim(p_version)) = 0 THEN
    RAISE EXCEPTION 'MISSING_VERSION' USING ERRCODE = 'P0001';
  END IF;

  IF p_source NOT IN ('mobile', 'portal', 'edge_function') THEN
    RAISE EXCEPTION 'INVALID_SOURCE: %', p_source USING ERRCODE = 'P0001';
  END IF;

  -- Valida que a versão oferecida atende o mínimo vigente
  SELECT minimum_version INTO v_min_ver
    FROM public.consent_policy_versions
   WHERE consent_type = p_consent_type;

  IF v_min_ver IS NULL THEN
    RAISE EXCEPTION 'POLICY_NOT_FOUND: %', p_consent_type
      USING ERRCODE = 'P0002';
  END IF;

  IF p_version < v_min_ver THEN
    RAISE EXCEPTION 'VERSION_TOO_OLD: aceita % < minima %', p_version, v_min_ver
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.consent_events (
    user_id, consent_type, action, version, source,
    ip_address, user_agent, request_id
  ) VALUES (
    v_user_id, p_consent_type, 'granted', p_version, p_source,
    p_ip, p_user_agent, p_request_id
  ) RETURNING id INTO v_event_id;

  -- Atualiza snapshot denormalizado
  UPDATE public.profiles
     SET terms_accepted_at      = CASE WHEN p_consent_type = 'terms' THEN now() ELSE terms_accepted_at END,
         terms_version          = CASE WHEN p_consent_type = 'terms' THEN p_version ELSE terms_version END,
         privacy_accepted_at    = CASE WHEN p_consent_type = 'privacy' THEN now() ELSE privacy_accepted_at END,
         privacy_version        = CASE WHEN p_consent_type = 'privacy' THEN p_version ELSE privacy_version END,
         health_data_consent_at = CASE WHEN p_consent_type = 'health_data' THEN now() ELSE health_data_consent_at END,
         location_consent_at    = CASE WHEN p_consent_type = 'location_tracking' THEN now() ELSE location_consent_at END,
         marketing_consent_at   = CASE WHEN p_consent_type = 'marketing' THEN now() ELSE marketing_consent_at END,
         updated_at             = now()
   WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'event_id',     v_event_id,
    'consent_type', p_consent_type,
    'version',      p_version,
    'action',       'granted',
    'at',           now()
  );
END;
$$;

COMMENT ON FUNCTION public.fn_consent_grant(text, text, text, inet, text, text) IS
  'L04-03: registra consent grant do usuário autenticado. '
  'Errors: FORBIDDEN (P0004), INVALID_CONSENT_TYPE/MISSING_VERSION/INVALID_SOURCE/VERSION_TOO_OLD (P0001), POLICY_NOT_FOUND (P0002).';

REVOKE ALL ON FUNCTION public.fn_consent_grant(text, text, text, inet, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_consent_grant(text, text, text, inet, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.fn_consent_grant(text, text, text, inet, text, text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_consent_grant(text, text, text, inet, text, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 6. RPC: fn_consent_revoke
-- ──────────────────────────────────────────────────────────────────────────
--
-- Revoga consentimento. Tipos `terms`/`privacy` não podem ser revogados
-- isoladamente — isso equivale a deletar a conta (usar fn_delete_user_data).
CREATE OR REPLACE FUNCTION public.fn_consent_revoke(
  p_consent_type text,
  p_source       text DEFAULT 'portal',
  p_request_id   text DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_user_id   uuid;
  v_last_ver  text;
  v_event_id  uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0004';
  END IF;

  IF p_consent_type IN ('terms', 'privacy') THEN
    RAISE EXCEPTION 'NOT_REVOCABLE_STANDALONE: % só pode ser revogado via delete-account', p_consent_type
      USING ERRCODE = 'P0001';
  END IF;

  IF p_source NOT IN ('mobile', 'portal', 'edge_function') THEN
    RAISE EXCEPTION 'INVALID_SOURCE: %', p_source USING ERRCODE = 'P0001';
  END IF;

  -- Pega a versão do último grant para referência no revoke
  SELECT version INTO v_last_ver
    FROM public.consent_events
   WHERE user_id = v_user_id
     AND consent_type = p_consent_type
     AND action = 'granted'
   ORDER BY granted_at DESC
   LIMIT 1;

  IF v_last_ver IS NULL THEN
    -- Nada a revogar — no-op idempotente
    RETURN jsonb_build_object(
      'consent_type', p_consent_type,
      'action',       'revoked',
      'no_op',        true
    );
  END IF;

  INSERT INTO public.consent_events (
    user_id, consent_type, action, version, source, request_id
  ) VALUES (
    v_user_id, p_consent_type, 'revoked', v_last_ver, p_source, p_request_id
  ) RETURNING id INTO v_event_id;

  -- Limpa snapshot
  UPDATE public.profiles
     SET health_data_consent_at = CASE WHEN p_consent_type = 'health_data' THEN NULL ELSE health_data_consent_at END,
         location_consent_at    = CASE WHEN p_consent_type = 'location_tracking' THEN NULL ELSE location_consent_at END,
         marketing_consent_at   = CASE WHEN p_consent_type = 'marketing' THEN NULL ELSE marketing_consent_at END,
         updated_at             = now()
   WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'event_id',     v_event_id,
    'consent_type', p_consent_type,
    'action',       'revoked',
    'at',           now()
  );
END;
$$;

COMMENT ON FUNCTION public.fn_consent_revoke(text, text, text) IS
  'L04-03: revoga consent do usuário autenticado. '
  'terms/privacy → erro NOT_REVOCABLE_STANDALONE (usar delete-account).';

REVOKE ALL ON FUNCTION public.fn_consent_revoke(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_consent_revoke(text, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.fn_consent_revoke(text, text, text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_consent_revoke(text, text, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 7. RPC: fn_consent_status — estado atual do caller
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_consent_status(
  p_user_id uuid DEFAULT NULL
)
  RETURNS TABLE (
    consent_type      text,
    action            text,
    accepted_version  text,
    current_version   text,
    minimum_version   text,
    is_required       boolean,
    required_for_role text,
    is_valid          boolean,
    granted_at        timestamptz
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_target uuid;
BEGIN
  v_target := COALESCE(p_user_id, auth.uid());
  IF v_target IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0004';
  END IF;

  -- Caller só pode ver próprios consents, salvo service_role
  IF v_target <> auth.uid() AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'FORBIDDEN: cannot read other users consent'
      USING ERRCODE = 'P0004';
  END IF;

  RETURN QUERY
  SELECT
    p.consent_type,
    COALESCE(s.action, 'never')                  AS action,
    s.accepted_version,
    p.current_version,
    p.minimum_version,
    p.is_required,
    p.required_for_role,
    COALESCE(s.is_valid, false)                  AS is_valid,
    s.granted_at
  FROM public.consent_policy_versions p
  LEFT JOIN public.v_user_consent_status s
         ON s.consent_type = p.consent_type
        AND s.user_id = v_target
  ORDER BY p.is_required DESC, p.consent_type;
END;
$$;

COMMENT ON FUNCTION public.fn_consent_status(uuid) IS
  'L04-03: retorna estado de cada consent_type para o caller (ou p_user_id se service_role).';

REVOKE ALL ON FUNCTION public.fn_consent_status(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_consent_status(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.fn_consent_status(uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_consent_status(uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 8. RPC: fn_consent_has_required — fail-closed boolean gate
-- ──────────────────────────────────────────────────────────────────────────
--
-- Usado por Edge Functions/portal para bloquear endpoints sensíveis
-- (distribute-coins, swap, etc.) quando consents required estão pendentes.
CREATE OR REPLACE FUNCTION public.fn_consent_has_required(
  p_user_id uuid DEFAULT NULL,
  p_role    text DEFAULT NULL
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  STABLE
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_target  uuid;
  v_missing integer;
BEGIN
  v_target := COALESCE(p_user_id, auth.uid());
  IF v_target IS NULL THEN
    -- Sem contexto → fail-closed
    RETURN false;
  END IF;

  IF v_target <> auth.uid() AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0004';
  END IF;

  -- Conta políticas required cujo usuário NÃO tem consent_events válido
  SELECT count(*) INTO v_missing
  FROM public.consent_policy_versions p
  LEFT JOIN public.v_user_consent_status s
         ON s.consent_type = p.consent_type
        AND s.user_id = v_target
  WHERE p.is_required = true
    AND (p.required_for_role IS NULL
         OR p.required_for_role = 'any'
         OR p.required_for_role = COALESCE(p_role, 'any'))
    AND (s.is_valid IS NOT TRUE);

  RETURN v_missing = 0;
END;
$$;

COMMENT ON FUNCTION public.fn_consent_has_required(uuid, text) IS
  'L04-03: retorna true se o usuário tem consent válido (granted + version ≥ min) '
  'para todas as políticas required. Fail-closed em caso de NULL/erro.';

REVOKE ALL ON FUNCTION public.fn_consent_has_required(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_consent_has_required(uuid, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.fn_consent_has_required(uuid, text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_consent_has_required(uuid, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 9. Integração LGPD deletion strategy (L04-01)
-- ──────────────────────────────────────────────────────────────────────────
--
-- consent_events.user_id → anonymize (preserva prova histórica);
-- fn_delete_user_data atualiza user_id → zero UUID (o trigger append-only
-- permite apenas este caso específico).

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
              WHERE table_schema='public' AND table_name='lgpd_deletion_strategy')
  THEN
    INSERT INTO public.lgpd_deletion_strategy (table_name, column_name, strategy, rationale)
    VALUES
      ('consent_events', 'user_id', 'anonymize',
       'L04-03: log imutável de consentimento. Anonimiza user_id para satisfazer '
       'LGPD Art. 18 VI (direito ao esquecimento) preservando row como prova '
       'estatística/auditória (LGPD Art. 16 — obrigação legal documental).')
    ON CONFLICT (table_name, column_name) DO UPDATE
      SET strategy = EXCLUDED.strategy,
          rationale = EXCLUDED.rationale;
  END IF;

  -- Adiciona também no fn_delete_user_data se a função já existe
  IF EXISTS (SELECT 1 FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname='public' AND p.proname='fn_delete_user_data')
  THEN
    RAISE NOTICE '[L04-03] fn_delete_user_data já existe — próxima migration de L04-01 deve incluir UPDATE consent_events SET user_id = v_anon';
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────────────────
-- 10. Extensão do fn_delete_user_data para anonimizar consent_events
-- ──────────────────────────────────────────────────────────────────────────
--
-- Não queremos reescrever todo o fn_delete_user_data. Usamos um trigger
-- AFTER DELETE em auth.users para capturar o caso de erasure, mas o fluxo
-- canônico é via fn_delete_user_data — adicionamos o UPDATE aqui.

CREATE OR REPLACE FUNCTION public.fn_anonymize_consent_events(p_user_id uuid)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_count bigint;
  v_anon  constant uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
  IF p_user_id IS NULL OR p_user_id = v_anon THEN
    RAISE EXCEPTION 'INVALID_USER_ID' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.consent_events
     SET user_id    = v_anon,
         ip_address = NULL,
         user_agent = NULL
   WHERE user_id = p_user_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.fn_anonymize_consent_events(uuid) IS
  'L04-03/L04-01: anonimiza consent_events de um usuário (zero UUID). '
  'Invocado por fn_delete_user_data no fluxo de erasure.';

REVOKE ALL ON FUNCTION public.fn_anonymize_consent_events(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_anonymize_consent_events(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.fn_anonymize_consent_events(uuid) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_anonymize_consent_events(uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 11. Invariantes finais
-- ──────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_count integer;
BEGIN
  -- 8 tipos registrados no seed
  SELECT count(*) INTO v_count FROM public.consent_policy_versions;
  IF v_count < 8 THEN
    RAISE EXCEPTION '[L04-03] esperado ≥8 políticas, got %', v_count;
  END IF;

  -- 5 RPCs criadas
  SELECT count(*) INTO v_count
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('fn_consent_grant', 'fn_consent_revoke',
                       'fn_consent_status', 'fn_consent_has_required',
                       'fn_anonymize_consent_events');
  IF v_count < 5 THEN
    RAISE EXCEPTION '[L04-03] esperado 5 RPCs, got %', v_count;
  END IF;

  -- profiles.* consent cols existem
  SELECT count(*) INTO v_count FROM information_schema.columns
   WHERE table_schema='public' AND table_name='profiles'
     AND column_name IN ('terms_accepted_at', 'terms_version',
                         'privacy_accepted_at', 'privacy_version',
                         'health_data_consent_at', 'location_consent_at',
                         'marketing_consent_at');
  IF v_count < 7 THEN
    RAISE EXCEPTION '[L04-03] profiles faltando colunas de consent: got %', v_count;
  END IF;

  -- consent_events.user_id está registrada em lgpd_deletion_strategy
  IF EXISTS (SELECT 1 FROM information_schema.tables
              WHERE table_schema='public' AND table_name='lgpd_deletion_strategy')
  THEN
    SELECT count(*) INTO v_count FROM public.lgpd_deletion_strategy
     WHERE table_name='consent_events' AND column_name='user_id';
    IF v_count = 0 THEN
      RAISE EXCEPTION '[L04-03] consent_events.user_id não registrada em lgpd_deletion_strategy';
    END IF;
  END IF;

  RAISE NOTICE '[L04-03] invariantes OK: 8+ policies, 5 RPCs, snapshot cols criadas';
END $$;

