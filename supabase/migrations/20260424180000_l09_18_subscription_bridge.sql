-- ============================================================================
-- L09-18 / ADR-0010 F-CON-1 — Bridge legado→novo + CI guard de convergência
--
-- Contexto (ver docs/adr/ADR-0010-billing-subscriptions-consolidation.md):
--
-- O backend tem 2 modelos paralelos de subscription de atleta:
--   * Legado: public.coaching_subscriptions (status agregado, sem invoices)
--   * Novo:   public.athlete_subscriptions + .athlete_subscription_invoices
--             (invoice-level, multi-gateway, modelo canônico)
--
-- O webhook do Asaas (supabase/functions/asaas-webhook/index.ts) escreve só
-- no legado. Resultado em produção, com L09-13/14/15/16/17 já em pé:
--   * Atleta paga → coaching_subscriptions.status='active' (webhook ok)
--   * MAS athlete_subscription_invoices da invoice corrente fica 'pending'
--   * Cron L09-14 sweep depois → invoice fica 'overdue' (FALSO POSITIVO)
--   * FinancialAlertBanner (L09-17) dispara alerta vermelho para atleta que
--     já pagou.
--
-- Esta migration entrega F-CON-1 do plano de 3 fases do ADR:
--
--   1. fn_subscription_bridge_mark_paid_from_legacy(legacy_sub_id, period, ext)
--      — chamada pelo webhook em PAYMENT_CONFIRMED/RECEIVED. Resolve
--      (group_id, athlete_user_id) a partir do legado, encontra a invoice
--      nova correspondente e dispara fn_subscription_mark_invoice_paid.
--      Idempotente, fail-soft (retorna jsonb com motivo, nunca raise em
--      caminho normal).
--
--   2. fn_find_subscription_models_divergence(p_max_samples)
--      — detector. Para cada coaching_subscriptions com status='active' e
--      last_payment_at no mês corrente, retorna casos onde o atleta tem
--      athlete_subscriptions ativo MAS nenhuma invoice 'paid' no
--      period_month corrente. Esses são falsos positivos potenciais.
--
--   3. fn_assert_subscription_models_converged(p_max_samples)
--      — wrapper P0010. Usado pelo CI guard `audit:billing-models-converged`
--      e pelo cron-health-monitor scaffolding (L06-04).
--
-- Pattern: SECURITY DEFINER + service_role runtime check + search_path
-- locked, igual L23-09 / L09-13.
--
-- Idempotência: CREATE OR REPLACE para todas; sem DDL nas tabelas
-- legadas/novas (rollback = drop function).
-- ============================================================================

BEGIN;

-- ─── 1. Bridge: webhook → marcar invoice nova como paga ──────────────────────
--
-- Argumentos:
--   p_legacy_subscription_id  — id em coaching_subscriptions (o que o
--                                webhook já tem em mãos via asaas_subscription_map
--                                ou externalReference)
--   p_period_month            — mês de referência da fatura (primeiro dia).
--                                Quando NULL, usa o primeiro dia do mês atual.
--   p_external_charge_id      — id do payment no gateway (asaasPaymentId).
--                                Usado como tie-breaker se houver várias
--                                invoices no mesmo period.
--
-- Retorno (jsonb): {
--   ok            : bool,            -- true se a chamada foi bem-sucedida
--   matched       : bool,            -- true se uma invoice foi encontrada
--   was_paid_now  : bool,            -- true se invoice foi marcada paid agora
--                                       (false se já estava paga -> idempotente)
--   invoice_id    : uuid|null,
--   reason        : text             -- código/explicação para log/observabilidade
-- }
--
-- Códigos de `reason`:
--   'paid_now'              — a invoice estava pending|overdue e foi fechada
--   'already_paid'          — invoice já estava paid (idempotente, no-op)
--   'invoice_not_found'     — não há invoice nova para esse (athlete, group, period)
--                              (esperado durante a transição F-CON-2)
--   'no_athlete_sub'        — não há athlete_subscriptions para esse atleta
--                              (esperado: atleta foi onboarded só no legado)
--   'legacy_sub_not_found'  — coaching_subscriptions.id inexistente (anomalia)
--   'cancelled_invoice'     — invoice nova está cancelada (anomalia, não
--                              tenta reabrir; loga e segue)

