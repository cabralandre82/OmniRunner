


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."cleanup_rate_limits"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  DELETE FROM public.api_rate_limits
  WHERE window_start < now() - interval '1 hour';
$$;


ALTER FUNCTION "public"."cleanup_rate_limits"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."compute_leaderboard_global_weekly"("p_period_key" "text", "p_start_ms" bigint, "p_end_ms" bigint) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  lb_id TEXT;
  row_count INTEGER;
BEGIN
  lb_id := 'global_weekly_distance_' || p_period_key;

  INSERT INTO public.leaderboards (id, scope, period, metric, period_key, computed_at_ms, is_final)
  VALUES (lb_id, 'global', 'weekly', 'distance', p_period_key, EXTRACT(EPOCH FROM now())::BIGINT * 1000, false)
  ON CONFLICT (id) DO UPDATE SET computed_at_ms = EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  DELETE FROM public.leaderboard_entries WHERE leaderboard_id = lb_id;

  INSERT INTO public.leaderboard_entries (leaderboard_id, user_id, display_name, avatar_url, level, value, rank, period_key)
  SELECT
    lb_id,
    s.user_id,
    p.display_name,
    p.avatar_url,
    COALESCE(FLOOR(POWER(pp.total_xp::DOUBLE PRECISION / 100, 2.0/3.0))::INTEGER, 0),
    SUM(s.total_distance_m),
    ROW_NUMBER() OVER (ORDER BY SUM(s.total_distance_m) DESC),
    p_period_key
  FROM public.sessions s
  JOIN public.profiles p ON p.id = s.user_id
  LEFT JOIN public.profile_progress pp ON pp.user_id = s.user_id
  WHERE s.is_verified = true
    AND s.start_time_ms BETWEEN p_start_ms AND p_end_ms
    AND s.total_distance_m > 0
  GROUP BY s.user_id, p.display_name, p.avatar_url, pp.total_xp
  ORDER BY SUM(s.total_distance_m) DESC
  LIMIT 200;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$;


ALTER FUNCTION "public"."compute_leaderboard_global_weekly"("p_period_key" "text", "p_start_ms" bigint, "p_end_ms" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'Runner'),
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user_gamification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.wallets (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO public.profile_progress (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user_gamification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_profile_progress"("p_user_id" "uuid", "p_xp" integer, "p_distance_m" double precision, "p_moving_ms" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE public.profile_progress
  SET
    total_xp              = total_xp + p_xp,
    season_xp             = season_xp + p_xp,
    lifetime_session_count = lifetime_session_count + 1,
    lifetime_distance_m   = lifetime_distance_m + p_distance_m,
    lifetime_moving_ms    = lifetime_moving_ms + p_moving_ms,
    updated_at            = now()
  WHERE user_id = p_user_id;
END;
$$;


ALTER FUNCTION "public"."increment_profile_progress"("p_user_id" "uuid", "p_xp" integer, "p_distance_m" double precision, "p_moving_ms" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_rate_limit"("p_user_id" "uuid", "p_fn" "text", "p_window_seconds" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_window_start timestamptz;
  v_count        int;
BEGIN
  v_window_start := to_timestamp(
    floor(extract(epoch FROM now()) / p_window_seconds) * p_window_seconds
  );

  INSERT INTO public.api_rate_limits (user_id, fn, window_start, count)
  VALUES (p_user_id, p_fn, v_window_start, 1)
  ON CONFLICT (user_id, fn, window_start)
  DO UPDATE SET count = api_rate_limits.count + 1
  RETURNING count INTO v_count;

  RETURN v_count;
END;
$$;


ALTER FUNCTION "public"."increment_rate_limit"("p_user_id" "uuid", "p_fn" "text", "p_window_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_wallet_balance"("p_user_id" "uuid", "p_delta" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE public.wallets
  SET
    balance_coins         = balance_coins + p_delta,
    lifetime_earned_coins = CASE WHEN p_delta > 0
                              THEN lifetime_earned_coins + p_delta
                              ELSE lifetime_earned_coins END,
    lifetime_spent_coins  = CASE WHEN p_delta < 0
                              THEN lifetime_spent_coins + ABS(p_delta)
                              ELSE lifetime_spent_coins END,
    updated_at = now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.wallets (user_id, balance_coins, lifetime_earned_coins, lifetime_spent_coins)
    VALUES (
      p_user_id,
      GREATEST(0, p_delta),
      CASE WHEN p_delta > 0 THEN p_delta ELSE 0 END,
      CASE WHEN p_delta < 0 THEN ABS(p_delta) ELSE 0 END
    );
  END IF;
END;
$$;


ALTER FUNCTION "public"."increment_wallet_balance"("p_user_id" "uuid", "p_delta" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_group_member_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."update_group_member_count"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."analytics_submissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "group_id" "uuid" NOT NULL,
    "distance_m" double precision NOT NULL,
    "moving_ms" bigint NOT NULL,
    "avg_pace_sec_per_km" double precision,
    "avg_bpm" integer,
    "start_time_ms" bigint NOT NULL,
    "end_time_ms" bigint NOT NULL,
    "processed_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."analytics_submissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."api_rate_limits" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "fn" "text" NOT NULL,
    "window_start" timestamp with time zone NOT NULL,
    "count" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."api_rate_limits" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."api_rate_limits_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."api_rate_limits_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."api_rate_limits_id_seq" OWNED BY "public"."api_rate_limits"."id";



CREATE TABLE IF NOT EXISTS "public"."athlete_baselines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "group_id" "uuid" NOT NULL,
    "metric" "text" NOT NULL,
    "value" double precision NOT NULL,
    "sample_size" integer NOT NULL,
    "window_start_ms" bigint NOT NULL,
    "window_end_ms" bigint NOT NULL,
    "computed_at_ms" bigint NOT NULL
);


ALTER TABLE "public"."athlete_baselines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."athlete_trends" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "group_id" "uuid" NOT NULL,
    "metric" "text" NOT NULL,
    "period" "text" NOT NULL,
    "direction" "text" NOT NULL,
    "current_value" double precision NOT NULL,
    "baseline_value" double precision NOT NULL,
    "change_percent" double precision NOT NULL,
    "data_points" integer NOT NULL,
    "latest_period_key" "text" NOT NULL,
    "analyzed_at_ms" bigint NOT NULL
);


ALTER TABLE "public"."athlete_trends" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."badge_awards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "badge_id" "text" NOT NULL,
    "trigger_session_id" "uuid",
    "unlocked_at_ms" bigint NOT NULL,
    "xp_awarded" integer DEFAULT 0 NOT NULL,
    "coins_awarded" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."badge_awards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."badges" (
    "id" "text" NOT NULL,
    "category" "text" NOT NULL,
    "tier" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "icon_asset" "text" DEFAULT ''::"text" NOT NULL,
    "xp_reward" integer DEFAULT 0 NOT NULL,
    "coins_reward" integer DEFAULT 0 NOT NULL,
    "criteria_type" "text" NOT NULL,
    "criteria_json" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_secret" boolean DEFAULT false NOT NULL,
    "season_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "badges_category_check" CHECK (("category" = ANY (ARRAY['distance'::"text", 'frequency'::"text", 'speed'::"text", 'endurance'::"text", 'social'::"text", 'special'::"text"]))),
    CONSTRAINT "badges_tier_check" CHECK (("tier" = ANY (ARRAY['bronze'::"text", 'silver'::"text", 'gold'::"text", 'diamond'::"text"])))
);


ALTER TABLE "public"."badges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."challenge_participants" (
    "challenge_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "status" "text" DEFAULT 'invited'::"text" NOT NULL,
    "responded_at_ms" bigint,
    "progress_value" double precision DEFAULT 0 NOT NULL,
    "contributing_session_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "last_submitted_at_ms" bigint,
    CONSTRAINT "challenge_participants_status_check" CHECK (("status" = ANY (ARRAY['invited'::"text", 'accepted'::"text", 'declined'::"text", 'withdrawn'::"text"])))
);


ALTER TABLE "public"."challenge_participants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."challenge_results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "challenge_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "final_value" double precision NOT NULL,
    "rank" integer,
    "outcome" "text" NOT NULL,
    "coins_earned" integer DEFAULT 0 NOT NULL,
    "session_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "calculated_at_ms" bigint NOT NULL,
    CONSTRAINT "challenge_results_outcome_check" CHECK (("outcome" = ANY (ARRAY['won'::"text", 'lost'::"text", 'tied'::"text", 'completed_target'::"text", 'participated'::"text", 'did_not_finish'::"text"])))
);


ALTER TABLE "public"."challenge_results" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."challenge_run_bindings" (
    "session_id" "uuid" NOT NULL,
    "challenge_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "accepted" boolean NOT NULL,
    "rejection_reason" "text",
    "metric_value" double precision,
    "session_distance_m" double precision NOT NULL,
    "session_verified" boolean NOT NULL,
    "session_integrity_flags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "session_had_hr" boolean NOT NULL,
    "evaluated_at_ms" bigint NOT NULL,
    CONSTRAINT "challenge_run_bindings_rejection_reason_check" CHECK (("rejection_reason" = ANY (ARRAY['not_completed'::"text", 'not_verified'::"text", 'below_min_distance'::"text", 'outside_window'::"text", 'already_submitted'::"text", 'missing_heart_rate'::"text"])))
);


ALTER TABLE "public"."challenge_run_bindings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."challenges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "creator_user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "type" "text" NOT NULL,
    "title" "text",
    "metric" "text" NOT NULL,
    "target" double precision,
    "window_ms" bigint NOT NULL,
    "start_mode" "text" DEFAULT 'on_accept'::"text" NOT NULL,
    "fixed_start_ms" bigint,
    "min_session_distance_m" double precision DEFAULT 1000 NOT NULL,
    "anti_cheat_policy" "text" DEFAULT 'standard'::"text" NOT NULL,
    "entry_fee_coins" integer DEFAULT 0 NOT NULL,
    "created_at_ms" bigint NOT NULL,
    "starts_at_ms" bigint,
    "ends_at_ms" bigint,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "challenges_anti_cheat_policy_check" CHECK (("anti_cheat_policy" = ANY (ARRAY['standard'::"text", 'strict'::"text"]))),
    CONSTRAINT "challenges_entry_fee_coins_check" CHECK (("entry_fee_coins" >= 0)),
    CONSTRAINT "challenges_metric_check" CHECK (("metric" = ANY (ARRAY['distance'::"text", 'pace'::"text", 'time'::"text"]))),
    CONSTRAINT "challenges_start_mode_check" CHECK (("start_mode" = ANY (ARRAY['on_accept'::"text", 'scheduled'::"text"]))),
    CONSTRAINT "challenges_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'completing'::"text", 'completed'::"text", 'cancelled'::"text", 'expired'::"text"]))),
    CONSTRAINT "challenges_type_check" CHECK (("type" = ANY (ARRAY['one_vs_one'::"text", 'group'::"text"])))
);


