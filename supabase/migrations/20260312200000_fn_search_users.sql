-- Create fn_search_users for friend search in the app.
--
-- 20260226230000_social_profiles.sql criou uma versão anterior com return
-- columns (user_id, display_name, avatar_url, instagram_handle, tiktok_handle).
-- CREATE OR REPLACE não permite mudar return type — precisa DROP antes.
-- Mesma assinatura de args (text, uuid, integer) então o DROP é seguro.
DROP FUNCTION IF EXISTS public.fn_search_users(text, uuid, integer);

CREATE OR REPLACE FUNCTION public.fn_search_users(
  p_query text,
  p_caller_id uuid,
  p_limit integer DEFAULT 20
)
RETURNS TABLE(
  id uuid,
  display_name text,
  avatar_url text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.display_name, p.avatar_url
  FROM profiles p
  WHERE p.id <> p_caller_id
    AND p.display_name ILIKE '%' || p_query || '%'
    AND p.onboarding_state = 'READY'
  ORDER BY p.display_name
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_search_users(text, uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_search_users(text, uuid, integer) TO authenticated;
