-- ═══════════════════════════════════════════════════════════════════════════
-- L05-09 — Custody daily deposit cap (antifraude / AML guardrail)
--
-- Problema (CPO 5.9, Lente 5):
--   Não há limite por grupo/dia de depósitos em `custody_deposits`. Um
--   admin_master comprometido (ou a chave service_role vazada para um
--   grupo) pode depositar US$ 10M de uma vez, lavando dinheiro através
--   da plataforma — não há custo material para o atacante: o gateway
--   (Stripe/MercadoPago) cobra cartão/PIX, o lastro entra em
--   `custody_accounts.total_deposited_usd`, e a partir daí tudo flui
--   pela mesma cadeia que cobre depósitos legítimos.
--
-- Defesa em profundidade — esta migration é a 4ª camada (após
--   L01-04 ownership cross-group + L01-04 idempotency + L18-01 wallet
--   mutation guard). Adiciona um TETO POR DIA por grupo, configurável
--   por platform_admin, com trilha de auditoria completa.
--
-- Modelo:
--   • Cada `custody_accounts` ganha 3 colunas: `daily_deposit_limit_usd`
--     (default 50_000.00), `daily_limit_timezone` (default
--     'America/Sao_Paulo' — produto BR-first), `daily_limit_updated_at`
--     + `daily_limit_updated_by` para forensics.
--   • Janela "hoje" é definida por `daily_limit_timezone` da própria
--     conta, não global UTC — assessoria que opera em outra TZ pode ter
--     o teto realinhado sem migration.
--   • Função `fn_check_daily_deposit_window(group_id, amount_usd)`
--     READ-only: retorna current_total/limit/available/would_exceed +
--     window_start/end e a TZ ativa. Útil para preview no frontend e
--     para debugging.
--   • Função `fn_apply_daily_deposit_cap(group_id, amount_usd)` RAISES
--     `DAILY_DEPOSIT_CAP_EXCEEDED (P0010)` se o depósito ultrapassaria
--     o teto — chamada DENTRO de `fn_create_custody_deposit_idempotent`
--     APENAS no miss-path (replay idempotente já consumiu o budget na
--     criação original e não deve re-cobrar).
--   • Função `fn_set_daily_deposit_cap(group_id, new_cap, actor, reason)`
--     atomicamente atualiza o cap e grava em `custody_daily_cap_changes`
--     (audit table dedicada — query CFO mais barata que filtrar
--     `portal_audit_log` por action LIKE).
--
-- Política contábil:
--   Janela conta `status IN ('pending','confirmed')`. Refunded/failed
--   NÃO contam (foram revertidos via L03-13 ou nunca completaram).
--   Isso permite que reversões via `reverse_custody_deposit_atomic`
--   liberem budget dentro do mesmo dia — útil para corrigir erros
--   sem ter que esperar 24h.
--
-- Backwards compat:
--   • Aditivo: 3 colunas novas com DEFAULT, 4 funções novas, 1 tabela
--     audit nova.
--   • `fn_create_custody_deposit_idempotent` mantém signature; a única
--     mudança observável é o novo error code P0010 quando o teto é
--     ultrapassado (mapeado em `POST /api/custody` como 422
--     DAILY_DEPOSIT_CAP_EXCEEDED).
--   • Backfill: contas pré-existentes ganham default 50_000 + TZ
--     'America/Sao_Paulo'. Platform admin pode ajustar via novo
--     endpoint `PATCH /api/platform/custody/[groupId]/daily-cap`.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Schema: custody_accounts ganha 3 colunas
-- ───────────────────────────────────────────────────────────────────────────
ALTER TABLE public.custody_accounts
  ADD COLUMN IF NOT EXISTS daily_deposit_limit_usd numeric(14,2)
    NOT NULL DEFAULT 50000.00
    CHECK (daily_deposit_limit_usd >= 0);

ALTER TABLE public.custody_accounts
  ADD COLUMN IF NOT EXISTS daily_limit_timezone text
    NOT NULL DEFAULT 'America/Sao_Paulo';

ALTER TABLE public.custody_accounts
  ADD COLUMN IF NOT EXISTS daily_limit_updated_at timestamptz;