ALTER TABLE "public"."challenges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."coach_insights" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid" NOT NULL,
    "target_user_id" "uuid",
    "target_display_name" "text",
    "type" "text" NOT NULL,
    "priority" "text" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "metric" "text",
    "reference_value" double precision,
    "change_percent" double precision,
    "related_entity_id" "uuid",
    "created_at_ms" bigint NOT NULL,
    "read_at_ms" bigint,
    "dismissed" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."coach_insights" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."coaching_groups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "logo_url" "text",
    "coach_user_id" "uuid" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "city" "text" DEFAULT ''::"text" NOT NULL,
    "created_at_ms" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "coaching_groups_name_check" CHECK ((("length"("name") >= 3) AND ("length"("name") <= 80)))
);


ALTER TABLE "public"."coaching_groups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."coaching_invites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid" NOT NULL,
    "invited_user_id" "uuid" NOT NULL,
    "invited_by_user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "expires_at_ms" bigint NOT NULL,
    "created_at_ms" bigint NOT NULL,
    CONSTRAINT "coaching_invites_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."coaching_invites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."coaching_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "group_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "role" "text" DEFAULT 'athlete'::"text" NOT NULL,
    "joined_at_ms" bigint NOT NULL,
    CONSTRAINT "coaching_members_role_check" CHECK (("role" = ANY (ARRAY['coach'::"text", 'assistant'::"text", 'athlete'::"text"])))
);


ALTER TABLE "public"."coaching_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."coaching_ranking_entries" (
    "ranking_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "value" double precision NOT NULL,
    "rank" integer NOT NULL,
    "session_count" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."coaching_ranking_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."coaching_rankings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid" NOT NULL,
    "metric" "text" NOT NULL,
    "period" "text" NOT NULL,
    "period_key" "text" NOT NULL,
    "starts_at_ms" bigint NOT NULL,
    "ends_at_ms" bigint NOT NULL,
    "computed_at_ms" bigint NOT NULL,
    CONSTRAINT "coaching_rankings_metric_check" CHECK (("metric" = ANY (ARRAY['volume_distance'::"text", 'total_time'::"text", 'best_pace'::"text", 'consistency_days'::"text"]))),
    CONSTRAINT "coaching_rankings_period_check" CHECK (("period" = ANY (ARRAY['weekly'::"text", 'monthly'::"text", 'custom'::"text"])))
);


ALTER TABLE "public"."coaching_rankings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."coin_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "delta_coins" integer NOT NULL,
    "reason" "text" NOT NULL,
    "ref_id" "text",
    "created_at_ms" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "coin_ledger_reason_check" CHECK (("reason" = ANY (ARRAY['session_completed'::"text", 'challenge_one_vs_one_completed'::"text", 'challenge_one_vs_one_won'::"text", 'challenge_group_completed'::"text", 'streak_weekly'::"text", 'streak_monthly'::"text", 'pr_distance'::"text", 'pr_pace'::"text", 'challenge_entry_fee'::"text", 'challenge_pool_won'::"text", 'challenge_entry_refund'::"text", 'cosmetic_purchase'::"text", 'admin_adjustment'::"text", 'badge_reward'::"text", 'mission_reward'::"text"])))
);


ALTER TABLE "public"."coin_ledger" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."event_participations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "joined_at_ms" bigint NOT NULL,
    "current_value" double precision DEFAULT 0 NOT NULL,
    "rank" integer,
    "completed" boolean DEFAULT false NOT NULL,
    "completed_at_ms" bigint,
    "contributing_session_count" integer DEFAULT 0 NOT NULL,
    "contributing_session_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "rewards_claimed" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."event_participations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "image_url" "text",
    "type" "text" NOT NULL,
    "metric" "text" NOT NULL,
    "target_value" double precision,
    "starts_at_ms" bigint NOT NULL,
    "ends_at_ms" bigint NOT NULL,
    "max_participants" integer,
    "created_by_system" boolean DEFAULT false NOT NULL,
    "creator_user_id" "uuid",
    "xp_completion" integer DEFAULT 0 NOT NULL,
    "coins_completion" integer DEFAULT 0 NOT NULL,
    "xp_participation" integer DEFAULT 0 NOT NULL,
    "badge_id" "text",
    "status" "text" DEFAULT 'upcoming'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "events_metric_check" CHECK (("metric" = ANY (ARRAY['distance'::"text", 'sessions'::"text", 'moving_time'::"text"]))),
    CONSTRAINT "events_status_check" CHECK (("status" = ANY (ARRAY['upcoming'::"text", 'active'::"text", 'completed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "events_type_check" CHECK (("type" = ANY (ARRAY['individual'::"text", 'team'::"text"])))
);


ALTER TABLE "public"."events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."friendships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id_a" "uuid" NOT NULL,
    "user_id_b" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at_ms" bigint NOT NULL,
    "accepted_at_ms" bigint,
    CONSTRAINT "friendships_check" CHECK (("user_id_a" < "user_id_b")),
    CONSTRAINT "friendships_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text", 'blocked'::"text"])))
);


