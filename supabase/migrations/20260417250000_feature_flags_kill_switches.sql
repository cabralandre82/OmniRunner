-- ═══════════════════════════════════════════════════════════════════════════
-- L06-06 — Feature flags como kill switches operacionais
--
-- Estende a tabela `feature_flags` (criada em 20260304950000) para suportar:
--   • scope (global / group:<uuid> / env:<staging|prod>)
--   • category (product, kill_switch, banner, experimental, operational)
--   • audit trail completo (quem, quando, antes/depois, motivo)
--   • PK em UUID `id` para casar com admin UI; (key, scope) UNIQUE
--   • helpers SQL (fn_feature_enabled, fn_assert_feature_enabled)
--   • seed dos 6 subsistemas financeiros + 1 banner
--
-- Convenção semântica (única para evitar confusão):
--   enabled = true  → "permitido / ligado"
--   enabled = false → "bloqueado / desligado / kill switch ativo"
--
-- Para "matar" um subsistema, set enabled=false. Para acionar banner de
-- manutenção, set enabled=true (banner.* tem semântica do nome — true=mostrar).
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Estender colunas (idempotente; backwards-compatible)
-- ───────────────────────────────────────────────────────────────────────────
ALTER TABLE public.feature_flags
  ADD COLUMN IF NOT EXISTS id          uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS scope       text NOT NULL DEFAULT 'global',
  ADD COLUMN IF NOT EXISTS category    text NOT NULL DEFAULT 'product',
  ADD COLUMN IF NOT EXISTS reason      text,
  ADD COLUMN IF NOT EXISTS updated_by  uuid REFERENCES auth.users(id);

-- Garantir CHECK de category (idempotente)
DO $check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'feature_flags_category_check'
  ) THEN
    ALTER TABLE public.feature_flags
      ADD CONSTRAINT feature_flags_category_check
      CHECK (category IN ('product','kill_switch','banner','experimental','operational'));
  END IF;
END
$check$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Reorganizar PK: id (UUID) é PK, (key, scope) é UNIQUE
-- ───────────────────────────────────────────────────────────────────────────
DO $pk$
BEGIN
  -- Drop old PK em key se ainda existe
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'feature_flags_pkey'
      AND conrelid = 'public.feature_flags'::regclass
      AND pg_get_constraintdef(oid) ILIKE 'PRIMARY KEY (key)'
  ) THEN
    ALTER TABLE public.feature_flags DROP CONSTRAINT feature_flags_pkey;
  END IF;

  -- Cria PK em id se ainda não existir
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.feature_flags'::regclass AND contype = 'p'
  ) THEN
    ALTER TABLE public.feature_flags ADD PRIMARY KEY (id);
  END IF;

  -- (key, scope) UNIQUE — substitui a PK antiga em key
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'feature_flags_key_scope_unique'
  ) THEN
    ALTER TABLE public.feature_flags
      ADD CONSTRAINT feature_flags_key_scope_unique UNIQUE (key, scope);
  END IF;
END
$pk$;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Audit log (immutable trail de toda mudança)
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.feature_flag_audit (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  flag_id         uuid,
  flag_key        text NOT NULL,
  flag_scope      text NOT NULL,
  action          text NOT NULL CHECK (action IN ('insert','update','delete')),
  old_enabled     boolean,
  new_enabled     boolean,
  old_rollout_pct integer,
  new_rollout_pct integer,
  reason          text,
  actor_user_id   uuid,
  actor_role      text,
  changed_at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.feature_flag_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ffa_platform_admin_read" ON public.feature_flag_audit;
CREATE POLICY "ffa_platform_admin_read"
  ON public.feature_flag_audit FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.platform_role = 'admin')
  );

GRANT SELECT ON public.feature_flag_audit TO authenticated;
GRANT ALL    ON public.feature_flag_audit TO service_role;

