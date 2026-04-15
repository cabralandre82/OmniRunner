-- Remove the original 1-argument overload of fn_list_partnerships.
-- The 3-argument version (p_limit, p_offset with DEFAULT) in migration
-- 20260318000000_partner_assessorias_rls_and_remove.sql already covers
-- calls with a single p_group_id argument.
-- Having both caused PGRST203 (ambiguous function) in the PostgREST layer.
DROP FUNCTION IF EXISTS public.fn_list_partnerships(uuid);
