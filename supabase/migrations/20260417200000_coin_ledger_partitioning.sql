-- ══════════════════════════════════════════════════════════════════════════
-- L19-01 — Partitioning de coin_ledger por created_at_ms (RANGE mensal)
--
-- Referência auditoria:
--   docs/audit/findings/L19-01-coin-ledger-nao-e-particionada-tabela-crescendo-sem.md
--   docs/audit/parts/19-dba.md [19.1]
--
-- Problema:
--   `coin_ledger` é tabela monolítica. Projeção: 100k usuários × 50 tx/mês ×
--   24 meses = 120M rows em 2 anos. Impactos:
--     - Reconciliação full-scan em horas (cron `reconcile-wallets-cron`).
--     - VACUUM/autovacuum bloqueiam.
--     - Backup/restore caro; PITR cresce sem controle.
--     - DELETE/ARCHIVE de dados antigos = bloat + WAL desnecessário.
--     - Query `idx_ledger_user(user_id, created_at_ms DESC)` vira ~22 GB
--       tornando o planner instável.
--
-- Correção (esta migration):
--   1. Nova tabela `coin_ledger_idempotency(ref_id, reason, ledger_id)` —
--      companion table não-particionada com PK composta. Uniqueness global
--      de ref_id (antes enforced pelo partial UNIQUE em coin_ledger) agora
--      reside aqui. Partitioned tables exigem que unique indexes incluam
--      a partition key, o que quebraria idempotência.
--   2. Helpers `coin_ledger_ensure_partition(p_month)` e
--      `coin_ledger_detach_old_partition(p_cutoff)` — gestão mensal.
--   3. Rename de `coin_ledger` → `coin_ledger_monolithic`; cria novo
--      `coin_ledger` particionado por RANGE(created_at_ms). Partições
--      mensais 2024-01 → 2028-12 + DEFAULT catchall. INSERT-SELECT
--      copia dados. DROP do antigo ao fim.
--   4. Refactor de `emit_coins_atomic` (L02-01) para claim idempotency slot
--      na companion table antes de inserir em coin_ledger. Semântica
--      preservada: was_idempotent=true em retry.
--   5. pg_cron (se instalado) agenda ensure_partition mensal.
--
-- Performance real esperada (prod com 120M rows):
--   - Query WHERE user_id = X AND created_at_ms BETWEEN A AND B:
--     partition pruning + index-only scan = ms em vez de segundos.
--   - Reconcile wallets: scan paralelo por partição = horas → minutos.
--   - ARCHIVE de dados antigos: ALTER TABLE DETACH PARTITION (instant) em
--     vez de DELETE (lock exclusivo por horas).
--   - Backup: pg_dump --table coin_ledger_pYYYYMM seletivo.
--
-- Breaking changes:
--   - PK de `coin_ledger` muda de `(id)` para `(id, created_at_ms)` — partition
--     key deve integrar unique constraint (regra PostgreSQL).
--   - Confirmado via pg_constraint: NENHUM FK aponta para coin_ledger.id,
--     então a mudança de PK não quebra integridade referencial.
--   - Global UUID uniqueness é garantida por gen_random_uuid() (colisão
--     ≈ 2^61).
--   - Partial UNIQUE INDEX `idx_coin_ledger_ref_id_institution_issue_unique`
--     dropado (substituído pela companion table).
-- ══════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Companion table: coin_ledger_idempotency
-- ──────────────────────────────────────────────────────────────────────────
--
-- Uniqueness de ref_id dentro de um reason. Não particionada — é o âncora
-- de idempotência que o particionamento não pode prover globalmente.
-- Bounded growth: uma row por (ref_id, reason). Rotina de GC opcional pode
-- apagar entries > 1 ano sem consequências (retry após 1 ano é cenário
-- operacional raríssimo).
CREATE TABLE IF NOT EXISTS public.coin_ledger_idempotency (
  ref_id     text        NOT NULL,
  reason     text        NOT NULL,
  ledger_id  uuid        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ref_id, reason)
);

