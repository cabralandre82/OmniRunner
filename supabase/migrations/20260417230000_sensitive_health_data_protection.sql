-- ══════════════════════════════════════════════════════════════════════════
-- L04-04 — LGPD Art. 11: proteção reforçada de dados pessoais sensíveis
--          (saúde, biométricos, localização precisa)
--
-- Referência auditoria:
--   docs/audit/findings/L04-04-dados-de-saude-biometricos-dados-sensiveis-lgpd-art.md
--   docs/audit/parts/03-clo-cpo.md [4.4]
--
-- Problema:
--   sessions, athlete_baselines, athlete_trends e runs armazenam frequência
--   cardíaca, pace, distância, trajetórias GPS e KPIs biométricos. LGPD Art. 11
--   classifica saúde + biométrico + localização precisa como dados SENSÍVEIS,
--   exigindo:
--     a) minimização (só quem precisa lê)
--     b) base legal específica (consentimento destacado OU execução contratual)
--     c) registro de acesso auditável
--     d) possibilidade de revogação granular
--   Estado atual:
--     - sessions_staff_read permite acesso por coach sem consent-check
--     - athlete_baselines/trends idem (coach OU assistant do grupo lê tudo)
--     - nenhum log de leitura cross-user
--     - nenhum gate de consentimento `coach_data_share`
--   Consequência: exposição sem prova de base legal → enforcement ANPD agravado.
--
-- Correção:
--   1. `sensitive_health_columns` — registry que declara quais (tabela, coluna)
--      carregam dado sensível LGPD Art. 11. Fonte-única para CI drift-check.
--   2. `sensitive_data_access_log` — log append-only de CADA leitura cross-user
--      mediada por RPC oficial (actor, subject, table, request_id, ip, ua, ts).
--   3. `fn_can_read_athlete_health(athlete_id)` — helper STABLE que retorna
--      true se caller é o próprio atleta OU (coach/assistant no grupo do atleta
--      E atleta tem consent `coach_data_share` válido). Used by RLS policies.
--   4. `fn_read_athlete_health_snapshot(athlete_id, request_id)` — RPC oficial
--      para dashboards coach: valida autorização, grava access_log, retorna
--      snapshot JSON (últimas baselines/trends/3 sessions com HR-range).
--   5. Hardening RLS:
--        - sessions: sessions_staff_read → sessions_coach_consent_read
--        - athlete_baselines: baselines_read → baselines_coach_consent_read
--        - athlete_trends: trends_read → trends_coach_consent_read
--        - runs: runs_coach_consent_read (nova policy — coach podia não ler
--          runs, agora lê sob consent)
--      Todas aplicam o filtro de consent via fn_can_read_athlete_health.
--   6. Auto-grant implícito: trigger ON INSERT em coaching_members registra
--      `coach_data_share` quando usuário é adicionado como `athlete` a um
--      grupo. Base legal: execução contratual (ao entrar no grupo o atleta
--      aceita o serviço da assessoria). Atleta pode revogar depois via
--      fn_consent_revoke → trigger move coaching_members role? Não; mantém o
--      vínculo mas RLS para de retornar dados.
--   7. Backfill para coaching_members pré-existentes: emite consent_events
--      source=`backfill` com timestamp = joined_at_ms.
--   8. `sensitive_data_access_log` entra em lgpd_deletion_strategy como
--      `anonymize` (actor_id + subject_id viram 00000000...). Preserva
--      cadeia de custódia auditável após erasure LGPD Art. 18 VI.
--   9. View `v_sensitive_health_coverage_gaps` — lista columns declaradas no
--      registry que não existem na DB (detecta drift em CI).
--
-- Compat:
--   - Dashboards coach que lêem direto `sessions`/`athlete_baselines` via
--     PostgREST CONTINUAM funcionando, porém agora exigem o atleta ter
--     consent `coach_data_share` válido (backfill cobre legado).
--   - Coach dashboards NOVOS devem preferir fn_read_athlete_health_snapshot
--     para garantir audit-trail (raw SELECTs não logam).
--   - Se atleta revogar `coach_data_share`, coach vê nada (fail-closed por
--     design — é o comportamento desejado pela LGPD).
-- ══════════════════════════════════════════════════════════════════════════