ALTER TABLE "public"."friendships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_goals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "target_value" double precision NOT NULL,
    "current_value" double precision DEFAULT 0 NOT NULL,
    "metric" "text" NOT NULL,
    "starts_at_ms" bigint NOT NULL,
    "ends_at_ms" bigint NOT NULL,
    "created_by_user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    CONSTRAINT "group_goals_metric_check" CHECK (("metric" = ANY (ARRAY['distance'::"text", 'sessions'::"text", 'moving_time'::"text"]))),
    CONSTRAINT "group_goals_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'completed'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."group_goals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "joined_at_ms" bigint NOT NULL,
    CONSTRAINT "group_members_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'moderator'::"text", 'member'::"text"]))),
    CONSTRAINT "group_members_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'banned'::"text", 'left'::"text"])))
);


ALTER TABLE "public"."group_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."groups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "avatar_url" "text",
    "created_by_user_id" "uuid" NOT NULL,
    "created_at_ms" bigint NOT NULL,
    "privacy" "text" DEFAULT 'open'::"text" NOT NULL,
    "max_members" integer DEFAULT 100 NOT NULL,
    "member_count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "groups_max_members_check" CHECK ((("max_members" >= 2) AND ("max_members" <= 200))),
    CONSTRAINT "groups_name_check" CHECK ((("length"("name") >= 3) AND ("length"("name") <= 50))),
    CONSTRAINT "groups_privacy_check" CHECK (("privacy" = ANY (ARRAY['open'::"text", 'closed'::"text", 'secret'::"text"])))
);


ALTER TABLE "public"."groups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."leaderboard_entries" (
    "leaderboard_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "avatar_url" "text",
    "level" integer DEFAULT 0 NOT NULL,
    "value" double precision NOT NULL,
    "rank" integer NOT NULL,
    "period_key" "text" NOT NULL
);


ALTER TABLE "public"."leaderboard_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."leaderboards" (
    "id" "text" NOT NULL,
    "scope" "text" NOT NULL,
    "group_id" "uuid",
    "period" "text" NOT NULL,
    "metric" "text" NOT NULL,
    "period_key" "text" NOT NULL,
    "computed_at_ms" bigint NOT NULL,
    "is_final" boolean DEFAULT false NOT NULL,
    CONSTRAINT "leaderboards_metric_check" CHECK (("metric" = ANY (ARRAY['distance'::"text", 'sessions'::"text", 'moving_time'::"text", 'avg_pace'::"text", 'season_xp'::"text"]))),
    CONSTRAINT "leaderboards_period_check" CHECK (("period" = ANY (ARRAY['weekly'::"text", 'monthly'::"text", 'season'::"text"]))),
    CONSTRAINT "leaderboards_scope_check" CHECK (("scope" = ANY (ARRAY['global'::"text", 'friends'::"text", 'group'::"text", 'season'::"text"])))
);


ALTER TABLE "public"."leaderboards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mission_progress" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "current_value" double precision DEFAULT 0 NOT NULL,
    "target_value" double precision NOT NULL,
    "assigned_at_ms" bigint NOT NULL,
    "completed_at_ms" bigint,
    "completion_count" integer DEFAULT 0 NOT NULL,
    "contributing_session_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "mission_progress_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'completed'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."mission_progress" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."missions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "difficulty" "text" NOT NULL,
    "slot" "text" NOT NULL,
    "xp_reward" integer DEFAULT 0 NOT NULL,
    "coins_reward" integer DEFAULT 0 NOT NULL,
    "criteria_type" "text" NOT NULL,
    "criteria_json" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "expires_at_ms" bigint,
    "season_id" "uuid",
    "max_completions" integer DEFAULT 1 NOT NULL,
    "cooldown_ms" bigint,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "missions_difficulty_check" CHECK (("difficulty" = ANY (ARRAY['easy'::"text", 'medium'::"text", 'hard'::"text"]))),
    CONSTRAINT "missions_slot_check" CHECK (("slot" = ANY (ARRAY['daily'::"text", 'weekly'::"text", 'season'::"text"])))
);