CREATE INDEX IF NOT EXISTS idx_ffa_flag_changed ON public.feature_flag_audit(flag_key, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_ffa_changed      ON public.feature_flag_audit(changed_at DESC);

-- Trigger
CREATE OR REPLACE FUNCTION public.fn_feature_flag_audit()
  RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_id   uuid := auth.uid();  -- NULL se via service_role direto
  v_actor_role text := current_setting('request.jwt.claims', true)::jsonb->>'role';
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.feature_flag_audit
      (flag_id, flag_key, flag_scope, action,
       old_enabled, new_enabled, old_rollout_pct, new_rollout_pct,
       reason, actor_user_id, actor_role)
    VALUES
      (NEW.id, NEW.key, NEW.scope, 'insert',
       NULL, NEW.enabled, NULL, NEW.rollout_pct,
       NEW.reason, COALESCE(NEW.updated_by, v_actor_id), v_actor_role);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Só audita se houve mudança material
    IF OLD.enabled IS DISTINCT FROM NEW.enabled
       OR OLD.rollout_pct IS DISTINCT FROM NEW.rollout_pct
       OR OLD.reason IS DISTINCT FROM NEW.reason THEN
      INSERT INTO public.feature_flag_audit
        (flag_id, flag_key, flag_scope, action,
         old_enabled, new_enabled, old_rollout_pct, new_rollout_pct,
         reason, actor_user_id, actor_role)
      VALUES
        (NEW.id, NEW.key, NEW.scope, 'update',
         OLD.enabled, NEW.enabled, OLD.rollout_pct, NEW.rollout_pct,
         NEW.reason, COALESCE(NEW.updated_by, v_actor_id), v_actor_role);
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.feature_flag_audit
      (flag_id, flag_key, flag_scope, action,
       old_enabled, new_enabled, old_rollout_pct, new_rollout_pct,
       reason, actor_user_id, actor_role)
    VALUES
      (OLD.id, OLD.key, OLD.scope, 'delete',
       OLD.enabled, NULL, OLD.rollout_pct, NULL,
       OLD.reason, v_actor_id, v_actor_role);
    RETURN OLD;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_feature_flag_audit ON public.feature_flags;
CREATE TRIGGER trg_feature_flag_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.feature_flags
  FOR EACH ROW EXECUTE FUNCTION public.fn_feature_flag_audit();

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Helper SQL functions
-- ───────────────────────────────────────────────────────────────────────────

-- Resolve flag para um escopo, com fallback global. Retorna a row mais
-- específica (prioridade: scope exato > 'global' > NULL).
CREATE OR REPLACE FUNCTION public.fn_feature_resolve(
  p_key   text,
  p_scope text DEFAULT 'global'
)
  RETURNS TABLE(
    enabled     boolean,
    rollout_pct integer,
    category    text,
    scope       text
  )
  LANGUAGE sql STABLE
  SET search_path = public, pg_temp
AS $$
  SELECT enabled, rollout_pct, category, scope
  FROM public.feature_flags
  WHERE key = p_key
    AND scope IN (p_scope, 'global')
  ORDER BY (scope = p_scope) DESC, scope ASC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.fn_feature_resolve(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_feature_resolve(text, text) TO authenticated, service_role;

-- Boolean simples: feature está ON?
-- p_default_when_missing = comportamento quando flag não existe (default true =
-- "fail open" — sistema continua operando mesmo sem flag cadastrada). Para
-- flags críticas como banners, callers devem passar false explicitamente.
CREATE OR REPLACE FUNCTION public.fn_feature_enabled(
  p_key                     text,
  p_scope                   text   DEFAULT 'global',
  p_default_when_missing    boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql STABLE
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_enabled boolean;
BEGIN
  SELECT r.enabled INTO v_enabled
  FROM public.fn_feature_resolve(p_key, p_scope) r;

  IF v_enabled IS NULL THEN
    RETURN p_default_when_missing;
  END IF;
  RETURN v_enabled;
END $$;
REVOKE ALL ON FUNCTION public.fn_feature_enabled(text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_feature_enabled(text, text, boolean)
  TO authenticated, service_role;

-- RPC para callers em SQL (RPCs em RPC) que querem RAISE em vez de check
-- manual. Útil para edge functions que recebem 503 padronizado.
CREATE OR REPLACE FUNCTION public.fn_assert_feature_enabled(
  p_key   text,
  p_scope text DEFAULT 'global'
)
  RETURNS void
  LANGUAGE plpgsql STABLE
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.fn_feature_enabled(p_key, p_scope, true) THEN
    RAISE EXCEPTION 'FEATURE_DISABLED: %', p_key
      USING ERRCODE = 'P0F01', HINT = 'kill_switch ativo — checar /platform/feature-flags';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.fn_assert_feature_enabled(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_assert_feature_enabled(text, text)
  TO authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. RLS UPDATE/INSERT — restringir a service_role e platform_admins
-- ───────────────────────────────────────────────────────────────────────────
-- Convenção do projeto: platform admins = profiles.platform_role = 'admin'.
-- service_role bypassa RLS então ops via runbook (SQL direto) sempre funciona.
DROP POLICY IF EXISTS "ff_platform_admin_write_insert" ON public.feature_flags;
CREATE POLICY "ff_platform_admin_write_insert"
  ON public.feature_flags FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.platform_role = 'admin')
  );

DROP POLICY IF EXISTS "ff_platform_admin_write_update" ON public.feature_flags;
CREATE POLICY "ff_platform_admin_write_update"
  ON public.feature_flags FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.platform_role = 'admin')
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.platform_role = 'admin')
  );