-- ──────────────────────────────────────────────────────────────────────────
-- 0. Estender consent_events.source para aceitar 'system' e 'backfill'
--    (L04-03 aceitava apenas {mobile, portal, edge_function, migration,
--     admin_override}; L04-04 precisa de auto-grant de `coach_data_share`
--     via trigger DB e backfill retroativo).
-- ──────────────────────────────────────────────────────────────────────────
ALTER TABLE public.consent_events
  DROP CONSTRAINT IF EXISTS consent_events_source_check;
ALTER TABLE public.consent_events
  ADD CONSTRAINT consent_events_source_check
  CHECK (source = ANY (ARRAY[
    'mobile', 'portal', 'edge_function',
    'migration', 'admin_override',
    'system',    -- trigger DB auto-grant (ex: coach_data_share ao ingressar em grupo)
    'backfill'   -- migration retroativa sobre dados legados
  ]));


-- ──────────────────────────────────────────────────────────────────────────
-- 1. Registry de colunas sensíveis (fonte-única LGPD Art. 11)
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sensitive_health_columns (
  table_name       text NOT NULL,
  column_name      text NOT NULL,
  sensitivity      text NOT NULL CHECK (sensitivity IN (
                     'health',        -- HR, VO2, injury, fitness level
                     'biometric',     -- cadence, stride, HRV
                     'location',      -- GPS precise trajectory
                     'physical_perf'  -- pace/speed inferível de saúde
                   )),
  legal_basis      text NOT NULL CHECK (legal_basis IN (
                     'consent',           -- Art. 11 II `a`
                     'contract',          -- Art. 11 II `b` (exec contratual)
                     'health_protection'  -- Art. 11 II `f`
                   )),
  rationale        text NOT NULL,
  added_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (table_name, column_name)
);

COMMENT ON TABLE public.sensitive_health_columns IS
  'L04-04: registry declarativo de colunas que carregam dado pessoal sensível LGPD Art. 11. Fonte-única para RLS, CI drift-check e runbook de incidentes.';

ALTER TABLE public.sensitive_health_columns ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.sensitive_health_columns FROM PUBLIC, anon;
GRANT SELECT ON public.sensitive_health_columns TO authenticated;
GRANT ALL ON public.sensitive_health_columns TO service_role;

DROP POLICY IF EXISTS "shc_read" ON public.sensitive_health_columns;
CREATE POLICY "shc_read" ON public.sensitive_health_columns
  FOR SELECT TO authenticated USING (true);

INSERT INTO public.sensitive_health_columns (table_name, column_name, sensitivity, legal_basis, rationale) VALUES
  ('sessions',          'avg_bpm',          'health',        'consent',  'Frequência cardíaca — dado de saúde Art. 11'),
  ('sessions',          'max_bpm',          'health',        'consent',  'FC máxima — dado de saúde Art. 11'),
  ('sessions',          'avg_pace_sec_km',  'physical_perf', 'contract', 'Pace — indicador de condicionamento físico'),
  ('sessions',          'points_path',      'location',      'consent',  'Trajetória GPS precisa Art. 11'),
  ('sessions',          'total_distance_m', 'physical_perf', 'contract', 'Distância percorrida — inferível de fitness'),
  ('sessions',          'moving_ms',        'physical_perf', 'contract', 'Tempo de movimento — inferível de fitness'),
  ('runs',              'distance_meters',  'physical_perf', 'contract', 'Distância — inferível de fitness'),
  ('runs',              'duration_seconds', 'physical_perf', 'contract', 'Duração — inferível de fitness'),
  ('athlete_baselines', 'value',            'health',        'consent',  'Baseline biométrico (HR, pace) por métrica'),
  ('athlete_trends',    'current_value',    'health',        'consent',  'Trend biométrico — saúde Art. 11'),
  ('athlete_trends',    'baseline_value',   'health',        'consent',  'Baseline referência — saúde Art. 11')
ON CONFLICT (table_name, column_name) DO UPDATE
  SET sensitivity = EXCLUDED.sensitivity,
      legal_basis = EXCLUDED.legal_basis,
      rationale   = EXCLUDED.rationale;

