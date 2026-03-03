# STEP 05 — Schema, RLS & Rollback Plan

> Migrations SQL completas para o motor de snapshots diários de KPIs.

---

## 1. Migration: `20260303200000_coaching_kpis_snapshots.sql`

Arquivo: `supabase/migrations/20260303200000_coaching_kpis_snapshots.sql`

```sql
-- ============================================================================
-- Migration: Daily KPI Snapshots for Coaching Groups
-- Step 05 — Pre-aggregated engagement, retention, and athlete-level metrics
-- ============================================================================

-- ─── 1. coaching_kpis_daily ─────────────────────────────────────────────────
-- One row per (group_id, day). Computed by cron job, never written by app.

CREATE TABLE IF NOT EXISTS public.coaching_kpis_daily (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id       uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  day            date NOT NULL,

  -- Membership counts (snapshot at end of day)
  total_members      integer NOT NULL DEFAULT 0,
  total_athletes     integer NOT NULL DEFAULT 0,
  total_coaches      integer NOT NULL DEFAULT 0,
  new_members_today  integer NOT NULL DEFAULT 0,

  -- Activity (from sessions with status >= 3, is_verified, distance >= 1000)
  dau                integer NOT NULL DEFAULT 0,
  wau                integer NOT NULL DEFAULT 0,
  mau                integer NOT NULL DEFAULT 0,
  sessions_today     integer NOT NULL DEFAULT 0,
  distance_today_m   double precision NOT NULL DEFAULT 0,
  unique_athletes_today integer NOT NULL DEFAULT 0,

  -- Retention (week-over-week)
  retention_wow_pct  numeric(5,2),  -- % of last week's active users also active this week

  -- Challenges
  active_challenges  integer NOT NULL DEFAULT 0,

  computed_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_kpis_group_day UNIQUE (group_id, day)
);

-- ─── 2. coaching_athlete_kpis_daily ─────────────────────────────────────────
-- One row per (group_id, user_id, day). Per-athlete engagement snapshot.

CREATE TABLE IF NOT EXISTS public.coaching_athlete_kpis_daily (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id       uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day            date NOT NULL,

  -- Engagement score 0–100
  engagement_score   integer NOT NULL DEFAULT 0
    CHECK (engagement_score >= 0 AND engagement_score <= 100),

  -- Activity windows
  sessions_7d        integer NOT NULL DEFAULT 0,
  sessions_14d       integer NOT NULL DEFAULT 0,
  sessions_30d       integer NOT NULL DEFAULT 0,
  distance_7d_m      double precision NOT NULL DEFAULT 0,

  -- Last session timestamp
  last_session_at_ms bigint,

  -- Risk classification
  risk_level         text NOT NULL DEFAULT 'ok'
    CHECK (risk_level IN ('ok', 'medium', 'high')),

  -- Streak
  current_streak     integer NOT NULL DEFAULT 0,

  computed_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_athlete_kpis_group_user_day UNIQUE (group_id, user_id, day)
);

-- ─── 3. coaching_alerts ─────────────────────────────────────────────────────
-- Alerts generated daily for staff review.

CREATE TABLE IF NOT EXISTS public.coaching_alerts (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id       uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  user_id        uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  day            date NOT NULL,

  alert_type     text NOT NULL
    CHECK (alert_type IN (
      'athlete_high_risk',
      'athlete_medium_risk',
      'engagement_drop',
      'milestone_reached',
      'inactive_7d',
      'inactive_14d',
      'inactive_30d'
    )),

  title          text NOT NULL,
  message        text NOT NULL DEFAULT '',
  severity       text NOT NULL DEFAULT 'info'
    CHECK (severity IN ('info', 'warning', 'critical')),

  is_read        boolean NOT NULL DEFAULT false,
  read_at        timestamptz,
  read_by        uuid REFERENCES auth.users(id),

  created_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_alert_dedup UNIQUE (group_id, user_id, day, alert_type)
);

-- ─── 4. Indexes ─────────────────────────────────────────────────────────────

-- coaching_kpis_daily: lookup by group + recent days
CREATE INDEX IF NOT EXISTS idx_kpis_daily_group_day
  ON public.coaching_kpis_daily(group_id, day DESC);

-- coaching_athlete_kpis_daily: lookup for a group's athletes on a day
CREATE INDEX IF NOT EXISTS idx_athlete_kpis_group_day
  ON public.coaching_athlete_kpis_daily(group_id, day DESC);

-- coaching_athlete_kpis_daily: lookup for a specific athlete across days
CREATE INDEX IF NOT EXISTS idx_athlete_kpis_user_day
  ON public.coaching_athlete_kpis_daily(user_id, day DESC);

-- coaching_athlete_kpis_daily: find at-risk athletes quickly
CREATE INDEX IF NOT EXISTS idx_athlete_kpis_risk
  ON public.coaching_athlete_kpis_daily(group_id, day, risk_level)
  WHERE risk_level IN ('medium', 'high');

-- coaching_alerts: unread alerts per group
CREATE INDEX IF NOT EXISTS idx_alerts_group_unread
  ON public.coaching_alerts(group_id, day DESC)
  WHERE is_read = false;

-- coaching_alerts: alerts for a specific user
CREATE INDEX IF NOT EXISTS idx_alerts_user
  ON public.coaching_alerts(user_id, day DESC);

-- sessions: composite index for engagement queries (eliminates G6 gargalo)
CREATE INDEX IF NOT EXISTS idx_sessions_engagement
  ON public.sessions(user_id, start_time_ms DESC)
  WHERE status >= 3 AND is_verified = true AND total_distance_m >= 1000;

-- ─── 5. RLS Policies ────────────────────────────────────────────────────────

ALTER TABLE public.coaching_kpis_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_athlete_kpis_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_alerts ENABLE ROW LEVEL SECURITY;

-- 5.1 coaching_kpis_daily: staff do grupo lê KPIs do grupo
CREATE POLICY "kpis_daily_staff_read" ON public.coaching_kpis_daily
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_kpis_daily.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 5.2 coaching_kpis_daily: platform admin reads all
CREATE POLICY "kpis_daily_platform_admin_read" ON public.coaching_kpis_daily
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- 5.3 coaching_athlete_kpis_daily: staff do grupo lê todos os atletas do grupo
CREATE POLICY "athlete_kpis_staff_read" ON public.coaching_athlete_kpis_daily
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_athlete_kpis_daily.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 5.4 coaching_athlete_kpis_daily: atleta lê apenas suas próprias linhas
CREATE POLICY "athlete_kpis_own_read" ON public.coaching_athlete_kpis_daily
  FOR SELECT USING (
    auth.uid() = user_id
  );

-- 5.5 coaching_athlete_kpis_daily: platform admin reads all
CREATE POLICY "athlete_kpis_platform_admin_read" ON public.coaching_athlete_kpis_daily
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- 5.6 coaching_alerts: staff do grupo lê e marca como lidos
CREATE POLICY "alerts_staff_read" ON public.coaching_alerts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_alerts.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

CREATE POLICY "alerts_staff_update" ON public.coaching_alerts
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_alerts.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_alerts.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 5.7 coaching_alerts: platform admin reads all
CREATE POLICY "alerts_platform_admin_read" ON public.coaching_alerts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- ─── 6. Grants ──────────────────────────────────────────────────────────────

GRANT SELECT ON TABLE public.coaching_kpis_daily TO authenticated;
GRANT ALL ON TABLE public.coaching_kpis_daily TO service_role;

GRANT SELECT ON TABLE public.coaching_athlete_kpis_daily TO authenticated;
GRANT ALL ON TABLE public.coaching_athlete_kpis_daily TO service_role;

GRANT SELECT, UPDATE ON TABLE public.coaching_alerts TO authenticated;
GRANT ALL ON TABLE public.coaching_alerts TO service_role;
```