DROP POLICY IF EXISTS "ff_platform_admin_write_delete" ON public.feature_flags;
CREATE POLICY "ff_platform_admin_write_delete"
  ON public.feature_flags FOR DELETE
  USING (
    EXISTS (SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.platform_role = 'admin')
  );

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Seed: subsistemas financeiros (todos enabled=true por default — operação
--    normal). Para "matar" basta UPDATE enabled=false via UI ou SQL.
-- ───────────────────────────────────────────────────────────────────────────
INSERT INTO public.feature_flags (key, enabled, rollout_pct, category, metadata)
VALUES
  ('swap.enabled',                  true, 100, 'kill_switch',
   '{"description":"Marketplace B2B de swap de coins (sellers/buyers).",
     "subsystem":"swap","owner":"finance","runbook":"docs/runbooks/CUSTODY_INCIDENT_RUNBOOK.md"}'),
  ('custody.deposits.enabled',      true, 100, 'kill_switch',
   '{"description":"Aceitar novos depósitos (Asaas → custody_accounts).",
     "subsystem":"custody","owner":"finance","runbook":"docs/runbooks/GATEWAY_OUTAGE_RUNBOOK.md"}'),
  ('custody.withdrawals.enabled',   true, 100, 'kill_switch',
   '{"description":"Aceitar novos saques de custódia (POST /api/custody/withdraw).",
     "subsystem":"custody","owner":"finance","runbook":"docs/runbooks/WITHDRAW_STUCK_RUNBOOK.md"}'),
  ('clearing.interclub.enabled',    true, 100, 'kill_switch',
   '{"description":"Settle automático entre grupos (clearing_settlements).",
     "subsystem":"clearing","owner":"finance","runbook":"docs/runbooks/CLEARING_STUCK_RUNBOOK.md"}'),
  ('distribute_coins.enabled',      true, 100, 'kill_switch',
   '{"description":"Emissão de coins para atletas (POST /api/distribute-coins).",
     "subsystem":"coins","owner":"finance","runbook":"docs/runbooks/CUSTODY_INCIDENT_RUNBOOK.md"}'),
  ('auto_topup.enabled',            true, 100, 'kill_switch',
   '{"description":"Recarga automática de custódia quando saldo < threshold.",
     "subsystem":"custody","owner":"finance","runbook":"docs/runbooks/CUSTODY_INCIDENT_RUNBOOK.md"}'),
  -- Banners operacionais (default=false — ativados sob incident)
  ('banner.gateway_outage',         false, 0,   'banner',
   '{"description":"Banner público: \"Estamos enfrentando intermitência no provedor de pagamentos.\"",
     "i18n_key":"banner.gateway_outage_message",
     "owner":"platform","runbook":"docs/runbooks/GATEWAY_OUTAGE_RUNBOOK.md"}'),
  ('banner.maintenance_mode',       false, 0,   'banner',
   '{"description":"Banner público: \"Plataforma em manutenção programada.\"",
     "i18n_key":"banner.maintenance_message",
     "owner":"platform","runbook":"docs/runbooks/DR_PROCEDURE.md"}')