ALTER TABLE "public"."missions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profile_progress" (
    "user_id" "uuid" NOT NULL,
    "total_xp" integer DEFAULT 0 NOT NULL,
    "season_xp" integer DEFAULT 0 NOT NULL,
    "current_season_id" "uuid",
    "daily_streak_count" integer DEFAULT 0 NOT NULL,
    "last_streak_day_ms" bigint,
    "has_freeze_available" boolean DEFAULT false NOT NULL,
    "weekly_session_count" integer DEFAULT 0 NOT NULL,
    "monthly_session_count" integer DEFAULT 0 NOT NULL,
    "lifetime_session_count" integer DEFAULT 0 NOT NULL,
    "lifetime_distance_m" double precision DEFAULT 0 NOT NULL,
    "lifetime_moving_ms" bigint DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profile_progress" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "display_name" "text" DEFAULT 'Runner'::"text" NOT NULL,
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."race_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "location" "text" DEFAULT ''::"text" NOT NULL,
    "metric" "text" NOT NULL,
    "target_distance_m" double precision,
    "starts_at_ms" bigint NOT NULL,
    "ends_at_ms" bigint NOT NULL,
    "status" "text" DEFAULT 'upcoming'::"text" NOT NULL,
    "max_participants" integer,
    "created_by_user_id" "uuid" NOT NULL,
    "created_at_ms" bigint NOT NULL,
    "xp_reward" integer DEFAULT 0 NOT NULL,
    "coins_reward" integer DEFAULT 0 NOT NULL,
    "badge_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "race_events_metric_check" CHECK (("metric" = ANY (ARRAY['distance'::"text", 'time'::"text", 'pace'::"text"]))),
    CONSTRAINT "race_events_status_check" CHECK (("status" = ANY (ARRAY['upcoming'::"text", 'active'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."race_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."race_participations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "race_event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "joined_at_ms" bigint NOT NULL,
    "total_distance_m" double precision DEFAULT 0 NOT NULL,
    "total_moving_ms" bigint DEFAULT 0 NOT NULL,
    "best_pace_sec_per_km" double precision,
    "contributing_session_count" integer DEFAULT 0 NOT NULL,
    "contributing_session_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "completed" boolean DEFAULT false NOT NULL,
    "completed_at_ms" bigint,
    "rank" integer
);


ALTER TABLE "public"."race_participations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."race_results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "race_event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "final_rank" integer NOT NULL,
    "total_distance_m" double precision DEFAULT 0 NOT NULL,
    "total_moving_ms" bigint DEFAULT 0 NOT NULL,
    "best_pace_sec_per_km" double precision,
    "session_count" integer DEFAULT 0 NOT NULL,
    "target_completed" boolean DEFAULT false NOT NULL,
    "xp_awarded" integer DEFAULT 0 NOT NULL,
    "coins_awarded" integer DEFAULT 0 NOT NULL,
    "badge_id" "text",
    "computed_at_ms" bigint NOT NULL
);


ALTER TABLE "public"."race_results" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "started_at" timestamp with time zone,
    "ended_at" timestamp with time zone,
    "distance_meters" integer,
    "duration_seconds" integer,
    "source" "text" DEFAULT 'app'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."season_progress" (
    "user_id" "uuid" NOT NULL,
    "season_id" "uuid" NOT NULL,
    "season_xp" integer DEFAULT 0 NOT NULL,
    "claimed_milestone_indices" integer[] DEFAULT '{}'::integer[] NOT NULL,
    "end_rewards_claimed" boolean DEFAULT false NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."season_progress" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."seasons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "status" "text" DEFAULT 'upcoming'::"text" NOT NULL,
    "starts_at_ms" bigint NOT NULL,
    "ends_at_ms" bigint NOT NULL,
    "pass_xp_milestones" integer[] DEFAULT '{200,500,1000,2000,3500,5000,7500,10000,15000,20000}'::integer[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "seasons_status_check" CHECK (("status" = ANY (ARRAY['upcoming'::"text", 'active'::"text", 'settling'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."seasons" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" smallint DEFAULT 0 NOT NULL,
    "start_time_ms" bigint NOT NULL,
    "end_time_ms" bigint,
    "total_distance_m" double precision DEFAULT 0 NOT NULL,
    "moving_ms" bigint DEFAULT 0 NOT NULL,
    "avg_pace_sec_km" double precision,
    "avg_bpm" integer,
    "max_bpm" integer,
    "is_verified" boolean DEFAULT true NOT NULL,
    "integrity_flags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "ghost_session_id" "uuid",
    "points_path" "text",
    "is_synced" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wallets" (
    "user_id" "uuid" NOT NULL,
    "balance_coins" integer DEFAULT 0 NOT NULL,
    "lifetime_earned_coins" integer DEFAULT 0 NOT NULL,
    "lifetime_spent_coins" integer DEFAULT 0 NOT NULL,
    "last_reconciled_at_ms" bigint,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wallets_balance_coins_check" CHECK (("balance_coins" >= 0))
);


ALTER TABLE "public"."wallets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."xp_transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "xp" integer NOT NULL,
    "source" "text" NOT NULL,
    "ref_id" "text",
    "created_at_ms" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "xp_transactions_source_check" CHECK (("source" = ANY (ARRAY['session'::"text", 'badge'::"text", 'mission'::"text", 'streak'::"text", 'challenge'::"text"])))
);


ALTER TABLE "public"."xp_transactions" OWNER TO "postgres";


ALTER TABLE ONLY "public"."api_rate_limits" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."api_rate_limits_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."analytics_submissions"
    ADD CONSTRAINT "analytics_submissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."analytics_submissions"
    ADD CONSTRAINT "analytics_submissions_session_id_key" UNIQUE ("session_id");



ALTER TABLE ONLY "public"."api_rate_limits"
    ADD CONSTRAINT "api_rate_limits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."api_rate_limits"
    ADD CONSTRAINT "api_rate_limits_user_id_fn_window_start_key" UNIQUE ("user_id", "fn", "window_start");



ALTER TABLE ONLY "public"."athlete_baselines"
    ADD CONSTRAINT "athlete_baselines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."athlete_baselines"
    ADD CONSTRAINT "athlete_baselines_user_id_group_id_metric_key" UNIQUE ("user_id", "group_id", "metric");



ALTER TABLE ONLY "public"."athlete_trends"
    ADD CONSTRAINT "athlete_trends_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."athlete_trends"
    ADD CONSTRAINT "athlete_trends_user_id_group_id_metric_period_key" UNIQUE ("user_id", "group_id", "metric", "period");



ALTER TABLE ONLY "public"."badge_awards"
    ADD CONSTRAINT "badge_awards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."badge_awards"
    ADD CONSTRAINT "badge_awards_user_id_badge_id_key" UNIQUE ("user_id", "badge_id");



ALTER TABLE ONLY "public"."badges"
    ADD CONSTRAINT "badges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."challenge_participants"
    ADD CONSTRAINT "challenge_participants_pkey" PRIMARY KEY ("challenge_id", "user_id");



ALTER TABLE ONLY "public"."challenge_results"
    ADD CONSTRAINT "challenge_results_challenge_id_user_id_key" UNIQUE ("challenge_id", "user_id");



ALTER TABLE ONLY "public"."challenge_results"
    ADD CONSTRAINT "challenge_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."challenge_run_bindings"
    ADD CONSTRAINT "challenge_run_bindings_pkey" PRIMARY KEY ("session_id", "challenge_id");



ALTER TABLE ONLY "public"."challenges"
    ADD CONSTRAINT "challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."coach_insights"
    ADD CONSTRAINT "coach_insights_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."coaching_groups"
    ADD CONSTRAINT "coaching_groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."coaching_invites"
    ADD CONSTRAINT "coaching_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."coaching_members"
    ADD CONSTRAINT "coaching_members_group_id_user_id_key" UNIQUE ("group_id", "user_id");



ALTER TABLE ONLY "public"."coaching_members"
    ADD CONSTRAINT "coaching_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."coaching_ranking_entries"
    ADD CONSTRAINT "coaching_ranking_entries_pkey" PRIMARY KEY ("ranking_id", "user_id");



ALTER TABLE ONLY "public"."coaching_rankings"
    ADD CONSTRAINT "coaching_rankings_group_id_metric_period_key_key" UNIQUE ("group_id", "metric", "period_key");



ALTER TABLE ONLY "public"."coaching_rankings"
    ADD CONSTRAINT "coaching_rankings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."coin_ledger"
    ADD CONSTRAINT "coin_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."event_participations"
    ADD CONSTRAINT "event_participations_event_id_user_id_key" UNIQUE ("event_id", "user_id");



ALTER TABLE ONLY "public"."event_participations"
    ADD CONSTRAINT "event_participations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_user_id_a_user_id_b_key" UNIQUE ("user_id_a", "user_id_b");



ALTER TABLE ONLY "public"."group_goals"
    ADD CONSTRAINT "group_goals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_group_id_user_id_key" UNIQUE ("group_id", "user_id");



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leaderboard_entries"
    ADD CONSTRAINT "leaderboard_entries_pkey" PRIMARY KEY ("leaderboard_id", "user_id");



ALTER TABLE ONLY "public"."leaderboards"
    ADD CONSTRAINT "leaderboards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mission_progress"
    ADD CONSTRAINT "mission_progress_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."missions"
    ADD CONSTRAINT "missions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profile_progress"
    ADD CONSTRAINT "profile_progress_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."race_events"
    ADD CONSTRAINT "race_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."race_participations"
    ADD CONSTRAINT "race_participations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."race_participations"
    ADD CONSTRAINT "race_participations_race_event_id_user_id_key" UNIQUE ("race_event_id", "user_id");



ALTER TABLE ONLY "public"."race_results"
    ADD CONSTRAINT "race_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."race_results"
    ADD CONSTRAINT "race_results_race_event_id_user_id_key" UNIQUE ("race_event_id", "user_id");



ALTER TABLE ONLY "public"."runs"
    ADD CONSTRAINT "runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."season_progress"
    ADD CONSTRAINT "season_progress_pkey" PRIMARY KEY ("user_id", "season_id");



ALTER TABLE ONLY "public"."seasons"
    ADD CONSTRAINT "seasons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wallets"
    ADD CONSTRAINT "wallets_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."xp_transactions"
    ADD CONSTRAINT "xp_transactions_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_api_rate_limits_user_fn" ON "public"."api_rate_limits" USING "btree" ("user_id", "fn");



CREATE INDEX "idx_badge_awards_user" ON "public"."badge_awards" USING "btree" ("user_id", "unlocked_at_ms" DESC);



CREATE INDEX "idx_baselines_group" ON "public"."athlete_baselines" USING "btree" ("group_id");



CREATE INDEX "idx_baselines_user_group" ON "public"."athlete_baselines" USING "btree" ("user_id", "group_id");



CREATE INDEX "idx_challenge_parts_user" ON "public"."challenge_participants" USING "btree" ("user_id", "status");



CREATE INDEX "idx_challenges_creator" ON "public"."challenges" USING "btree" ("creator_user_id", "status");



CREATE INDEX "idx_challenges_status" ON "public"."challenges" USING "btree" ("status");



CREATE INDEX "idx_coaching_members_group" ON "public"."coaching_members" USING "btree" ("group_id", "role");



CREATE INDEX "idx_coaching_members_user" ON "public"."coaching_members" USING "btree" ("user_id");



CREATE INDEX "idx_event_parts_user" ON "public"."event_participations" USING "btree" ("user_id");



CREATE INDEX "idx_events_status" ON "public"."events" USING "btree" ("status", "starts_at_ms");



CREATE INDEX "idx_friendships_a" ON "public"."friendships" USING "btree" ("user_id_a", "status");



CREATE INDEX "idx_friendships_b" ON "public"."friendships" USING "btree" ("user_id_b", "status");



CREATE INDEX "idx_group_goals" ON "public"."group_goals" USING "btree" ("group_id", "status");



CREATE INDEX "idx_group_members_group" ON "public"."group_members" USING "btree" ("group_id", "status");



CREATE INDEX "idx_group_members_user" ON "public"."group_members" USING "btree" ("user_id", "status");



CREATE INDEX "idx_groups_privacy" ON "public"."groups" USING "btree" ("privacy") WHERE ("privacy" <> 'secret'::"text");



CREATE INDEX "idx_insights_group" ON "public"."coach_insights" USING "btree" ("group_id", "created_at_ms" DESC);



CREATE INDEX "idx_insights_type" ON "public"."coach_insights" USING "btree" ("group_id", "type");



CREATE INDEX "idx_insights_unread" ON "public"."coach_insights" USING "btree" ("group_id") WHERE (("read_at_ms" IS NULL) AND ("dismissed" = false));



CREATE INDEX "idx_leaderboards_scope" ON "public"."leaderboards" USING "btree" ("scope", "period", "metric", "period_key");



CREATE INDEX "idx_ledger_user" ON "public"."coin_ledger" USING "btree" ("user_id", "created_at_ms" DESC);



CREATE INDEX "idx_mission_progress_user" ON "public"."mission_progress" USING "btree" ("user_id", "status");



CREATE INDEX "idx_profiles_display_name" ON "public"."profiles" USING "btree" ("display_name");



CREATE INDEX "idx_race_events_group" ON "public"."race_events" USING "btree" ("group_id", "status");



CREATE INDEX "idx_runs_user_created" ON "public"."runs" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_sessions_status" ON "public"."sessions" USING "btree" ("user_id", "status");



CREATE INDEX "idx_sessions_user" ON "public"."sessions" USING "btree" ("user_id", "start_time_ms" DESC);



CREATE INDEX "idx_sessions_verified" ON "public"."sessions" USING "btree" ("user_id") WHERE ("is_verified" = true);



CREATE INDEX "idx_submissions_group_time" ON "public"."analytics_submissions" USING "btree" ("group_id", "start_time_ms" DESC);



CREATE INDEX "idx_submissions_user_group" ON "public"."analytics_submissions" USING "btree" ("user_id", "group_id");



CREATE INDEX "idx_trends_direction" ON "public"."athlete_trends" USING "btree" ("group_id", "direction");



CREATE INDEX "idx_trends_group" ON "public"."athlete_trends" USING "btree" ("group_id");



CREATE INDEX "idx_trends_user_group" ON "public"."athlete_trends" USING "btree" ("user_id", "group_id");



CREATE INDEX "idx_xp_tx_user" ON "public"."xp_transactions" USING "btree" ("user_id", "created_at_ms" DESC);



CREATE OR REPLACE TRIGGER "trg_group_member_count" AFTER INSERT OR DELETE OR UPDATE ON "public"."group_members" FOR EACH ROW EXECUTE FUNCTION "public"."update_group_member_count"();



ALTER TABLE ONLY "public"."analytics_submissions"
    ADD CONSTRAINT "analytics_submissions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."athlete_baselines"
    ADD CONSTRAINT "athlete_baselines_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."athlete_trends"
    ADD CONSTRAINT "athlete_trends_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."badge_awards"
    ADD CONSTRAINT "badge_awards_badge_id_fkey" FOREIGN KEY ("badge_id") REFERENCES "public"."badges"("id");



ALTER TABLE ONLY "public"."badge_awards"
    ADD CONSTRAINT "badge_awards_trigger_session_id_fkey" FOREIGN KEY ("trigger_session_id") REFERENCES "public"."sessions"("id");



ALTER TABLE ONLY "public"."badge_awards"
    ADD CONSTRAINT "badge_awards_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."badges"
    ADD CONSTRAINT "badges_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id");



ALTER TABLE ONLY "public"."challenge_participants"
    ADD CONSTRAINT "challenge_participants_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "public"."challenges"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."challenge_participants"
    ADD CONSTRAINT "challenge_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."challenge_results"
    ADD CONSTRAINT "challenge_results_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "public"."challenges"("id");



ALTER TABLE ONLY "public"."challenge_results"
    ADD CONSTRAINT "challenge_results_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."challenge_run_bindings"
    ADD CONSTRAINT "challenge_run_bindings_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "public"."challenges"("id");



ALTER TABLE ONLY "public"."challenge_run_bindings"
    ADD CONSTRAINT "challenge_run_bindings_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."sessions"("id");



ALTER TABLE ONLY "public"."challenge_run_bindings"
    ADD CONSTRAINT "challenge_run_bindings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."challenges"
    ADD CONSTRAINT "challenges_creator_user_id_fkey" FOREIGN KEY ("creator_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."coaching_groups"
    ADD CONSTRAINT "coaching_groups_coach_user_id_fkey" FOREIGN KEY ("coach_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."coaching_invites"
    ADD CONSTRAINT "coaching_invites_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."coaching_groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."coaching_invites"
    ADD CONSTRAINT "coaching_invites_invited_by_user_id_fkey" FOREIGN KEY ("invited_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."coaching_invites"
    ADD CONSTRAINT "coaching_invites_invited_user_id_fkey" FOREIGN KEY ("invited_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."coaching_members"
    ADD CONSTRAINT "coaching_members_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."coaching_groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."coaching_members"
    ADD CONSTRAINT "coaching_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."coaching_ranking_entries"
    ADD CONSTRAINT "coaching_ranking_entries_ranking_id_fkey" FOREIGN KEY ("ranking_id") REFERENCES "public"."coaching_rankings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."coaching_ranking_entries"
    ADD CONSTRAINT "coaching_ranking_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."coaching_rankings"
    ADD CONSTRAINT "coaching_rankings_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."coaching_groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."coin_ledger"
    ADD CONSTRAINT "coin_ledger_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_participations"
    ADD CONSTRAINT "event_participations_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_participations"
    ADD CONSTRAINT "event_participations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_badge_id_fkey" FOREIGN KEY ("badge_id") REFERENCES "public"."badges"("id");



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_creator_user_id_fkey" FOREIGN KEY ("creator_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_user_id_a_fkey" FOREIGN KEY ("user_id_a") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_user_id_b_fkey" FOREIGN KEY ("user_id_b") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_goals"
    ADD CONSTRAINT "group_goals_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."group_goals"
    ADD CONSTRAINT "group_goals_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."leaderboard_entries"
    ADD CONSTRAINT "leaderboard_entries_leaderboard_id_fkey" FOREIGN KEY ("leaderboard_id") REFERENCES "public"."leaderboards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."leaderboard_entries"
    ADD CONSTRAINT "leaderboard_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."leaderboards"
    ADD CONSTRAINT "leaderboards_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id");



ALTER TABLE ONLY "public"."mission_progress"
    ADD CONSTRAINT "mission_progress_mission_id_fkey" FOREIGN KEY ("mission_id") REFERENCES "public"."missions"("id");



ALTER TABLE ONLY "public"."mission_progress"
    ADD CONSTRAINT "mission_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."missions"
    ADD CONSTRAINT "missions_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id");



ALTER TABLE ONLY "public"."profile_progress"
    ADD CONSTRAINT "profile_progress_current_season_id_fkey" FOREIGN KEY ("current_season_id") REFERENCES "public"."seasons"("id");



ALTER TABLE ONLY "public"."profile_progress"
    ADD CONSTRAINT "profile_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."race_events"
    ADD CONSTRAINT "race_events_badge_id_fkey" FOREIGN KEY ("badge_id") REFERENCES "public"."badges"("id");



ALTER TABLE ONLY "public"."race_events"
    ADD CONSTRAINT "race_events_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."race_events"
    ADD CONSTRAINT "race_events_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."coaching_groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."race_participations"
    ADD CONSTRAINT "race_participations_race_event_id_fkey" FOREIGN KEY ("race_event_id") REFERENCES "public"."race_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."race_participations"
    ADD CONSTRAINT "race_participations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."race_results"
    ADD CONSTRAINT "race_results_badge_id_fkey" FOREIGN KEY ("badge_id") REFERENCES "public"."badges"("id");



ALTER TABLE ONLY "public"."race_results"
    ADD CONSTRAINT "race_results_race_event_id_fkey" FOREIGN KEY ("race_event_id") REFERENCES "public"."race_events"("id");



ALTER TABLE ONLY "public"."race_results"
    ADD CONSTRAINT "race_results_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."runs"
    ADD CONSTRAINT "runs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."season_progress"
    ADD CONSTRAINT "season_progress_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id");



ALTER TABLE ONLY "public"."season_progress"
    ADD CONSTRAINT "season_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wallets"
    ADD CONSTRAINT "wallets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."xp_transactions"
    ADD CONSTRAINT "xp_transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."analytics_submissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."api_rate_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."athlete_baselines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."athlete_trends" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."badge_awards" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "badge_awards_own_read" ON "public"."badge_awards" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "badge_awards_public_read" ON "public"."badge_awards" FOR SELECT USING (true);



ALTER TABLE "public"."badges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "badges_read_all" ON "public"."badges" FOR SELECT USING (true);



CREATE POLICY "baselines_read" ON "public"."athlete_baselines" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."coaching_members"
  WHERE (("coaching_members"."group_id" = "athlete_baselines"."group_id") AND ("coaching_members"."user_id" = "auth"."uid"()) AND ("coaching_members"."role" = ANY (ARRAY['coach'::"text", 'assistant'::"text"])))))));



CREATE POLICY "bindings_own_read" ON "public"."challenge_run_bindings" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."challenge_participants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "challenge_parts_delete_own" ON "public"."challenge_participants" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "challenge_parts_insert_own" ON "public"."challenge_participants" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "challenge_parts_own_read" ON "public"."challenge_participants" FOR SELECT USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."challenge_participants" "cp2"
  WHERE (("cp2"."challenge_id" = "challenge_participants"."challenge_id") AND ("cp2"."user_id" = "auth"."uid"()))))));



