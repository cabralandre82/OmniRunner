-- ============================================================================
-- L09-13 / L09-14 — pg_cron para faturas de assinatura de atleta
--
-- Contexto (do estudo de prontidão de go-to-market do financeiro, 2026-04-24):
--
-- A migration L23-09 criou o par de funções que sustenta o billing recorrente:
--
--   * public.fn_subscription_generate_cycle(p_period_month DATE DEFAULT NULL)
--     — gera 1 row em athlete_subscription_invoices por (subscription ativa,
--       período) com ON CONFLICT DO NOTHING (idempotente).
--
--   * public.fn_subscription_mark_overdue()
--     — UPDATE athlete_subscription_invoices SET status='overdue' WHERE
--       status='pending' AND due_date < CURRENT_DATE (idempotente).
--
-- Ambas rejeitam chamadas de roles que não sejam service_role (runtime check
-- `IF current_setting('role') IS DISTINCT FROM 'service_role' THEN RAISE`).
-- Grants estão corretos (EXECUTE TO service_role).
--
-- **O que faltava:** nenhuma PERFORM cron.schedule(...). Resultado:
--   - Faturas nunca são geradas em produção.
--   - Inadimplentes nunca viram 'overdue' (status fica eterno 'pending').
--   - Qualquer surface que consuma athlete_subscription_invoices mostra
--     estado vazio (bloqueia go-to-market do portal financeiro).
--
-- Esta migration fecha os dois gaps (L09-13 + L09-14). Os dois jobs moram no
-- mesmo arquivo porque formam um par operacional: generate cria as rows,
-- overdue as envelhece. Separar em arquivos dobra a superfície de rollback.
--
-- Pattern L12-11 (idempotency): DO + pg_extension check + unschedule defensivo
-- + schedule. Pattern L12-01 (seed cron_run_state): insere rows 'never_run'
-- para ops ter visibilidade imediata.
--
-- Não usamos advisory lock (L12-03 style): as duas funções são 100%
-- idempotentes, cadência mensal/diária não tem risco de overlap, e o wrapper
-- existe para crons */5 ou mais agressivos.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- ─── L09-13 · generate_cycle (mensal, dia 1, 05:00 UTC) ──────────────────────

DO $l09_13$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L09-13] pg_cron not installed; skipping schedule';
    RETURN;
  END IF;

  -- Unschedule defensivo (re-aplicação da migration não deve duplicar).
  BEGIN
    PERFORM cron.unschedule('l09_13_subscription_generate_cycle');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Dia 1 às 05:00 UTC (02:00 BRT): fora de horário comercial, antes do
  -- início de expediente, sem conflito com outros jobs no repo.
  --
  -- Dia 1 é obrigatório: fn_subscription_generate_cycle usa
  -- date_trunc('month', now()) como default de período, e due_date é
  -- period + (billing_day-1) dias. Rodar mid-month faria invoices
  -- nascerem com due_date no passado (e seriam imediatamente marcadas
  -- como overdue pelo L09-14, cenário errado).
  --
  -- SET LOCAL role = 'service_role' é necessário: pg_cron roda como
  -- postgres; a função exige service_role em runtime. SET LOCAL só vale
  -- para a transação do job — não afeta outras sessões.
  PERFORM cron.schedule(
    'l09_13_subscription_generate_cycle',
    '0 5 1 * *',
    $job$
    SET LOCAL role = 'service_role';
    SELECT public.fn_subscription_generate_cycle();
    $job$
  );

  RAISE NOTICE '[L09-13] scheduled l09_13_subscription_generate_cycle at 05:00 UTC on day 1';
END
$l09_13$;

-- Seed cron_run_state para ops ter visibilidade imediata (padrão L12-01).
INSERT INTO public.cron_run_state(name, last_status)
VALUES ('l09_13_subscription_generate_cycle', 'never_run')
ON CONFLICT (name) DO NOTHING;

-- ─── L09-14 · mark_overdue (diário, 05:30 UTC) ───────────────────────────────

DO $l09_14$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L09-14] pg_cron not installed; skipping schedule';
    RETURN;
  END IF;

  BEGIN
    PERFORM cron.unschedule('l09_14_subscription_mark_overdue');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Diário 05:30 UTC (30 min depois do generate_cycle). No dia 1,
  -- generate cria as rows do mês (~<1s) e overdue roda em seguida
  -- (UPDATE vazio quando não há due_date passado; idempotente).
  --
  -- Cadência diária é suficiente: due_date tem granularidade de dia.
  -- Rodar de hora em hora causaria 23/24 execuções com UPDATE vazio
  -- e aumento de lock contention desnecessário.
  PERFORM cron.schedule(
    'l09_14_subscription_mark_overdue',
    '30 5 * * *',
    $job$
    SET LOCAL role = 'service_role';
    SELECT public.fn_subscription_mark_overdue();
    $job$
  );

  RAISE NOTICE '[L09-14] scheduled l09_14_subscription_mark_overdue at 05:30 UTC daily';
END
$l09_14$;

INSERT INTO public.cron_run_state(name, last_status)
VALUES ('l09_14_subscription_mark_overdue', 'never_run')
ON CONFLICT (name) DO NOTHING;

-- ─── Self-tests ──────────────────────────────────────────────────────────────
-- Tolerantes a ambiente sem pg_cron (dev local): se a extensão não existe,
-- o cron.job table também não existe e as queries abaixo falham com
-- undefined_table — capturamos e seguimos. Em prod (Supabase), pg_cron
-- está sempre disponível, então os checks valem.

DO $selftest$
DECLARE
  v_count_generate INT := 0;
  v_count_overdue  INT := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L09-13/14] self-test skipped (pg_cron absent)';
    RETURN;
  END IF;

  SELECT count(*) INTO v_count_generate
  FROM cron.job
  WHERE jobname = 'l09_13_subscription_generate_cycle';

  IF v_count_generate <> 1 THEN
    RAISE EXCEPTION '[L09-13] self-test: expected exactly 1 job, got %', v_count_generate;
  END IF;

  SELECT count(*) INTO v_count_overdue
  FROM cron.job
  WHERE jobname = 'l09_14_subscription_mark_overdue';

  IF v_count_overdue <> 1 THEN
    RAISE EXCEPTION '[L09-14] self-test: expected exactly 1 job, got %', v_count_overdue;
  END IF;

  -- Confirma seed de cron_run_state (independente da extensão).
  IF NOT EXISTS (
    SELECT 1 FROM public.cron_run_state
    WHERE name IN (
      'l09_13_subscription_generate_cycle',
      'l09_14_subscription_mark_overdue'
    )
  ) THEN
    RAISE EXCEPTION '[L09-13/14] self-test: cron_run_state seeds missing';
  END IF;

  RAISE NOTICE '[L09-13/14] self-tests passed';
END
$selftest$;
