-- Fix: championship_templates only had a SELECT policy.
-- INSERT/UPDATE/DELETE were blocked by RLS, causing "Erro ao salvar modelo".

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'championship_templates'
      AND n.nspname = 'public'
  ) THEN

    DROP POLICY IF EXISTS "championship_templates_insert" ON public.championship_templates;
    CREATE POLICY "championship_templates_insert"
      ON public.championship_templates
      FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.coaching_members cm
          WHERE cm.group_id = championship_templates.owner_group_id
            AND cm.user_id = auth.uid()
            AND cm.role IN ('admin_master', 'professor')
        )
      );

    DROP POLICY IF EXISTS "championship_templates_update" ON public.championship_templates;
    CREATE POLICY "championship_templates_update"
      ON public.championship_templates
      FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM public.coaching_members cm
          WHERE cm.group_id = championship_templates.owner_group_id
            AND cm.user_id = auth.uid()
            AND cm.role IN ('admin_master', 'professor')
        )
      );

    DROP POLICY IF EXISTS "championship_templates_delete" ON public.championship_templates;
    CREATE POLICY "championship_templates_delete"
      ON public.championship_templates
      FOR DELETE
      USING (
        EXISTS (
          SELECT 1 FROM public.coaching_members cm
          WHERE cm.group_id = championship_templates.owner_group_id
            AND cm.user_id = auth.uid()
            AND cm.role IN ('admin_master', 'professor')
        )
      );

  END IF;
END;
$$;