CREATE POLICY "challenge_parts_own_update" ON "public"."challenge_participants" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."challenge_results" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "challenge_results_participant_read" ON "public"."challenge_results" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."challenge_participants" "cp"
  WHERE (("cp"."challenge_id" = "challenge_results"."challenge_id") AND ("cp"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."challenge_run_bindings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."challenges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "challenges_delete_own" ON "public"."challenges" FOR DELETE USING (("auth"."uid"() = "creator_user_id"));



CREATE POLICY "challenges_insert_auth" ON "public"."challenges" FOR INSERT WITH CHECK (("auth"."uid"() = "creator_user_id"));



CREATE POLICY "challenges_select_authenticated" ON "public"."challenges" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "challenges_update_own" ON "public"."challenges" FOR UPDATE USING (("auth"."uid"() = "creator_user_id")) WITH CHECK (("auth"."uid"() = "creator_user_id"));



ALTER TABLE "public"."coach_insights" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "coach_reads_insights" ON "public"."coach_insights" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."coaching_members"
  WHERE (("coaching_members"."group_id" = "coach_insights"."group_id") AND ("coaching_members"."user_id" = "auth"."uid"()) AND ("coaching_members"."role" = ANY (ARRAY['coach'::"text", 'assistant'::"text"]))))));



CREATE POLICY "coach_updates_insights" ON "public"."coach_insights" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."coaching_members"
  WHERE (("coaching_members"."group_id" = "coach_insights"."group_id") AND ("coaching_members"."user_id" = "auth"."uid"()) AND ("coaching_members"."role" = ANY (ARRAY['coach'::"text", 'assistant'::"text"])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."coaching_members"
  WHERE (("coaching_members"."group_id" = "coach_insights"."group_id") AND ("coaching_members"."user_id" = "auth"."uid"()) AND ("coaching_members"."role" = ANY (ARRAY['coach'::"text", 'assistant'::"text"]))))));



