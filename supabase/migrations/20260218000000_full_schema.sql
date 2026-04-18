-- ============================================================================
-- Omni Runner — Full Supabase Schema
-- Generated: 2026-02-18
-- Reference: domain entities in omni_runner/lib/domain/entities/
-- ============================================================================
-- Run order: this file is self-contained. Execute in a single transaction.
-- Depends on: Supabase Auth (auth.users), existing analytics tables (20260217).
-- ============================================================================

-- ── 0. Extensions ──────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── 1. PROFILES ────────────────────────────────────────────────────────────
-- Extends auth.users with app-specific fields.
-- Auto-created via trigger on auth.users INSERT.

CREATE TABLE IF NOT EXISTS public.profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name    TEXT NOT NULL DEFAULT 'Runner',
  avatar_url      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_display_name ON public.profiles(display_name);

-- Trigger: auto-create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'Runner'),
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_read_all" ON public.profiles
  FOR SELECT USING (true);

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ── 2. SESSIONS ────────────────────────────────────────────────────────────
-- Workout sessions synced from the mobile app.
-- Reference: WorkoutSessionEntity, sync_payload.md

CREATE TABLE IF NOT EXISTS public.sessions (
  id                UUID PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status            SMALLINT NOT NULL DEFAULT 0,
  start_time_ms     BIGINT NOT NULL,
  end_time_ms       BIGINT,
  total_distance_m  DOUBLE PRECISION NOT NULL DEFAULT 0,
  moving_ms         BIGINT NOT NULL DEFAULT 0,
  avg_pace_sec_km   DOUBLE PRECISION,
  avg_bpm           INTEGER,
  max_bpm           INTEGER,
  is_verified       BOOLEAN NOT NULL DEFAULT true,
  integrity_flags   TEXT[] NOT NULL DEFAULT '{}',
  ghost_session_id  UUID,
  points_path       TEXT,
  is_synced         BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sessions_user ON public.sessions(user_id, start_time_ms DESC);
CREATE INDEX idx_sessions_status ON public.sessions(user_id, status);
CREATE INDEX idx_sessions_verified ON public.sessions(user_id) WHERE is_verified = true;

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sessions_own_read" ON public.sessions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "sessions_own_insert" ON public.sessions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "sessions_own_update" ON public.sessions
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── 3. SEASONS ─────────────────────────────────────────────────────────────
-- 90-day competitive seasons. Admin-managed.
-- Reference: SeasonEntity

CREATE TABLE IF NOT EXISTS public.seasons (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'upcoming'
                    CHECK (status IN ('upcoming','active','settling','completed')),
  starts_at_ms      BIGINT NOT NULL,
  ends_at_ms        BIGINT NOT NULL,
  pass_xp_milestones INTEGER[] NOT NULL DEFAULT '{200,500,1000,2000,3500,5000,7500,10000,15000,20000}',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.seasons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "seasons_read_all" ON public.seasons
  FOR SELECT USING (true);

-- ── 4. BADGES ──────────────────────────────────────────────────────────────
-- Badge catalog. Admin-managed, read-only for users.
-- Reference: BadgeEntity

CREATE TABLE IF NOT EXISTS public.badges (
  id              TEXT PRIMARY KEY,
  category        TEXT NOT NULL CHECK (category IN ('distance','frequency','speed','endurance','social','special')),
  tier            TEXT NOT NULL CHECK (tier IN ('bronze','silver','gold','diamond')),
  name            TEXT NOT NULL,
  description     TEXT NOT NULL,
  icon_asset      TEXT NOT NULL DEFAULT '',
  xp_reward       INTEGER NOT NULL DEFAULT 0,
  coins_reward    INTEGER NOT NULL DEFAULT 0,
  criteria_type   TEXT NOT NULL,
  criteria_json   JSONB NOT NULL DEFAULT '{}',
  is_secret       BOOLEAN NOT NULL DEFAULT false,
  season_id       UUID REFERENCES public.seasons(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "badges_read_all" ON public.badges
  FOR SELECT USING (true);

-- ── 5. BADGE_AWARDS ────────────────────────────────────────────────────────
-- Badges unlocked by users. Immutable.
-- Reference: BadgeAwardEntity

CREATE TABLE IF NOT EXISTS public.badge_awards (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_id            TEXT NOT NULL REFERENCES public.badges(id),
  trigger_session_id  UUID REFERENCES public.sessions(id),
  unlocked_at_ms      BIGINT NOT NULL,
  xp_awarded          INTEGER NOT NULL DEFAULT 0,
  coins_awarded       INTEGER NOT NULL DEFAULT 0,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE(user_id, badge_id)
);

CREATE INDEX idx_badge_awards_user ON public.badge_awards(user_id, unlocked_at_ms DESC);

ALTER TABLE public.badge_awards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "badge_awards_own_read" ON public.badge_awards
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "badge_awards_public_read" ON public.badge_awards
  FOR SELECT USING (true);

-- ── 6. PROFILE_PROGRESS ───────────────────────────────────────────────────
-- Denormalized progression state per user.
-- Reference: ProfileProgressEntity

CREATE TABLE IF NOT EXISTS public.profile_progress (
  user_id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  total_xp              INTEGER NOT NULL DEFAULT 0,
  season_xp             INTEGER NOT NULL DEFAULT 0,
  current_season_id     UUID REFERENCES public.seasons(id),
  daily_streak_count    INTEGER NOT NULL DEFAULT 0,
  last_streak_day_ms    BIGINT,
  has_freeze_available  BOOLEAN NOT NULL DEFAULT false,
  weekly_session_count  INTEGER NOT NULL DEFAULT 0,
  monthly_session_count INTEGER NOT NULL DEFAULT 0,
  lifetime_session_count INTEGER NOT NULL DEFAULT 0,
  lifetime_distance_m   DOUBLE PRECISION NOT NULL DEFAULT 0,
  lifetime_moving_ms    BIGINT NOT NULL DEFAULT 0,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profile_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "progress_own_read" ON public.profile_progress
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "progress_public_read" ON public.profile_progress
  FOR SELECT USING (true);

-- ── 7. XP_TRANSACTIONS ────────────────────────────────────────────────────
-- Immutable XP credit log.
-- Reference: XpTransactionEntity

CREATE TABLE IF NOT EXISTS public.xp_transactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  xp              INTEGER NOT NULL,
  source          TEXT NOT NULL CHECK (source IN ('session','badge','mission','streak','challenge')),
  ref_id          TEXT,
  created_at_ms   BIGINT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_xp_tx_user ON public.xp_transactions(user_id, created_at_ms DESC);

ALTER TABLE public.xp_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "xp_tx_own_read" ON public.xp_transactions
  FOR SELECT USING (auth.uid() = user_id);

-- ── 8. SEASON_PROGRESS ────────────────────────────────────────────────────
-- Per-user progress within a season.
-- Reference: SeasonProgressEntity

CREATE TABLE IF NOT EXISTS public.season_progress (
  user_id                   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  season_id                 UUID NOT NULL REFERENCES public.seasons(id),
  season_xp                 INTEGER NOT NULL DEFAULT 0,
  claimed_milestone_indices INTEGER[] NOT NULL DEFAULT '{}',
  end_rewards_claimed       BOOLEAN NOT NULL DEFAULT false,
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, season_id)
);

ALTER TABLE public.season_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "season_progress_own_read" ON public.season_progress
  FOR SELECT USING (auth.uid() = user_id);

-- ── 9. WALLETS ─────────────────────────────────────────────────────────────
-- OmniCoins balance per user.
-- Reference: WalletEntity

CREATE TABLE IF NOT EXISTS public.wallets (
  user_id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance_coins         INTEGER NOT NULL DEFAULT 0 CHECK (balance_coins >= 0),
  lifetime_earned_coins INTEGER NOT NULL DEFAULT 0,
  lifetime_spent_coins  INTEGER NOT NULL DEFAULT 0,
  last_reconciled_at_ms BIGINT,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wallets_own_read" ON public.wallets
  FOR SELECT USING (auth.uid() = user_id);

-- ── 10. COIN_LEDGER ───────────────────────────────────────────────────────
-- Immutable OmniCoins transaction log.
-- Reference: LedgerEntryEntity

CREATE TABLE IF NOT EXISTS public.coin_ledger (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  delta_coins     INTEGER NOT NULL,
  reason          TEXT NOT NULL CHECK (reason IN (
    'session_completed','challenge_one_vs_one_completed','challenge_one_vs_one_won',
    'challenge_group_completed','streak_weekly','streak_monthly',
    'pr_distance','pr_pace','challenge_entry_fee','challenge_pool_won',
    'challenge_entry_refund','cosmetic_purchase','admin_adjustment',
    'badge_reward','mission_reward'
  )),
  ref_id          TEXT,
  created_at_ms   BIGINT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ledger_user ON public.coin_ledger(user_id, created_at_ms DESC);

ALTER TABLE public.coin_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ledger_own_read" ON public.coin_ledger
  FOR SELECT USING (auth.uid() = user_id);

-- ── 11. MISSIONS ──────────────────────────────────────────────────────────
-- Mission definitions (daily/weekly/season). Admin-managed.
-- Reference: MissionEntity

CREATE TABLE IF NOT EXISTS public.missions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title           TEXT NOT NULL,
  description     TEXT NOT NULL,
  difficulty      TEXT NOT NULL CHECK (difficulty IN ('easy','medium','hard')),
  slot            TEXT NOT NULL CHECK (slot IN ('daily','weekly','season')),
  xp_reward       INTEGER NOT NULL DEFAULT 0,
  coins_reward    INTEGER NOT NULL DEFAULT 0,
  criteria_type   TEXT NOT NULL,
  criteria_json   JSONB NOT NULL DEFAULT '{}',
  expires_at_ms   BIGINT,
  season_id       UUID REFERENCES public.seasons(id),
  max_completions INTEGER NOT NULL DEFAULT 1,
  cooldown_ms     BIGINT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.missions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "missions_read_all" ON public.missions
  FOR SELECT USING (true);

-- ── 12. MISSION_PROGRESS ──────────────────────────────────────────────────
-- Per-user mission progress tracking.
-- Reference: MissionProgressEntity

CREATE TABLE IF NOT EXISTS public.mission_progress (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mission_id                UUID NOT NULL REFERENCES public.missions(id),
  status                    TEXT NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','completed','expired')),
  current_value             DOUBLE PRECISION NOT NULL DEFAULT 0,
  target_value              DOUBLE PRECISION NOT NULL,
  assigned_at_ms            BIGINT NOT NULL,
  completed_at_ms           BIGINT,
  completion_count          INTEGER NOT NULL DEFAULT 0,
  contributing_session_ids  UUID[] NOT NULL DEFAULT '{}',
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_mission_progress_user ON public.mission_progress(user_id, status);

ALTER TABLE public.mission_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mission_progress_own_read" ON public.mission_progress
  FOR SELECT USING (auth.uid() = user_id);

-- ── 13. FRIENDSHIPS ───────────────────────────────────────────────────────
-- Bidirectional friend links.
-- Reference: FriendshipEntity

CREATE TABLE IF NOT EXISTS public.friendships (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id_a     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id_b     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','accepted','declined','blocked')),
  created_at_ms BIGINT NOT NULL,
  accepted_at_ms BIGINT,

  UNIQUE(user_id_a, user_id_b),
  CHECK (user_id_a < user_id_b)
);

CREATE INDEX idx_friendships_a ON public.friendships(user_id_a, status);
CREATE INDEX idx_friendships_b ON public.friendships(user_id_b, status);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "friendships_own_read" ON public.friendships
  FOR SELECT USING (auth.uid() = user_id_a OR auth.uid() = user_id_b);

CREATE POLICY "friendships_own_insert" ON public.friendships
  FOR INSERT WITH CHECK (auth.uid() = user_id_a OR auth.uid() = user_id_b);

CREATE POLICY "friendships_own_update" ON public.friendships
  FOR UPDATE USING (auth.uid() = user_id_a OR auth.uid() = user_id_b);

-- ── 14. GROUPS ─────────────────────────────────────────────────────────────
-- Social running groups.
-- Reference: GroupEntity

CREATE TABLE IF NOT EXISTS public.groups (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL CHECK (length(name) BETWEEN 3 AND 50),
  description       TEXT NOT NULL DEFAULT '',
  avatar_url        TEXT,
  created_by_user_id UUID NOT NULL REFERENCES auth.users(id),
  created_at_ms     BIGINT NOT NULL,
  privacy           TEXT NOT NULL DEFAULT 'open'
                    CHECK (privacy IN ('open','closed','secret')),
  max_members       INTEGER NOT NULL DEFAULT 100 CHECK (max_members BETWEEN 2 AND 200),
  member_count      INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_groups_privacy ON public.groups(privacy) WHERE privacy != 'secret';

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

-- NOTE: groups_read_public and groups_update_admin are deferred to after
-- group_members table creation (they reference group_members).

CREATE POLICY "groups_insert_auth" ON public.groups
  FOR INSERT WITH CHECK (auth.uid() = created_by_user_id);

-- ── 15. GROUP_MEMBERS ──────────────────────────────────────────────────────
-- Group membership records.
-- Reference: GroupMemberEntity

CREATE TABLE IF NOT EXISTS public.group_members (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name  TEXT NOT NULL,
  role          TEXT NOT NULL DEFAULT 'member'
                CHECK (role IN ('admin','moderator','member')),
  status        TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','banned','left')),
  joined_at_ms  BIGINT NOT NULL,

  UNIQUE(group_id, user_id)
);

CREATE INDEX idx_group_members_user ON public.group_members(user_id, status);
CREATE INDEX idx_group_members_group ON public.group_members(group_id, status);

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "group_members_read" ON public.group_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_members.group_id
        AND gm.user_id = auth.uid()
        AND gm.status = 'active'
    )
  );

CREATE POLICY "group_members_insert_self" ON public.group_members
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "group_members_update_mod" ON public.group_members
  FOR UPDATE USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_members.group_id
        AND gm.user_id = auth.uid()
        AND gm.role IN ('admin','moderator')
        AND gm.status = 'active'
    )
  );

-- Deferred policies for public.groups (depend on group_members)

CREATE POLICY "groups_read_public" ON public.groups
  FOR SELECT USING (
    privacy != 'secret'
    OR EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = groups.id
        AND gm.user_id = auth.uid()
        AND gm.status = 'active'
    )
  );

CREATE POLICY "groups_update_admin" ON public.groups
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = groups.id
        AND gm.user_id = auth.uid()
        AND gm.role = 'admin'
        AND gm.status = 'active'
    )
  );

-- ── 16. GROUP_GOALS ────────────────────────────────────────────────────────
-- Collective group goals.
-- Reference: GroupGoalEntity

CREATE TABLE IF NOT EXISTS public.group_goals (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id            UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  description         TEXT NOT NULL DEFAULT '',
  target_value        DOUBLE PRECISION NOT NULL,
  current_value       DOUBLE PRECISION NOT NULL DEFAULT 0,
  metric              TEXT NOT NULL CHECK (metric IN ('distance','sessions','moving_time')),
  starts_at_ms        BIGINT NOT NULL,
  ends_at_ms          BIGINT NOT NULL,
  created_by_user_id  UUID NOT NULL REFERENCES auth.users(id),
  status              TEXT NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active','completed','expired'))
);

CREATE INDEX idx_group_goals ON public.group_goals(group_id, status);

ALTER TABLE public.group_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "group_goals_read_member" ON public.group_goals
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_goals.group_id
        AND gm.user_id = auth.uid()
        AND gm.status = 'active'
    )
  );