CREATE OR REPLACE FUNCTION public.fn_subscription_bridge_mark_paid_from_legacy(
  p_legacy_subscription_id UUID,
  p_period_month           DATE DEFAULT NULL,
  p_external_charge_id     TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period         DATE;
  v_group_id       UUID;
  v_athlete_id     UUID;
  v_athlete_sub_id UUID;
  v_invoice        public.athlete_subscription_invoices%ROWTYPE;
  v_was_paid_now   BOOLEAN;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'fn_subscription_bridge_mark_paid_from_legacy is service-role only'
      USING ERRCODE = '42501';
  END IF;

  v_period := COALESCE(
    date_trunc('month', p_period_month)::date,
    date_trunc('month', CURRENT_DATE)::date
  );

  SELECT cs.group_id, cs.athlete_user_id
    INTO v_group_id, v_athlete_id
    FROM public.coaching_subscriptions cs
   WHERE cs.id = p_legacy_subscription_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'matched', false,
      'was_paid_now', false,
      'invoice_id', NULL,
      'reason', 'legacy_sub_not_found'
    );
  END IF;

  SELECT id
    INTO v_athlete_sub_id
    FROM public.athlete_subscriptions
   WHERE group_id = v_group_id
     AND athlete_user_id = v_athlete_id
     AND status IN ('active', 'paused')
   LIMIT 1;

  IF v_athlete_sub_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'matched', false,
      'was_paid_now', false,
      'invoice_id', NULL,
      'reason', 'no_athlete_sub'
    );
  END IF;

  -- Tenta resolver pelo external_charge_id (exato) primeiro; senão por
  -- (subscription_id, period_month) — UNIQUE em athlete_sub_invoices_period_uniq.
  IF p_external_charge_id IS NOT NULL AND length(p_external_charge_id) > 0 THEN
    SELECT * INTO v_invoice
      FROM public.athlete_subscription_invoices
     WHERE subscription_id = v_athlete_sub_id
       AND external_charge_id = p_external_charge_id
     LIMIT 1;
  END IF;

  IF v_invoice.id IS NULL THEN
    SELECT * INTO v_invoice
      FROM public.athlete_subscription_invoices
     WHERE subscription_id = v_athlete_sub_id
       AND period_month = v_period
     LIMIT 1;
  END IF;

  IF v_invoice.id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'matched', false,
      'was_paid_now', false,
      'invoice_id', NULL,
      'reason', 'invoice_not_found'
    );
  END IF;

  IF v_invoice.status = 'paid' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'matched', true,
      'was_paid_now', false,
      'invoice_id', v_invoice.id,
      'reason', 'already_paid'
    );
  END IF;

  IF v_invoice.status = 'cancelled' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'matched', true,
      'was_paid_now', false,
      'invoice_id', v_invoice.id,
      'reason', 'cancelled_invoice'
    );
  END IF;

  -- Status é 'pending' ou 'overdue' — fecha via função canônica.
  -- fn_subscription_mark_invoice_paid retorna FALSE se a invoice foi
  -- mudada concorrentemente para 'paid' entre o SELECT e o UPDATE
  -- (race com outro caller); tratamos isso como idempotência.
  v_was_paid_now := public.fn_subscription_mark_invoice_paid(
    v_invoice.id,
    p_external_charge_id
  );

  RETURN jsonb_build_object(
    'ok', true,
    'matched', true,
    'was_paid_now', v_was_paid_now,
    'invoice_id', v_invoice.id,
    'reason', CASE WHEN v_was_paid_now THEN 'paid_now' ELSE 'already_paid' END
  );

