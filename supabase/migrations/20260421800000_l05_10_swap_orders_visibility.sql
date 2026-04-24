-- L05-10 — swap_orders visibility filter
--
-- Antes: getOpenSwapOffers(groupId) retornava ofertas de TODOS os
-- grupos. Concorrentes diretos enxergavam preços/spreads, vazando
-- estratégia comercial (ex.: clube A vê que clube B está com 20%
-- de desconto e copia ou subbid).
--
-- Depois:
--   • visibility text DEFAULT 'public' CHECK IN ('public','private','whitelist')
--     - public: comportamento legado (qualquer grupo qualificado vê)
--     - private: só seller + buyer já vinculado vêem
--     - whitelist: seller + grupos em whitelist_group_ids vêem
--   • whitelist_group_ids uuid[] DEFAULT '{}'
--   • Policy adicional READ filtra por visibility
--
-- OmniCoin policy: zero writes a coin_ledger ou wallets.
-- L04-07-OK

BEGIN;

ALTER TABLE public.swap_orders
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public';

ALTER TABLE public.swap_orders
  ADD COLUMN IF NOT EXISTS whitelist_group_ids uuid[] NOT NULL DEFAULT '{}';

DO $cnstr$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'swap_orders_visibility_chk'
  ) THEN
    ALTER TABLE public.swap_orders
      ADD CONSTRAINT swap_orders_visibility_chk
      CHECK (visibility IN ('public','private','whitelist'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'swap_orders_whitelist_only_when_used'
  ) THEN
    ALTER TABLE public.swap_orders
      ADD CONSTRAINT swap_orders_whitelist_only_when_used
      CHECK (
        visibility = 'whitelist'
          OR whitelist_group_ids = '{}'::uuid[]
      );
  END IF;
END;
$cnstr$;

CREATE INDEX IF NOT EXISTS idx_swap_orders_visibility_open
  ON public.swap_orders (visibility, created_at DESC)
  WHERE status = 'open';

DROP POLICY IF EXISTS "swap_orders_group_read" ON public.swap_orders;

CREATE POLICY "swap_orders_group_read"
  ON public.swap_orders
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
        AND (
          cm.group_id = swap_orders.seller_group_id
          OR (visibility = 'public'
              AND swap_orders.status IN ('open','matched','settled'))
          OR (visibility = 'private'
              AND swap_orders.buyer_group_id IS NOT NULL
              AND cm.group_id = swap_orders.buyer_group_id)
          OR (visibility = 'whitelist'
              AND cm.group_id = ANY(swap_orders.whitelist_group_ids))
        )
    )
  );

COMMENT ON COLUMN public.swap_orders.visibility IS
  'L05-10: public (legacy/default), private (seller+buyer only), '
  'whitelist (seller + groups in whitelist_group_ids).';

DO $self$
DECLARE
  v_pol_count int;
BEGIN
  SELECT count(*) INTO v_pol_count FROM pg_policies
  WHERE schemaname='public' AND tablename='swap_orders'
    AND policyname='swap_orders_group_read';
  IF v_pol_count <> 1 THEN
    RAISE EXCEPTION 'L05-10 self-test: read policy missing/ambiguous (count=%)', v_pol_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='swap_orders'
      AND column_name='visibility'
  ) THEN
    RAISE EXCEPTION 'L05-10 self-test: visibility column missing';
  END IF;
  RAISE NOTICE 'L05-10 self-test PASSED';
END;
$self$;

COMMIT;