ALTER TABLE "public"."coaching_groups" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "coaching_groups_insert_coach" ON "public"."coaching_groups" FOR INSERT WITH CHECK (("auth"."uid"() = "coach_user_id"));



CREATE POLICY "coaching_groups_member_read" ON "public"."coaching_groups" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."coaching_members" "cm"
  WHERE (("cm"."group_id" = "coaching_groups"."id") AND ("cm"."user_id" = "auth"."uid"())))));



CREATE POLICY "coaching_groups_update_coach" ON "public"."coaching_groups" FOR UPDATE USING (("auth"."uid"() = "coach_user_id"));



ALTER TABLE "public"."coaching_invites" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "coaching_invites_read" ON "public"."coaching_invites" FOR SELECT USING ((("auth"."uid"() = "invited_user_id") OR (EXISTS ( SELECT 1
   FROM "public"."coaching_members" "cm"
  WHERE (("cm"."group_id" = "coaching_invites"."group_id") AND ("cm"."user_id" = "auth"."uid"()) AND ("cm"."role" = ANY (ARRAY['coach'::"text", 'assistant'::"text"])))))));



CREATE POLICY "coaching_invites_update" ON "public"."coaching_invites" FOR UPDATE USING (("auth"."uid"() = "invited_user_id"));



ALTER TABLE "public"."coaching_members" ENABLE ROW LEVEL SECURITY;


-- Helper function to avoid infinite recursion in coaching_members RLS.
CREATE OR REPLACE FUNCTION public.user_coaching_group_ids()
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = 'public'
AS $$
  SELECT group_id FROM public.coaching_members WHERE user_id = auth.uid();
$$;

CREATE POLICY "coaching_members_group_read"
  ON "public"."coaching_members"
  FOR SELECT
  USING (group_id IN (SELECT public.user_coaching_group_ids()));



