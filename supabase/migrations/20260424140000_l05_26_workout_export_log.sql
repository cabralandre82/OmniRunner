-- ============================================================================
-- L05-26 — coaching_workout_export_log: spine de delivery confirmation para .fit
--
-- Antes desta migration não registrávamos nada quando o .fit era gerado
-- (nem pelo app do atleta via Edge Function, nem pelo portal do coach
-- via a rota adicionada em L05-25). Coach não tinha como saber "quem
-- puxou o treino esta semana", suporte não tinha pivot, e qualquer bug
-- do encoder (L05-21/22/23) ficava invisível por meses.
--
-- Esta tabela é insert-only, RLS dupla (staff vê rows do grupo; atleta
-- vê só próprias). A view `v_assignment_last_export` projeta o último
-- evento por assignment, usada pelo portal na página de atribuições.
--
-- Quando L22-10 (Apple WorkoutKit / Connect IQ nativo) puder pingar
-- `kind='delivered'`, essa tabela já é o destino — o CHECK no campo
-- `kind` inclui 'delivered' desde agora para evitar migration futura.
--
-- DECISAO L05-26
-- ============================================================================

BEGIN;

-- ─── 1. Tabela ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.coaching_workout_export_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  actor_user_id   uuid NOT NULL REFERENCES auth.users(id),
  template_id     uuid NOT NULL REFERENCES public.coaching_workout_templates(id) ON DELETE CASCADE,
  assignment_id   uuid REFERENCES public.coaching_workout_assignments(id) ON DELETE SET NULL,
  surface         text NOT NULL
    CHECK (surface IN ('app', 'portal')),
  kind            text NOT NULL DEFAULT 'generated'
    CHECK (kind IN ('generated', 'shared', 'delivered', 'failed')),
  bytes           int,
  device_hint     text
    CHECK (device_hint IS NULL OR device_hint IN (
      'garmin', 'coros', 'suunto', 'polar', 'apple_watch', 'wear_os', 'other'
    )),
  share_target    text,
  error_code      text,
  created_at      timestamptz NOT NULL DEFAULT now(),

  -- Se kind='failed', error_code é obrigatório (sem isso o log é inútil).
  CONSTRAINT chk_failed_requires_error_code
    CHECK (kind <> 'failed' OR (error_code IS NOT NULL AND length(error_code) > 0)),

  -- bytes só faz sentido em 'generated' / 'shared'. 'failed' tem NULL.
  CONSTRAINT chk_bytes_non_negative
    CHECK (bytes IS NULL OR bytes >= 0)
);

COMMENT ON TABLE public.coaching_workout_export_log IS
  'Insert-only log de gerações de .fit (app + portal). Spine de delivery confirmation. L05-26.';
COMMENT ON COLUMN public.coaching_workout_export_log.surface IS
  'Origem: "app" (atleta no Flutter) ou "portal" (coach baixando pelo web).';
COMMENT ON COLUMN public.coaching_workout_export_log.kind IS
  'generated=bytes prontos; shared=SharePlus retornou OK (futuro); delivered=watch ACK via WorkoutKit/Connect IQ (Wave C); failed=erro.';
COMMENT ON COLUMN public.coaching_workout_export_log.device_hint IS
  'Tipo de relógio conhecido no momento da geração (via watch_type ou device_link).';