COMMENT ON TABLE public.coin_ledger_idempotency IS
  'L19-01: âncora de idempotência para coin_ledger (particionada). Uma row '
  'por (ref_id, reason) garante que retries produzam o mesmo ledger_id. '
  'Consultada por emit_coins_atomic antes do INSERT em coin_ledger.';

CREATE INDEX IF NOT EXISTS idx_coin_ledger_idempotency_created_at
  ON public.coin_ledger_idempotency (created_at DESC);

ALTER TABLE public.coin_ledger_idempotency ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.coin_ledger_idempotency FROM PUBLIC;
REVOKE ALL ON public.coin_ledger_idempotency FROM anon;
REVOKE ALL ON public.coin_ledger_idempotency FROM authenticated;
GRANT  ALL ON public.coin_ledger_idempotency TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Helper: coin_ledger_ensure_partition(p_month)
-- ──────────────────────────────────────────────────────────────────────────
--
-- Idempotente. Cria partição mensal se não existir.
-- Partition name: coin_ledger_pYYYYMM.
-- Range: [first-day-of-month ms, first-day-of-next-month ms).
CREATE OR REPLACE FUNCTION public.coin_ledger_ensure_partition(p_month date)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_name     text;
  v_start_ms bigint;
  v_end_ms   bigint;
  v_exists   boolean;
BEGIN
  IF p_month IS NULL THEN
    RAISE EXCEPTION 'coin_ledger_ensure_partition: p_month is NULL' USING ERRCODE = 'P0001';
  END IF;
  p_month := date_trunc('month', p_month)::date;
  v_name  := 'coin_ledger_p' || to_char(p_month, 'YYYYMM');

  SELECT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = v_name
  ) INTO v_exists;

  IF v_exists THEN
    RETURN v_name;
  END IF;

  v_start_ms := (extract(epoch from p_month) * 1000)::bigint;
  v_end_ms   := (extract(epoch from (p_month + interval '1 month')) * 1000)::bigint;

  EXECUTE format(
    'CREATE TABLE public.%I PARTITION OF public.coin_ledger FOR VALUES FROM (%L) TO (%L)',
    v_name, v_start_ms, v_end_ms
  );
  RETURN v_name;
END;
$$;

COMMENT ON FUNCTION public.coin_ledger_ensure_partition(date) IS
  'L19-01: cria partição mensal de coin_ledger (coin_ledger_pYYYYMM). '
  'Idempotente. Chamado por cron mensalmente para N+2 meses à frente.';