-- ── 17. CHALLENGES ─────────────────────────────────────────────────────────
-- 1v1 and group challenges.
-- Reference: ChallengeEntity, ChallengeRulesEntity

CREATE TABLE IF NOT EXISTS public.challenges (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_user_id     UUID NOT NULL REFERENCES auth.users(id),
  status              TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','active','completing','completed','cancelled','expired')),
  type                TEXT NOT NULL CHECK (type IN ('one_vs_one','group')),
  title               TEXT,
  -- Rules (denormalized from ChallengeRulesEntity)
  metric              TEXT NOT NULL CHECK (metric IN ('distance','pace','time')),
  target              DOUBLE PRECISION,
  window_ms           BIGINT NOT NULL,
  start_mode          TEXT NOT NULL DEFAULT 'on_accept'
                      CHECK (start_mode IN ('on_accept','scheduled')),
  fixed_start_ms      BIGINT,
  min_session_distance_m DOUBLE PRECISION NOT NULL DEFAULT 1000,
  anti_cheat_policy   TEXT NOT NULL DEFAULT 'standard'
                      CHECK (anti_cheat_policy IN ('standard','strict')),
  entry_fee_coins     INTEGER NOT NULL DEFAULT 0 CHECK (entry_fee_coins >= 0),
  -- Timestamps
  created_at_ms       BIGINT NOT NULL,
  starts_at_ms        BIGINT,
  ends_at_ms          BIGINT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_challenges_creator ON public.challenges(creator_user_id, status);
CREATE INDEX idx_challenges_status ON public.challenges(status);

ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;

-- NOTE: challenges_participant_read is deferred to after
-- challenge_participants table creation (it references challenge_participants).

CREATE POLICY "challenges_insert_auth" ON public.challenges
  FOR INSERT WITH CHECK (auth.uid() = creator_user_id);

-- ── 18. CHALLENGE_PARTICIPANTS ─────────────────────────────────────────────
-- Participants within a challenge.
-- Reference: ChallengeParticipantEntity

CREATE TABLE IF NOT EXISTS public.challenge_participants (
  challenge_id              UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  user_id                   UUID NOT NULL REFERENCES auth.users(id),
  display_name              TEXT NOT NULL,
  status                    TEXT NOT NULL DEFAULT 'invited'
                            CHECK (status IN ('invited','accepted','declined','withdrawn')),
  responded_at_ms           BIGINT,
  progress_value            DOUBLE PRECISION NOT NULL DEFAULT 0,
  contributing_session_ids  UUID[] NOT NULL DEFAULT '{}',
  last_submitted_at_ms      BIGINT,

  PRIMARY KEY (challenge_id, user_id)
);

CREATE INDEX idx_challenge_parts_user ON public.challenge_participants(user_id, status);

ALTER TABLE public.challenge_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "challenge_parts_own_read" ON public.challenge_participants
  FOR SELECT USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.challenge_participants cp2
      WHERE cp2.challenge_id = challenge_participants.challenge_id
        AND cp2.user_id = auth.uid()
    )
  );

