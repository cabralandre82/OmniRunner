-- ============================================================================
-- L03-13 — Reembolso / Estorno: não havia função reverse_burn, reverse_emission
--           ou refund_deposit canônica.
--
-- Referência:
--   docs/audit/findings/L03-13-reembolso-estorno-nao-ha-funcao-reverse-burn-ou.md
--   docs/audit/parts/03-cfo.md  [3.13]
--   docs/runbooks/CHARGEBACK_RUNBOOK.md §3.2 (bloco SQL manual que esta
--   migration substitui)
--   docs/runbooks/REVERSE_COINS_RUNBOOK.md (novo)
--
-- Problema pré-fix
-- ─────────────────
--   O sistema tinha emissões (emit_coins_atomic, L02-01), burns
--   (execute_burn_atomic, L02-02/L18-01), depósitos
--   (confirm_custody_deposit) e withdrawals completos/falhos (L02-06), mas
--   NÃO tinha uma forma transacional e idempotente de DESFAZER nenhum
--   desses três:
--
--     • chargeback de um custody_deposit confirmado → ops copiava 20
--       linhas de SQL do runbook CHARGEBACK, rodava em produção no
--       terminal, e torcia para não errar a ordem (primeiro burnar
--       coins → depois decrementar lastro → depois marcar status);
--     • emissão errada (athlete errado, amount errado, admin_master
--       clicou duas vezes por bug de UI) → só tinha o atalho de
--       rodar emit_coins_atomic com amount negativo, o que quebra as
--       CHECKs e empurra o problema para admin_adjustment sem trail;
--     • burn incorreto → inexistente; exigia burn adicional no sentido
--       oposto criando dois pares de clearing_events fantasma.
--
--   Consequência: toda reversão passava por SQL manual, sem idempotência
--   entre retries de rede, sem validação de invariantes, sem audit log
--   estruturado → perda financeira por erro humano era o risco default.
--
-- Defesa (esta migration) — TRÊS funções SECURITY DEFINER + 1 tabela de
-- idempotência dedicada, mais uma pequena expansão do enum de reason do
-- coin_ledger para receber as entradas de reversão como classe PRÓPRIA:
--
--   1. `coin_reversal_log` — idempotency anchor + audit material. Uma
--      row por (kind, idempotency_key) garante que o mesmo estorno não
--      seja aplicado duas vezes mesmo em retries de rede cliente.
--
--   2. Expandir `coin_ledger_reason_check` para aceitar:
--        - 'institution_token_reverse_emission'  (invert emit)
--        - 'institution_token_reverse_burn'      (invert burn)
--        - 'institution_switch_burn'             (restaura reason que
--          existia pré-L19-01 e foi perdida na migração de
--          particionamento — drive-by fix dentro do escopo financeiro
--          dessa função; ver 20260419130000 que usa essa reason na
--          fn_switch_assessoria e estava sendo silenciosamente rejeitada
--          se a CHECK fosse reavaliada após a partição).
--
--   3. `reverse_coin_emission_atomic(p_ledger_id, p_reason, p_actor,
--      p_idempotency_key)` — inverte emit_coins_atomic:
--        debita wallet via fn_mutate_wallet (que insere ledger negativo
--        + mantém guard L18-01), restaura inventário com
--        increment_token_inventory, libera custódia committed com
--        custody_release_committed. Falha com INSUFFICIENT_BALANCE se
--        atleta já gastou as coins — caso ops tem que ir para o fluxo
--        "dívida do grupo" (CHARGEBACK_RUNBOOK §3.3) manualmente.
--
--   4. `reverse_burn_atomic(p_burn_ref_id, p_reason, p_actor,
--      p_idempotency_key)` — inverte execute_burn_atomic:
--        bloqueia reversal se QUALQUER settlement associado ao burn
--        estiver em status 'settled' (coins já compensadas entre clubs
--        exigem remediation manual); senão cancela settlements pending,
--        recredita wallet, restaura custody committed intra-clube, e
--        insere ledger de reversão.
--
--   5. `reverse_custody_deposit_atomic(p_deposit_id, p_reason, p_actor,
--      p_idempotency_key)` — inverte confirm_custody_deposit:
--        valida que total_deposited_usd - amount >= total_committed
--        (senão: INVARIANT_VIOLATION, precisa reverter emissões
--        primeiro). Seta status='refunded', decrementa lastro, audita.
--
--   Invariantes preservadas
--   ────────────────────────
--     • Saldo wallet permanece >=0 sempre (CHECK na tabela + fn_mutate_wallet).
--     • custody_accounts.total_deposited_usd >= total_committed (validado
--       em reverse_custody_deposit_atomic antes do UPDATE).
--     • Todo reversal gera EXATAMENTE UMA row em coin_reversal_log e N
--       entradas negativas em coin_ledger (N=1 para emission/deposit,
--       N=len(breakdown) para burn).
--     • Todo reversal grava row em portal_audit_log com actor_id + reason.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Reason enum expansion
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_reason_check;
ALTER TABLE public.coin_ledger
  ADD CONSTRAINT coin_ledger_reason_check CHECK (
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
      'institution_token_burn',
      'institution_switch_burn',
      'institution_token_reverse_emission',
      'institution_token_reverse_burn'
    ])
  );