CREATE POLICY "coaching_rank_entries_read" ON "public"."coaching_ranking_entries" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."coaching_rankings" "cr"
     JOIN "public"."coaching_members" "cm" ON (("cm"."group_id" = "cr"."group_id")))
  WHERE (("cr"."id" = "coaching_ranking_entries"."ranking_id") AND ("cm"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."coaching_ranking_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."coaching_rankings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "coaching_rankings_member_read" ON "public"."coaching_rankings" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."coaching_members" "cm"
  WHERE (("cm"."group_id" = "coaching_rankings"."group_id") AND ("cm"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."coin_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."event_participations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "event_parts_event_read" ON "public"."event_participations" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."event_participations" "ep2"
  WHERE (("ep2"."event_id" = "event_participations"."event_id") AND ("ep2"."user_id" = "auth"."uid"())))));



CREATE POLICY "event_parts_insert_self" ON "public"."event_participations" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "event_parts_own_read" ON "public"."event_participations" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "events_read_all" ON "public"."events" FOR SELECT USING (true);



ALTER TABLE "public"."friendships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "friendships_own_insert" ON "public"."friendships" FOR INSERT WITH CHECK ((("auth"."uid"() = "user_id_a") OR ("auth"."uid"() = "user_id_b")));



CREATE POLICY "friendships_own_read" ON "public"."friendships" FOR SELECT USING ((("auth"."uid"() = "user_id_a") OR ("auth"."uid"() = "user_id_b")));



CREATE POLICY "friendships_own_update" ON "public"."friendships" FOR UPDATE USING ((("auth"."uid"() = "user_id_a") OR ("auth"."uid"() = "user_id_b")));



ALTER TABLE "public"."group_goals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "group_goals_read_member" ON "public"."group_goals" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."group_members" "gm"
  WHERE (("gm"."group_id" = "group_goals"."group_id") AND ("gm"."user_id" = "auth"."uid"()) AND ("gm"."status" = 'active'::"text")))));



ALTER TABLE "public"."group_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "group_members_insert_self" ON "public"."group_members" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



-- Helper functions to avoid infinite recursion in group_members RLS.
CREATE OR REPLACE FUNCTION public.user_social_group_ids()
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = 'public'
AS $$
  SELECT group_id FROM public.group_members
  WHERE user_id = auth.uid() AND status = 'active';
$$;

CREATE OR REPLACE FUNCTION public.is_group_admin_or_mod(p_group_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = p_group_id
      AND user_id = auth.uid()
      AND role IN ('admin', 'moderator')
      AND status = 'active'
  );
$$;

CREATE POLICY "group_members_read"
  ON "public"."group_members"
  FOR SELECT
  USING (group_id IN (SELECT public.user_social_group_ids()));

CREATE POLICY "group_members_update_mod"
  ON "public"."group_members"
  FOR UPDATE
  USING (
    auth.uid() = user_id
    OR public.is_group_admin_or_mod(group_id)
  );



ALTER TABLE "public"."groups" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "groups_insert_auth" ON "public"."groups" FOR INSERT WITH CHECK (("auth"."uid"() = "created_by_user_id"));



CREATE POLICY "groups_read_public" ON "public"."groups" FOR SELECT USING ((("privacy" <> 'secret'::"text") OR (EXISTS ( SELECT 1
   FROM "public"."group_members" "gm"
  WHERE (("gm"."group_id" = "groups"."id") AND ("gm"."user_id" = "auth"."uid"()) AND ("gm"."status" = 'active'::"text"))))));



CREATE POLICY "groups_update_admin" ON "public"."groups" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."group_members" "gm"
  WHERE (("gm"."group_id" = "groups"."id") AND ("gm"."user_id" = "auth"."uid"()) AND ("gm"."role" = 'admin'::"text") AND ("gm"."status" = 'active'::"text")))));



CREATE POLICY "lb_entries_read" ON "public"."leaderboard_entries" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."leaderboards" "lb"
  WHERE ("lb"."id" = "leaderboard_entries"."leaderboard_id"))));



ALTER TABLE "public"."leaderboard_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."leaderboards" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "leaderboards_read_all" ON "public"."leaderboards" FOR SELECT USING ((("scope" = ANY (ARRAY['global'::"text", 'season'::"text"])) OR (("scope" = 'group'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."group_members" "gm"
  WHERE (("gm"."group_id" = "leaderboards"."group_id") AND ("gm"."user_id" = "auth"."uid"()) AND ("gm"."status" = 'active'::"text"))))) OR (("scope" = 'friends'::"text") AND true)));



CREATE POLICY "ledger_own_read" ON "public"."coin_ledger" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."mission_progress" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mission_progress_own_read" ON "public"."mission_progress" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."missions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "missions_read_all" ON "public"."missions" FOR SELECT USING (true);



ALTER TABLE "public"."profile_progress" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_insert_own" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "profiles_select_own" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "profiles_update_own" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "progress_own_read" ON "public"."profile_progress" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "progress_public_read" ON "public"."profile_progress" FOR SELECT USING (true);



ALTER TABLE "public"."race_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "race_events_member_read" ON "public"."race_events" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."coaching_members" "cm"
  WHERE (("cm"."group_id" = "race_events"."group_id") AND ("cm"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."race_participations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "race_parts_member_read" ON "public"."race_participations" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."race_events" "re"
     JOIN "public"."coaching_members" "cm" ON (("cm"."group_id" = "re"."group_id")))
  WHERE (("re"."id" = "race_participations"."race_event_id") AND ("cm"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."race_results" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "race_results_member_read" ON "public"."race_results" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."race_events" "re"
     JOIN "public"."coaching_members" "cm" ON (("cm"."group_id" = "re"."group_id")))
  WHERE (("re"."id" = "race_results"."race_event_id") AND ("cm"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."runs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "runs_delete_own" ON "public"."runs" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "runs_insert_own" ON "public"."runs" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "runs_select_own" ON "public"."runs" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "runs_update_own" ON "public"."runs" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."season_progress" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "season_progress_own_read" ON "public"."season_progress" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."seasons" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "seasons_read_all" ON "public"."seasons" FOR SELECT USING (true);



ALTER TABLE "public"."sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sessions_own_insert" ON "public"."sessions" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "sessions_own_read" ON "public"."sessions" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "sessions_own_update" ON "public"."sessions" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "trends_read" ON "public"."athlete_trends" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."coaching_members"
  WHERE (("coaching_members"."group_id" = "athlete_trends"."group_id") AND ("coaching_members"."user_id" = "auth"."uid"()) AND ("coaching_members"."role" = ANY (ARRAY['coach'::"text", 'assistant'::"text"])))))));



CREATE POLICY "user_inserts_own_submissions" ON "public"."analytics_submissions" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "user_reads_own_submissions" ON "public"."analytics_submissions" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."wallets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wallets_own_read" ON "public"."wallets" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."xp_transactions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "xp_tx_own_read" ON "public"."xp_transactions" FOR SELECT USING (("auth"."uid"() = "user_id"));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_rate_limits"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_rate_limits"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_rate_limits"() TO "service_role";