-- Colunas de tabelas opcionais (existem conforme migrations aplicadas):
--   support_tickets.self_reported_injuries → registrar se a tabela existir.
--   coaching_athlete_kpis_daily.* — idem.
--   running_dna_profiles.* — idem.
-- Em CI todas as tabelas existem; localmente o registry toleraria drift via view.
DO $bootstrap$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT tbl, col, sensitivity, rationale FROM (VALUES
      ('support_tickets',             'description',          'health',    'Descrição pode incluir lesão/queixa médica'),
      ('coaching_athlete_kpis_daily', 'hr_avg_bpm',           'health',    'KPI diário HR — saúde Art. 11'),
      ('coaching_athlete_kpis_daily', 'hr_max_bpm',           'health',    'KPI diário HR max — saúde Art. 11'),
      ('coaching_athlete_kpis_daily', 'avg_pace_sec_km',      'physical_perf', 'KPI diário pace — indicador fitness'),
      ('running_dna_profiles',        'profile_json',         'biometric', 'DNA biométrico inferido (cadência, stride)')
    ) AS t(tbl, col, sensitivity, rationale)
  LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.col
    ) THEN
      INSERT INTO public.sensitive_health_columns (table_name, column_name, sensitivity, legal_basis, rationale)
      VALUES (r.tbl, r.col, r.sensitivity,
              CASE WHEN r.sensitivity = 'physical_perf' THEN 'contract' ELSE 'consent' END,
              r.rationale)
      ON CONFLICT (table_name, column_name) DO NOTHING;
    END IF;
  END LOOP;
END
$bootstrap$;


