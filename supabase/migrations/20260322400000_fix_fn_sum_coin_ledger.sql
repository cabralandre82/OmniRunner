-- fn_sum_coin_ledger_by_group: now that issuer_group_id column exists,
-- replace dynamic SQL stub with a direct query for performance

CREATE OR REPLACE FUNCTION public.fn_sum_coin_ledger_by_group(p_group_id uuid)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sum bigint;
BEGIN
  SELECT COALESCE(SUM(delta_coins), 0)::bigint
  INTO v_sum
  FROM public.coin_ledger
  WHERE issuer_group_id = p_group_id;

  RETURN v_sum;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_sum_coin_ledger_by_group(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sum_coin_ledger_by_group(uuid) TO authenticated;