ON CONFLICT (key, scope) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────────
-- 7. LGPD coverage: feature_flags.updated_by e feature_flag_audit.actor_user_id
--    são audit columns — preservar histórico ao deletar user (set null).
-- ───────────────────────────────────────────────────────────────────────────
DO $lgpd$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'lgpd_deletion_strategy'
  ) THEN
    INSERT INTO public.lgpd_deletion_strategy
      (table_name, column_name, strategy, rationale)
    VALUES
      ('feature_flags', 'updated_by', 'defensive_optional',
       'L06-06: audit trail de quem alterou kill switch operacional. '
       'Pode ser SET NULL na deleção do user — preserva log sem PII. '
       'Base legal: LGPD Art. 7 IX (legítimo interesse — audit ops).'),
      ('feature_flag_audit', 'actor_user_id', 'defensive_optional',
       'L06-06: log imutável de mudança de feature flag. Anonimização '
       '(SET NULL) preserva o evento sem expor o operador. Base legal: '
       'LGPD Art. 7 IX (audit ops) + Art. 16 II (obrigação legal de '
       'manter trilha de mudança em sistema financeiro).')
    ON CONFLICT (table_name, column_name) DO UPDATE
      SET strategy = EXCLUDED.strategy,
          rationale = EXCLUDED.rationale;
  END IF;
END
$lgpd$;

-- ───────────────────────────────────────────────────────────────────────────
-- 8. Backfill metadata em flags antigas (não destrutivo)
-- ───────────────────────────────────────────────────────────────────────────
UPDATE public.feature_flags
SET category = 'product'
WHERE category = 'product'
  AND key IN ('parks_enabled','matchmaking_enabled','wrapped_enabled',
              'running_dna_enabled','strava_import_enabled','trainingpeaks_enabled');

-- ───────────────────────────────────────────────────────────────────────────
-- 9. Invariants check (auto-test ao aplicar migration)
-- ───────────────────────────────────────────────────────────────────────────
DO $invariants$
DECLARE
  v_kill_switch_count integer;
  v_banner_count      integer;
  v_audit_works       boolean;
BEGIN
  SELECT COUNT(*) INTO v_kill_switch_count
  FROM public.feature_flags WHERE category = 'kill_switch';
  IF v_kill_switch_count < 6 THEN
    RAISE EXCEPTION '[L06-06] expected >= 6 kill_switch flags, got %', v_kill_switch_count;
  END IF;

  SELECT COUNT(*) INTO v_banner_count
  FROM public.feature_flags WHERE category = 'banner';
  IF v_banner_count < 2 THEN
    RAISE EXCEPTION '[L06-06] expected >= 2 banner flags, got %', v_banner_count;
  END IF;

  -- fn_feature_enabled deve retornar true para distribute_coins (default seed)
  IF NOT public.fn_feature_enabled('distribute_coins.enabled') THEN
    RAISE EXCEPTION '[L06-06] fn_feature_enabled smoke failed for distribute_coins.enabled';
  END IF;

  -- fn_feature_enabled deve retornar true para flag inexistente (fail-open default)
  IF NOT public.fn_feature_enabled('nonexistent.flag', 'global', true) THEN
    RAISE EXCEPTION '[L06-06] fn_feature_enabled fail-open default broken';
  END IF;

  -- fn_assert_feature_enabled deve passar para flag enabled
  PERFORM public.fn_assert_feature_enabled('distribute_coins.enabled');

  -- Audit trigger funciona? Insere e verifica
  INSERT INTO public.feature_flags (key, enabled, rollout_pct, category, reason)
  VALUES ('_smoke.audit_test', true, 100, 'experimental', 'L06-06 invariants check')
  ON CONFLICT (key, scope) DO UPDATE SET enabled = EXCLUDED.enabled, reason = EXCLUDED.reason;

  SELECT EXISTS (
    SELECT 1 FROM public.feature_flag_audit
    WHERE flag_key = '_smoke.audit_test' AND action IN ('insert','update')
  ) INTO v_audit_works;

  IF NOT v_audit_works THEN
    RAISE EXCEPTION '[L06-06] feature_flag_audit trigger não disparou';
  END IF;

  -- Cleanup smoke entry
  DELETE FROM public.feature_flags WHERE key = '_smoke.audit_test';
END
$invariants$;

COMMENT ON TABLE public.feature_flags IS
  'L06-06 — Feature flags (product rollouts) + kill switches operacionais. '
  'enabled=true significa "permitido". Para matar subsistema, set enabled=false. '
  'Audit em public.feature_flag_audit.';

COMMENT ON COLUMN public.feature_flags.category IS
  'product=rollout normal, kill_switch=desligar subsistema crítico, '
  'banner=mostrar mensagem pública, experimental=feature em teste, '
  'operational=config operacional não-feature.';

COMMENT ON COLUMN public.feature_flags.scope IS
  '"global" (default) | "group:<uuid>" | "env:<staging|prod>". '
  'Helpers fazem fallback do scope específico para global.';