CREATE POLICY "challenge_parts_own_update" ON public.challenge_participants
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Deferred policy for public.challenges (depends on challenge_participants)

CREATE POLICY "challenges_participant_read" ON public.challenges
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.challenge_participants cp
      WHERE cp.challenge_id = challenges.id
        AND cp.user_id = auth.uid()
    )
  );

-- ── 19. CHALLENGE_RESULTS ──────────────────────────────────────────────────
-- Finalized challenge results. Immutable.
-- Reference: ChallengeResultEntity, ParticipantResult

CREATE TABLE IF NOT EXISTS public.challenge_results (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id              UUID NOT NULL REFERENCES public.challenges(id),
  user_id                   UUID NOT NULL REFERENCES auth.users(id),
  final_value               DOUBLE PRECISION NOT NULL,
  rank                      INTEGER,
  outcome                   TEXT NOT NULL CHECK (outcome IN ('won','lost','tied','completed_target','participated','did_not_finish')),
  coins_earned              INTEGER NOT NULL DEFAULT 0,
  session_ids               UUID[] NOT NULL DEFAULT '{}',
  calculated_at_ms          BIGINT NOT NULL,

  UNIQUE(challenge_id, user_id)
);

ALTER TABLE public.challenge_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "challenge_results_participant_read" ON public.challenge_results
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.challenge_participants cp
      WHERE cp.challenge_id = challenge_results.challenge_id
        AND cp.user_id = auth.uid()
    )
  );