-- ─── 2. Índices ────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_export_log_assignment
  ON public.coaching_workout_export_log (assignment_id, created_at DESC)
  WHERE assignment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_export_log_template
  ON public.coaching_workout_export_log (template_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_export_log_group_created
  ON public.coaching_workout_export_log (group_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_export_log_actor
  ON public.coaching_workout_export_log (actor_user_id, created_at DESC);

-- ─── 3. RLS ────────────────────────────────────────────────────────────────

ALTER TABLE public.coaching_workout_export_log ENABLE ROW LEVEL SECURITY;

-- 3.1 Staff lê rows do próprio grupo
DROP POLICY IF EXISTS "staff_export_log_select" ON public.coaching_workout_export_log;
CREATE POLICY "staff_export_log_select"
  ON public.coaching_workout_export_log FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_export_log.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 3.2 Atleta lê apenas as próprias rows (para "meu histórico de envio")
DROP POLICY IF EXISTS "athlete_export_log_select_own" ON public.coaching_workout_export_log;
CREATE POLICY "athlete_export_log_select_own"
  ON public.coaching_workout_export_log FOR SELECT USING (
    actor_user_id = auth.uid()
  );

-- 3.3 Insert: actor_user_id deve casar com auth.uid() E deve ser membro do grupo
DROP POLICY IF EXISTS "self_export_log_insert" ON public.coaching_workout_export_log;
CREATE POLICY "self_export_log_insert"
  ON public.coaching_workout_export_log FOR INSERT WITH CHECK (
    actor_user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_export_log.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- Sem policies de UPDATE/DELETE: append-only.

-- ─── 4. View: último evento por assignment ─────────────────────────────────

-- Projeção DISTINCT ON (assignment_id) ORDER BY created_at DESC.
-- View com SECURITY INVOKER (default PG15+) → herda RLS do caller.
CREATE OR REPLACE VIEW public.v_assignment_last_export AS
SELECT DISTINCT ON (assignment_id)
  assignment_id,
  group_id,
  template_id,
  actor_user_id,
  surface,
  kind,
  device_hint,
  bytes,
  created_at AS last_export_at
FROM public.coaching_workout_export_log
WHERE assignment_id IS NOT NULL
ORDER BY assignment_id, created_at DESC;

COMMENT ON VIEW public.v_assignment_last_export IS
  'Último evento de export (.fit) por assignment. Fonte: coaching_workout_export_log. L05-26.';

GRANT SELECT ON public.v_assignment_last_export TO authenticated;

-- ─── 5. Self-check ─────────────────────────────────────────────────────────

DO $selfcheck$
DECLARE
  v_columns int;
  v_policies int;
  v_view int;
BEGIN
  SELECT count(*) INTO v_columns
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'coaching_workout_export_log';
  IF v_columns < 10 THEN
    RAISE EXCEPTION '[L05-26.self_check] tabela não tem todas as colunas (expected>=10, got %)', v_columns;
  END IF;

  SELECT count(*) INTO v_policies
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'coaching_workout_export_log';
  IF v_policies < 3 THEN
    RAISE EXCEPTION '[L05-26.self_check] esperava >=3 policies (staff/athlete/insert), encontrou %', v_policies;
  END IF;

  SELECT count(*) INTO v_view
  FROM information_schema.views
  WHERE table_schema = 'public'
    AND table_name = 'v_assignment_last_export';
  IF v_view <> 1 THEN
    RAISE EXCEPTION '[L05-26.self_check] view v_assignment_last_export ausente';
  END IF;

  -- CHECK negativa: kind='failed' sem error_code deve ser rejeitado
  BEGIN
    INSERT INTO public.coaching_workout_export_log
      (group_id, actor_user_id, template_id, surface, kind, error_code)
    VALUES
      -- IDs bobos; vamos receber violação de FK ou de CHECK. Queremos CHECK primeiro.
      ('00000000-0000-0000-0000-000000000000',
       '00000000-0000-0000-0000-000000000000',
       '00000000-0000-0000-0000-000000000000',
       'app', 'failed', NULL);
    RAISE EXCEPTION '[L05-26.self_check] CHECK chk_failed_requires_error_code não rejeitou failed sem error_code';
  EXCEPTION
    WHEN check_violation THEN
      -- Esperado.
      NULL;
    WHEN foreign_key_violation THEN
      -- Em alguns setups PG o FK pode ser checado antes do CHECK; não é ideal
      -- mas não queremos falhar a migration por isso (o CHECK ainda está lá).
      RAISE NOTICE '[L05-26.self_check] FK checada antes do CHECK (aceitável)';
  END;
END
$selfcheck$;

COMMIT;
