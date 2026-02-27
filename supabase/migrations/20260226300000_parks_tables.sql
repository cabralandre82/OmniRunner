-- ============================================================================
-- Omni Runner — Parks: tables, seed, leaderboard view
-- Date: 2026-02-26
-- Origin: DECISÃO 084 — Parks end-to-end
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. parks — catalog of known running parks
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.parks (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  city          TEXT NOT NULL,
  state         TEXT NOT NULL,
  center_lat    DOUBLE PRECISION NOT NULL,
  center_lng    DOUBLE PRECISION NOT NULL,
  radius_m      DOUBLE PRECISION NOT NULL DEFAULT 1000,
  area_sq_m     DOUBLE PRECISION,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.parks IS
  'Known running parks. radius_m used for point-in-radius detection on activity import.';

ALTER TABLE public.parks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "parks_read_all" ON public.parks
  FOR SELECT USING (true);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. park_activities — activities linked to a park
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.park_activities (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  park_id             TEXT NOT NULL REFERENCES public.parks(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id          UUID REFERENCES public.sessions(id) ON DELETE SET NULL,
  strava_activity_id  BIGINT,
  display_name        TEXT,
  distance_m          DOUBLE PRECISION NOT NULL DEFAULT 0,
  moving_time_s       INTEGER NOT NULL DEFAULT 0,
  avg_pace_sec_km     DOUBLE PRECISION,
  avg_heartrate       DOUBLE PRECISION,
  start_time          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.park_activities IS
  'Activities matched to a park via GPS proximity. Populated by strava-webhook.';

CREATE INDEX idx_park_activities_park ON public.park_activities(park_id, start_time DESC);
CREATE INDEX idx_park_activities_user ON public.park_activities(user_id);
CREATE UNIQUE INDEX idx_park_activities_session ON public.park_activities(session_id)
  WHERE session_id IS NOT NULL;

ALTER TABLE public.park_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "park_activities_read_all" ON public.park_activities
  FOR SELECT USING (true);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. park_segments — named segments within a park (future)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.park_segments (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  park_id               TEXT NOT NULL REFERENCES public.parks(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  length_m              DOUBLE PRECISION NOT NULL DEFAULT 0,
  record_holder_name    TEXT,
  record_holder_id      UUID REFERENCES auth.users(id),
  record_pace_sec_per_km DOUBLE PRECISION,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.park_segments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "park_segments_read_all" ON public.park_segments
  FOR SELECT USING (true);

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. park_leaderboard — materialized view as table, refreshed periodically
-- ═══════════════════════════════════════════════════════════════════════════
-- Using a table + function instead of a materialized view for RLS support.

CREATE TABLE IF NOT EXISTS public.park_leaderboard (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  park_id       TEXT NOT NULL REFERENCES public.parks(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name  TEXT,
  category      TEXT NOT NULL CHECK (category IN ('pace', 'distance', 'frequency', 'streak', 'evolution', 'longestRun')),
  rank          INTEGER NOT NULL,
  value         DOUBLE PRECISION NOT NULL,
  period        TEXT NOT NULL DEFAULT 'all_time',
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_park_leaderboard_park ON public.park_leaderboard(park_id, category, rank);

ALTER TABLE public.park_leaderboard ENABLE ROW LEVEL SECURITY;

CREATE POLICY "park_leaderboard_read_all" ON public.park_leaderboard
  FOR SELECT USING (true);

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. fn_refresh_park_leaderboard — recompute rankings for a park
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_refresh_park_leaderboard(p_park_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.park_leaderboard WHERE park_id = p_park_id;

  -- Category: pace (best avg pace, lower is better)
  INSERT INTO public.park_leaderboard (park_id, user_id, display_name, category, rank, value)
  SELECT
    p_park_id,
    user_id,
    display_name,
    'pace',
    ROW_NUMBER() OVER (ORDER BY MIN(avg_pace_sec_km) ASC),
    MIN(avg_pace_sec_km)
  FROM public.park_activities
  WHERE park_id = p_park_id
    AND avg_pace_sec_km IS NOT NULL
    AND avg_pace_sec_km > 0
  GROUP BY user_id, display_name;

  -- Category: distance (total distance accumulated)
  INSERT INTO public.park_leaderboard (park_id, user_id, display_name, category, rank, value)
  SELECT
    p_park_id,
    user_id,
    display_name,
    'distance',
    ROW_NUMBER() OVER (ORDER BY SUM(distance_m) DESC),
    SUM(distance_m)
  FROM public.park_activities
  WHERE park_id = p_park_id
  GROUP BY user_id, display_name;

  -- Category: frequency (number of visits)
  INSERT INTO public.park_leaderboard (park_id, user_id, display_name, category, rank, value)
  SELECT
    p_park_id,
    user_id,
    display_name,
    'frequency',
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC),
    COUNT(*)
  FROM public.park_activities
  WHERE park_id = p_park_id
  GROUP BY user_id, display_name;

  -- Category: longestRun (single longest run)
  INSERT INTO public.park_leaderboard (park_id, user_id, display_name, category, rank, value)
  SELECT
    p_park_id,
    user_id,
    display_name,
    'longestRun',
    ROW_NUMBER() OVER (ORDER BY MAX(distance_m) DESC),
    MAX(distance_m)
  FROM public.park_activities
  WHERE park_id = p_park_id
  GROUP BY user_id, display_name;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Trigger: auto-refresh leaderboard on new park_activity
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_park_activity_refresh()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM public.fn_refresh_park_leaderboard(NEW.park_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_park_activity_inserted
  AFTER INSERT ON public.park_activities
  FOR EACH ROW EXECUTE FUNCTION public.trg_park_activity_refresh();

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. Seed parks from app catalog
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.parks (id, name, city, state, center_lat, center_lng, radius_m, area_sq_m) VALUES
  ('park_ibirapuera', 'Parque Ibirapuera', 'São Paulo', 'SP', -23.5874, -46.6576, 700, 1584000),
  ('park_villa_lobos', 'Parque Villa-Lobos', 'São Paulo', 'SP', -23.5468, -46.7219, 550, 732000),
  ('park_povo', 'Parque do Povo', 'São Paulo', 'SP', -23.5856, -46.6908, 300, 133000),
  ('park_ceret', 'CERET', 'São Paulo', 'SP', -23.5757, -46.5896, 400, 286000),
  ('park_aterro_flamengo', 'Aterro do Flamengo', 'Rio de Janeiro', 'RJ', -22.9320, -43.1740, 800, 1200000),
  ('park_lagoa', 'Lagoa Rodrigo de Freitas', 'Rio de Janeiro', 'RJ', -22.9711, -43.2105, 900, 2180000),
  ('park_barigui', 'Parque Barigui', 'Curitiba', 'PR', -25.4230, -49.3115, 700, 1400000),
  ('park_cidade_brasilia', 'Parque da Cidade Sarah Kubitschek', 'Brasília', 'DF', -15.8050, -47.8920, 1200, 4200000),
  ('park_mangabeiras', 'Parque das Mangabeiras', 'Belo Horizonte', 'MG', -19.9530, -43.9180, 900, 2350000),
  ('park_redempcao', 'Parque da Redenção', 'Porto Alegre', 'RS', -30.0385, -51.2140, 450, 376000),
  ('park_moinhos', 'Parque Moinhos de Vento (Parcão)', 'Porto Alegre', 'RS', -30.0260, -51.2000, 250, 115000),
  ('park_carmo', 'Parque do Carmo', 'São Paulo', 'SP', -23.5800, -46.4780, 700, 1500000),
  ('park_aclimacao', 'Parque da Aclimação', 'São Paulo', 'SP', -23.5715, -46.6335, 250, 112000),
  ('park_piqueri', 'Parque Piqueri', 'São Paulo', 'SP', -23.5280, -46.5750, 200, 97000),
  ('park_ecologico_tiete', 'Parque Ecológico do Tietê', 'São Paulo', 'SP', -23.5050, -46.5400, 1500, 14000000),
  ('park_independencia', 'Parque da Independência', 'São Paulo', 'SP', -23.5850, -46.6115, 300, 161000),
  ('park_quinta_boa_vista', 'Quinta da Boa Vista', 'Rio de Janeiro', 'RJ', -22.9060, -43.2230, 350, 155000),
  ('park_tijuca', 'Parque Nacional da Tijuca', 'Rio de Janeiro', 'RJ', -22.9570, -43.2870, 3000, 39530000),
  ('park_orla_copacabana', 'Orla de Copacabana', 'Rio de Janeiro', 'RJ', -22.9711, -43.1823, 500, 160000),
  ('park_agua_mineral', 'Parque Nacional de Brasília (Água Mineral)', 'Brasília', 'DF', -15.7350, -47.9300, 4000, 42389000),
  ('park_olhos_dagua', 'Parque Olhos D''Água', 'Brasília', 'DF', -15.7700, -47.8600, 350, 210000),
  ('park_ermida_dom_bosco', 'Ermida Dom Bosco / Orla do Lago', 'Brasília', 'DF', -15.8350, -47.8400, 200, 50000),
  ('park_jaqueira', 'Parque da Jaqueira', 'Recife', 'PE', -8.0370, -34.8990, 200, 70000),
  ('park_dona_lindu', 'Parque Dona Lindu', 'Recife', 'PE', -8.1300, -34.9060, 150, 27000),
  ('park_pituacu', 'Parque Metropolitano de Pituaçu', 'Salvador', 'BA', -12.9600, -38.4300, 1000, 4250000),
  ('park_cidade_salvador', 'Parque da Cidade (Salvador)', 'Salvador', 'BA', -13.0050, -38.4630, 500, 720000),
  ('park_cocó', 'Parque do Cocó', 'Fortaleza', 'CE', -3.7450, -38.4900, 700, 1571000),
  ('park_beira_mar_fortaleza', 'Calçadão da Beira-Mar', 'Fortaleza', 'CE', -3.7250, -38.5050, 500, 80000),
  ('park_tangua', 'Parque Tanguá', 'Curitiba', 'PR', -25.3835, -49.2846, 350, 235000),
  ('park_botanico_curitiba', 'Jardim Botânico de Curitiba', 'Curitiba', 'PR', -25.4420, -49.2373, 300, 178000),
  ('park_lagoa_pampulha', 'Orla da Lagoa da Pampulha', 'Belo Horizonte', 'MG', -19.8630, -43.9700, 1200, 3800000),
  ('park_municipal_bh', 'Parque Municipal Américo Renné Giannetti', 'Belo Horizonte', 'MG', -19.9290, -43.9370, 300, 182000),
  ('park_flamboyant', 'Parque Flamboyant', 'Goiânia', 'GO', -16.7130, -49.2430, 300, 125000),
  ('park_vacas_brava', 'Parque Vaca Brava', 'Goiânia', 'GO', -16.7050, -49.2720, 150, 19000),
  ('park_bosque_buritis', 'Bosque dos Buritis', 'Goiânia', 'GO', -16.6810, -49.2690, 250, 120000),
  ('park_mindu', 'Parque Municipal do Mindú', 'Manaus', 'AM', -3.0960, -60.0200, 350, 330000),
  ('park_bosque_rodrigues_alves', 'Bosque Rodrigues Alves', 'Belém', 'PA', -1.4280, -48.4700, 250, 150000),
  ('park_beira_mar_floripa', 'Parque Linear Beira-Mar', 'Florianópolis', 'SC', -27.5870, -48.5400, 350, 70000),
  ('park_taquaral', 'Parque Portugal (Taquaral)', 'Campinas', 'SP', -22.8710, -47.0490, 500, 650000),
  ('park_pedra_cebola', 'Parque Pedra da Cebola', 'Vitória', 'ES', -20.2860, -40.2890, 250, 100000),
  ('park_cidade_natal', 'Parque da Cidade (Natal)', 'Natal', 'RN', -5.8450, -35.2130, 500, 640000),
  ('park_lagoa_jansen', 'Parque Ecológico da Lagoa da Jansen', 'São Luís', 'MA', -2.4980, -44.2870, 300, 150000),
  ('park_nacoes_indigenas', 'Parque das Nações Indígenas', 'Campo Grande', 'MS', -20.4530, -54.5880, 700, 1190000),
  ('park_solon_lucena', 'Parque Solon de Lucena (Lagoa)', 'João Pessoa', 'PB', -7.1190, -34.8780, 200, 65000),
  ('park_cidade_niteroi', 'Parque da Cidade (Niterói)', 'Niterói', 'RJ', -22.9330, -43.0840, 300, 149000),
  ('park_orla_santos', 'Orla de Santos', 'Santos', 'SP', -23.9700, -46.3350, 1000, 200000),
  ('park_curupira', 'Parque Curupira', 'Ribeirão Preto', 'SP', -21.1850, -47.8280, 250, 120000)
ON CONFLICT (id) DO NOTHING;

COMMIT;