-- ── 20. CHALLENGE_RUN_BINDINGS ─────────────────────────────────────────────
-- Audit trail: session → challenge validation.
-- Reference: ChallengeRunBindingEntity

CREATE TABLE IF NOT EXISTS public.challenge_run_bindings (
  session_id              UUID NOT NULL REFERENCES public.sessions(id),
  challenge_id            UUID NOT NULL REFERENCES public.challenges(id),
  user_id                 UUID NOT NULL REFERENCES auth.users(id),
  accepted                BOOLEAN NOT NULL,
  rejection_reason        TEXT CHECK (rejection_reason IN (
    'not_completed','not_verified','below_min_distance',
    'outside_window','already_submitted','missing_heart_rate'
  )),
  metric_value            DOUBLE PRECISION,
  session_distance_m      DOUBLE PRECISION NOT NULL,
  session_verified        BOOLEAN NOT NULL,
  session_integrity_flags TEXT[] NOT NULL DEFAULT '{}',
  session_had_hr          BOOLEAN NOT NULL,
  evaluated_at_ms         BIGINT NOT NULL,

  PRIMARY KEY (session_id, challenge_id)
);

ALTER TABLE public.challenge_run_bindings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bindings_own_read" ON public.challenge_run_bindings
  FOR SELECT USING (auth.uid() = user_id);

