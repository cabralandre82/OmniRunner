ALTER TABLE public.coaching_workout_templates
  ADD COLUMN IF NOT EXISTS version int NOT NULL DEFAULT 1;

ALTER TABLE public.coaching_training_sessions
  ADD COLUMN IF NOT EXISTS version int NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION public.bump_version()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.version := OLD.version + 1;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_template_version
  BEFORE UPDATE ON public.coaching_workout_templates
  FOR EACH ROW EXECUTE FUNCTION bump_version();

CREATE TRIGGER trg_session_version
  BEFORE UPDATE ON public.coaching_training_sessions
  FOR EACH ROW EXECUTE FUNCTION bump_version();