EXCEPTION
  WHEN insufficient_privilege THEN
    -- 42501: re-raise. Se um caller chamou a bridge sem service_role,
    -- queremos uma falha explícita e fail-loud (não fail-soft que
    -- mascararia bug de wiring). O webhook sempre roda como
    -- service_role, então isso só dispara em uso indevido.
    RAISE;
  WHEN OTHERS THEN
    -- fail-soft: nunca propaga outros erros pro webhook. Retorna ok=false
    -- com motivo pra observabilidade. O webhook loga e segue 200 (decisão
    -- fail-open por design — ver ASAAS_WEBHOOK_RUNBOOK §9).
    RETURN jsonb_build_object(
      'ok', false,
      'matched', false,
      'was_paid_now', false,
      'invoice_id', NULL,
      'reason', 'exception:' || SQLSTATE || ':' || left(SQLERRM, 200)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_subscription_bridge_mark_paid_from_legacy(UUID, DATE, TEXT)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_subscription_bridge_mark_paid_from_legacy(UUID, DATE, TEXT)
  TO service_role;

-- ─── 2. Detector de divergência ──────────────────────────────────────────────
--
-- Para cada coaching_subscriptions com status='active' que recebeu pagamento
-- no mês corrente (last_payment_at no current_month), checa que existe
-- invoice nova 'paid' no mesmo period_month. Reporta os casos divergentes,
-- desde que o atleta TENHA athlete_subscriptions (senão é o gap esperado de
-- F-CON-2, não bug de convergência).
--
-- Retorna: linhas com (legacy_subscription_id, group_id, athlete_user_id,
-- period_month, last_payment_at, kind), onde kind ∈
--   'invoice_pending'   : invoice existe mas está 'pending' (bridge não rodou ou perdeu)
--   'invoice_overdue'   : pior cenário — invoice virou overdue (alerta vermelho falso)
--   'invoice_missing'   : invoice nova nem foi gerada (cron L09-13 fora do ar)

CREATE OR REPLACE FUNCTION public.fn_find_subscription_models_divergence(
  p_max_samples INT DEFAULT 50
) RETURNS TABLE (
  legacy_subscription_id UUID,
  group_id               UUID,
  athlete_user_id        UUID,
  period_month           DATE,
  last_payment_at        TIMESTAMPTZ,
  kind                   TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_period DATE := date_trunc('month', CURRENT_DATE)::date;
BEGIN
  RETURN QUERY
  SELECT
    cs.id              AS legacy_subscription_id,
    cs.group_id        AS group_id,
    cs.athlete_user_id AS athlete_user_id,
    v_period           AS period_month,
    cs.last_payment_at AS last_payment_at,
    CASE
      WHEN inv.id IS NULL                 THEN 'invoice_missing'
      WHEN inv.status = 'overdue'         THEN 'invoice_overdue'
      WHEN inv.status = 'pending'         THEN 'invoice_pending'
      ELSE 'unknown'
    END                AS kind
  FROM public.coaching_subscriptions cs
  JOIN public.athlete_subscriptions  asub
    ON asub.group_id = cs.group_id
   AND asub.athlete_user_id = cs.athlete_user_id
   AND asub.status IN ('active', 'paused')
  LEFT JOIN public.athlete_subscription_invoices inv
    ON inv.subscription_id = asub.id
   AND inv.period_month = v_period
  WHERE cs.status = 'active'
    AND cs.last_payment_at IS NOT NULL
    AND cs.last_payment_at >= v_period
    AND (inv.id IS NULL OR inv.status IN ('pending', 'overdue'))
  ORDER BY cs.last_payment_at DESC
  LIMIT GREATEST(p_max_samples, 1);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_find_subscription_models_divergence(INT)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_find_subscription_models_divergence(INT)
  TO service_role, authenticated;

-- ─── 3. Assert wrapper (raise P0010) ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_assert_subscription_models_converged(
  p_max_samples INT DEFAULT 10
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count   INT;
  v_samples JSONB;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'fn_assert_subscription_models_converged is service-role only'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_count
    FROM public.fn_find_subscription_models_divergence(p_max_samples);

  IF v_count = 0 THEN
    RETURN;
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'legacy_subscription_id', d.legacy_subscription_id,
    'group_id', d.group_id,
    'athlete_user_id', d.athlete_user_id,
    'period_month', d.period_month,
    'last_payment_at', d.last_payment_at,
    'kind', d.kind
  ))
  INTO v_samples
  FROM public.fn_find_subscription_models_divergence(p_max_samples) d;

  RAISE EXCEPTION
    'subscription models divergence detected: % case(s) [ADR-0010 F-CON-1] — samples: %',
    v_count, v_samples
    USING ERRCODE = 'P0010';
END;
$$;

REVOKE ALL ON FUNCTION public.fn_assert_subscription_models_converged(INT)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_assert_subscription_models_converged(INT)
  TO service_role;

-- ─── 4. Self-test (DO block) ─────────────────────────────────────────────────
--
-- Apenas confirma que as 3 funções foram registradas com a assinatura
-- esperada. Não testa caminhos felizes (isso é responsabilidade do CI script
-- + integration tests TypeScript).

DO $$
BEGIN
  IF to_regprocedure('public.fn_subscription_bridge_mark_paid_from_legacy(uuid,date,text)') IS NULL THEN
    RAISE EXCEPTION 'L09-18 self-test FAILED: bridge function missing';
  END IF;

  IF to_regprocedure('public.fn_find_subscription_models_divergence(integer)') IS NULL THEN
    RAISE EXCEPTION 'L09-18 self-test FAILED: detector function missing';
  END IF;

  IF to_regprocedure('public.fn_assert_subscription_models_converged(integer)') IS NULL THEN
    RAISE EXCEPTION 'L09-18 self-test FAILED: assert function missing';
  END IF;

  RAISE NOTICE 'L09-18 / ADR-0010 F-CON-1 self-test ✅ — 3 funções registradas';
END
$$;

COMMIT;

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ Próximos passos (F-CON-2, fora desta migration):                           ║
-- ║   * Patch supabase/functions/asaas-webhook/index.ts para chamar            ║
-- ║     fn_subscription_bridge_mark_paid_from_legacy em PAYMENT_CONFIRMED/      ║
-- ║     PAYMENT_RECEIVED (fail-open).                                          ║
-- ║   * npm run audit:billing-models-converged (CI guard novo).                ║
-- ║   * Atualizar docs/runbooks/ASAAS_WEBHOOK_RUNBOOK.md com seção bridge.     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