ALTER TABLE public.custody_accounts
  ADD COLUMN IF NOT EXISTS daily_limit_updated_by uuid
    REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.custody_accounts.daily_deposit_limit_usd IS
  'L05-09: teto diário (USD) de depósitos PENDING+CONFIRMED para este grupo. '
  'Default 50_000. Zero = depósitos bloqueados. Alterar via '
  'fn_set_daily_deposit_cap (audit-trailed).';

COMMENT ON COLUMN public.custody_accounts.daily_limit_timezone IS
  'L05-09: timezone IANA usada para definir a janela "hoje" do cap. '
  'Default America/Sao_Paulo (produto BR-first). Aceita qualquer TZ '
  'reconhecida por pg_timezone_names.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Audit table — histórico de mudanças do cap
--    Mantemos separada de portal_audit_log porque CFO consulta
--    "deltas de cap nas últimas 24h" frequentemente, e essa tabela é
--    estreita (3 colunas vs metadata jsonb arbitrário) — query barata
--    e indexada.
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.custody_daily_cap_changes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  previous_cap_usd numeric(14,2) NOT NULL,
  new_cap_usd     numeric(14,2) NOT NULL CHECK (new_cap_usd >= 0),
  actor_user_id   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason          text NOT NULL CHECK (length(trim(reason)) >= 10),
  changed_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_custody_daily_cap_changes_group
  ON public.custody_daily_cap_changes(group_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_custody_daily_cap_changes_actor
  ON public.custody_daily_cap_changes(actor_user_id, changed_at DESC);

ALTER TABLE public.custody_daily_cap_changes ENABLE ROW LEVEL SECURITY;

-- Idempotent CREATE POLICY (Postgres < 15 doesn't support IF NOT EXISTS)
DROP POLICY IF EXISTS "cap_changes_admin_master_read"
  ON public.custody_daily_cap_changes;

CREATE POLICY "cap_changes_admin_master_read"
  ON public.custody_daily_cap_changes
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = custody_daily_cap_changes.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

REVOKE ALL ON TABLE public.custody_daily_cap_changes FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.custody_daily_cap_changes TO authenticated;
GRANT ALL ON TABLE public.custody_daily_cap_changes TO service_role;

COMMENT ON TABLE public.custody_daily_cap_changes IS
  'L05-09: histórico de alterações em custody_accounts.daily_deposit_limit_usd. '
  'Cada mudança via fn_set_daily_deposit_cap grava 1 row aqui. '
  'CFO usa para reconciliação e investigação de fraude.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. fn_check_daily_deposit_window — read-only preview
--    Devolve a janela diária ATIVA + uso corrente + se um depósito de
--    `p_amount_usd` (passe 0 só para inspecionar) ultrapassaria o teto.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_check_daily_deposit_window(
  p_group_id     uuid,
  p_amount_usd   numeric DEFAULT 0
)
  RETURNS TABLE(
    current_total_usd   numeric,
    daily_limit_usd     numeric,
    available_today_usd numeric,
    would_exceed        boolean,
    window_start_utc    timestamptz,
    window_end_utc      timestamptz,
    timezone            text
  )
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_tz            text;
  v_limit         numeric(14,2);
  v_window_start  timestamptz;
  v_window_end    timestamptz;
  v_total         numeric(14,2);
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_group_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_amount_usd IS NULL OR p_amount_usd < 0 THEN
    RAISE EXCEPTION 'p_amount_usd must be >= 0' USING ERRCODE = 'P0001';
  END IF;

  -- Carrega TZ + cap. Se a conta não existe ainda, defaults conservadores
  -- (TZ Sao_Paulo, cap 50_000) — coerente com a coluna DEFAULT.
  SELECT ca.daily_limit_timezone, ca.daily_deposit_limit_usd
    INTO v_tz, v_limit
  FROM public.custody_accounts ca
  WHERE ca.group_id = p_group_id;

  IF v_tz IS NULL THEN
    v_tz    := 'America/Sao_Paulo';
    v_limit := 50000.00;
  END IF;

  -- Janela "hoje" no TZ da conta. `date_trunc('day', now() AT TIME ZONE tz)`
  -- devolve um timestamp NAIVE (sem TZ) equivalente à 00:00 local; o
  -- AT TIME ZONE seguinte re-introduz a TZ, dando o instante UTC exato.
  v_window_start := (date_trunc('day', now() AT TIME ZONE v_tz)) AT TIME ZONE v_tz;
  v_window_end   := v_window_start + interval '1 day';

  -- Soma depósitos pending+confirmed na janela. Refunded/failed não contam.
  SELECT COALESCE(SUM(d.amount_usd), 0)::numeric(14,2)
    INTO v_total
  FROM public.custody_deposits d
  WHERE d.group_id = p_group_id
    AND d.status IN ('pending', 'confirmed')
    AND d.created_at >= v_window_start
    AND d.created_at < v_window_end;

  RETURN QUERY
  SELECT
    v_total,
    v_limit,
    GREATEST(v_limit - v_total, 0)::numeric(14,2),
    (v_total + p_amount_usd > v_limit),
    v_window_start,
    v_window_end,
    v_tz;
END $$;

REVOKE ALL ON FUNCTION public.fn_check_daily_deposit_window(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_check_daily_deposit_window(uuid, numeric) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_check_daily_deposit_window(uuid, numeric) IS
  'L05-09: read-only preview da janela diária de depósito (current_total, '
  'limit, available, would_exceed). NÃO altera estado. Use no frontend '
  'antes de mostrar o formulário de depósito.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. fn_apply_daily_deposit_cap — guardrail (RAISES on breach)
--    Chamado dentro de fn_create_custody_deposit_idempotent no miss-path.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_apply_daily_deposit_cap(
  p_group_id   uuid,
  p_amount_usd numeric
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
  IF p_amount_usd IS NULL OR p_amount_usd <= 0 THEN
    RAISE EXCEPTION 'p_amount_usd must be > 0' USING ERRCODE = 'P0001';
  END IF;

  SELECT *
    INTO v_check
  FROM public.fn_check_daily_deposit_window(p_group_id, p_amount_usd);

  IF v_check.would_exceed THEN
    RAISE EXCEPTION
      'DAILY_DEPOSIT_CAP_EXCEEDED: group=% would_total=% limit=% tz=%',
      p_group_id, v_check.current_total_usd + p_amount_usd, v_check.daily_limit_usd, v_check.timezone
      USING
        ERRCODE = 'P0010',
        HINT    = format(
          'Cap diário de US$ %s atingido (uso atual US$ %s, disponível US$ %s, janela em %s). '
          'Aumente via PATCH /api/platform/custody/[groupId]/daily-cap (platform admin only) '
          'ou aguarde a próxima janela. Runbook: CUSTODY_DAILY_CAP_RUNBOOK.',
          v_check.daily_limit_usd,
          v_check.current_total_usd,
          v_check.available_today_usd,
          v_check.timezone
        );
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.fn_apply_daily_deposit_cap(uuid, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_apply_daily_deposit_cap(uuid, numeric) TO service_role;

COMMENT ON FUNCTION public.fn_apply_daily_deposit_cap(uuid, numeric) IS
  'L05-09: aplica o cap diário; RAISES P0010 DAILY_DEPOSIT_CAP_EXCEEDED se '
  'o depósito ultrapassaria o teto. Chamado dentro de '
  'fn_create_custody_deposit_idempotent (miss-path).';

-- ───────────────────────────────────────────────────────────────────────────
-- 5. fn_set_daily_deposit_cap — atualiza cap + grava audit
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_daily_deposit_cap(
  p_group_id        uuid,
  p_new_cap_usd     numeric,
  p_actor_user_id   uuid,
  p_reason          text
)
  RETURNS TABLE(
    out_group_id         uuid,
    out_previous_cap_usd numeric,
    out_new_cap_usd      numeric,
    out_changed_at       timestamptz
  )
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_previous numeric(14,2);
  v_now      timestamptz := now();
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_group_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'p_actor_user_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_new_cap_usd IS NULL OR p_new_cap_usd < 0 THEN
    RAISE EXCEPTION 'p_new_cap_usd must be >= 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'p_reason must be >= 10 chars (postmortem obrigatório)'
      USING ERRCODE = 'P0001';
  END IF;

  -- Garante a conta + lock para serializar mudanças.
  INSERT INTO public.custody_accounts (group_id) VALUES (p_group_id)
  ON CONFLICT (group_id) DO NOTHING;

  SELECT ca.daily_deposit_limit_usd
    INTO v_previous
  FROM public.custody_accounts ca
  WHERE ca.group_id = p_group_id
  FOR UPDATE;

  UPDATE public.custody_accounts ca
  SET daily_deposit_limit_usd = p_new_cap_usd,
      daily_limit_updated_at  = v_now,
      daily_limit_updated_by  = p_actor_user_id,
      updated_at              = v_now
  WHERE ca.group_id = p_group_id;

  INSERT INTO public.custody_daily_cap_changes (
    group_id, previous_cap_usd, new_cap_usd, actor_user_id, reason, changed_at
  ) VALUES (
    p_group_id, v_previous, p_new_cap_usd, p_actor_user_id, p_reason, v_now
  );

  RETURN QUERY
  SELECT p_group_id, v_previous, p_new_cap_usd, v_now;
END $$;

REVOKE ALL ON FUNCTION public.fn_set_daily_deposit_cap(uuid, numeric, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_set_daily_deposit_cap(uuid, numeric, uuid, text) TO service_role;

ALTER FUNCTION public.fn_set_daily_deposit_cap(uuid, numeric, uuid, text)
  SET lock_timeout = '2s';

COMMENT ON FUNCTION public.fn_set_daily_deposit_cap(uuid, numeric, uuid, text) IS
  'L05-09: atualiza custody_accounts.daily_deposit_limit_usd e grava entry em '
  'custody_daily_cap_changes. Reason >= 10 chars (postmortem obrigatório). '
  'Chamado por PATCH /api/platform/custody/[groupId]/daily-cap.';

-- ───────────────────────────────────────────────────────────────────────────
-- 6. fn_create_custody_deposit_idempotent — wire cap check no miss-path
--    Mantém signature idêntica; replay idempotente NÃO re-cobra (se a
--    chave já produziu um deposit, ele já consumiu seu budget na criação
--    original). Apenas miss-path (chave nova) chama o cap.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_create_custody_deposit_idempotent(
  p_group_id          uuid,
  p_amount_usd        numeric,
  p_coins_equivalent  integer,
  p_payment_gateway   text,
  p_idempotency_key   text
)
  RETURNS TABLE(
    deposit_id        uuid,
    was_idempotent    boolean,
    status            text,
    amount_usd        numeric,
    coins_equivalent  integer,
    payment_gateway   text,
    payment_reference text,
    created_at        timestamptz
  )
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing_id uuid;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_group_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'p_idempotency_key must be >= 8 chars (UUID v4 recomendado)'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_amount_usd IS NULL OR p_amount_usd <= 0 THEN
    RAISE EXCEPTION 'p_amount_usd must be > 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_coins_equivalent IS NULL OR p_coins_equivalent <= 0 THEN
    RAISE EXCEPTION 'p_coins_equivalent must be > 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_payment_gateway NOT IN ('stripe', 'mercadopago') THEN
    RAISE EXCEPTION 'p_payment_gateway must be stripe|mercadopago' USING ERRCODE = 'P0001';
  END IF;

  -- Idempotency hit: a chave já gravou um deposit para este grupo.
  -- Replay devolve o deposit existente sem re-cobrar o cap (já contado).
  SELECT d.id INTO v_existing_id
  FROM public.custody_deposits d
  WHERE d.group_id = p_group_id
    AND d.idempotency_key = p_idempotency_key
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN QUERY
      SELECT d.id, true, d.status, d.amount_usd, d.coins_equivalent,
             d.payment_gateway, d.payment_reference, d.created_at
      FROM public.custody_deposits d
      WHERE d.id = v_existing_id;
    RETURN;
  END IF;

  -- L05-09 — miss-path: cobra o cap diário ANTES de inserir. RAISES
  -- P0010 DAILY_DEPOSIT_CAP_EXCEEDED se ultrapassaria o teto.
  PERFORM public.fn_apply_daily_deposit_cap(p_group_id, p_amount_usd);

  -- Miss → INSERT. Race com outro request com mesma chave é resolvido
  -- por unique_violation (UNIQUE composto group_id + idempotency_key).
  BEGIN
    INSERT INTO public.custody_deposits (
      group_id, amount_usd, coins_equivalent, payment_gateway,
      status, idempotency_key
    )
    VALUES (
      p_group_id, p_amount_usd, p_coins_equivalent, p_payment_gateway,
      'pending', p_idempotency_key
    )
    RETURNING id INTO v_existing_id;

    RETURN QUERY
      SELECT d.id, false, d.status, d.amount_usd, d.coins_equivalent,
             d.payment_gateway, d.payment_reference, d.created_at
      FROM public.custody_deposits d
      WHERE d.id = v_existing_id;
    RETURN;

  EXCEPTION WHEN unique_violation THEN
    -- Race: outro request criou primeiro. Devolve o vencedor (replay).
    SELECT d.id INTO v_existing_id
    FROM public.custody_deposits d
    WHERE d.group_id = p_group_id AND d.idempotency_key = p_idempotency_key;

    RETURN QUERY
      SELECT d.id, true, d.status, d.amount_usd, d.coins_equivalent,
             d.payment_gateway, d.payment_reference, d.created_at
      FROM public.custody_deposits d
      WHERE d.id = v_existing_id;
    RETURN;
  END;
END $$;

REVOKE ALL ON FUNCTION public.fn_create_custody_deposit_idempotent(uuid, numeric, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_create_custody_deposit_idempotent(uuid, numeric, integer, text, text) TO service_role;

ALTER FUNCTION public.fn_create_custody_deposit_idempotent(uuid, numeric, integer, text, text)
  SET lock_timeout = '2s';

COMMENT ON FUNCTION public.fn_create_custody_deposit_idempotent(uuid, numeric, integer, text, text) IS
  'L01-04 + L05-09: cria custody_deposit idempotente com cap diário. Replay '
  'da mesma idempotency_key NÃO re-cobra o cap. Miss-path RAISES P0010 '
  'DAILY_DEPOSIT_CAP_EXCEEDED se ultrapassaria daily_deposit_limit_usd.';

-- ───────────────────────────────────────────────────────────────────────────
-- 7. Self-test (DO block, exercita cap + audit + idempotência interaction)
--    Validações:
--      (a) coluna daily_deposit_limit_usd criada com default 50_000
--      (b) fn_check_daily_deposit_window devolve a janela correta
--      (c) fn_apply_daily_deposit_cap RAISES P0010 quando excede
--      (d) fn_create_custody_deposit_idempotent miss-path bloqueia
--      (e) replay idempotente devolve deposit existente sem re-cobrar
--      (f) fn_set_daily_deposit_cap atualiza + grava audit
-- ───────────────────────────────────────────────────────────────────────────
DO $selftest$
DECLARE
  v_group_id        uuid;
  v_actor           uuid;
  v_window          record;
  v_set             record;
  v_caught          boolean := false;
  v_dep_id          uuid;
  v_dep2_id         uuid;
  v_was_idem        boolean;
  v_change_count    int;
BEGIN
  -- (a) coluna existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'custody_accounts'
      AND column_name = 'daily_deposit_limit_usd'
  ) THEN
    RAISE EXCEPTION '[L05-09] coluna daily_deposit_limit_usd não criada';
  END IF;

  -- Acha um grupo + um user para o teste; se não houver, pula
  SELECT id INTO v_group_id FROM public.coaching_groups LIMIT 1;
  SELECT id INTO v_actor FROM auth.users LIMIT 1;

  IF v_group_id IS NULL OR v_actor IS NULL THEN
    RAISE NOTICE '[L05-09] sem coaching_groups/auth.users — skip RPC self-test';
    RETURN;
  END IF;

  -- Garante conta com cap conhecido para o teste (BR TZ)
  INSERT INTO public.custody_accounts (group_id) VALUES (v_group_id)
  ON CONFLICT DO NOTHING;

  PERFORM public.fn_set_daily_deposit_cap(
    v_group_id, 1000.00, v_actor,
    'L05-09 self-test: set cap to 1000 for guardrail probe'
  );

  -- Limpa qualquer deposit antigo na janela (teste hermético)
  DELETE FROM public.custody_deposits
  WHERE group_id = v_group_id
    AND idempotency_key LIKE 'L05-09-selftest-%';

  -- (b) preview window: 0 atual, 1000 limit, 200 amount → not exceed
  SELECT * INTO v_window FROM public.fn_check_daily_deposit_window(v_group_id, 200.00);
  IF v_window.would_exceed IS NOT FALSE THEN
    RAISE EXCEPTION '[L05-09] window check (200) should not exceed: %', v_window;
  END IF;

  -- (c) preview window: 1500 amount → exceed
  SELECT * INTO v_window FROM public.fn_check_daily_deposit_window(v_group_id, 1500.00);
  IF v_window.would_exceed IS NOT TRUE THEN
    RAISE EXCEPTION '[L05-09] window check (1500) should exceed: %', v_window;
  END IF;

  -- (d) miss-path: cria primeiro deposit ok (200 USD)
  SELECT deposit_id, was_idempotent
    INTO v_dep_id, v_was_idem
  FROM public.fn_create_custody_deposit_idempotent(
    v_group_id, 200.00, 200, 'stripe', 'L05-09-selftest-aaaaaaaa-1'
  );

  IF v_dep_id IS NULL OR v_was_idem IS NOT FALSE THEN
    RAISE EXCEPTION '[L05-09] first deposit failed (id=% idem=%)', v_dep_id, v_was_idem;
  END IF;

  -- (e) replay idempotente: mesma chave devolve mesmo deposit, was_idem=true
  SELECT deposit_id, was_idempotent
    INTO v_dep2_id, v_was_idem
  FROM public.fn_create_custody_deposit_idempotent(
    v_group_id, 200.00, 200, 'stripe', 'L05-09-selftest-aaaaaaaa-1'
  );

  IF v_dep2_id IS DISTINCT FROM v_dep_id OR v_was_idem IS NOT TRUE THEN
    RAISE EXCEPTION '[L05-09] idempotent replay failed (dep1=% dep2=% idem=%)',
      v_dep_id, v_dep2_id, v_was_idem;
  END IF;

  -- (d, neg) miss-path: tentar 1500 ultrapassa o cap (já tem 200) → P0010
  v_caught := false;
  BEGIN
    PERFORM public.fn_create_custody_deposit_idempotent(
      v_group_id, 1500.00, 1500, 'stripe', 'L05-09-selftest-bbbbbbbb-2'
    );
  EXCEPTION
    WHEN SQLSTATE 'P0010' THEN v_caught := true;
  END;

  IF NOT v_caught THEN
    RAISE EXCEPTION '[L05-09] expected P0010 DAILY_DEPOSIT_CAP_EXCEEDED on 1500 deposit';
  END IF;

  -- (f) audit table tem 1 row pelo set_cap inicial (de 50000 → 1000)
  SELECT count(*) INTO v_change_count
  FROM public.custody_daily_cap_changes
  WHERE group_id = v_group_id
    AND reason LIKE 'L05-09 self-test:%';

  IF v_change_count < 1 THEN
    RAISE EXCEPTION '[L05-09] audit table missing self-test row (count=%)', v_change_count;
  END IF;

  -- Cleanup hermético
  DELETE FROM public.custody_deposits
  WHERE group_id = v_group_id
    AND idempotency_key LIKE 'L05-09-selftest-%';

  DELETE FROM public.custody_daily_cap_changes
  WHERE group_id = v_group_id
    AND reason LIKE 'L05-09 self-test:%';

  -- Devolve o cap default (50_000) deixando a conta como encontramos
  UPDATE public.custody_accounts
  SET daily_deposit_limit_usd = 50000.00,
      daily_limit_updated_at  = NULL,
      daily_limit_updated_by  = NULL
  WHERE group_id = v_group_id;

  RAISE NOTICE '[L05-09] self-test OK — cap guardrail + audit + idempotency interaction validated';
END
$selftest$;
