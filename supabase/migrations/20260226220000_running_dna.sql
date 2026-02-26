-- Running DNA: cached athlete profile with radar scores, insights, PR predictions
-- Reference: ROADMAP_NEXT.md §3 DNA do Corredor

CREATE TABLE IF NOT EXISTS public.running_dna (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  radar_scores    JSONB NOT NULL DEFAULT '{}',
  insights        TEXT[] NOT NULL DEFAULT '{}',
  pr_predictions  JSONB,
  stats           JSONB NOT NULL DEFAULT '{}',
  updated_at_ms   BIGINT NOT NULL
);

CREATE INDEX idx_running_dna_user ON public.running_dna(user_id);

ALTER TABLE public.running_dna ENABLE ROW LEVEL SECURITY;

CREATE POLICY "dna_own_read" ON public.running_dna
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "dna_service_upsert" ON public.running_dna
  FOR INSERT WITH CHECK (true);

CREATE POLICY "dna_service_update" ON public.running_dna
  FOR UPDATE USING (true);
