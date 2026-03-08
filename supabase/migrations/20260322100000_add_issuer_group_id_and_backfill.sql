-- Add issuer_group_id column to coin_ledger if missing
-- This column was supposed to exist from migration 20260228150001 but
-- the FK reference may have silently failed in that migration.

ALTER TABLE public.coin_ledger
  ADD COLUMN IF NOT EXISTS issuer_group_id UUID;

-- Add FK constraint (safe: IF NOT EXISTS not supported for constraints, use DO block)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_coin_ledger_issuer_group'
      AND table_name = 'coin_ledger'
  ) THEN
    ALTER TABLE public.coin_ledger
      ADD CONSTRAINT fk_coin_ledger_issuer_group
      FOREIGN KEY (issuer_group_id)
      REFERENCES public.coaching_groups(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- Create index for the column
CREATE INDEX IF NOT EXISTS idx_coin_ledger_issuer_group
  ON public.coin_ledger (issuer_group_id)
  WHERE issuer_group_id IS NOT NULL;

-- Backfill: set issuer_group_id from token_intents for existing ISSUE entries
UPDATE public.coin_ledger
SET issuer_group_id = ti.group_id
FROM public.token_intents ti
WHERE coin_ledger.ref_id = ti.id::text
  AND coin_ledger.reason = 'institution_token_issue'
  AND coin_ledger.issuer_group_id IS NULL
  AND ti.group_id IS NOT NULL;