-- ── 21. LEADERBOARDS ───────────────────────────────────────────────────────
-- Materialized leaderboard snapshots.
-- Reference: LeaderboardEntity

CREATE TABLE IF NOT EXISTS public.leaderboards (
  id              TEXT PRIMARY KEY,
  scope           TEXT NOT NULL CHECK (scope IN ('global','friends','group','season')),
  group_id        UUID REFERENCES public.groups(id),
  period          TEXT NOT NULL CHECK (period IN ('weekly','monthly','season')),
  metric          TEXT NOT NULL CHECK (metric IN ('distance','sessions','moving_time','avg_pace','season_xp')),
  period_key      TEXT NOT NULL,
  computed_at_ms  BIGINT NOT NULL,
  is_final        BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX idx_leaderboards_scope ON public.leaderboards(scope, period, metric, period_key);

ALTER TABLE public.leaderboards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "leaderboards_read_all" ON public.leaderboards
  FOR SELECT USING (
    scope IN ('global','season')
    OR (scope = 'group' AND EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = leaderboards.group_id
        AND gm.user_id = auth.uid()
        AND gm.status = 'active'
    ))
    OR (scope = 'friends' AND true)
  );

-- ── 22. LEADERBOARD_ENTRIES ────────────────────────────────────────────────
-- Individual rows in a leaderboard.
-- Reference: LeaderboardEntryEntity

