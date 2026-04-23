-- ═══════════════════════════════════════════════════════════════════════════
-- L12-05 — auto-topup-hourly: cap diário de cobrança automática
--
-- Problema (Lente 12 — Cron/Scheduler, item 12.5):
--   `auto-topup-cron` roda de hora em hora e chama `auto-topup-check` para
--   cada grupo com `enabled=true`. As salvaguardas pré-fix eram:
--     • cooldown 24h (last_triggered_at — atualizado APÓS Stripe sucesso,
--       então race window = duração da chamada Stripe ~5-30s)
--     • monthly cap (max_per_month, default 3, max absoluto 10)
--   Mas: NÃO havia cap diário. Cenário-de-fraude realista:
--     1. Atleta admin_master comprometido OU bug em settings que zere
--        `last_triggered_at` repetidamente.
--     2. `auto-topup-check` é também invocado INLINE após cada token-debit
--        (ver header da fn). Burst de N debits em <1min → N invocações
--        paralelas, todas leem `last_triggered_at=NULL`, todas passam o
--        cooldown check (race), todas criam PaymentIntent → cobrança 24×/dia.
--     3. Mesmo sem race: max_per_month=10 + cooldown 24h limita a ~10/mês,
--        mas o ataque "1 cobrança/dia × 30 dias" ainda é teoricamente
--        possível se o atacante manipula `last_triggered_at`.
--   Sem cap diário em USD/BRL absoluto: um pacote default ~R$ 200 × 24
--   cobranças = R$ 4.800/dia indevidos no cartão do cliente, com refund
--   manual via Stripe + suporte a um cliente já desconfiado.
--
-- Defesa em profundidade — esta migration adiciona:
--   • Cap diário em BRL (default R$ 500/dia/grupo) e cap diário em
--     contagem (default 3 cobranças/dia/grupo, máximo absoluto 24 — o
--     cron roda hourly). Conservador: tunável por admin_master mas com
--     defaults que cobrem 95% dos casos legítimos.
--   • Janela "hoje" no TZ por-conta (default America/Sao_Paulo) — coerente
--     com L05-09 custody daily cap. Tesoureiro pensa em "00:00 BRT", não
--     "00:00 UTC".
--   • Atomização do guardrail via `fn_apply_auto_topup_daily_cap` chamada
--     ANTES da PaymentIntent.create no edge function. RAISE P0010 com
--     hint estruturado.
--   • Audit table dedicada `billing_auto_topup_cap_changes` para CFO
--     investigar mudanças (CFO ↔ admin_master conversation thread).
--   • RPC canônica `fn_set_auto_topup_daily_cap` exige reason >= 10 chars
--     (postmortem obrigatório quando cap é elevado).
--
-- Política contábil:
--   Janela conta `billing_purchases` com `source='auto_topup'` AND
--   `status IN ('pending','paid','fulfilled')` no intervalo do TZ. Status
--   'cancelled' NÃO conta (Stripe declined ou rolled back via fn_fulfill).
--
-- Backwards compat:
--   Aditivo: 5 colunas novas com DEFAULT, 3 funções novas, 1 tabela
--   audit nova. `auto-topup-check` ganha 1 chamada nova ao RPC; se a RPC
--   estiver ausente (deploy parcial — não acontece em prod), edge function
--   continua funcionando (skip cap check com WARN log).
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Schema: billing_auto_topup_settings ganha 5 colunas
-- ───────────────────────────────────────────────────────────────────────────
ALTER TABLE public.billing_auto_topup_settings
  ADD COLUMN IF NOT EXISTS daily_charge_cap_brl numeric(10,2)
    NOT NULL DEFAULT 500.00
    CHECK (daily_charge_cap_brl >= 0);

ALTER TABLE public.billing_auto_topup_settings
  ADD COLUMN IF NOT EXISTS daily_max_charges integer
    NOT NULL DEFAULT 3
    CHECK (daily_max_charges >= 1 AND daily_max_charges <= 24);