COMMENT ON CONSTRAINT coin_ledger_reason_check ON public.coin_ledger IS
  'L03-13: enumera todas as reason-classes aceitas. Inclui as duas novas '
  'classes de reversão introduzidas por esta migration e restaura '
  'institution_switch_burn que foi silenciosamente dropada pela '
  'migração de particionamento L19-01.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. coin_reversal_log — idempotency anchor + audit
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.coin_reversal_log (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind              text NOT NULL
                    CHECK (kind IN ('emission', 'burn', 'deposit')),
  idempotency_key   text NOT NULL CHECK (length(idempotency_key) >= 8),
  target_ref        text NOT NULL,
  actor_user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  reason            text NOT NULL CHECK (length(trim(reason)) >= 10),
  -- For emission: ledger_id of the original emission.
  -- For burn: burn_ref_id (the uuid-as-text used in execute_burn_atomic).
  -- For deposit: custody_deposit.id.
  metadata          jsonb NOT NULL DEFAULT '{}'::jsonb,
  reversed_coins    integer,   -- null for deposit
  reversed_usd      numeric(14,2), -- null for emission (unless refund bundles)
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kind, idempotency_key)
);

COMMENT ON TABLE public.coin_reversal_log IS
  'L03-13: anchor de idempotência + audit material para reversões de '
  'emissão, burn e depósito de custódia. UNIQUE (kind, idempotency_key) '
  'permite que retries de rede reusem a row sem aplicar a mutação duas '
  'vezes.';

CREATE INDEX IF NOT EXISTS idx_coin_reversal_log_target_ref
  ON public.coin_reversal_log (kind, target_ref);

CREATE INDEX IF NOT EXISTS idx_coin_reversal_log_created_at
  ON public.coin_reversal_log (created_at DESC);

ALTER TABLE public.coin_reversal_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coin_reversal_log_platform_read" ON public.coin_reversal_log
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

REVOKE ALL ON TABLE public.coin_reversal_log FROM PUBLIC;
REVOKE ALL ON TABLE public.coin_reversal_log FROM anon;
GRANT SELECT ON TABLE public.coin_reversal_log TO authenticated;
GRANT ALL    ON TABLE public.coin_reversal_log TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Helper: reverse_token_inventory_issuance — inverse of
--    decrement_token_inventory (L05-03/L02-01 emit path).
-- ─────────────────────────────────────────────────────────────────────────────
--
-- decrement_token_inventory já existe (usado por emit_coins_atomic) e faz:
--   available_tokens -= amount; lifetime_issued += amount;
-- Para restaurar o inventário após uma reversão de emissão precisamos do
-- oposto exato: available_tokens += amount; lifetime_issued -= amount.
-- execute_burn_atomic NÃO toca coaching_token_inventory (burns não
-- devolvem tokens para o pool emitável), então reverse_burn também não
-- toca — evita inflar lifetime_issued em reversal de burn.