---

## 2. Compute Functions (chamadas pelo cron)

Arquivo: `supabase/migrations/20260303200001_coaching_kpis_functions.sql`

```sql
-- ============================================================================
-- Functions: compute_coaching_kpis_daily / compute_athlete_kpis / compute_alerts
-- Called by Edge Function cron job. SECURITY DEFINER, owned by service_role.
-- ============================================================================

-- ─── compute_coaching_kpis_daily ────────────────────────────────────────────
-- Computes group-level KPIs for a single day. Idempotent (upsert).

CREATE OR REPLACE FUNCTION public.compute_coaching_kpis_daily(p_day date)
  RETURNS integer
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_count integer := 0;
  v_group record;
  v_day_start_ms bigint;
  v_day_end_ms bigint;
  v_week_start_ms bigint;
  v_month_start_ms bigint;
  v_prev_week_start_ms bigint;
BEGIN
  v_day_start_ms := extract(epoch from p_day::timestamp at time zone 'UTC')::bigint * 1000;
  v_day_end_ms := v_day_start_ms + 86400000;
  v_week_start_ms := v_day_start_ms - 6 * 86400000;
  v_month_start_ms := v_day_start_ms - 29 * 86400000;
  v_prev_week_start_ms := v_week_start_ms - 7 * 86400000;

  FOR v_group IN
    SELECT id AS group_id FROM public.coaching_groups
  LOOP
    INSERT INTO public.coaching_kpis_daily (
      group_id, day,
      total_members, total_athletes, total_coaches, new_members_today,
      dau, wau, mau, sessions_today, distance_today_m, unique_athletes_today,
      retention_wow_pct, active_challenges, computed_at
    )
    SELECT
      v_group.group_id,
      p_day,
      -- Membership
      (SELECT count(*) FROM coaching_members WHERE group_id = v_group.group_id),
      (SELECT count(*) FROM coaching_members WHERE group_id = v_group.group_id AND role = 'athlete'),
      (SELECT count(*) FROM coaching_members WHERE group_id = v_group.group_id AND role IN ('admin_master','coach','assistant')),
      (SELECT count(*) FROM coaching_members WHERE group_id = v_group.group_id
         AND joined_at_ms >= v_day_start_ms AND joined_at_ms < v_day_end_ms),
      -- DAU
      (SELECT count(DISTINCT s.user_id) FROM sessions s
       JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
       WHERE s.start_time_ms >= v_day_start_ms AND s.start_time_ms < v_day_end_ms
         AND s.status >= 3 AND s.is_verified = true AND s.total_distance_m >= 1000),
      -- WAU
      (SELECT count(DISTINCT s.user_id) FROM sessions s
       JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
       WHERE s.start_time_ms >= v_week_start_ms AND s.start_time_ms < v_day_end_ms
         AND s.status >= 3 AND s.is_verified = true AND s.total_distance_m >= 1000),
      -- MAU
      (SELECT count(DISTINCT s.user_id) FROM sessions s
       JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
       WHERE s.start_time_ms >= v_month_start_ms AND s.start_time_ms < v_day_end_ms
         AND s.status >= 3 AND s.is_verified = true AND s.total_distance_m >= 1000),
      -- Sessions today
      (SELECT count(*) FROM sessions s
       JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
       WHERE s.start_time_ms >= v_day_start_ms AND s.start_time_ms < v_day_end_ms
         AND s.status >= 3 AND s.is_verified = true),
      -- Distance today
      (SELECT coalesce(sum(s.total_distance_m), 0) FROM sessions s
       JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
       WHERE s.start_time_ms >= v_day_start_ms AND s.start_time_ms < v_day_end_ms
         AND s.status >= 3 AND s.is_verified = true),
      -- Unique athletes today
      (SELECT count(DISTINCT s.user_id) FROM sessions s
       JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
       WHERE s.start_time_ms >= v_day_start_ms AND s.start_time_ms < v_day_end_ms
         AND s.status >= 3 AND s.is_verified = true),
      -- WoW retention
      (SELECT CASE WHEN prev.cnt = 0 THEN NULL
              ELSE round((curr_and_prev.cnt::numeric / prev.cnt) * 100, 2) END
       FROM
         (SELECT count(DISTINCT s.user_id) AS cnt FROM sessions s
          JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
          WHERE s.start_time_ms >= v_prev_week_start_ms AND s.start_time_ms < v_week_start_ms
            AND s.status >= 3 AND s.is_verified = true AND s.total_distance_m >= 1000) prev,
         (SELECT count(*) AS cnt FROM (
            SELECT s.user_id FROM sessions s
            JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
            WHERE s.start_time_ms >= v_week_start_ms AND s.start_time_ms < v_day_end_ms
              AND s.status >= 3 AND s.is_verified = true AND s.total_distance_m >= 1000
            INTERSECT
            SELECT s.user_id FROM sessions s
            JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group.group_id
            WHERE s.start_time_ms >= v_prev_week_start_ms AND s.start_time_ms < v_week_start_ms
              AND s.status >= 3 AND s.is_verified = true AND s.total_distance_m >= 1000
          ) x) curr_and_prev),
      -- Active challenges
      (SELECT count(*) FROM challenges c
       JOIN challenge_participants cp ON cp.challenge_id = c.id
       JOIN coaching_members cm ON cm.user_id = cp.user_id AND cm.group_id = v_group.group_id
       WHERE c.status = 'active'),
      now()
    ON CONFLICT (group_id, day) DO UPDATE SET
      total_members = EXCLUDED.total_members,
      total_athletes = EXCLUDED.total_athletes,
      total_coaches = EXCLUDED.total_coaches,
      new_members_today = EXCLUDED.new_members_today,
      dau = EXCLUDED.dau,
      wau = EXCLUDED.wau,
      mau = EXCLUDED.mau,
      sessions_today = EXCLUDED.sessions_today,
      distance_today_m = EXCLUDED.distance_today_m,
      unique_athletes_today = EXCLUDED.unique_athletes_today,
      retention_wow_pct = EXCLUDED.retention_wow_pct,
      active_challenges = EXCLUDED.active_challenges,
      computed_at = now();

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── compute_coaching_athlete_kpis_daily ────────────────────────────────────
-- Per-athlete engagement snapshot. Optional group_id filter.

CREATE OR REPLACE FUNCTION public.compute_coaching_athlete_kpis_daily(
  p_day date,
  p_group_id uuid DEFAULT NULL
)
  RETURNS integer
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_count integer := 0;
  v_member record;
  v_day_start_ms bigint;
  v_7d_start_ms bigint;
  v_14d_start_ms bigint;
  v_30d_start_ms bigint;
  v_s7 integer;
  v_s14 integer;
  v_s30 integer;
  v_dist7 double precision;
  v_last_ms bigint;
  v_streak integer;
  v_score integer;
  v_risk text;
BEGIN
  v_day_start_ms := extract(epoch from p_day::timestamp at time zone 'UTC')::bigint * 1000;
  v_7d_start_ms := v_day_start_ms - 6 * 86400000;
  v_14d_start_ms := v_day_start_ms - 13 * 86400000;
  v_30d_start_ms := v_day_start_ms - 29 * 86400000;

  FOR v_member IN
    SELECT cm.user_id, cm.group_id
    FROM coaching_members cm
    WHERE cm.role = 'athlete'
      AND (p_group_id IS NULL OR cm.group_id = p_group_id)
  LOOP
    -- Sessions in windows
    SELECT count(*), coalesce(sum(total_distance_m), 0)
    INTO v_s7, v_dist7
    FROM sessions
    WHERE user_id = v_member.user_id
      AND start_time_ms >= v_7d_start_ms
      AND status >= 3 AND is_verified = true;

    SELECT count(*) INTO v_s14
    FROM sessions
    WHERE user_id = v_member.user_id
      AND start_time_ms >= v_14d_start_ms
      AND status >= 3 AND is_verified = true;

    SELECT count(*) INTO v_s30
    FROM sessions
    WHERE user_id = v_member.user_id
      AND start_time_ms >= v_30d_start_ms
      AND status >= 3 AND is_verified = true;

    -- Last session
    SELECT max(start_time_ms) INTO v_last_ms
    FROM sessions
    WHERE user_id = v_member.user_id
      AND status >= 3 AND is_verified = true;

    -- Streak (from profile_progress)
    SELECT coalesce(daily_streak_count, 0) INTO v_streak
    FROM profile_progress
    WHERE user_id = v_member.user_id;
    v_streak := coalesce(v_streak, 0);

    -- Engagement score (0–100):
    --   frequency (7d):  min(sessions_7d * 15, 45)
    --   recency:         30 if last session < 3d, 20 if < 7d, 10 if < 14d, 0 else
    --   consistency:     min(sessions_14d * 3, 15)
    --   streak:          min(streak * 2, 10)
    v_score := least(v_s7 * 15, 45);

    IF v_last_ms IS NOT NULL THEN
      IF v_last_ms >= v_day_start_ms - 2 * 86400000 THEN
        v_score := v_score + 30;
      ELSIF v_last_ms >= v_day_start_ms - 6 * 86400000 THEN
        v_score := v_score + 20;
      ELSIF v_last_ms >= v_day_start_ms - 13 * 86400000 THEN
        v_score := v_score + 10;
      END IF;
    END IF;

    v_score := v_score + least(v_s14 * 3, 15);
    v_score := v_score + least(v_streak * 2, 10);
    v_score := least(v_score, 100);

    -- Risk level
    IF v_score >= 40 THEN
      v_risk := 'ok';
    ELSIF v_score >= 20 THEN
      v_risk := 'medium';
    ELSE
      v_risk := 'high';
    END IF;

    INSERT INTO coaching_athlete_kpis_daily (
      group_id, user_id, day,
      engagement_score, sessions_7d, sessions_14d, sessions_30d,
      distance_7d_m, last_session_at_ms, risk_level, current_streak,
      computed_at
    ) VALUES (
      v_member.group_id, v_member.user_id, p_day,
      v_score, v_s7, v_s14, v_s30,
      v_dist7, v_last_ms, v_risk, v_streak,
      now()
    )
    ON CONFLICT (group_id, user_id, day) DO UPDATE SET
      engagement_score = EXCLUDED.engagement_score,
      sessions_7d = EXCLUDED.sessions_7d,
      sessions_14d = EXCLUDED.sessions_14d,
      sessions_30d = EXCLUDED.sessions_30d,
      distance_7d_m = EXCLUDED.distance_7d_m,
      last_session_at_ms = EXCLUDED.last_session_at_ms,
      risk_level = EXCLUDED.risk_level,
      current_streak = EXCLUDED.current_streak,
      computed_at = now();

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── compute_coaching_alerts_daily ──────────────────────────────────────────
-- Generates alerts based on athlete KPI snapshots. Run AFTER athlete KPIs.

CREATE OR REPLACE FUNCTION public.compute_coaching_alerts_daily(p_day date)
  RETURNS integer
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_count integer := 0;
  v_athlete record;
  v_day_start_ms bigint;
BEGIN
  v_day_start_ms := extract(epoch from p_day::timestamp at time zone 'UTC')::bigint * 1000;

  FOR v_athlete IN
    SELECT ak.group_id, ak.user_id, ak.engagement_score, ak.risk_level,
           ak.sessions_7d, ak.last_session_at_ms,
           cm.display_name
    FROM coaching_athlete_kpis_daily ak
    JOIN coaching_members cm ON cm.user_id = ak.user_id AND cm.group_id = ak.group_id
    WHERE ak.day = p_day
  LOOP
    -- High risk alert
    IF v_athlete.risk_level = 'high' THEN
      INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
      VALUES (
        v_athlete.group_id, v_athlete.user_id, p_day,
        'athlete_high_risk',
        format('%s em risco alto', v_athlete.display_name),
        format('Score de engajamento: %s/100. Sem atividade recente.', v_athlete.engagement_score),
        'critical'
      )
      ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
      v_count := v_count + 1;

    ELSIF v_athlete.risk_level = 'medium' THEN
      INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
      VALUES (
        v_athlete.group_id, v_athlete.user_id, p_day,
        'athlete_medium_risk',
        format('%s com engajamento médio', v_athlete.display_name),
        format('Score: %s/100. Atividade em queda.', v_athlete.engagement_score),
        'warning'
      )
      ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
      v_count := v_count + 1;
    END IF;

    -- Inactive alerts (by days since last session)
    IF v_athlete.last_session_at_ms IS NOT NULL THEN
      IF v_athlete.last_session_at_ms < v_day_start_ms - 29 * 86400000 THEN
        INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
        VALUES (
          v_athlete.group_id, v_athlete.user_id, p_day,
          'inactive_30d',
          format('%s inativo há 30+ dias', v_athlete.display_name),
          'Considere entrar em contato para verificar a situação.',
          'critical'
        )
        ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
        v_count := v_count + 1;

      ELSIF v_athlete.last_session_at_ms < v_day_start_ms - 13 * 86400000 THEN
        INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
        VALUES (
          v_athlete.group_id, v_athlete.user_id, p_day,
          'inactive_14d',
          format('%s inativo há 14+ dias', v_athlete.display_name),
          'Uma mensagem de incentivo pode ajudar.',
          'warning'
        )
        ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
        v_count := v_count + 1;

      ELSIF v_athlete.last_session_at_ms < v_day_start_ms - 6 * 86400000 THEN
        INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
        VALUES (
          v_athlete.group_id, v_athlete.user_id, p_day,
          'inactive_7d',
          format('%s sem atividade na última semana', v_athlete.display_name),
          'Sem corrida nos últimos 7 dias.',
          'info'
        )
        ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
        v_count := v_count + 1;
      END IF;
    ELSIF v_athlete.last_session_at_ms IS NULL THEN
      INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
      VALUES (
        v_athlete.group_id, v_athlete.user_id, p_day,
        'inactive_30d',
        format('%s nunca registrou uma corrida', v_athlete.display_name),
        'Atleta cadastrado mas sem nenhuma sessão.',
        'warning'
      )
      ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.compute_coaching_kpis_daily TO service_role;
GRANT EXECUTE ON FUNCTION public.compute_coaching_athlete_kpis_daily TO service_role;
GRANT EXECUTE ON FUNCTION public.compute_coaching_alerts_daily TO service_role;
```