CREATE TABLE IF NOT EXISTS public.leaderboard_entries (
  leaderboard_id  TEXT NOT NULL REFERENCES public.leaderboards(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  display_name    TEXT NOT NULL,
  avatar_url      TEXT,
  level           INTEGER NOT NULL DEFAULT 0,
  value           DOUBLE PRECISION NOT NULL,
  rank            INTEGER NOT NULL,
  period_key      TEXT NOT NULL,

  PRIMARY KEY (leaderboard_id, user_id)
);

ALTER TABLE public.leaderboard_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "lb_entries_read" ON public.leaderboard_entries
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.leaderboards lb
      WHERE lb.id = leaderboard_entries.leaderboard_id
    )
  );

-- ── 23. EVENTS ─────────────────────────────────────────────────────────────
-- Virtual running events (system or user-created).
-- Reference: EventEntity, EventRewards

CREATE TABLE IF NOT EXISTS public.events (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title               TEXT NOT NULL,
  description         TEXT NOT NULL DEFAULT '',
  image_url           TEXT,
  type                TEXT NOT NULL CHECK (type IN ('individual','team')),
  metric              TEXT NOT NULL CHECK (metric IN ('distance','sessions','moving_time')),
  target_value        DOUBLE PRECISION,
  starts_at_ms        BIGINT NOT NULL,
  ends_at_ms          BIGINT NOT NULL,
  max_participants    INTEGER,
  created_by_system   BOOLEAN NOT NULL DEFAULT false,
  creator_user_id     UUID REFERENCES auth.users(id),
  xp_completion       INTEGER NOT NULL DEFAULT 0,
  coins_completion    INTEGER NOT NULL DEFAULT 0,
  xp_participation    INTEGER NOT NULL DEFAULT 0,
  badge_id            TEXT REFERENCES public.badges(id),
  status              TEXT NOT NULL DEFAULT 'upcoming'
                      CHECK (status IN ('upcoming','active','completed','cancelled')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_events_status ON public.events(status, starts_at_ms);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "events_read_all" ON public.events
  FOR SELECT USING (true);

-- ── 24. EVENT_PARTICIPATIONS ───────────────────────────────────────────────
-- User participation in events.
-- Reference: EventParticipationEntity

CREATE TABLE IF NOT EXISTS public.event_participations (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id                  UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id                   UUID NOT NULL REFERENCES auth.users(id),
  display_name              TEXT NOT NULL,
  joined_at_ms              BIGINT NOT NULL,
  current_value             DOUBLE PRECISION NOT NULL DEFAULT 0,
  rank                      INTEGER,
  completed                 BOOLEAN NOT NULL DEFAULT false,
  completed_at_ms           BIGINT,
  contributing_session_count INTEGER NOT NULL DEFAULT 0,
  contributing_session_ids  UUID[] NOT NULL DEFAULT '{}',
  rewards_claimed           BOOLEAN NOT NULL DEFAULT false,

  UNIQUE(event_id, user_id)
);

CREATE INDEX idx_event_parts_user ON public.event_participations(user_id);

ALTER TABLE public.event_participations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "event_parts_own_read" ON public.event_participations
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "event_parts_event_read" ON public.event_participations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.event_participations ep2
      WHERE ep2.event_id = event_participations.event_id
        AND ep2.user_id = auth.uid()
    )
  );

CREATE POLICY "event_parts_insert_self" ON public.event_participations
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ── 25. COACHING_GROUPS ────────────────────────────────────────────────────
-- Private coaching (assessoria) groups.
-- Reference: CoachingGroupEntity

CREATE TABLE IF NOT EXISTS public.coaching_groups (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL CHECK (length(name) BETWEEN 3 AND 80),
  logo_url        TEXT,
  coach_user_id   UUID NOT NULL REFERENCES auth.users(id),
  description     TEXT NOT NULL DEFAULT '',
  city            TEXT NOT NULL DEFAULT '',
  created_at_ms   BIGINT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.coaching_groups ENABLE ROW LEVEL SECURITY;

-- NOTE: coaching_groups_member_read is deferred to after
-- coaching_members table creation (it references coaching_members).

CREATE POLICY "coaching_groups_insert_coach" ON public.coaching_groups
  FOR INSERT WITH CHECK (auth.uid() = coach_user_id);

CREATE POLICY "coaching_groups_update_coach" ON public.coaching_groups
  FOR UPDATE USING (auth.uid() = coach_user_id);

-- ── 26. COACHING_MEMBERS ───────────────────────────────────────────────────
-- Coaching group memberships.
-- Reference: CoachingMemberEntity

CREATE TABLE IF NOT EXISTS public.coaching_members (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_id      UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  display_name  TEXT NOT NULL,
  role          TEXT NOT NULL DEFAULT 'athlete'
                CHECK (role IN ('coach','assistant','athlete')),
  joined_at_ms  BIGINT NOT NULL,

  UNIQUE(group_id, user_id)
);

CREATE INDEX idx_coaching_members_user ON public.coaching_members(user_id);
CREATE INDEX idx_coaching_members_group ON public.coaching_members(group_id, role);

ALTER TABLE public.coaching_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coaching_members_group_read" ON public.coaching_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm2
      WHERE cm2.group_id = coaching_members.group_id
        AND cm2.user_id = auth.uid()
    )
  );