ALTER TABLE public.billing_auto_topup_settings
  ADD COLUMN IF NOT EXISTS daily_limit_timezone text
    NOT NULL DEFAULT 'America/Sao_Paulo';

ALTER TABLE public.billing_auto_topup_settings
  ADD COLUMN IF NOT EXISTS daily_limit_updated_at timestamptz;

ALTER TABLE public.billing_auto_topup_settings
  ADD COLUMN IF NOT EXISTS daily_limit_updated_by uuid
    REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.billing_auto_topup_settings.daily_charge_cap_brl IS
  'L12-05: teto diário (BRL) de cobranças auto-topup PENDING+PAID+FULFILLED. '
  'Default 500.00. Zero = auto-topup bloqueado. Alterar via '
  'fn_set_auto_topup_daily_cap (audit-trailed).';

COMMENT ON COLUMN public.billing_auto_topup_settings.daily_max_charges IS
  'L12-05: teto diário (count) de cobranças auto-topup. Default 3, '
  'máximo absoluto 24 (cron roda hourly). Defesa contra burst '
  'de invocações inline pós token-debit.';

COMMENT ON COLUMN public.billing_auto_topup_settings.daily_limit_timezone IS
  'L12-05: timezone IANA usada para definir a janela "hoje" do cap. '
  'Default America/Sao_Paulo (produto BR-first). Coerente com L05-09.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Audit table — histórico de mudanças do cap
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.billing_auto_topup_cap_changes (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id                 uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  previous_cap_brl         numeric(10,2) NOT NULL,
  new_cap_brl              numeric(10,2) NOT NULL CHECK (new_cap_brl >= 0),
  previous_max_charges     integer NOT NULL,
  new_max_charges          integer NOT NULL CHECK (new_max_charges >= 1 AND new_max_charges <= 24),
  previous_timezone        text NOT NULL,
  new_timezone             text NOT NULL,
  actor_user_id            uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason                   text NOT NULL CHECK (length(trim(reason)) >= 10),
  idempotency_key          text,
  changed_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auto_topup_cap_changes_group
  ON public.billing_auto_topup_cap_changes(group_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_auto_topup_cap_changes_actor
  ON public.billing_auto_topup_cap_changes(actor_user_id, changed_at DESC);

-- Idempotency unique partial — replays seguros mesmo sob race condition
CREATE UNIQUE INDEX IF NOT EXISTS uq_auto_topup_cap_changes_idem
  ON public.billing_auto_topup_cap_changes(group_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

ALTER TABLE public.billing_auto_topup_cap_changes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auto_topup_cap_changes_admin_master_read"
  ON public.billing_auto_topup_cap_changes;

CREATE POLICY "auto_topup_cap_changes_admin_master_read"
  ON public.billing_auto_topup_cap_changes
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_auto_topup_cap_changes.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

REVOKE ALL ON TABLE public.billing_auto_topup_cap_changes FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.billing_auto_topup_cap_changes TO authenticated;
GRANT ALL ON TABLE public.billing_auto_topup_cap_changes TO service_role;

COMMENT ON TABLE public.billing_auto_topup_cap_changes IS
  'L12-05: histórico de alterações em billing_auto_topup_settings.daily_*. '
  'Cada mudança via fn_set_auto_topup_daily_cap grava 1 row aqui. '
  'CFO usa para reconciliação e investigação de fraude.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. fn_check_auto_topup_daily_window — read-only preview
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_check_auto_topup_daily_window(
  p_group_id        uuid,
  p_charge_amount_brl numeric DEFAULT 0
)
  RETURNS TABLE(
    current_count_today    integer,
    daily_max_charges      integer,
    available_count        integer,
    current_total_brl      numeric,
    daily_charge_cap_brl   numeric,
    available_brl          numeric,
    would_exceed_count     boolean,
    would_exceed_total     boolean,
    would_exceed           boolean,
    window_start_utc       timestamptz,
    window_end_utc         timestamptz,
    timezone               text
  )
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_tz             text;
  v_cap_brl        numeric(10,2);
  v_max_count      integer;
  v_window_start   timestamptz;
  v_window_end     timestamptz;
  v_current_count  integer;
  v_current_total  numeric(10,2);
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_group_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_charge_amount_brl IS NULL OR p_charge_amount_brl < 0 THEN
    RAISE EXCEPTION 'p_charge_amount_brl must be >= 0' USING ERRCODE = 'P0001';
  END IF;

  SELECT s.daily_limit_timezone, s.daily_charge_cap_brl, s.daily_max_charges
    INTO v_tz, v_cap_brl, v_max_count
  FROM public.billing_auto_topup_settings s
  WHERE s.group_id = p_group_id;

  IF v_tz IS NULL THEN
    -- Settings não existem (auto-topup nunca habilitado). Defaults
    -- conservadores coerentes com a coluna DEFAULT.
    v_tz        := 'America/Sao_Paulo';
    v_cap_brl   := 500.00;
    v_max_count := 3;
  END IF;

  v_window_start := (date_trunc('day', now() AT TIME ZONE v_tz)) AT TIME ZONE v_tz;
  v_window_end   := v_window_start + interval '1 day';

  -- Conta cobranças PENDING+PAID+FULFILLED no TZ. CANCELLED (Stripe
  -- decline ou rollback) NÃO conta — não foi cobrado de fato.
  SELECT
    COALESCE(COUNT(*), 0)::integer,
    COALESCE(SUM(p.price_cents), 0)::numeric / 100.0
    INTO v_current_count, v_current_total
  FROM public.billing_purchases p
  WHERE p.group_id = p_group_id
    AND p.source = 'auto_topup'
    AND p.status IN ('pending', 'paid', 'fulfilled')
    AND p.currency = 'BRL'
    AND p.created_at >= v_window_start
    AND p.created_at < v_window_end;

  RETURN QUERY
  SELECT
    v_current_count,
    v_max_count,
    GREATEST(v_max_count - v_current_count, 0),
    v_current_total,
    v_cap_brl,
    GREATEST(v_cap_brl - v_current_total, 0)::numeric(10,2),
    (v_current_count + 1 > v_max_count),
    (v_current_total + p_charge_amount_brl > v_cap_brl),
    ((v_current_count + 1 > v_max_count)
      OR (v_current_total + p_charge_amount_brl > v_cap_brl)),
    v_window_start,
    v_window_end,
    v_tz;
END $$;

REVOKE ALL ON FUNCTION public.fn_check_auto_topup_daily_window(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_check_auto_topup_daily_window(uuid, numeric) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_check_auto_topup_daily_window(uuid, numeric) IS
  'L12-05: read-only preview da janela diária de auto-topup (count, total, '
  'caps, would_exceed). NÃO altera estado.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. fn_apply_auto_topup_daily_cap — guardrail (RAISES on breach)
--    Chamado pelo edge function `auto-topup-check` ANTES do
--    `stripe.paymentIntents.create`. Se P0010, edge function pula a
--    PaymentIntent e devolve {triggered: false, reason: 'daily_cap_reached'}.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_apply_auto_topup_daily_cap(
  p_group_id          uuid,
  p_charge_amount_brl numeric
)
  RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_check record;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_group_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_charge_amount_brl IS NULL OR p_charge_amount_brl <= 0 THEN
    RAISE EXCEPTION 'p_charge_amount_brl must be > 0' USING ERRCODE = 'P0001';
  END IF;

  SELECT *
    INTO v_check
  FROM public.fn_check_auto_topup_daily_window(p_group_id, p_charge_amount_brl);

  IF v_check.would_exceed THEN
    RAISE EXCEPTION
      'AUTO_TOPUP_DAILY_CAP_EXCEEDED: group=% count=%/% total_brl=%/% tz=%',
      p_group_id,
      v_check.current_count_today + 1,
      v_check.daily_max_charges,
      v_check.current_total_brl + p_charge_amount_brl,
      v_check.daily_charge_cap_brl,
      v_check.timezone
      USING
        ERRCODE = 'P0010',
        HINT    = format(
          'Cap diário atingido (count %s/%s OR total R$ %s/%s atingido na janela %s). '
          'Aguarde a próxima janela ou suba o cap em /portal/settings (admin_master) ou '
          'PATCH /api/platform/auto-topup/[groupId]/daily-cap (platform admin). '
          'Runbook: AUTO_TOPUP_DAILY_CAP_RUNBOOK.',
          v_check.current_count_today + 1,
          v_check.daily_max_charges,
          v_check.current_total_brl + p_charge_amount_brl,
          v_check.daily_charge_cap_brl,
          v_check.timezone
        );
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.fn_apply_auto_topup_daily_cap(uuid, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_apply_auto_topup_daily_cap(uuid, numeric) TO service_role;

COMMENT ON FUNCTION public.fn_apply_auto_topup_daily_cap(uuid, numeric) IS
  'L12-05: aplica cap diário; RAISES P0010 AUTO_TOPUP_DAILY_CAP_EXCEEDED se '
  'a próxima cobrança ultrapassaria count OR total. Chamado por '
  'auto-topup-check edge function ANTES de Stripe.paymentIntents.create.';

-- ───────────────────────────────────────────────────────────────────────────
-- 5. fn_set_auto_topup_daily_cap — atualiza cap + grava audit
--    Idempotente via (group_id, idempotency_key) UNIQUE partial.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_auto_topup_daily_cap(
  p_group_id          uuid,
  p_new_cap_brl       numeric,
  p_new_max_charges   integer,
  p_actor_user_id     uuid,
  p_reason            text,
  p_timezone          text DEFAULT NULL,
  p_idempotency_key   text DEFAULT NULL
)
  RETURNS TABLE(
    out_group_id              uuid,
    out_previous_cap_brl      numeric,
    out_new_cap_brl           numeric,
    out_previous_max_charges  integer,
    out_new_max_charges       integer,
    out_previous_timezone     text,
    out_new_timezone          text,
    out_changed_at            timestamptz,
    out_was_idempotent        boolean
  )
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_settings   record;
  v_target_tz  text;
  v_now        timestamptz := now();
  v_replay     record;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_group_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'p_actor_user_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_new_cap_brl IS NULL OR p_new_cap_brl < 0 THEN
    RAISE EXCEPTION 'p_new_cap_brl must be >= 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_new_max_charges IS NULL
     OR p_new_max_charges < 1
     OR p_new_max_charges > 24 THEN
    RAISE EXCEPTION 'p_new_max_charges must be between 1 and 24' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'p_reason must be >= 10 chars (postmortem obrigatório)'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NOT NULL AND length(trim(p_idempotency_key)) < 8 THEN
    RAISE EXCEPTION 'p_idempotency_key must be NULL or >= 8 chars'
      USING ERRCODE = 'P0001';
  END IF;

  -- TZ: preserva o atual se p_timezone IS NULL; caso contrário valida.
  IF p_timezone IS NOT NULL THEN
    BEGIN
      PERFORM (now() AT TIME ZONE p_timezone);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'p_timezone is not a valid IANA timezone: %', p_timezone
        USING ERRCODE = 'P0001';
    END;
  END IF;

  -- Idempotency early-return.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT c.previous_cap_brl, c.new_cap_brl,
           c.previous_max_charges, c.new_max_charges,
           c.previous_timezone, c.new_timezone, c.changed_at
      INTO v_replay
    FROM public.billing_auto_topup_cap_changes c
    WHERE c.group_id = p_group_id
      AND c.idempotency_key = p_idempotency_key
    LIMIT 1;

    IF FOUND THEN
      RETURN QUERY SELECT
        p_group_id,
        v_replay.previous_cap_brl,
        v_replay.new_cap_brl,
        v_replay.previous_max_charges,
        v_replay.new_max_charges,
        v_replay.previous_timezone,
        v_replay.new_timezone,
        v_replay.changed_at,
        TRUE;
      RETURN;
    END IF;
  END IF;

  -- Settings devem existir (admin_master criou via portal). Não criamos
  -- aqui porque billing_auto_topup_settings.product_id é NOT NULL FK e
  -- não temos um product_id para semear; fail-loud.
  SELECT s.daily_charge_cap_brl, s.daily_max_charges, s.daily_limit_timezone
    INTO v_settings
  FROM public.billing_auto_topup_settings s
  WHERE s.group_id = p_group_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AUTO_TOPUP_SETTINGS_NOT_FOUND: group=%', p_group_id
      USING
        ERRCODE = 'P0002',
        HINT    = 'Crie settings via POST /api/auto-topup antes de '
                  'mudar caps diários.';
  END IF;

  v_target_tz := COALESCE(p_timezone, v_settings.daily_limit_timezone);

  UPDATE public.billing_auto_topup_settings
    SET daily_charge_cap_brl   = p_new_cap_brl,
        daily_max_charges      = p_new_max_charges,
        daily_limit_timezone   = v_target_tz,
        daily_limit_updated_at = v_now,
        daily_limit_updated_by = p_actor_user_id,
        updated_at             = v_now
  WHERE group_id = p_group_id;

  INSERT INTO public.billing_auto_topup_cap_changes (
    group_id, previous_cap_brl, new_cap_brl,
    previous_max_charges, new_max_charges,
    previous_timezone, new_timezone,
    actor_user_id, reason, idempotency_key, changed_at
  ) VALUES (
    p_group_id, v_settings.daily_charge_cap_brl, p_new_cap_brl,
    v_settings.daily_max_charges, p_new_max_charges,
    v_settings.daily_limit_timezone, v_target_tz,
    p_actor_user_id, p_reason, p_idempotency_key, v_now
  );

  RETURN QUERY SELECT
    p_group_id,
    v_settings.daily_charge_cap_brl,
    p_new_cap_brl,
    v_settings.daily_max_charges,
    p_new_max_charges,
    v_settings.daily_limit_timezone,
    v_target_tz,
    v_now,
    FALSE;
END $$;

REVOKE ALL ON FUNCTION public.fn_set_auto_topup_daily_cap(uuid, numeric, integer, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_set_auto_topup_daily_cap(uuid, numeric, integer, uuid, text, text, text) TO service_role;

COMMENT ON FUNCTION public.fn_set_auto_topup_daily_cap(uuid, numeric, integer, uuid, text, text, text) IS
  'L12-05: atomically updates daily cap + grava audit. Idempotent via '
  '(group_id, idempotency_key) UNIQUE partial. Reason >= 10 chars.';

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Self-test — falha o deploy se algo regredir
-- ───────────────────────────────────────────────────────────────────────────
DO $self_test$
DECLARE
  v_ok integer;
BEGIN
  -- Schema check
  SELECT count(*) INTO v_ok
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'billing_auto_topup_settings'
    AND column_name IN (
      'daily_charge_cap_brl',
      'daily_max_charges',
      'daily_limit_timezone',
      'daily_limit_updated_at',
      'daily_limit_updated_by'
    );
  IF v_ok < 5 THEN
    RAISE EXCEPTION 'L12-05 schema regression: expected 5 daily_* columns, found %', v_ok;
  END IF;

  -- Audit table
  SELECT count(*) INTO v_ok
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name = 'billing_auto_topup_cap_changes';
  IF v_ok < 1 THEN
    RAISE EXCEPTION 'L12-05 audit table regression: billing_auto_topup_cap_changes missing';
  END IF;

  -- Function registry
  SELECT count(*) INTO v_ok
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'fn_check_auto_topup_daily_window',
      'fn_apply_auto_topup_daily_cap',
      'fn_set_auto_topup_daily_cap'
    );
  IF v_ok < 3 THEN
    RAISE EXCEPTION 'L12-05 function regression: expected 3 fn_*, found %', v_ok;
  END IF;
END $self_test$;