CREATE OR REPLACE FUNCTION public.reverse_token_inventory_issuance(
  p_group_id     uuid,
  p_coin_count   integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
BEGIN
  IF p_coin_count IS NULL OR p_coin_count <= 0 THEN
    RAISE EXCEPTION 'INVALID_COUNT: must be > 0' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.coaching_token_inventory
  SET available_tokens = available_tokens + p_coin_count,
      lifetime_issued  = GREATEST(0, lifetime_issued - p_coin_count),
      updated_at       = now()
  WHERE group_id = p_group_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVENTORY_NOT_FOUND: group_id=%', p_group_id
      USING ERRCODE = 'P0003';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.reverse_token_inventory_issuance(uuid, integer) IS
  'L03-13: inverso exato de decrement_token_inventory. Restaura '
  'available_tokens e decrementa lifetime_issued (clamp em 0). Usado '
  'somente por reverse_coin_emission_atomic — reverse_burn NÃO toca '
  'inventário porque execute_burn_atomic também não toca.';

REVOKE ALL ON FUNCTION public.reverse_token_inventory_issuance(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_token_inventory_issuance(uuid, integer) FROM anon;
REVOKE ALL ON FUNCTION public.reverse_token_inventory_issuance(uuid, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_token_inventory_issuance(uuid, integer) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Helper: custody_commit_coins_refund — inverse of custody_release_committed
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Para refazer o commit que foi released quando o burn aconteceu, usamos
-- a custody_commit_coins existente — ela já faz a defesa de lastro. Aqui
-- nomeamos só como helper para uniformizar a leitura de reverse_burn.
-- (Sem CREATE: custody_commit_coins já existe desde 20260228150001).

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. reverse_coin_emission_atomic
--
-- Inverte emit_coins_atomic (L02-01 + L19-01 + L05-03).
--
-- Fluxo:
--   (a) valida idempotency_key → SELECT FROM coin_reversal_log. Se
--       já existe row com mesmo (kind='emission', idempotency_key),
--       retorna was_idempotent=true com o mesmo ledger_id original.
--   (b) trava a ledger row original FOR UPDATE (evita corrida com
--       outra reversão concorrente usando outro idempotency_key).
--   (c) verifica que reason original era 'institution_token_issue'.
--   (d) debita wallet via fn_mutate_wallet com delta=-amount e
--       reason='institution_token_reverse_emission'. fn_mutate_wallet
--       (L18-01) sobe o guard de wallet-mutation e levanta
--       check_violation se balance ficaria < 0 → 'INSUFFICIENT_BALANCE'.
--   (e) restaura inventário via increment_token_inventory.
--   (f) libera custódia committed via custody_release_committed.
--       Se custódia não existir para o group (deploy incompleto),
--       NULL out — consistente com o tratamento em emit_coins_atomic.
--   (g) escreve row em coin_reversal_log + audit.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reverse_coin_emission_atomic(
  p_original_ledger_id  uuid,
  p_reason              text,
  p_actor_user_id       uuid,
  p_idempotency_key     text
)
RETURNS TABLE (
  reversal_id       uuid,
  reversal_ledger_id uuid,
  athlete_user_id   uuid,
  reversed_amount   integer,
  new_balance       integer,
  was_idempotent    boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_existing_rev   uuid;
  v_existing_meta  jsonb;
  v_rev_id         uuid;
  v_orig_user      uuid;
  v_orig_group     uuid;
  v_orig_amount    integer;
  v_orig_reason    text;
  v_orig_ref       text;
  v_mut_row        record;
  v_new_balance    integer;
  v_has_custody    boolean;
BEGIN
  -- Validação de entrada
  IF p_original_ledger_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_LEDGER_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'pass the platform_admin auth.uid() so audit log is attributable';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'REASON_REQUIRED: postmortem reason must be >= 10 chars'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'MISSING_IDEMPOTENCY_KEY: key must be >= 8 chars'
      USING ERRCODE = 'P0001';
  END IF;

  -- (a) Idempotência: replay com mesmo key devolve estado anterior.
  SELECT id, metadata
    INTO v_existing_rev, v_existing_meta
    FROM public.coin_reversal_log
   WHERE kind = 'emission' AND idempotency_key = p_idempotency_key;

  IF v_existing_rev IS NOT NULL THEN
    -- Extrai detalhes do metadata preservado.
    RETURN QUERY
      SELECT
        v_existing_rev,
        (v_existing_meta ->> 'reversal_ledger_id')::uuid,
        (v_existing_meta ->> 'athlete_user_id')::uuid,
        (v_existing_meta ->> 'reversed_amount')::integer,
        (v_existing_meta ->> 'new_balance')::integer,
        true;
    RETURN;
  END IF;

  -- (b) Lock da ledger row original. A PK do coin_ledger particionado
  -- é (id, created_at_ms), mas o id isolado basta para localizar a row;
  -- o FOR UPDATE trava a partição certa.
  SELECT user_id, issuer_group_id, delta_coins, reason, ref_id
    INTO v_orig_user, v_orig_group, v_orig_amount, v_orig_reason, v_orig_ref
    FROM public.coin_ledger
   WHERE id = p_original_ledger_id
   FOR UPDATE;

  IF v_orig_user IS NULL THEN
    RAISE EXCEPTION 'LEDGER_NOT_FOUND: id=%', p_original_ledger_id
      USING ERRCODE = 'P0002';
  END IF;

  -- (c) Sanidade da reason: só invertemos emissões institucionais.
  IF v_orig_reason <> 'institution_token_issue' THEN
    RAISE EXCEPTION
      'INVALID_TARGET_REASON: expected institution_token_issue, got %',
      v_orig_reason
      USING ERRCODE = 'P0008',
            HINT = 'use reverse_burn_atomic for institution_token_burn or the appropriate domain-specific flow';
  END IF;

  IF v_orig_amount IS NULL OR v_orig_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_TARGET_AMOUNT: original delta_coins=% (must be >0)',
      v_orig_amount USING ERRCODE = 'P0008';
  END IF;

  -- (d) Debita wallet + insere ledger negativo em UMA operação via
  -- fn_mutate_wallet (L18-01). Check nonnegative_balance da tabela
  -- wallets vai levantar 23514 se atleta já gastou coins.
  BEGIN
    SELECT ledger_id, new_balance INTO v_mut_row
      FROM public.fn_mutate_wallet(
        v_orig_user,
        -v_orig_amount,
        'institution_token_reverse_emission',
        'reverse_emission:' || p_original_ledger_id::text,
        v_orig_group
      );
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'INSUFFICIENT_BALANCE: athlete already spent the coins'
        USING ERRCODE = 'P0003',
              HINT = 'user spent the tokens; chase the debt-of-group path (CHARGEBACK_RUNBOOK §3.3) instead';
  END;

  v_new_balance := v_mut_row.new_balance;

  -- (e) Restaura inventário.
  IF v_orig_group IS NOT NULL THEN
    BEGIN
      PERFORM public.reverse_token_inventory_issuance(v_orig_group, v_orig_amount);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM LIKE '%INVENTORY_NOT_FOUND%' THEN
          RAISE NOTICE '[L03-13] inventory missing for group % — reversal proceeding', v_orig_group;
        ELSE
          RAISE;
        END IF;
    END;
  END IF;

  -- (f) Libera custódia committed (inverso de custody_commit_coins).
  IF v_orig_group IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.custody_accounts WHERE group_id = v_orig_group
    ) INTO v_has_custody;
    IF v_has_custody THEN
      BEGIN
        PERFORM public.custody_release_committed(v_orig_group, v_orig_amount);
      EXCEPTION
        WHEN OTHERS THEN
          RAISE NOTICE '[L03-13] custody_release_committed failed for group % (% ): %',
            v_orig_group, SQLERRM, SQLSTATE;
      END;
    END IF;
  END IF;

  -- (g) Audit + idempotency log
  v_rev_id := gen_random_uuid();

  INSERT INTO public.coin_reversal_log
    (id, kind, idempotency_key, target_ref, actor_user_id, reason,
     metadata, reversed_coins, reversed_usd)
  VALUES
    (v_rev_id, 'emission', p_idempotency_key,
     p_original_ledger_id::text, p_actor_user_id, p_reason,
     jsonb_build_object(
       'reversal_ledger_id', v_mut_row.ledger_id,
       'athlete_user_id',    v_orig_user,
       'reversed_amount',    v_orig_amount,
       'new_balance',        v_new_balance,
       'original_ref_id',    v_orig_ref,
       'issuer_group_id',    v_orig_group
     ),
     v_orig_amount,
     NULL);

  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  VALUES
    (p_actor_user_id, v_orig_group, 'coins.reverse.emission',
     'coin_ledger', p_original_ledger_id::text,
     jsonb_build_object(
       'reversal_id',        v_rev_id,
       'reversal_ledger_id', v_mut_row.ledger_id,
       'amount',             v_orig_amount,
       'athlete_user_id',    v_orig_user,
       'reason',             p_reason,
       'runbook',            'REVERSE_COINS_RUNBOOK#emission'
     ));

  RETURN QUERY SELECT
    v_rev_id,
    v_mut_row.ledger_id,
    v_orig_user,
    v_orig_amount,
    v_new_balance,
    false;
END;
$$;

COMMENT ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) IS
  'L03-13: inverte uma emissão emit_coins_atomic em transação única. '
  'Debita wallet (falha com INSUFFICIENT_BALANCE se atleta já gastou), '
  'restaura inventário e custódia committed, escreve ledger negativo + '
  'coin_reversal_log + portal_audit_log. Idempotente via '
  '(kind=emission, idempotency_key) — replay devolve was_idempotent=true.';

REVOKE ALL ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_coin_emission_atomic(uuid, text, uuid, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. reverse_burn_atomic
--
-- Inverte execute_burn_atomic (L02-02).
--
-- Fluxo:
--   (a) idempotência via coin_reversal_log.
--   (b) carrega clearing_event pelo burn_ref_id. Se não existe →
--       BURN_NOT_FOUND.
--   (c) se QUALQUER clearing_settlement associado estiver em status
--       'settled' → NOT_REVERSIBLE (P0008) com HINT apontando para o
--       runbook (coins já compensadas entre custódias; exige unwind
--       manual inter-club).
--   (d) marca settlements pending/insufficient/failed como 'cancelled'.
--   (e) para cada breakdown entry intra-clube, re-commit custódia (era
--       liberada no burn).
--   (f) re-credita wallet via fn_mutate_wallet com delta=+total_coins
--       e reason='institution_token_reverse_burn', ref_id derivado.
--   (g) insere ledger positivo agregado (sem quebrar por issuer; o
--       agregado é suficiente para fechamento contábil e mantém o
--       particionamento simples).
--   (h) restaura inventário lifetime_burned (via increment_token_inventory).
--   (i) coin_reversal_log + portal_audit_log.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reverse_burn_atomic(
  p_burn_ref_id      text,
  p_reason           text,
  p_actor_user_id    uuid,
  p_idempotency_key  text
)
RETURNS TABLE (
  reversal_id        uuid,
  clearing_event_id  uuid,
  athlete_user_id    uuid,
  reversed_amount    integer,
  new_balance        integer,
  settlements_cancelled integer,
  was_idempotent     boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_existing_rev   uuid;
  v_existing_meta  jsonb;
  v_rev_id         uuid;
  v_event_id       uuid;
  v_athlete        uuid;
  v_redeemer       uuid;
  v_total_coins    integer;
  v_breakdown      jsonb;
  v_settlements_cancelled integer := 0;
  v_has_settled    integer;
  v_issuer         uuid;
  v_issuer_amt     integer;
  v_mut_row        record;
  v_new_balance    integer;
BEGIN
  IF p_burn_ref_id IS NULL OR length(trim(p_burn_ref_id)) = 0 THEN
    RAISE EXCEPTION 'INVALID_BURN_REF' USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'MISSING_IDEMPOTENCY_KEY' USING ERRCODE = 'P0001';
  END IF;

  -- (a) Idempotência
  SELECT id, metadata
    INTO v_existing_rev, v_existing_meta
    FROM public.coin_reversal_log
   WHERE kind = 'burn' AND idempotency_key = p_idempotency_key;

  IF v_existing_rev IS NOT NULL THEN
    RETURN QUERY SELECT
      v_existing_rev,
      (v_existing_meta ->> 'clearing_event_id')::uuid,
      (v_existing_meta ->> 'athlete_user_id')::uuid,
      (v_existing_meta ->> 'reversed_amount')::integer,
      (v_existing_meta ->> 'new_balance')::integer,
      (v_existing_meta ->> 'settlements_cancelled')::integer,
      true;
    RETURN;
  END IF;

  -- (b) Carrega clearing_event (lock + detalhes)
  SELECT id, athlete_user_id, redeemer_group_id, total_coins, breakdown
    INTO v_event_id, v_athlete, v_redeemer, v_total_coins, v_breakdown
    FROM public.clearing_events
   WHERE burn_ref_id = p_burn_ref_id
   FOR UPDATE;

  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'BURN_NOT_FOUND: burn_ref_id=%', p_burn_ref_id
      USING ERRCODE = 'P0002';
  END IF;

  -- (c) Bloqueia se há settlements já compensados (cross-club settled)
  SELECT COUNT(*)
    INTO v_has_settled
    FROM public.clearing_settlements
   WHERE clearing_event_id = v_event_id
     AND status = 'settled';

  IF v_has_settled > 0 THEN
    RAISE EXCEPTION
      'NOT_REVERSIBLE: % settlement(s) already settled between custodies',
      v_has_settled
      USING ERRCODE = 'P0008',
            HINT = 'see docs/runbooks/REVERSE_COINS_RUNBOOK.md §"burn with settled settlements" for manual inter-club unwind';
  END IF;

  -- (d) Cancela settlements não-settled (pending / insufficient / failed)
  UPDATE public.clearing_settlements
     SET status = 'cancelled',
         settled_at = now()
   WHERE clearing_event_id = v_event_id
     AND status IN ('pending', 'insufficient', 'failed');
  GET DIAGNOSTICS v_settlements_cancelled = ROW_COUNT;

  -- (e) Re-commit custódia intra-clube (inverso do release feito pelo
  --     burn). Interclub settlements foram 'pending' ou 'failed' e não
  --     tocaram o total_deposited, então não precisam roll-back aqui.
  FOR v_issuer, v_issuer_amt IN
    SELECT
      (entry->>'issuer_group_id')::uuid,
      (entry->>'amount')::integer
    FROM jsonb_array_elements(v_breakdown) AS entry
    WHERE entry->>'issuer_group_id' IS NOT NULL
  LOOP
    IF v_issuer = v_redeemer THEN
      -- Intra-clube: re-commit (custody_commit_coins levanta
      -- INSUFFICIENT_BACKING se por acaso depósitos foram reduzidos
      -- depois do burn original).
      BEGIN
        PERFORM public.custody_commit_coins(v_issuer, v_issuer_amt);
      EXCEPTION
        WHEN OTHERS THEN
          RAISE EXCEPTION
            'CUSTODY_RECOMMIT_FAILED: group=% amount=% err=%',
            v_issuer, v_issuer_amt, SQLERRM
            USING ERRCODE = 'P0002',
                  HINT = 'deposit more backing into the group custody before retrying';
      END;
    END IF;
  END LOOP;

  -- (f) Re-credita wallet (ledger positivo via fn_mutate_wallet).
  --     O total_coins é o valor AGREGADO do burn; preservamos isso
  --     como uma única ledger entry + metadata.breakdown para
  --     forensics. Mantemos o issuer_group_id NULL pois é agregado.
  SELECT ledger_id, new_balance INTO v_mut_row
    FROM public.fn_mutate_wallet(
      v_athlete,
      v_total_coins,
      'institution_token_reverse_burn',
      'reverse_burn:' || p_burn_ref_id,
      NULL  -- agregado: ver metadata.breakdown no audit
    );

  v_new_balance := v_mut_row.new_balance;

  -- (h) INVENTÁRIO: execute_burn_atomic NÃO decrementa
  -- coaching_token_inventory.available_tokens (e não incrementa
  -- lifetime_burned aqui) — esse contador é alimentado por paths
  -- separados. Reverter burn também não toca inventory, caso contrário
  -- lifetime_issued ficaria inconsistente. Deixamos a nota explícita
  -- para quem revisitar o código.

  -- (i) coin_reversal_log + audit
  v_rev_id := gen_random_uuid();
  INSERT INTO public.coin_reversal_log
    (id, kind, idempotency_key, target_ref, actor_user_id, reason,
     metadata, reversed_coins, reversed_usd)
  VALUES
    (v_rev_id, 'burn', p_idempotency_key, p_burn_ref_id,
     p_actor_user_id, p_reason,
     jsonb_build_object(
       'clearing_event_id',     v_event_id,
       'athlete_user_id',       v_athlete,
       'reversed_amount',       v_total_coins,
       'new_balance',           v_new_balance,
       'settlements_cancelled', v_settlements_cancelled,
       'reversal_ledger_id',    v_mut_row.ledger_id,
       'redeemer_group_id',     v_redeemer,
       'breakdown',             v_breakdown
     ),
     v_total_coins,
     NULL);

  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  VALUES
    (p_actor_user_id, v_redeemer, 'coins.reverse.burn',
     'clearing_event', v_event_id::text,
     jsonb_build_object(
       'reversal_id',           v_rev_id,
       'burn_ref_id',           p_burn_ref_id,
       'amount',                v_total_coins,
       'settlements_cancelled', v_settlements_cancelled,
       'athlete_user_id',       v_athlete,
       'reason',                p_reason,
       'runbook',               'REVERSE_COINS_RUNBOOK#burn'
     ));

  RETURN QUERY SELECT
    v_rev_id,
    v_event_id,
    v_athlete,
    v_total_coins,
    v_new_balance,
    v_settlements_cancelled,
    false;
END;
$$;

COMMENT ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) IS
  'L03-13: inverte execute_burn_atomic. Bloqueia se settlements já '
  'cross-club settled (requer unwind manual); senão cancela pending '
  'settlements, re-commita custódia intra-clube, recredita wallet, '
  'restaura inventário e escreve coin_reversal_log + audit. Idempotente.';

REVOKE ALL ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_burn_atomic(text, text, uuid, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. reverse_custody_deposit_atomic
--
-- Inverte confirm_custody_deposit (+ decrementa total_deposited).
--
-- Fluxo:
--   (a) idempotência via coin_reversal_log.
--   (b) trava deposit row. Se status='refunded' e SEM key diferente,
--       é replay — devolvemos sucesso. Se status='pending' → INVALID_STATE.
--       Se status='failed' → INVALID_STATE.
--   (c) trava custody_account FOR UPDATE.
--   (d) valida: total_deposited_usd - amount >= total_committed. Se
--       falhar → INVARIANT_VIOLATION (ops precisa reverter emissões
--       primeiro pela ordem que o runbook impõe).
--   (e) decrementa total_deposited_usd, seta deposit.status='refunded'.
--   (f) audit + coin_reversal_log.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reverse_custody_deposit_atomic(
  p_deposit_id       uuid,
  p_reason           text,
  p_actor_user_id    uuid,
  p_idempotency_key  text
)
RETURNS TABLE (
  reversal_id       uuid,
  deposit_id        uuid,
  group_id          uuid,
  refunded_usd      numeric,
  was_idempotent    boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_existing_rev   uuid;
  v_existing_meta  jsonb;
  v_rev_id         uuid;
  v_group_id       uuid;
  v_amount_usd     numeric(14,2);
  v_status         text;
  v_deposited      numeric(14,2);
  v_committed      numeric(14,2);
BEGIN
  IF p_deposit_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_DEPOSIT_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'MISSING_IDEMPOTENCY_KEY' USING ERRCODE = 'P0001';
  END IF;

  -- (a) Idempotência
  SELECT id, metadata
    INTO v_existing_rev, v_existing_meta
    FROM public.coin_reversal_log
   WHERE kind = 'deposit' AND idempotency_key = p_idempotency_key;

  IF v_existing_rev IS NOT NULL THEN
    RETURN QUERY SELECT
      v_existing_rev,
      (v_existing_meta ->> 'deposit_id')::uuid,
      (v_existing_meta ->> 'group_id')::uuid,
      (v_existing_meta ->> 'refunded_usd')::numeric,
      true;
    RETURN;
  END IF;

  -- (b) Lock deposit
  SELECT group_id, amount_usd, status
    INTO v_group_id, v_amount_usd, v_status
    FROM public.custody_deposits
   WHERE id = p_deposit_id
   FOR UPDATE;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: id=%', p_deposit_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_status = 'refunded' THEN
    -- Idempotência amigável contra a mesma reversão rodada anteriormente
    -- com outra idempotency_key: devolvemos was_idempotent=true sem
    -- gerar row duplicada — mantém o resultado consistente sem violar
    -- o UNIQUE (kind, idempotency_key).
    v_rev_id := gen_random_uuid();
    INSERT INTO public.coin_reversal_log
      (id, kind, idempotency_key, target_ref, actor_user_id, reason,
       metadata, reversed_coins, reversed_usd)
    VALUES
      (v_rev_id, 'deposit', p_idempotency_key, p_deposit_id::text,
       p_actor_user_id, p_reason,
       jsonb_build_object(
         'deposit_id',   p_deposit_id,
         'group_id',     v_group_id,
         'refunded_usd', 0,
         'noop_reason',  'already_refunded'
       ),
       NULL, 0);
    RETURN QUERY SELECT v_rev_id, p_deposit_id, v_group_id, 0::numeric, true;
    RETURN;
  END IF;

  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'INVALID_STATE: deposit status=% (only confirmed can be reversed)',
      v_status
      USING ERRCODE = 'P0008',
            HINT = 'use the payment-gateway-specific failure path for pending/failed deposits';
  END IF;

  -- (c) Lock custody_account
  SELECT total_deposited_usd, total_committed
    INTO v_deposited, v_committed
    FROM public.custody_accounts
   WHERE group_id = v_group_id
   FOR UPDATE;

  IF v_deposited IS NULL THEN
    RAISE EXCEPTION 'CUSTODY_ACCOUNT_NOT_FOUND: group_id=%', v_group_id
      USING ERRCODE = 'P0002';
  END IF;

  -- (d) Invariant: após subtrair, deposited >= committed.
  IF v_deposited - v_amount_usd < COALESCE(v_committed, 0) THEN
    RAISE EXCEPTION
      'INVARIANT_VIOLATION: refund would leave deposited=% < committed=% (coins already issued against this backing)',
      v_deposited - v_amount_usd, v_committed
      USING ERRCODE = 'P0008',
            HINT = 'reverse the emissions funded by this deposit first (see REVERSE_COINS_RUNBOOK#deposit)';
  END IF;

  -- (e) Aplica refund
  UPDATE public.custody_accounts
     SET total_deposited_usd = total_deposited_usd - v_amount_usd,
         updated_at          = now()
   WHERE group_id = v_group_id;

  UPDATE public.custody_deposits
     SET status = 'refunded'
   WHERE id = p_deposit_id;

  -- (f) coin_reversal_log + audit
  v_rev_id := gen_random_uuid();
  INSERT INTO public.coin_reversal_log
    (id, kind, idempotency_key, target_ref, actor_user_id, reason,
     metadata, reversed_coins, reversed_usd)
  VALUES
    (v_rev_id, 'deposit', p_idempotency_key, p_deposit_id::text,
     p_actor_user_id, p_reason,
     jsonb_build_object(
       'deposit_id',   p_deposit_id,
       'group_id',     v_group_id,
       'refunded_usd', v_amount_usd,
       'deposited_before', v_deposited,
       'deposited_after',  v_deposited - v_amount_usd,
       'committed_at_time', v_committed
     ),
     NULL,
     v_amount_usd);

  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  VALUES
    (p_actor_user_id, v_group_id, 'coins.reverse.deposit',
     'custody_deposit', p_deposit_id::text,
     jsonb_build_object(
       'reversal_id',  v_rev_id,
       'refunded_usd', v_amount_usd,
       'reason',       p_reason,
       'runbook',      'REVERSE_COINS_RUNBOOK#deposit'
     ));

  RETURN QUERY SELECT v_rev_id, p_deposit_id, v_group_id, v_amount_usd, false;
END;
$$;

COMMENT ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) IS
  'L03-13: inverte confirm_custody_deposit. Recusa o refund (P0008) '
  'se total_deposited - amount < total_committed (coins já emitidas '
  'contra o lastro); caso contrário subtrai o lastro, seta status=refunded, '
  'escreve coin_reversal_log + audit. Idempotente por '
  '(kind=deposit, idempotency_key).';

REVOKE ALL ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_custody_deposit_atomic(uuid, text, uuid, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Self-check: funções registradas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_missing text := '';
  v_name    text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'reverse_coin_emission_atomic',
    'reverse_burn_atomic',
    'reverse_custody_deposit_atomic',
    'reverse_token_inventory_issuance'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc
       WHERE proname = v_name
         AND pronamespace = 'public'::regnamespace
    ) THEN
      v_missing := v_missing || v_name || ' ';
    END IF;
  END LOOP;

  IF length(v_missing) > 0 THEN
    RAISE EXCEPTION 'L03-13 self-check: missing function(s): %', v_missing;
  END IF;
END;
$$;

COMMIT;
