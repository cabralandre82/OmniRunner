-- Social profiles: Instagram/TikTok handles + friendship invited_by
-- Reference: Friends & Social Community feature

BEGIN;

-- Add social media handles to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS instagram_handle TEXT,
  ADD COLUMN IF NOT EXISTS tiktok_handle TEXT;

-- Add invited_by to friendships (tracks who initiated)
ALTER TABLE public.friendships
  ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES auth.users(id);

-- Function to search users by display_name (for friend discovery)
CREATE OR REPLACE FUNCTION public.fn_search_users(
  p_query TEXT,
  p_caller_id UUID,
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE(
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  instagram_handle TEXT,
  tiktok_handle TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.display_name,
    p.avatar_url,
    p.instagram_handle,
    p.tiktok_handle
  FROM public.profiles p
  WHERE p.id != p_caller_id
    AND p.display_name ILIKE '%' || p_query || '%'
    AND p.onboarding_state = 'READY'
  ORDER BY
    CASE WHEN p.display_name ILIKE p_query || '%' THEN 0 ELSE 1 END,
    p.display_name
  LIMIT p_limit;
END;
$$;

COMMIT;
