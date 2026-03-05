-- Standardize all remaining Portuguese role values to English
UPDATE public.coaching_members SET role = 'athlete'      WHERE role = 'atleta';
UPDATE public.coaching_members SET role = 'coach'        WHERE role = 'professor';
UPDATE public.coaching_members SET role = 'admin_master'  WHERE role = 'administrador';
UPDATE public.coaching_members SET role = 'assistant'     WHERE role = 'assistente';

UPDATE public.coaching_join_requests SET requested_role = 'athlete'      WHERE requested_role = 'atleta';
UPDATE public.coaching_join_requests SET requested_role = 'coach'        WHERE requested_role = 'professor';
UPDATE public.coaching_join_requests SET requested_role = 'admin_master'  WHERE requested_role = 'administrador';
UPDATE public.coaching_join_requests SET requested_role = 'assistant'     WHERE requested_role = 'assistente';