-- Deferred policy for public.coaching_groups (depends on coaching_members)

CREATE POLICY "coaching_groups_member_read" ON public.coaching_groups
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_groups.id
        AND cm.user_id = auth.uid()
    )
  );

-- ── 27. COACHING_INVITES ───────────────────────────────────────────────────
-- Invitations to coaching groups.
-- Reference: CoachingInviteEntity

CREATE TABLE IF NOT EXISTS public.coaching_invites (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id            UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  invited_user_id     UUID NOT NULL REFERENCES auth.users(id),
  invited_by_user_id  UUID NOT NULL REFERENCES auth.users(id),
  status              TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','accepted','declined','expired')),
  expires_at_ms       BIGINT NOT NULL,
  created_at_ms       BIGINT NOT NULL
);

ALTER TABLE public.coaching_invites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coaching_invites_read" ON public.coaching_invites
  FOR SELECT USING (
    auth.uid() = invited_user_id
    OR EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_invites.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('coach','assistant')
    )
  );

CREATE POLICY "coaching_invites_update" ON public.coaching_invites
  FOR UPDATE USING (auth.uid() = invited_user_id);

-- ── 28. COACHING_RANKINGS ──────────────────────────────────────────────────
-- Coaching group ranking snapshots.
-- Reference: CoachingGroupRankingEntity

CREATE TABLE IF NOT EXISTS public.coaching_rankings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  metric          TEXT NOT NULL CHECK (metric IN ('volume_distance','total_time','best_pace','consistency_days')),
  period          TEXT NOT NULL CHECK (period IN ('weekly','monthly','custom')),
  period_key      TEXT NOT NULL,
  starts_at_ms    BIGINT NOT NULL,
  ends_at_ms      BIGINT NOT NULL,
  computed_at_ms  BIGINT NOT NULL,

  UNIQUE(group_id, metric, period_key)
);

ALTER TABLE public.coaching_rankings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coaching_rankings_member_read" ON public.coaching_rankings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_rankings.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- ── 29. COACHING_RANKING_ENTRIES ───────────────────────────────────────────
-- Individual rows in coaching rankings.
-- Reference: CoachingRankingEntryEntity

CREATE TABLE IF NOT EXISTS public.coaching_ranking_entries (
  ranking_id      UUID NOT NULL REFERENCES public.coaching_rankings(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  display_name    TEXT NOT NULL,
  value           DOUBLE PRECISION NOT NULL,
  rank            INTEGER NOT NULL,
  session_count   INTEGER NOT NULL DEFAULT 0,

  PRIMARY KEY (ranking_id, user_id)
);

ALTER TABLE public.coaching_ranking_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coaching_rank_entries_read" ON public.coaching_ranking_entries
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_rankings cr
      JOIN public.coaching_members cm ON cm.group_id = cr.group_id
      WHERE cr.id = coaching_ranking_entries.ranking_id
        AND cm.user_id = auth.uid()
    )
  );

-- ── 30. RACE_EVENTS ────────────────────────────────────────────────────────
-- Coaching race events (presential races).
-- Reference: RaceEventEntity

