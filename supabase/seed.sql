-- ============================================================================
-- Omni Runner — Seed Data
-- Badges catalog (MVP — 30 badges) + First Season
-- ============================================================================

-- ── First Season ─────────────────────────────────────────────────────────────
INSERT INTO public.seasons (id, name, status, starts_at_ms, ends_at_ms)
VALUES (
  'a1b2c3d4-0001-4000-8000-000000000001',
  'Temporada de Verão 2026',
  'active',
  1735689600000,  -- 2026-01-01 00:00:00 UTC
  1743465600000   -- 2026-03-31 23:59:59 UTC
) ON CONFLICT (id) DO NOTHING;

-- ── Badge Catalog ────────────────────────────────────────────────────────────

INSERT INTO public.badges (id, category, tier, name, description, xp_reward, coins_reward, criteria_type, criteria_json, is_secret) VALUES
-- Distance (8)
('badge_first_km', 'distance', 'bronze', 'Primeiro Quilômetro', 'Complete 1 sessão verificada ≥ 1 km', 50, 0, 'single_session_distance', '{"threshold_m": 1000}', false),
('badge_5k', 'distance', 'bronze', '5K Runner', 'Complete 1 sessão ≥ 5 km', 50, 0, 'single_session_distance', '{"threshold_m": 5000}', false),
('badge_10k', 'distance', 'silver', '10K Runner', 'Complete 1 sessão ≥ 10 km', 100, 0, 'single_session_distance', '{"threshold_m": 10000}', false),
('badge_half_marathon', 'distance', 'gold', 'Meia Maratona', 'Complete 1 sessão ≥ 21.1 km', 200, 0, 'single_session_distance', '{"threshold_m": 21100}', false),
('badge_marathon', 'distance', 'diamond', 'Maratona', 'Complete 1 sessão ≥ 42.195 km', 500, 0, 'single_session_distance', '{"threshold_m": 42195}', false),
('badge_50km_total', 'distance', 'bronze', '50 km Acumulados', 'Distância lifetime ≥ 50 km', 50, 0, 'lifetime_distance', '{"threshold_m": 50000}', false),
('badge_200km_total', 'distance', 'silver', '200 km Acumulados', 'Distância lifetime ≥ 200 km', 100, 0, 'lifetime_distance', '{"threshold_m": 200000}', false),
('badge_1000km_total', 'distance', 'gold', '1000 km Acumulados', 'Distância lifetime ≥ 1000 km', 200, 0, 'lifetime_distance', '{"threshold_m": 1000000}', false),
-- Frequency (9)
('badge_first_run', 'frequency', 'bronze', 'Primeiro Passo', 'Primeira sessão verificada completada', 50, 0, 'session_count', '{"count": 1}', false),
('badge_5_runs', 'frequency', 'bronze', 'Corredor Dedicado', '5 sessões verificadas completadas', 50, 0, 'session_count', '{"count": 5}', false),
('badge_10_runs', 'frequency', 'bronze', '10 Corridas', '10 sessões verificadas lifetime', 50, 0, 'session_count', '{"count": 10}', false),
('badge_50_runs', 'frequency', 'silver', '50 Corridas', '50 sessões verificadas lifetime', 100, 0, 'session_count', '{"count": 50}', false),
('badge_100_runs', 'frequency', 'gold', '100 Corridas', '100 sessões verificadas lifetime', 200, 0, 'session_count', '{"count": 100}', false),
('badge_500_runs', 'frequency', 'diamond', '500 Corridas', '500 sessões verificadas lifetime', 500, 0, 'session_count', '{"count": 500}', false),
('badge_streak_3', 'frequency', 'bronze', '3 Dias Seguidos', 'Sequência de 3 dias consecutivos correndo', 50, 0, 'daily_streak', '{"days": 3}', false),
('badge_streak_7', 'frequency', 'silver', '7 Dias Seguidos', 'Streak diário de 7 dias consecutivos', 100, 10, 'daily_streak', '{"days": 7}', false),
('badge_streak_14', 'frequency', 'gold', '14 Dias Seguidos', 'Sequência de 14 dias consecutivos correndo', 200, 0, 'daily_streak', '{"days": 14}', false),
('badge_streak_30', 'frequency', 'gold', '30 Dias Seguidos', 'Streak diário de 30 dias consecutivos', 200, 50, 'daily_streak', '{"days": 30}', false),
('badge_10km_week', 'frequency', 'bronze', '10 km na Semana', 'Corra 10 km ou mais em uma semana', 50, 0, 'weekly_distance', '{"threshold_m": 10000}', false),
-- Speed (5)
('badge_pace_6', 'speed', 'bronze', 'Abaixo de 6:00/km', 'Pace médio < 6:00/km em sessão ≥ 5 km', 50, 0, 'pace_below', '{"max_pace_sec_per_km": 360, "min_distance_m": 5000}', false),
('badge_pace_5', 'speed', 'silver', 'Abaixo de 5:00/km', 'Pace médio < 5:00/km em sessão ≥ 5 km', 100, 0, 'pace_below', '{"max_pace_sec_per_km": 300, "min_distance_m": 5000}', false),
('badge_pace_430', 'speed', 'gold', 'Abaixo de 4:30/km', 'Pace médio < 4:30/km em sessão ≥ 5 km', 200, 0, 'pace_below', '{"max_pace_sec_per_km": 270, "min_distance_m": 5000}', false),
('badge_pace_4', 'speed', 'diamond', 'Abaixo de 4:00/km', 'Pace médio < 4:00/km em sessão ≥ 5 km', 500, 0, 'pace_below', '{"max_pace_sec_per_km": 240, "min_distance_m": 5000}', false),
('badge_pr_pace', 'speed', 'bronze', 'PR Pace', 'Novo recorde pessoal de pace (sessão ≥ 1 km)', 50, 0, 'personal_record_pace', '{"min_distance_m": 1000}', false),
-- Endurance (4)
('badge_1h_run', 'endurance', 'bronze', '1 Hora Correndo', 'Sessão ≥ 60 minutos', 50, 0, 'single_session_duration', '{"threshold_ms": 3600000}', false),
('badge_2h_run', 'endurance', 'silver', '2 Horas Correndo', 'Sessão ≥ 120 minutos', 100, 0, 'single_session_duration', '{"threshold_ms": 7200000}', false),
('badge_10h_total', 'endurance', 'bronze', '10 Horas Acumuladas', 'Tempo total de corrida lifetime ≥ 600 min', 50, 0, 'lifetime_duration', '{"threshold_ms": 36000000}', false),
('badge_100h_total', 'endurance', 'gold', '100 Horas Acumuladas', 'Tempo total de corrida lifetime ≥ 6000 min', 200, 0, 'lifetime_duration', '{"threshold_ms": 360000000}', false),
-- Social (4)
('badge_first_challenge', 'social', 'bronze', 'Primeiro Desafio', 'Complete qualquer desafio', 50, 0, 'challenges_completed', '{"count": 1}', false),
('badge_5_challenges', 'social', 'silver', '5 Desafios', 'Complete 5 desafios', 100, 0, 'challenges_completed', '{"count": 5}', false),
('badge_challenge_won', 'social', 'bronze', 'Vitória no Desafio', 'Vença um desafio', 50, 0, 'challenge_won', '{"count": 1}', false),
('badge_champ_participant', 'social', 'silver', 'Campeonato Concluído', 'Participe e complete um campeonato', 100, 0, 'championship_completed', '{"count": 1}', false),
('badge_invicto', 'social', 'gold', 'Invicto', 'Vença 10 desafios 1v1 consecutivos', 200, 0, 'consecutive_wins', '{"count": 10}', false),
('badge_group_leader', 'social', 'silver', 'Líder de Grupo', 'Rank #1 em desafio de grupo com ≥ 5 participantes', 100, 0, 'group_leader', '{"min_participants": 5}', false),
-- Special (2)
('badge_early_bird', 'special', 'bronze', 'Madrugador', 'Sessão verificada iniciada antes das 06:00', 50, 0, 'session_before_hour', '{"hour_local": 6}', false),
('badge_night_owl', 'special', 'bronze', 'Coruja', 'Sessão verificada iniciada após 22:00', 50, 0, 'session_after_hour', '{"hour_local": 22}', false)
ON CONFLICT (id) DO NOTHING;

-- ── Billing Products (B2B Portal) ───────────────────────────────────────────
-- Credit packages available for assessorias via portal.omnirunner.app.
-- price_cents in BRL centavos. NEVER shown in the mobile app.
-- See DECISAO 047.

INSERT INTO public.billing_products (id, name, description, credits_amount, price_cents, currency, is_active, sort_order) VALUES
('bp_starter_500',   'Starter',     '500 OmniCoins — ideal para começar',                      500,   7500, 'BRL', true, 1),
('bp_basic_1500',    'Básico',      '1.500 OmniCoins — para assessorias em crescimento',       1500,  19900, 'BRL', true, 2),
('bp_pro_5000',      'Profissional','5.000 OmniCoins — para assessorias consolidadas',          5000,  59900, 'BRL', true, 3),
('bp_premium_15000', 'Premium',     '15.000 OmniCoins — melhor custo-benefício',               15000, 149900, 'BRL', true, 4),
('bp_enterprise_50k','Enterprise',  '50.000 OmniCoins — para grandes assessorias e eventos',   50000, 399900, 'BRL', true, 5)
ON CONFLICT (id) DO NOTHING;