REVOKE ALL ON FUNCTION public.coin_ledger_ensure_partition(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.coin_ledger_ensure_partition(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.coin_ledger_ensure_partition(date) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Helper: coin_ledger_detach_old_partition(p_cutoff)
-- ──────────────────────────────────────────────────────────────────────────
--
-- DETACH (instantâneo) da partição cujo range termina em ≤ p_cutoff_month.
-- A tabela resultante é standalone e pode ser dropada pelo operator ou
-- movida para coin_ledger_archive schema.
CREATE OR REPLACE FUNCTION public.coin_ledger_detach_old_partition(p_cutoff date)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_name   text;
  v_exists boolean;
BEGIN
  IF p_cutoff IS NULL THEN
    RAISE EXCEPTION 'coin_ledger_detach_old_partition: p_cutoff is NULL' USING ERRCODE = 'P0001';
  END IF;
  p_cutoff := date_trunc('month', p_cutoff)::date;
  v_name   := 'coin_ledger_p' || to_char(p_cutoff, 'YYYYMM');

  SELECT EXISTS (
    SELECT 1 FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    JOIN pg_class p ON p.oid = i.inhparent
    WHERE p.relname = 'coin_ledger' AND c.relname = v_name
  ) INTO v_exists;

  IF NOT v_exists THEN
    RETURN NULL;
  END IF;

  EXECUTE format('ALTER TABLE public.coin_ledger DETACH PARTITION public.%I', v_name);
  RETURN v_name;
END;
$$;

COMMENT ON FUNCTION public.coin_ledger_detach_old_partition(date) IS
  'L19-01: DETACH instantâneo de partição mensal antiga. Retorna nome da '
  'tabela standalone resultante (ou NULL se não existir). Operator decide '
  'se move para schema archive ou dropa.';

REVOKE ALL ON FUNCTION public.coin_ledger_detach_old_partition(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.coin_ledger_detach_old_partition(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.coin_ledger_detach_old_partition(date) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Swap: monolithic → partitioned
-- ──────────────────────────────────────────────────────────────────────────
--
-- Idempotência: se coin_ledger já é particionada, a migration é no-op.

DO $$
DECLARE
  v_is_partitioned boolean;
  v_row_count      bigint;
  v_current_count  bigint;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_partitioned_table
    WHERE partrelid = 'public.coin_ledger'::regclass
  ) INTO v_is_partitioned;

  IF v_is_partitioned THEN
    RAISE NOTICE '[L19-01] coin_ledger já é particionada — swap é no-op';
    RETURN;
  END IF;

  EXECUTE 'SELECT count(*) FROM public.coin_ledger' INTO v_row_count;
  RAISE NOTICE '[L19-01] coin_ledger monolítica tem % rows — iniciando swap', v_row_count;

  -- Drop idempotency unique index partial (substituído pela companion table)
  DROP INDEX IF EXISTS public.idx_coin_ledger_ref_id_institution_issue_unique;

  -- Seed idempotency table a partir dos dados existentes (preserva garantia)
  INSERT INTO public.coin_ledger_idempotency (ref_id, reason, ledger_id, created_at)
    SELECT ref_id, reason, id, created_at
      FROM public.coin_ledger
     WHERE reason = 'institution_token_issue' AND ref_id IS NOT NULL
  ON CONFLICT (ref_id, reason) DO NOTHING;

  -- Rename existing table
  ALTER TABLE public.coin_ledger RENAME TO coin_ledger_monolithic;
  ALTER INDEX IF EXISTS public.idx_ledger_user   RENAME TO idx_ledger_user_monolithic;
  ALTER INDEX IF EXISTS public.idx_ledger_issuer RENAME TO idx_ledger_issuer_monolithic;

  -- Nova tabela particionada
  CREATE TABLE public.coin_ledger (
    id               uuid        NOT NULL DEFAULT gen_random_uuid(),
    user_id          uuid        NOT NULL,
    delta_coins      integer     NOT NULL,
    reason           text        NOT NULL,
    ref_id           text,
    created_at_ms    bigint      NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    issuer_group_id  uuid,
    PRIMARY KEY (id, created_at_ms),
    CONSTRAINT coin_ledger_reason_check CHECK (
      reason = ANY (ARRAY[
        'session_completed',
        'challenge_one_vs_one_completed',
        'challenge_one_vs_one_won',
        'challenge_group_completed',
        'streak_weekly',
        'streak_monthly',
        'pr_distance',
        'pr_pace',
        'challenge_entry_fee',
        'challenge_pool_won',
        'challenge_entry_refund',
        'cosmetic_purchase',
        'admin_adjustment',
        'badge_reward',
        'mission_reward',
        'institution_token_issue',
        'institution_token_burn'
      ])
    ),
    CONSTRAINT coin_ledger_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT coin_ledger_issuer_group_id_fkey
      FOREIGN KEY (issuer_group_id) REFERENCES public.coaching_groups(id) ON DELETE SET NULL
  ) PARTITION BY RANGE (created_at_ms);

  COMMENT ON TABLE public.coin_ledger IS
    'L19-01: ledger financeiro particionado por created_at_ms mensal. '
    'Idempotência via coin_ledger_idempotency. '
    'FKs para auth.users (CASCADE) e coaching_groups (SET NULL) propagam para partições.';

  -- Recria índices locais (aplicados a cada partição automaticamente)
  CREATE INDEX idx_ledger_user   ON public.coin_ledger (user_id, created_at_ms DESC);
  CREATE INDEX idx_ledger_issuer ON public.coin_ledger (issuer_group_id);
  CREATE INDEX idx_ledger_reason ON public.coin_ledger (reason, created_at_ms DESC);

  -- RLS
  ALTER TABLE public.coin_ledger ENABLE ROW LEVEL SECURITY;
  CREATE POLICY ledger_own_read ON public.coin_ledger
    FOR SELECT USING (auth.uid() = user_id);

  REVOKE ALL ON public.coin_ledger FROM PUBLIC;
  REVOKE ALL ON public.coin_ledger FROM anon;
  GRANT  SELECT ON public.coin_ledger TO authenticated;
  GRANT  ALL    ON public.coin_ledger TO service_role;

  -- Partições mensais: 2024-01 a 2028-12 (60 meses) + DEFAULT catchall
  FOR i IN 0..59 LOOP
    PERFORM public.coin_ledger_ensure_partition(
      (DATE '2024-01-01' + (i * INTERVAL '1 month'))::date
    );
  END LOOP;

  CREATE TABLE IF NOT EXISTS public.coin_ledger_default
    PARTITION OF public.coin_ledger DEFAULT;

  -- Copy data from monolithic → partitioned (se houver)
  IF v_row_count > 0 THEN
    EXECUTE 'INSERT INTO public.coin_ledger '
         || '(id, user_id, delta_coins, reason, ref_id, created_at_ms, created_at, issuer_group_id) '
         || 'SELECT id, user_id, delta_coins, reason, ref_id, created_at_ms, created_at, issuer_group_id '
         || 'FROM public.coin_ledger_monolithic';

    SELECT count(*) INTO v_current_count FROM public.coin_ledger;
    IF v_current_count <> v_row_count THEN
      RAISE EXCEPTION '[L19-01] row count mismatch após cópia: esperado=% mas got=%',
        v_row_count, v_current_count;
    END IF;
    RAISE NOTICE '[L19-01] % rows copiadas para tabela particionada', v_row_count;
  END IF;

  DROP TABLE public.coin_ledger_monolithic CASCADE;
  RAISE NOTICE '[L19-01] swap completo (% partições criadas)',
    (SELECT count(*) FROM pg_inherits i JOIN pg_class p ON p.oid = i.inhparent
      WHERE p.relname = 'coin_ledger');
END $$;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. Refactor emit_coins_atomic: usar companion table para idempotência
-- ──────────────────────────────────────────────────────────────────────────
--
-- Mudanças vs. L02-01 original:
--   1. ON CONFLICT em coin_ledger.ref_id — removido (partial unique dropado).
--   2. INSERT claim em coin_ledger_idempotency primeiro.
--   3. Retorno was_idempotent=true se slot já reclamado.
--   4. Se slot claim sucede, usa o ledger_id reservado como PK da linha
--      em coin_ledger (consistente com retries que leem o slot).
CREATE OR REPLACE FUNCTION public.emit_coins_atomic(
  p_group_id         uuid,
  p_athlete_user_id  uuid,
  p_amount           integer,
  p_ref_id           text
)
RETURNS TABLE (
  ledger_id       uuid,
  new_balance     integer,
  was_idempotent  boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_ledger_id      uuid;
  v_existing_id    uuid;
  v_new_balance    integer;
  v_now_ms         bigint := (extract(epoch from now()) * 1000)::bigint;
  v_claimed        boolean;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: amount must be > 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_ref_id IS NULL OR length(p_ref_id) = 0 THEN
    RAISE EXCEPTION 'MISSING_REF_ID: ref_id is required for idempotency' USING ERRCODE = 'P0001';
  END IF;

  -- (A) Claim idempotency slot — gera ledger_id estável
  v_ledger_id := gen_random_uuid();
  INSERT INTO public.coin_ledger_idempotency (ref_id, reason, ledger_id)
    VALUES (p_ref_id, 'institution_token_issue', v_ledger_id)
  ON CONFLICT (ref_id, reason) DO NOTHING;

  SELECT ledger_id INTO v_existing_id
    FROM public.coin_ledger_idempotency
   WHERE ref_id = p_ref_id AND reason = 'institution_token_issue';

  v_claimed := (v_existing_id = v_ledger_id);

  IF NOT v_claimed THEN
    -- Idempotent retry: slot já existia. Retorna estado atual sem mutar nada.
    SELECT balance_coins INTO v_new_balance
      FROM public.wallets WHERE user_id = p_athlete_user_id;
    RETURN QUERY SELECT v_existing_id, COALESCE(v_new_balance, 0), true;
    RETURN;
  END IF;

  -- (B) INSERT coin_ledger com o ledger_id reservado
  INSERT INTO public.coin_ledger
    (id, user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
  VALUES
    (v_ledger_id, p_athlete_user_id, p_amount, 'institution_token_issue',
     p_ref_id, p_group_id, v_now_ms);

  -- (C) Custódia: commit coins contra lastro USD
  BEGIN
    PERFORM public.custody_commit_coins(p_group_id, p_amount);
  EXCEPTION
    WHEN undefined_function THEN NULL;
    WHEN OTHERS THEN
      RAISE EXCEPTION 'CUSTODY_FAILED: %', SQLERRM USING ERRCODE = 'P0002';
  END;

  -- (D) Decrementa inventário (CHECK >= 0 previne overdraft)
  BEGIN
    PERFORM public.decrement_token_inventory(p_group_id, p_amount);
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'INVENTORY_INSUFFICIENT' USING ERRCODE = 'P0003';
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%INVENTORY_NOT_FOUND%' THEN
        RAISE EXCEPTION 'INVENTORY_INSUFFICIENT' USING ERRCODE = 'P0003';
      END IF;
      RAISE;
  END;

  -- (E) Credita wallet
  PERFORM public.increment_wallet_balance(p_athlete_user_id, p_amount);

  SELECT balance_coins INTO v_new_balance FROM public.wallets
    WHERE user_id = p_athlete_user_id;

  RETURN QUERY SELECT v_ledger_id, COALESCE(v_new_balance, 0), false;
END;
$$;

COMMENT ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) IS
  'L02-01 + L19-01: emissão atômica de OmniCoins com idempotência via '
  'coin_ledger_idempotency (separada da tabela particionada). '
  'Retorna was_idempotent=true quando ref_id já foi processado. '
  'Erros: INVALID_AMOUNT, MISSING_REF_ID (P0001); CUSTODY_FAILED (P0002); '
  'INVENTORY_INSUFFICIENT (P0003).';

REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM authenticated;
REVOKE ALL ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.emit_coins_atomic(uuid, uuid, integer, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 6. pg_cron schedule (best-effort)
-- ──────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('coin_ledger_ensure_partition_monthly');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PERFORM cron.schedule(
      'coin_ledger_ensure_partition_monthly',
      '0 3 1 * *',  -- 3am no primeiro dia de cada mês
      $cron$
        SELECT public.coin_ledger_ensure_partition((CURRENT_DATE + INTERVAL '2 months')::date);
      $cron$
    );
    RAISE NOTICE '[L19-01] pg_cron job "coin_ledger_ensure_partition_monthly" agendado';
  ELSE
    RAISE NOTICE '[L19-01] pg_cron não instalado — agendamento manual necessário (ver runbook)';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[L19-01] pg_cron schedule falhou (ignorado): %', SQLERRM;
END $$;

-- ──────────────────────────────────────────────────────────────────────────
-- 7. Reparar view lgpd_user_data_coverage_gaps (L04-01)
-- ──────────────────────────────────────────────────────────────────────────
--
-- `information_schema.columns` expõe cada partição de coin_ledger como
-- uma tabela distinta (coin_ledger_pYYYYMM.user_id). Isso faria a view
-- L04-01 reportar as 60+ partições como "coverage gaps", quebrando o
-- invariant de compliance LGPD. Filtramos partições via pg_inherits.
--
-- Aplicado apenas se a view existir (L04-01 foi aplicado antes).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'lgpd_user_data_coverage_gaps'
  ) THEN
    CREATE OR REPLACE VIEW public.lgpd_user_data_coverage_gaps AS
    WITH partition_children AS (
      SELECT child.relname AS child_name
      FROM pg_inherits inh
      JOIN pg_class child   ON child.oid  = inh.inhrelid
      JOIN pg_class parent  ON parent.oid = inh.inhparent
      JOIN pg_namespace np  ON np.oid     = child.relnamespace
      JOIN pg_namespace pnp ON pnp.oid    = parent.relnamespace
      WHERE np.nspname = 'public' AND pnp.nspname = 'public'
    ),
    user_ref_columns AS (
      SELECT c.table_name, c.column_name
      FROM information_schema.columns c
      -- L19-01 + views-fix: filtra BASE TABLE para não computar views como
      -- gaps (v_* herdam cobertura das tabelas subjacentes). Mantém a
      -- exclusão de partitions via pg_inherits.
      JOIN information_schema.tables t
        ON t.table_schema = c.table_schema
       AND t.table_name   = c.table_name
      WHERE c.table_schema = 'public'
        AND t.table_type   = 'BASE TABLE'
        AND c.data_type    = 'uuid'
        AND (
          c.column_name IN (
            'user_id', 'athlete_user_id', 'target_user_id', 'actor_id',
            'creator_user_id', 'coach_user_id', 'created_by', 'created_by_user_id',
            'updated_by', 'reviewed_by', 'approved_by', 'invited_by_user_id',
            'invited_user_id', 'approval_reviewed_by', 'requested_by',
            'user_id_a', 'user_id_b'
          )
        )
        AND c.table_name NOT IN (
          'profiles',
          'coaching_groups'
        )
        -- L19-01: excluir partições (herdam da parent já registrada)
        AND c.table_name NOT IN (SELECT child_name FROM partition_children)
    )
    SELECT u.table_name, u.column_name
    FROM user_ref_columns u
    LEFT JOIN public.lgpd_deletion_strategy s
           ON s.table_name = u.table_name AND s.column_name = u.column_name
    WHERE s.table_name IS NULL
    ORDER BY u.table_name, u.column_name;

    COMMENT ON VIEW public.lgpd_user_data_coverage_gaps IS
      'L04-01 + L19-01: user-referencing columns em public.* sem estratégia LGPD. '
      'Exclui partition children (herdam cobertura da parent table).';

    RAISE NOTICE '[L19-01] view lgpd_user_data_coverage_gaps atualizada para excluir partitions';
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────────────────
-- 8. Invariantes de saída
-- ──────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_is_partitioned  boolean;
  v_partition_count integer;
  v_emit_has_sp     boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_partitioned_table WHERE partrelid = 'public.coin_ledger'::regclass
  ) INTO v_is_partitioned;
  IF NOT v_is_partitioned THEN
    RAISE EXCEPTION '[L19-01] invariant failed: coin_ledger não é particionada';
  END IF;

  SELECT count(*) INTO v_partition_count
    FROM pg_inherits i
    JOIN pg_class p ON p.oid = i.inhparent
   WHERE p.relname = 'coin_ledger';
  IF v_partition_count < 12 THEN
    RAISE EXCEPTION '[L19-01] invariant failed: apenas % partições (esperado ≥12)', v_partition_count;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'emit_coins_atomic'
      AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) c
                  WHERE c LIKE 'search_path=%')
  ) INTO v_emit_has_sp;
  IF NOT v_emit_has_sp THEN
    RAISE EXCEPTION '[L19-01] invariant failed: emit_coins_atomic sem search_path';
  END IF;
END $$;