CREATE TABLE IF NOT EXISTS public.race_events (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id            UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  description         TEXT NOT NULL DEFAULT '',
  location            TEXT NOT NULL DEFAULT '',
  metric              TEXT NOT NULL CHECK (metric IN ('distance','time','pace')),
  target_distance_m   DOUBLE PRECISION,
  starts_at_ms        BIGINT NOT NULL,
  ends_at_ms          BIGINT NOT NULL,
  status              TEXT NOT NULL DEFAULT 'upcoming'
                      CHECK (status IN ('upcoming','active','completed','cancelled')),
  max_participants    INTEGER,
  created_by_user_id  UUID NOT NULL REFERENCES auth.users(id),
  created_at_ms       BIGINT NOT NULL,
  xp_reward           INTEGER NOT NULL DEFAULT 0,
  coins_reward        INTEGER NOT NULL DEFAULT 0,
  badge_id            TEXT REFERENCES public.badges(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_race_events_group ON public.race_events(group_id, status);

ALTER TABLE public.race_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "race_events_member_read" ON public.race_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = race_events.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- ── 31. RACE_PARTICIPATIONS ────────────────────────────────────────────────
-- Athlete participation in race events.
-- Reference: RaceParticipationEntity

CREATE TABLE IF NOT EXISTS public.race_participations (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  race_event_id             UUID NOT NULL REFERENCES public.race_events(id) ON DELETE CASCADE,
  user_id                   UUID NOT NULL REFERENCES auth.users(id),
  display_name              TEXT NOT NULL,
  joined_at_ms              BIGINT NOT NULL,
  total_distance_m          DOUBLE PRECISION NOT NULL DEFAULT 0,
  total_moving_ms           BIGINT NOT NULL DEFAULT 0,
  best_pace_sec_per_km      DOUBLE PRECISION,
  contributing_session_count INTEGER NOT NULL DEFAULT 0,
  contributing_session_ids  UUID[] NOT NULL DEFAULT '{}',
  completed                 BOOLEAN NOT NULL DEFAULT false,
  completed_at_ms           BIGINT,
  rank                      INTEGER,

  UNIQUE(race_event_id, user_id)
);

ALTER TABLE public.race_participations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "race_parts_member_read" ON public.race_participations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.race_events re
      JOIN public.coaching_members cm ON cm.group_id = re.group_id
      WHERE re.id = race_participations.race_event_id
        AND cm.user_id = auth.uid()
    )
  );

-- ── 32. RACE_RESULTS ───────────────────────────────────────────────────────
-- Finalized race results. Immutable.
-- Reference: RaceResultEntity

CREATE TABLE IF NOT EXISTS public.race_results (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  race_event_id       UUID NOT NULL REFERENCES public.race_events(id),
  user_id             UUID NOT NULL REFERENCES auth.users(id),
  display_name        TEXT NOT NULL,
  final_rank          INTEGER NOT NULL,
  total_distance_m    DOUBLE PRECISION NOT NULL DEFAULT 0,
  total_moving_ms     BIGINT NOT NULL DEFAULT 0,
  best_pace_sec_per_km DOUBLE PRECISION,
  session_count       INTEGER NOT NULL DEFAULT 0,
  target_completed    BOOLEAN NOT NULL DEFAULT false,
  xp_awarded          INTEGER NOT NULL DEFAULT 0,
  coins_awarded       INTEGER NOT NULL DEFAULT 0,
  badge_id            TEXT REFERENCES public.badges(id),
  computed_at_ms      BIGINT NOT NULL,

  UNIQUE(race_event_id, user_id)
);

ALTER TABLE public.race_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "race_results_member_read" ON public.race_results
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.race_events re
      JOIN public.coaching_members cm ON cm.group_id = re.group_id
      WHERE re.id = race_results.race_event_id
        AND cm.user_id = auth.uid()
    )
  );

-- ── 33. STORAGE POLICIES ──────────────────────────────────────────────────
-- Bucket: session-points

INSERT INTO storage.buckets (id, name, public)
VALUES ('session-points', 'session-points', false)
ON CONFLICT (id) DO NOTHING;

-- storage.objects policies sobrevivem a DROP SCHEMA public — drop idempotente
-- garante fresh replay (disaster recovery / CI reset).
DROP POLICY IF EXISTS "session_points_own_upload" ON storage.objects;
CREATE POLICY "session_points_own_upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'session-points'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "session_points_own_read" ON storage.objects;
CREATE POLICY "session_points_own_read" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'session-points'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── 34. HELPER FUNCTIONS ──────────────────────────────────────────────────

-- Auto-create wallet and profile_progress on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user_gamification()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO public.profile_progress (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_gamification ON auth.users;
CREATE TRIGGER on_auth_user_gamification
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_gamification();

-- Update member_count on group_members changes
CREATE OR REPLACE FUNCTION public.update_group_member_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.groups
  SET member_count = (
    SELECT COUNT(*) FROM public.group_members
    WHERE group_id = COALESCE(NEW.group_id, OLD.group_id)
      AND status = 'active'
  )
  WHERE id = COALESCE(NEW.group_id, OLD.group_id);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_group_member_count ON public.group_members;
CREATE TRIGGER trg_group_member_count
  AFTER INSERT OR UPDATE OR DELETE ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.update_group_member_count();
