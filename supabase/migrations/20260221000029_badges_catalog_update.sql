-- ============================================================================
-- Omni Runner — Badge catalog update (DECISAO 045)
-- Date: 2026-02-26
-- Sprint: 20.2.1
-- ============================================================================
-- Adds new badges from the finalized automatic badge catalog:
--   - badge_5_runs (5 corridas)
--   - badge_streak_3 (3 dias seguidos)
--   - badge_streak_14 (14 dias seguidos)
--   - badge_10km_week (10 km na semana)
--   - badge_challenge_won (vitória em desafio)
--   - badge_champ_participant (campeonato concluído)
-- All use ON CONFLICT DO NOTHING for idempotency.
-- ============================================================================

INSERT INTO public.badges
  (id, category, tier, name, description, xp_reward, coins_reward, criteria_type, criteria_json, is_secret)
VALUES
  ('badge_5_runs',
   'frequency', 'bronze', 'Corredor Dedicado',
   '5 sessões verificadas completadas',
   50, 0, 'session_count', '{"count": 5}', false),

  ('badge_streak_3',
   'frequency', 'bronze', '3 Dias Seguidos',
   'Sequência de 3 dias consecutivos correndo',
   50, 0, 'daily_streak', '{"days": 3}', false),

  ('badge_streak_14',
   'frequency', 'gold', '14 Dias Seguidos',
   'Sequência de 14 dias consecutivos correndo',
   200, 0, 'daily_streak', '{"days": 14}', false),

  ('badge_10km_week',
   'frequency', 'bronze', '10 km na Semana',
   'Corra 10 km ou mais em uma semana',
   50, 0, 'weekly_distance', '{"threshold_m": 10000}', false),

  ('badge_challenge_won',
   'social', 'bronze', 'Vitória no Desafio',
   'Vença um desafio',
   50, 0, 'challenge_won', '{"count": 1}', false),

  ('badge_champ_participant',
   'social', 'silver', 'Campeonato Concluído',
   'Participe e complete um campeonato',
   100, 0, 'championship_completed', '{"count": 1}', false)

ON CONFLICT (id) DO NOTHING;