-- ──────────────────────────────────────────────────────────────────────────
-- 2. Log append-only de acesso a dados sensíveis (cross-user only)
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sensitive_data_access_log (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id       uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'::uuid
                   REFERENCES auth.users(id) ON DELETE SET DEFAULT,
  subject_id     uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'::uuid
                   REFERENCES auth.users(id) ON DELETE SET DEFAULT,
  actor_role     text NOT NULL CHECK (actor_role IN ('self','coach','assistant','admin_master','service_role','other')),
  resource       text NOT NULL CHECK (resource IN (
                   'sessions', 'runs', 'athlete_baselines', 'athlete_trends',
                   'coaching_athlete_kpis_daily', 'running_dna_profiles',
                   'athlete_health_snapshot', 'support_tickets'
                 )),
  action         text NOT NULL DEFAULT 'read' CHECK (action IN ('read','export','share')),
  request_id     text,
  ip_address     inet,
  user_agent     text,
  row_count      integer,
  denied         boolean NOT NULL DEFAULT false,
  denial_reason  text,
  accessed_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.sensitive_data_access_log IS
  'L04-04: log append-only de leitura cross-user de dados sensíveis (LGPD Art. 11 e ANPD Guia de Segurança). Prova de auditoria: quem leu o quê e quando. user_ids anonimizam ao zero-uuid em erasure LGPD (preserva evidência).';

CREATE INDEX IF NOT EXISTS idx_sdal_subject_time
  ON public.sensitive_data_access_log (subject_id, accessed_at DESC);
CREATE INDEX IF NOT EXISTS idx_sdal_actor_time
  ON public.sensitive_data_access_log (actor_id, accessed_at DESC);
CREATE INDEX IF NOT EXISTS idx_sdal_denied
  ON public.sensitive_data_access_log (denied, accessed_at DESC) WHERE denied = true;

ALTER TABLE public.sensitive_data_access_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sensitive_data_access_log FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE ON public.sensitive_data_access_log FROM authenticated;
GRANT SELECT ON public.sensitive_data_access_log TO authenticated;
GRANT ALL  ON public.sensitive_data_access_log TO service_role;

DROP POLICY IF EXISTS "sdal_subject_read" ON public.sensitive_data_access_log;
CREATE POLICY "sdal_subject_read" ON public.sensitive_data_access_log
  FOR SELECT TO authenticated
  USING (subject_id = auth.uid());

-- Trigger append-only + PII-scrub em erasure
CREATE OR REPLACE FUNCTION public._sdal_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_zero constant uuid := '00000000-0000-0000-0000-000000000000'::uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'SDAL_APPEND_ONLY: DELETE not allowed on sensitive_data_access_log'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- Apenas permitir UPDATE que seja a anonimização ON DELETE SET DEFAULT
    -- sobre as colunas FK (actor_id/subject_id) — todo outro UPDATE é bloqueado.
    IF (NEW.actor_id   = v_zero AND OLD.actor_id   <> v_zero)
    OR (NEW.subject_id = v_zero AND OLD.subject_id <> v_zero) THEN
      -- scrub PII vinculado ao user anonimizado
      IF NEW.actor_id = v_zero AND OLD.actor_id <> v_zero THEN
        NEW.ip_address := NULL;
        NEW.user_agent := NULL;
      END IF;
      IF (NEW.accessed_at, NEW.resource, NEW.action, NEW.actor_role, NEW.row_count, NEW.denied)
         IS DISTINCT FROM
         (OLD.accessed_at, OLD.resource, OLD.action, OLD.actor_role, OLD.row_count, OLD.denied) THEN
        RAISE EXCEPTION 'SDAL_APPEND_ONLY: only FK nullification allowed on update'
          USING ERRCODE = '42501';
      END IF;
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'SDAL_APPEND_ONLY: UPDATE not allowed on sensitive_data_access_log'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sdal_append_only ON public.sensitive_data_access_log;
CREATE TRIGGER trg_sdal_append_only
  BEFORE UPDATE OR DELETE ON public.sensitive_data_access_log
  FOR EACH ROW EXECUTE FUNCTION public._sdal_append_only();


-- ──────────────────────────────────────────────────────────────────────────
-- 3. Helper STABLE: can caller read athlete health data?
-- ──────────────────────────────────────────────────────────────────────────
-- Regra:
--   a) athlete é ele mesmo       → sempre true (titular LGPD Art. 9 I)
--   b) caller é coach/assistant no mesmo grupo do atleta E atleta tem consent
--      `coach_data_share` válido → true
--   c) demais casos              → false (fail-closed)
-- STABLE para permitir inlining em políticas RLS sem overhead por-row severo.
CREATE OR REPLACE FUNCTION public.fn_can_read_athlete_health(p_athlete_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL OR p_athlete_id IS NULL THEN
    RETURN false;
  END IF;

  -- (a) Self-access — titular sempre lê o próprio dado
  IF v_caller = p_athlete_id THEN
    RETURN true;
  END IF;

  -- (b) Coach/assistant/admin_master no mesmo grupo E atleta consentiu
  RETURN EXISTS (
    SELECT 1
      FROM public.coaching_members cm_coach
      JOIN public.coaching_members cm_ath
        ON cm_ath.group_id = cm_coach.group_id
     WHERE cm_coach.user_id = v_caller
       AND cm_coach.role IN ('coach', 'assistant', 'admin_master')
       AND cm_ath.user_id = p_athlete_id
       AND cm_ath.role = 'athlete'
  )
  AND EXISTS (
    SELECT 1
      FROM public.v_user_consent_status v
     WHERE v.user_id = p_athlete_id
       AND v.consent_type = 'coach_data_share'
       AND v.is_valid = true
  );
END;
$$;

COMMENT ON FUNCTION public.fn_can_read_athlete_health(uuid) IS
  'L04-04: autorização fail-closed para leitura de dados sensíveis do atleta. Usada por políticas RLS (sessions/runs/baselines/trends) e pela RPC fn_read_athlete_health_snapshot.';

REVOKE ALL ON FUNCTION public.fn_can_read_athlete_health(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_can_read_athlete_health(uuid) TO authenticated, service_role;


-- ──────────────────────────────────────────────────────────────────────────
-- 4. RPC: fn_log_sensitive_access — helper para callers registrarem acesso
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_log_sensitive_access(
  p_subject_id    uuid,
  p_resource      text,
  p_action        text    DEFAULT 'read',
  p_row_count     integer DEFAULT NULL,
  p_denied        boolean DEFAULT false,
  p_denial_reason text    DEFAULT NULL,
  p_request_id    text    DEFAULT NULL,
  p_ip            inet    DEFAULT NULL,
  p_user_agent    text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '5s'
AS $$
DECLARE
  v_caller  uuid := auth.uid();
  v_role    text;
  v_id      uuid;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501';
  END IF;

  IF p_subject_id IS NULL THEN
    RAISE EXCEPTION 'SUBJECT_REQUIRED' USING ERRCODE = '22004';
  END IF;

  IF v_caller = p_subject_id THEN
    v_role := 'self';
  ELSE
    SELECT CASE
             WHEN cm.role = 'coach' THEN 'coach'
             WHEN cm.role = 'assistant' THEN 'assistant'
             WHEN cm.role = 'admin_master' THEN 'admin_master'
             ELSE 'other'
           END
      INTO v_role
      FROM public.coaching_members cm
      JOIN public.coaching_members cm2 ON cm2.group_id = cm.group_id
     WHERE cm.user_id = v_caller
       AND cm2.user_id = p_subject_id
       AND cm2.role = 'athlete'
     LIMIT 1;
    v_role := COALESCE(v_role, 'other');
  END IF;

  INSERT INTO public.sensitive_data_access_log (
    actor_id, subject_id, actor_role, resource, action,
    request_id, ip_address, user_agent, row_count, denied, denial_reason
  ) VALUES (
    v_caller, p_subject_id, v_role, p_resource, p_action,
    p_request_id, p_ip, p_user_agent, p_row_count, p_denied, p_denial_reason
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.fn_log_sensitive_access(uuid,text,text,integer,boolean,text,text,inet,text) IS
  'L04-04: helper SECURITY DEFINER para registrar leitura/export/share de dados sensíveis. Callable por edge fns e portal/API — RLS das tabelas não loga, portanto dashboards DEVEM chamar esta RPC.';

REVOKE ALL ON FUNCTION public.fn_log_sensitive_access(uuid,text,text,integer,boolean,text,text,inet,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_log_sensitive_access(uuid,text,text,integer,boolean,text,text,inet,text) TO authenticated, service_role;


-- ──────────────────────────────────────────────────────────────────────────
-- 5. RPC: fn_read_athlete_health_snapshot — accessor oficial com audit trail
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_read_athlete_health_snapshot(
  p_athlete_id uuid,
  p_request_id text DEFAULT NULL,
  p_ip         inet DEFAULT NULL,
  p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '5s'
AS $$
DECLARE
  v_caller    uuid := auth.uid();
  v_allowed   boolean;
  v_role      text;
  v_snapshot  jsonb;
  v_row_count integer := 0;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_athlete_id IS NULL THEN
    RAISE EXCEPTION 'ATHLETE_REQUIRED' USING ERRCODE = '22004';
  END IF;

  v_allowed := public.fn_can_read_athlete_health(p_athlete_id);

  IF v_caller = p_athlete_id THEN v_role := 'self';
  ELSE
    SELECT CASE
             WHEN cm.role = 'coach' THEN 'coach'
             WHEN cm.role = 'assistant' THEN 'assistant'
             WHEN cm.role = 'admin_master' THEN 'admin_master'
             ELSE 'other'
           END
      INTO v_role
      FROM public.coaching_members cm
      JOIN public.coaching_members cm2 ON cm2.group_id = cm.group_id
     WHERE cm.user_id = v_caller
       AND cm2.user_id = p_athlete_id
       AND cm2.role = 'athlete'
     LIMIT 1;
    v_role := COALESCE(v_role, 'other');
  END IF;

  IF NOT v_allowed THEN
    -- NOTA: denial é reportado via payload (não RAISE) para que o INSERT no
    -- access_log persista. Uma RAISE EXCEPTION faria rollback do log inteiro
    -- e a plataforma perderia a evidência da tentativa negada — prejudicando
    -- análise forense LGPD. Edge function / portal traduzem este payload em
    -- HTTP 403.
    INSERT INTO public.sensitive_data_access_log (
      actor_id, subject_id, actor_role, resource, action,
      request_id, ip_address, user_agent, denied, denial_reason
    ) VALUES (
      v_caller, p_athlete_id, v_role, 'athlete_health_snapshot', 'read',
      p_request_id, p_ip, p_user_agent, true,
      CASE
        WHEN v_role IN ('coach','assistant','admin_master')
          THEN 'missing_coach_data_share_consent'
        ELSE 'not_authorized'
      END
    );
    RETURN jsonb_build_object(
      'error',        'NOT_AUTHORIZED',
      'denial_reason', CASE
                         WHEN v_role IN ('coach','assistant','admin_master')
                           THEN 'missing_coach_data_share_consent'
                         ELSE 'not_authorized'
                       END,
      'athlete_id',   p_athlete_id
    );
  END IF;

  WITH recent_sessions AS (
    SELECT id, start_time_ms, total_distance_m, moving_ms,
           avg_pace_sec_km, avg_bpm, max_bpm, is_verified
      FROM public.sessions
     WHERE user_id = p_athlete_id
       AND status = 2
     ORDER BY start_time_ms DESC
     LIMIT 5
  ),
  latest_baselines AS (
    SELECT metric, value, sample_size, computed_at_ms
      FROM public.athlete_baselines
     WHERE user_id = p_athlete_id
     ORDER BY computed_at_ms DESC
     LIMIT 10
  ),
  latest_trends AS (
    SELECT metric, period, direction, current_value, baseline_value, change_percent
      FROM public.athlete_trends
     WHERE user_id = p_athlete_id
     ORDER BY analyzed_at_ms DESC
     LIMIT 10
  )
  SELECT jsonb_build_object(
    'athlete_id',  p_athlete_id,
    'generated_at', extract(epoch FROM now()) * 1000,
    'sessions',    COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM recent_sessions s), '[]'::jsonb),
    'baselines',   COALESCE((SELECT jsonb_agg(to_jsonb(b)) FROM latest_baselines b), '[]'::jsonb),
    'trends',      COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM latest_trends t), '[]'::jsonb)
  ) INTO v_snapshot;

  v_row_count := (jsonb_array_length(v_snapshot->'sessions')
                + jsonb_array_length(v_snapshot->'baselines')
                + jsonb_array_length(v_snapshot->'trends'));

  INSERT INTO public.sensitive_data_access_log (
    actor_id, subject_id, actor_role, resource, action,
    request_id, ip_address, user_agent, row_count, denied
  ) VALUES (
    v_caller, p_athlete_id, v_role, 'athlete_health_snapshot', 'read',
    p_request_id, p_ip, p_user_agent, v_row_count, false
  );

  RETURN v_snapshot;
END;
$$;

COMMENT ON FUNCTION public.fn_read_athlete_health_snapshot(uuid,text,inet,text) IS
  'L04-04: accessor oficial para dashboard coach — retorna snapshot JSON de últimas sessions/baselines/trends E grava em sensitive_data_access_log. Use SEMPRE em vez de SELECTs diretos para garantir audit trail LGPD.';

REVOKE ALL ON FUNCTION public.fn_read_athlete_health_snapshot(uuid,text,inet,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_read_athlete_health_snapshot(uuid,text,inet,text) TO authenticated, service_role;


-- ──────────────────────────────────────────────────────────────────────────
-- 6. Hardening RLS: substituir políticas staff-amplas por consent-gated
-- ──────────────────────────────────────────────────────────────────────────

-- 6.1 sessions: drop staff_read (amplo) → cria sessions_coach_consent_read
DROP POLICY IF EXISTS sessions_staff_read ON public.sessions;
DROP POLICY IF EXISTS sessions_coach_consent_read ON public.sessions;
CREATE POLICY sessions_coach_consent_read ON public.sessions
  FOR SELECT TO authenticated
  USING (
    auth.uid() <> user_id
    AND public.fn_can_read_athlete_health(user_id)
  );

-- 6.2 athlete_baselines: drop baselines_read (coach amplo) → dois policies
DROP POLICY IF EXISTS baselines_read ON public.athlete_baselines;
DROP POLICY IF EXISTS baselines_self_read ON public.athlete_baselines;
DROP POLICY IF EXISTS baselines_coach_consent_read ON public.athlete_baselines;

CREATE POLICY baselines_self_read ON public.athlete_baselines
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY baselines_coach_consent_read ON public.athlete_baselines
  FOR SELECT TO authenticated
  USING (
    auth.uid() <> user_id
    AND public.fn_can_read_athlete_health(user_id)
  );

-- 6.3 athlete_trends: idem
DROP POLICY IF EXISTS trends_read ON public.athlete_trends;
DROP POLICY IF EXISTS trends_self_read ON public.athlete_trends;
DROP POLICY IF EXISTS trends_coach_consent_read ON public.athlete_trends;

CREATE POLICY trends_self_read ON public.athlete_trends
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY trends_coach_consent_read ON public.athlete_trends
  FOR SELECT TO authenticated
  USING (
    auth.uid() <> user_id
    AND public.fn_can_read_athlete_health(user_id)
  );

-- 6.4 runs: adiciona policy coach sob consent (antes coach não lia)
DROP POLICY IF EXISTS runs_coach_consent_read ON public.runs;
CREATE POLICY runs_coach_consent_read ON public.runs
  FOR SELECT TO authenticated
  USING (
    auth.uid() <> user_id
    AND public.fn_can_read_athlete_health(user_id)
  );

-- 6.5 Tabelas opcionais (criadas em migrations específicas — cobrem se
--     existirem localmente/em CI).
DO $tighten$
DECLARE
  v_tables text[] := ARRAY['coaching_athlete_kpis_daily', 'running_dna_profiles'];
  t text;
BEGIN
  FOREACH t IN ARRAY v_tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = t)
       AND EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = t AND column_name = 'user_id') THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS %I_self_read ON public.%I', t, t);
      EXECUTE format('DROP POLICY IF EXISTS %I_coach_consent_read ON public.%I', t, t);
      EXECUTE format($p$CREATE POLICY %I_self_read ON public.%I
                         FOR SELECT TO authenticated USING (user_id = auth.uid())$p$, t, t);
      EXECUTE format($p$CREATE POLICY %I_coach_consent_read ON public.%I
                         FOR SELECT TO authenticated
                         USING (auth.uid() <> user_id
                                AND public.fn_can_read_athlete_health(user_id))$p$, t, t);
    END IF;
  END LOOP;
END
$tighten$;


-- ──────────────────────────────────────────────────────────────────────────
-- 7. Auto-grant de `coach_data_share` ao entrar no grupo como atleta
-- ──────────────────────────────────────────────────────────────────────────
-- Base legal: ao aceitar participar de um grupo de assessoria o atleta
-- consente implicitamente com a visualização de seus dados pelo coach
-- (execução contratual, LGPD Art. 7 V). Mantemos registro explícito via
-- consent_events (source='system') para rastreabilidade. Atleta pode
-- revogar via fn_consent_revoke (já existente em L04-03).
CREATE OR REPLACE FUNCTION public._auto_grant_coach_data_share()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.role <> 'athlete' THEN
    RETURN NEW;
  END IF;

  -- Já tem consent válido? Nada a fazer.
  IF EXISTS (
    SELECT 1 FROM public.v_user_consent_status v
     WHERE v.user_id = NEW.user_id
       AND v.consent_type = 'coach_data_share'
       AND v.is_valid = true
  ) THEN
    RETURN NEW;
  END IF;

  -- Bypass do trigger append-only: INSERT é permitido; registra grant
  -- automático como prova de aceite contratual.
  INSERT INTO public.consent_events (
    user_id, consent_type, action, version, source, granted_at
  ) VALUES (
    NEW.user_id, 'coach_data_share', 'granted',
    COALESCE((SELECT current_version FROM public.consent_policy_versions
                WHERE consent_type = 'coach_data_share'), '1.0'),
    'system',
    COALESCE(to_timestamp(NEW.joined_at_ms / 1000.0), now())
  );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public._auto_grant_coach_data_share() IS
  'L04-04: ao inserir atleta em coaching_members, registra consent_event `coach_data_share` source=system como prova de aceite contratual. Atleta pode revogar via fn_consent_revoke.';

DROP TRIGGER IF EXISTS trg_coaching_members_auto_consent ON public.coaching_members;
CREATE TRIGGER trg_coaching_members_auto_consent
  AFTER INSERT ON public.coaching_members
  FOR EACH ROW EXECUTE FUNCTION public._auto_grant_coach_data_share();


-- ──────────────────────────────────────────────────────────────────────────
-- 8. Backfill: atletas pré-existentes em grupos sem consent_event
-- ──────────────────────────────────────────────────────────────────────────
DO $backfill$
DECLARE
  v_count integer := 0;
  v_version text;
BEGIN
  SELECT current_version INTO v_version
    FROM public.consent_policy_versions
   WHERE consent_type = 'coach_data_share';
  v_version := COALESCE(v_version, '1.0');

  INSERT INTO public.consent_events (
    user_id, consent_type, action, version, source, granted_at
  )
  SELECT DISTINCT ON (cm.user_id)
         cm.user_id,
         'coach_data_share',
         'granted',
         v_version,
         'backfill',
         COALESCE(to_timestamp(cm.joined_at_ms / 1000.0), now())
    FROM public.coaching_members cm
   WHERE cm.role = 'athlete'
     AND NOT EXISTS (
       SELECT 1 FROM public.consent_events ce
        WHERE ce.user_id = cm.user_id
          AND ce.consent_type = 'coach_data_share'
     );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'L04-04 backfill: % consent_event(s) `coach_data_share` granted via backfill', v_count;
END
$backfill$;


-- ──────────────────────────────────────────────────────────────────────────
-- 9. LGPD deletion strategy — sensitive_data_access_log
-- ──────────────────────────────────────────────────────────────────────────
DO $lgpd$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'lgpd_deletion_strategy'
  ) THEN
    INSERT INTO public.lgpd_deletion_strategy (table_name, column_name, strategy, rationale)
    VALUES
      ('sensitive_data_access_log', 'actor_id',   'anonymize',
       'L04-04: log imutável de leitura de dado sensível. Anonimiza actor_id para LGPD Art. 18 VI preservando evidência cross-reference de auditoria (ANPD Guia de Segurança).'),
      ('sensitive_data_access_log', 'subject_id', 'anonymize',
       'L04-04: idem — preserva registro de QUE houve leitura, sem expor quem foi titular.')
    ON CONFLICT (table_name, column_name) DO UPDATE
      SET strategy = EXCLUDED.strategy,
          rationale = EXCLUDED.rationale;
  END IF;