GRANT ALL ON FUNCTION "public"."compute_leaderboard_global_weekly"("p_period_key" "text", "p_start_ms" bigint, "p_end_ms" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."compute_leaderboard_global_weekly"("p_period_key" "text", "p_start_ms" bigint, "p_end_ms" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."compute_leaderboard_global_weekly"("p_period_key" "text", "p_start_ms" bigint, "p_end_ms" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user_gamification"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user_gamification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user_gamification"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_profile_progress"("p_user_id" "uuid", "p_xp" integer, "p_distance_m" double precision, "p_moving_ms" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_profile_progress"("p_user_id" "uuid", "p_xp" integer, "p_distance_m" double precision, "p_moving_ms" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_profile_progress"("p_user_id" "uuid", "p_xp" integer, "p_distance_m" double precision, "p_moving_ms" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_rate_limit"("p_user_id" "uuid", "p_fn" "text", "p_window_seconds" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_rate_limit"("p_user_id" "uuid", "p_fn" "text", "p_window_seconds" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_rate_limit"("p_user_id" "uuid", "p_fn" "text", "p_window_seconds" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_wallet_balance"("p_user_id" "uuid", "p_delta" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_wallet_balance"("p_user_id" "uuid", "p_delta" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_wallet_balance"("p_user_id" "uuid", "p_delta" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_group_member_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_group_member_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_group_member_count"() TO "service_role";



GRANT ALL ON TABLE "public"."analytics_submissions" TO "anon";
GRANT ALL ON TABLE "public"."analytics_submissions" TO "authenticated";
GRANT ALL ON TABLE "public"."analytics_submissions" TO "service_role";



GRANT ALL ON TABLE "public"."api_rate_limits" TO "anon";
GRANT ALL ON TABLE "public"."api_rate_limits" TO "authenticated";
GRANT ALL ON TABLE "public"."api_rate_limits" TO "service_role";



GRANT ALL ON SEQUENCE "public"."api_rate_limits_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."api_rate_limits_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."api_rate_limits_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."athlete_baselines" TO "anon";
GRANT ALL ON TABLE "public"."athlete_baselines" TO "authenticated";
GRANT ALL ON TABLE "public"."athlete_baselines" TO "service_role";



GRANT ALL ON TABLE "public"."athlete_trends" TO "anon";
GRANT ALL ON TABLE "public"."athlete_trends" TO "authenticated";
GRANT ALL ON TABLE "public"."athlete_trends" TO "service_role";



GRANT ALL ON TABLE "public"."badge_awards" TO "anon";
GRANT ALL ON TABLE "public"."badge_awards" TO "authenticated";
GRANT ALL ON TABLE "public"."badge_awards" TO "service_role";



GRANT ALL ON TABLE "public"."badges" TO "anon";
GRANT ALL ON TABLE "public"."badges" TO "authenticated";
GRANT ALL ON TABLE "public"."badges" TO "service_role";



GRANT ALL ON TABLE "public"."challenge_participants" TO "anon";
GRANT ALL ON TABLE "public"."challenge_participants" TO "authenticated";
GRANT ALL ON TABLE "public"."challenge_participants" TO "service_role";



GRANT ALL ON TABLE "public"."challenge_results" TO "anon";
GRANT ALL ON TABLE "public"."challenge_results" TO "authenticated";
GRANT ALL ON TABLE "public"."challenge_results" TO "service_role";



GRANT ALL ON TABLE "public"."challenge_run_bindings" TO "anon";
GRANT ALL ON TABLE "public"."challenge_run_bindings" TO "authenticated";
GRANT ALL ON TABLE "public"."challenge_run_bindings" TO "service_role";



GRANT ALL ON TABLE "public"."challenges" TO "anon";
GRANT ALL ON TABLE "public"."challenges" TO "authenticated";
GRANT ALL ON TABLE "public"."challenges" TO "service_role";



GRANT ALL ON TABLE "public"."coach_insights" TO "anon";
GRANT ALL ON TABLE "public"."coach_insights" TO "authenticated";
GRANT ALL ON TABLE "public"."coach_insights" TO "service_role";



GRANT ALL ON TABLE "public"."coaching_groups" TO "anon";
GRANT ALL ON TABLE "public"."coaching_groups" TO "authenticated";
GRANT ALL ON TABLE "public"."coaching_groups" TO "service_role";



GRANT ALL ON TABLE "public"."coaching_invites" TO "anon";
GRANT ALL ON TABLE "public"."coaching_invites" TO "authenticated";
GRANT ALL ON TABLE "public"."coaching_invites" TO "service_role";



GRANT ALL ON TABLE "public"."coaching_members" TO "anon";
GRANT ALL ON TABLE "public"."coaching_members" TO "authenticated";
GRANT ALL ON TABLE "public"."coaching_members" TO "service_role";



GRANT ALL ON TABLE "public"."coaching_ranking_entries" TO "anon";
GRANT ALL ON TABLE "public"."coaching_ranking_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."coaching_ranking_entries" TO "service_role";



GRANT ALL ON TABLE "public"."coaching_rankings" TO "anon";
GRANT ALL ON TABLE "public"."coaching_rankings" TO "authenticated";
GRANT ALL ON TABLE "public"."coaching_rankings" TO "service_role";



GRANT ALL ON TABLE "public"."coin_ledger" TO "anon";
GRANT ALL ON TABLE "public"."coin_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."coin_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."event_participations" TO "anon";
GRANT ALL ON TABLE "public"."event_participations" TO "authenticated";
GRANT ALL ON TABLE "public"."event_participations" TO "service_role";



GRANT ALL ON TABLE "public"."events" TO "anon";
GRANT ALL ON TABLE "public"."events" TO "authenticated";
GRANT ALL ON TABLE "public"."events" TO "service_role";



GRANT ALL ON TABLE "public"."friendships" TO "anon";
GRANT ALL ON TABLE "public"."friendships" TO "authenticated";
GRANT ALL ON TABLE "public"."friendships" TO "service_role";



GRANT ALL ON TABLE "public"."group_goals" TO "anon";
GRANT ALL ON TABLE "public"."group_goals" TO "authenticated";
GRANT ALL ON TABLE "public"."group_goals" TO "service_role";



GRANT ALL ON TABLE "public"."group_members" TO "anon";
GRANT ALL ON TABLE "public"."group_members" TO "authenticated";
GRANT ALL ON TABLE "public"."group_members" TO "service_role";



GRANT ALL ON TABLE "public"."groups" TO "anon";
GRANT ALL ON TABLE "public"."groups" TO "authenticated";
GRANT ALL ON TABLE "public"."groups" TO "service_role";



GRANT ALL ON TABLE "public"."leaderboard_entries" TO "anon";
GRANT ALL ON TABLE "public"."leaderboard_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."leaderboard_entries" TO "service_role";



GRANT ALL ON TABLE "public"."leaderboards" TO "anon";
GRANT ALL ON TABLE "public"."leaderboards" TO "authenticated";
GRANT ALL ON TABLE "public"."leaderboards" TO "service_role";



GRANT ALL ON TABLE "public"."mission_progress" TO "anon";
GRANT ALL ON TABLE "public"."mission_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."mission_progress" TO "service_role";



GRANT ALL ON TABLE "public"."missions" TO "anon";
GRANT ALL ON TABLE "public"."missions" TO "authenticated";
GRANT ALL ON TABLE "public"."missions" TO "service_role";



GRANT ALL ON TABLE "public"."profile_progress" TO "anon";
GRANT ALL ON TABLE "public"."profile_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_progress" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."race_events" TO "anon";
GRANT ALL ON TABLE "public"."race_events" TO "authenticated";
GRANT ALL ON TABLE "public"."race_events" TO "service_role";



GRANT ALL ON TABLE "public"."race_participations" TO "anon";
GRANT ALL ON TABLE "public"."race_participations" TO "authenticated";
GRANT ALL ON TABLE "public"."race_participations" TO "service_role";



GRANT ALL ON TABLE "public"."race_results" TO "anon";
GRANT ALL ON TABLE "public"."race_results" TO "authenticated";
GRANT ALL ON TABLE "public"."race_results" TO "service_role";



GRANT ALL ON TABLE "public"."runs" TO "anon";
GRANT ALL ON TABLE "public"."runs" TO "authenticated";
GRANT ALL ON TABLE "public"."runs" TO "service_role";



GRANT ALL ON TABLE "public"."season_progress" TO "anon";
GRANT ALL ON TABLE "public"."season_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."season_progress" TO "service_role";



GRANT ALL ON TABLE "public"."seasons" TO "anon";
GRANT ALL ON TABLE "public"."seasons" TO "authenticated";
GRANT ALL ON TABLE "public"."seasons" TO "service_role";



GRANT ALL ON TABLE "public"."sessions" TO "anon";
GRANT ALL ON TABLE "public"."sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."sessions" TO "service_role";



GRANT ALL ON TABLE "public"."wallets" TO "anon";
GRANT ALL ON TABLE "public"."wallets" TO "authenticated";
GRANT ALL ON TABLE "public"."wallets" TO "service_role";



GRANT ALL ON TABLE "public"."xp_transactions" TO "anon";
GRANT ALL ON TABLE "public"."xp_transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."xp_transactions" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