---

## 3. Engagement Score — Fórmula

| Componente | Cálculo | Peso máximo |
|---|---|---|
| Frequência 7d | `min(sessions_7d * 15, 45)` | 45 |
| Recência | 30 (< 3d), 20 (< 7d), 10 (< 14d), 0 (> 14d) | 30 |
| Consistência 14d | `min(sessions_14d * 3, 15)` | 15 |
| Streak | `min(streak * 2, 10)` | 10 |
| **Total** | | **100** |

| Score | Risk Level |
|---|---|
| >= 40 | `ok` |
| 20–39 | `medium` |
| 0–19 | `high` |

---

## 4. Estratégia de Rollout / Rollback

### Rollout (3 fases)

**Fase 1 — Shadow mode (1 semana):**
- Deploy migration + Edge Function cron
- Cron roda diariamente às 03:00 UTC
- Portal/app NÃO leem snapshots ainda (continuam live)
- Equipe valida snapshots vs live manualmente

**Fase 2 — Portal first (1 semana):**
- Portal `/engagement` troca para ler `coaching_kpis_daily`
- Fallback: se snapshot do dia não existe, faz query live (código antigo)
- Feature flag `use_kpi_snapshots` em `platform_feature_flags`

**Fase 3 — App (1 semana depois):**
- App `StaffRetentionDashboardScreen` troca para ler snapshots via Supabase
- Fallback: mantém lógica live se snapshot não encontrado
- Remove queries live após 2 semanas sem fallback

### Rollback

```sql
-- Rollback completo (preserva dados para análise):
-- 1. Desligar o cron (delete scheduled function)
-- 2. App/portal voltam para queries live (feature flag off)
-- 3. Se necessário, drop tables:
DROP TABLE IF EXISTS public.coaching_alerts CASCADE;
DROP TABLE IF EXISTS public.coaching_athlete_kpis_daily CASCADE;
DROP TABLE IF EXISTS public.coaching_kpis_daily CASCADE;
DROP INDEX IF EXISTS idx_sessions_engagement;
DROP FUNCTION IF EXISTS public.compute_coaching_kpis_daily;
DROP FUNCTION IF EXISTS public.compute_coaching_athlete_kpis_daily;
DROP FUNCTION IF EXISTS public.compute_coaching_alerts_daily;
```

**Rollback é seguro** porque:
- As tabelas de snapshot são **write-only pelo cron**, nunca pelo app
- O app/portal podem voltar para queries live instantaneamente
- Nenhuma tabela existente é alterada (exceto o novo índice em `sessions`, que é aditivo)