END
$lgpd$;


-- ──────────────────────────────────────────────────────────────────────────
-- 10. View v_sensitive_health_coverage_gaps — CI drift detector
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_sensitive_health_coverage_gaps AS
SELECT
  shc.table_name,
  shc.column_name,
  shc.sensitivity,
  shc.legal_basis,
  CASE
    WHEN t.table_name IS NULL THEN 'table_missing'
    WHEN c.column_name IS NULL THEN 'column_missing'
    WHEN NOT COALESCE(pt.rowsecurity, false) THEN 'rls_disabled'
    ELSE 'ok'
  END AS status
FROM public.sensitive_health_columns shc
LEFT JOIN information_schema.tables t
  ON t.table_schema = 'public' AND t.table_name = shc.table_name
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public' AND c.table_name = shc.table_name AND c.column_name = shc.column_name
LEFT JOIN pg_tables pt
  ON pt.schemaname = 'public' AND pt.tablename = shc.table_name;

COMMENT ON VIEW public.v_sensitive_health_coverage_gaps IS
  'L04-04: status por (tabela, coluna) do registry vs DB real. Status = ok em CI; qualquer outro valor indica drift que deve bloquear deploy.';

REVOKE ALL ON public.v_sensitive_health_coverage_gaps FROM PUBLIC, anon;
GRANT SELECT ON public.v_sensitive_health_coverage_gaps TO authenticated, service_role;


-- ──────────────────────────────────────────────────────────────────────────
-- 11. Invariantes finais
-- ──────────────────────────────────────────────────────────────────────────
DO $invariant$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.sensitive_health_columns;
  IF v_count < 11 THEN
    RAISE EXCEPTION 'L04-04 invariant: sensitive_health_columns registry has only % rows (expected >= 11)', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM public.consent_policy_versions
    WHERE consent_type = 'coach_data_share' AND is_required IS NOT NULL;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'L04-04 invariant: consent_policy_versions must contain `coach_data_share` (L04-03 dependency)';
  END IF;

  -- RLS policies instaladas nos 4 alvos principais
  SELECT count(*) INTO v_count FROM pg_policies
   WHERE schemaname = 'public'
     AND (
       (tablename = 'sessions'           AND policyname = 'sessions_coach_consent_read') OR
       (tablename = 'athlete_baselines'  AND policyname = 'baselines_coach_consent_read') OR
       (tablename = 'athlete_trends'     AND policyname = 'trends_coach_consent_read') OR
       (tablename = 'runs'               AND policyname = 'runs_coach_consent_read')
     );
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'L04-04 invariant: expected 4 coach_consent_read policies, found %', v_count;
  END IF;
END
$invariant$;
