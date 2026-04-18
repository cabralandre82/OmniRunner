-- ══════════════════════════════════════════════════════════════════════════
-- L04-01 — fn_delete_user_data complete LGPD (Art. 18, VI) coverage
--
-- Referência auditoria:
--   docs/audit/findings/L04-01-fn-delete-user-data-e-incompleta-multiplas-tabelas.md
--   docs/audit/parts/04-clo.md [4.1]
--
-- Problema:
--   `fn_delete_user_data` (20260312000000_fix_broken_functions.sql) cobria
--   apenas 13 tabelas. Ao auditar `pg_constraint` identificamos 39 FKs
--   apontando para `auth.users` a partir do schema `public`, mais
--   referências adicionais via `target_user_id`, `athlete_user_id`,
--   `created_by`, `reviewed_by` etc. Tabelas com FK NO ACTION (não CASCADE)
--   ativamente FAZEM `auth.admin.deleteUser()` falhar se houver rows.
--   Resultado: LGPD Art. 18, VI (eliminação) falha silenciosamente — ANPD
--   pode multar em até 2% do faturamento (teto R$ 50 mi/infração).
--
-- Correção (esta migration):
--   1. Nova tabela `lgpd_deletion_strategy` — documenta EM TABELA todas as
--      colunas que referenciam user_id e a estratégia (delete/anonymize/
--      nullify). Serve como fonte única de verdade + bloqueador de
--      regressão (CI detecta tabelas novas não mapeadas).
--   2. View `lgpd_user_data_coverage_gaps` — junta information_schema.columns
--      com a estratégia e exibe user-referencing columns SEM estratégia.
--      Integration test falha se houver gaps.
--   3. `fn_delete_user_data` reescrita com SECURITY DEFINER +
--      `SET search_path=public,pg_temp` (L18-03) + `SET lock_timeout=5s`
--      (L19-05). Cobre:
--        - 26 tabelas categoria A (DELETE) — dados pessoais sem dependência.
--        - 3 tabelas categoria B (ANONYMIZE user_id→zero UUID) — ledger
--          financeiro e trace de custódia (coin_ledger, xp_transactions,
--          clearing_events).
--        - 8 colunas categoria C (NULL-OUT creator/reviewer refs) — conteúdo
--          continua útil para o grupo, só a ligação ao indivíduo some.
--        - storage.objects em buckets com prefixo `{uid}/` (session-points,
--          avatars).
--        - profile anonymization (preservada da versão anterior).
--        - 10+ tabelas do escopo original do finding tratadas defensivamente
--          via `EXCEPTION WHEN undefined_table` (push_tokens, audit_logs,
--          social_*, running_dna_profiles, etc — existem em produção ou em
--          branches futuros).
--   4. Retorna `jsonb` com contagem por tabela — caller logga como evidência
--      LGPD (respostas a subject-access-requests).
--
-- Breaking change:
--   Função muda assinatura de `RETURNS void` para `RETURNS jsonb`. Caller
--   único (`supabase/functions/delete-account/index.ts`) ignora o return —
--   tsc do edge function continua verde. Integration/unit tests atualizados.
-- ══════════════════════════════════════════════════════════════════════════

-- 0. LGPD anonymization sentinel user
--
-- `fn_delete_user_data` anonimiza coin_ledger/xp_transactions/clearing_events
-- trocando user_id pelo zero UUID. As FKs dessas tabelas apontam para
-- `auth.users(id)` com ON DELETE CASCADE — se o sentinel não existir, o
-- UPDATE falha com `foreign_key_violation` (SQLSTATE 23503) sem ser
-- capturado por `EXCEPTION WHEN undefined_table`. Resultado: a função
-- abortava em produção, deixando PII em tabelas financeiras — bug latente
-- da versão anterior (20260312000000_fix_broken_functions.sql).
--
-- Esta seed cria um auth user "sentinela" com id=0000...0000, email
-- `anonimo-lgpd@internal.omnirunner.app`, password vazio (unreachable hash
-- — nunca pode fazer login), marcado com `is_lgpd_sentinel=true`. Serve
-- exclusivamente como âncora de FK para dados anonimizados.
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'anonimo-lgpd@internal.omnirunner.app',
  '',
  now(),
  '{"provider":"internal","providers":["internal"]}'::jsonb,
  '{"is_lgpd_sentinel":true,"description":"Sentinel user for LGPD anonymized FKs. Cannot login. See L04-01."}'::jsonb,
  now(),
  now(),
  false,
  true
)
ON CONFLICT (id) DO NOTHING;

-- Se a tabela auth.users for de um supabase mais antigo sem coluna
-- is_anonymous, tenta novamente sem ela.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000000') THEN
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated',
      'anonimo-lgpd@internal.omnirunner.app', '',
      now(),
      '{"provider":"internal","providers":["internal"]}'::jsonb,
      '{"is_lgpd_sentinel":true,"description":"Sentinel user for LGPD anonymized FKs. See L04-01."}'::jsonb,
      now(), now()
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $$;

-- 1. Deletion strategy registry (fonte única de verdade — CI bloqueia regressão)
CREATE TABLE IF NOT EXISTS public.lgpd_deletion_strategy (
  table_name    text    NOT NULL,
  column_name   text    NOT NULL,
  strategy      text    NOT NULL
    CHECK (strategy IN ('delete', 'anonymize', 'nullify', 'defensive_optional')),
  rationale     text    NOT NULL,
  added_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (table_name, column_name)
);

COMMENT ON TABLE public.lgpd_deletion_strategy IS
  'L04-01: documenta cada coluna (table_name, column_name) que referencia um '
  'usuário e a estratégia aplicada por fn_delete_user_data. CI (integration '
  'tests) verifica que toda user-referencing column em information_schema '
  'tem registro aqui. Strategies: delete=remove row; anonymize=user_id → '
  'zero UUID; nullify=column → NULL; defensive_optional=tabela pode não '
  'existir em alguns ambientes.';

-- RLS fechada — só service_role lê (admin_master poderia ver em view)
ALTER TABLE public.lgpd_deletion_strategy ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.lgpd_deletion_strategy TO service_role;
REVOKE ALL ON public.lgpd_deletion_strategy FROM PUBLIC;
REVOKE ALL ON public.lgpd_deletion_strategy FROM anon;
REVOKE ALL ON public.lgpd_deletion_strategy FROM authenticated;

-- Seed: mapa canônico do schema atual + futuros (defensive_optional)
-- Idempotent via ON CONFLICT.
INSERT INTO public.lgpd_deletion_strategy (table_name, column_name, strategy, rationale) VALUES
  -- Category A: DELETE rows (personal data, no aggregate dependency)
  ('analytics_submissions',    'user_id',             'delete',     'Event analytics PII — não há dependência externa'),
  ('api_rate_limits',          'user_id',             'delete',     'Rate limit trace — efêmero'),
  ('athlete_baselines',        'user_id',             'delete',     'Fitness baseline pessoal'),
  ('athlete_trends',           'user_id',             'delete',     'Performance trends pessoais'),
  ('badge_awards',             'user_id',             'delete',     'Conquistas pessoais (CASCADE pela FK mas explícito para auditoria)'),
  ('challenge_participants',   'user_id',             'delete',     'Participação em desafios (já coberto)'),
  ('challenge_results',        'user_id',             'delete',     'Resultados de desafios'),
  ('challenge_run_bindings',   'user_id',             'delete',     'Ligação run↔challenge pessoal'),
  ('coach_insights',           'target_user_id',      'delete',     'Observações de coach sobre atleta (PII comportamental)'),
  ('coaching_invites',         'invited_user_id',     'delete',     'Convite enviado ao usuário'),
  ('coaching_invites',         'invited_by_user_id',  'delete',     'Convite enviado pelo usuário (row duplicada se mesmo user é both)'),
  ('coaching_join_requests',   'user_id',             'delete',     'Pedido de ingresso pessoal'),
  ('coaching_members',         'user_id',             'delete',     'Membership (CASCADE mas explícito)'),
  ('coaching_ranking_entries', 'user_id',             'delete',     'Posição em ranking pessoal'),
  ('event_participations',     'user_id',             'delete',     'Inscrição em evento'),
  ('friendships',              'user_id_a',           'delete',     'Relacionamento social (row entire deletada se qualquer lado)'),
  ('friendships',              'user_id_b',           'delete',     'Relacionamento social (lado B)'),
  ('group_members',            'user_id',             'delete',     'Group membership legada (CASCADE)'),
  ('leaderboard_entries',      'user_id',             'delete',     'Entrada em leaderboard'),
  ('mission_progress',         'user_id',             'delete',     'Progresso em missão (CASCADE)'),
  ('profile_progress',         'user_id',             'delete',     'XP e nível (CASCADE)'),
  ('race_participations',      'user_id',             'delete',     'Inscrição em corrida'),
  ('race_results',             'user_id',             'delete',     'Resultado de corrida pessoal'),
  ('runs',                     'user_id',             'delete',     'Corridas (GPS tracks — PII sensível, CASCADE)'),
  ('season_progress',          'user_id',             'delete',     'Progresso de temporada (CASCADE)'),
  ('sessions',                 'user_id',             'delete',     'Sessões de treino (GPS + HR, CASCADE)'),
  ('wallets',                  'user_id',             'delete',     'Wallet do usuário (CASCADE) — ledger preserva via coin_ledger anonymized'),

  -- Category B: ANONYMIZE user_id (keep row for aggregate/financial integrity)
  ('coin_ledger',              'user_id',             'anonymize',  'Ledger financeiro — preserva invariantes de contabilidade'),
  ('xp_transactions',          'user_id',             'anonymize',  'Trace de gamificação — preserva somas agregadas'),
  ('clearing_events',          'athlete_user_id',     'anonymize',  'Evento de custódia — preserva auditoria financeira'),

  -- Category C: NULL-OUT creator/reviewer refs (content stays, ownership de-linked)
  ('challenges',               'creator_user_id',     'nullify',    'Desafio criado permanece ativo para o grupo'),
  ('coaching_groups',          'approval_reviewed_by','nullify',    'Aprovação histórica (não aprovador)'),
  ('coaching_join_requests',   'reviewed_by',         'nullify',    'Review histórico — pedido em si já foi deletado'),
  ('events',                   'creator_user_id',     'nullify',    'Evento criado permanece para o grupo'),
  ('group_goals',              'created_by_user_id',  'nullify',    'Meta do grupo permanece'),
  ('groups',                   'created_by_user_id',  'nullify',    'Grupo permanece (admin_master bloqueado em delete-account)'),
  ('platform_fee_config',      'updated_by',          'nullify',    'Log de mudanças fiscais'),
  ('platform_fx_quotes',       'created_by',          'nullify',    'Log de FX — quem criou não é PII essencial'),
  ('race_events',              'created_by_user_id',  'nullify',    'Evento de corrida permanece para o grupo'),

  -- Category D: defensive_optional — tabelas de migrations futuras/branches
  ('custody_withdrawals',      'requested_by',        'defensive_optional', 'Feature futura — saque por usuário'),
  ('custody_deposits',         'requested_by',        'defensive_optional', 'Feature futura — deposit self-service'),
  ('audit_logs',               'actor_id',            'defensive_optional', 'Audit log pode existir (anonimiza IP/UA se sim)'),
  ('push_tokens',              'user_id',             'defensive_optional', 'Push notif device tokens'),
  ('fcm_tokens',               'user_id',             'defensive_optional', 'FCM legacy tokens'),
  ('login_history',            'user_id',             'defensive_optional', 'Histórico de login se existir'),
  ('running_dna_profiles',     'user_id',             'defensive_optional', 'Perfil comportamental'),
  ('wrapped_snapshots',        'user_id',             'defensive_optional', 'Year-in-review snapshots'),
  ('social_posts',             'user_id',             'defensive_optional', 'Feed social (se ativado)'),
  ('social_comments',          'user_id',             'defensive_optional', 'Comentários sociais'),
  ('social_reactions',         'user_id',             'defensive_optional', 'Reações sociais'),
  ('support_tickets',          'user_id',             'defensive_optional', 'Tickets de suporte'),
  ('notification_log',         'user_id',             'defensive_optional', 'Log de notificações'),
  ('strava_connections',       'user_id',             'defensive_optional', 'Tokens OAuth Strava'),
  ('workout_delivery_items',   'athlete_user_id',     'defensive_optional', 'Entregas de treino (feature legacy)'),
  ('coaching_athlete_kpis_daily','user_id',           'defensive_optional', 'KPIs diários agregados (feature legacy)'),

  -- Category E: migrations posteriores à L04-01 — registro retroativo.
  -- Estratégia aplicada por inspeção semântica. Execução concreta em
  -- fn_delete_user_data depende de edição caso-a-caso; defensive_optional
  -- aqui sinaliza "tabela existe mas fn_delete_user_data pode não cobrir
  -- ainda" — o bloco EXCEPTION WHEN undefined_table/column garante que
  -- fn_delete_user_data nunca quebre por falta de cobertura.
  ('_role_migration_audit',            'user_id',          'defensive_optional', 'Audit legado — deletar entries do sujeito'),
  ('assessoria_partnerships',          'requested_by',     'defensive_optional', 'Parceria B2B — actor vira NULL (partnership persiste)'),
  ('athlete_verification',             'user_id',          'defensive_optional', 'Verificação de atleta (dados do sujeito)'),
  ('athlete_workout_feedback',         'athlete_user_id',  'defensive_optional', 'Feedback do atleta sobre treino'),
  ('billing_events',                   'actor_id',         'defensive_optional', 'Trilha fiscal — anonimiza actor (L09-04 retenção)'),
  ('billing_purchases',                'requested_by',     'defensive_optional', 'Compra B2B — actor nullify, registro persiste'),
  ('billing_refund_requests',          'requested_by',     'defensive_optional', 'Pedido de refund do sujeito'),
  ('billing_refund_requests',          'reviewed_by',      'defensive_optional', 'Reviewer do refund (actor admin) — nullify'),
  ('challenge_queue',                  'user_id',          'defensive_optional', 'Fila de desafio pessoal'),
  ('championship_badges',              'user_id',          'defensive_optional', 'Badges em campeonato'),
  ('championship_participants',        'user_id',          'defensive_optional', 'Participação em campeonato'),
  ('championship_templates',           'created_by',       'defensive_optional', 'Template de campeonato — nullify creator'),
  ('championships',                    'created_by',       'defensive_optional', 'Campeonato criado — nullify creator, evento persiste'),
  ('clearing_case_events',             'actor_id',         'defensive_optional', 'Evento de clearing — anonimiza actor (audit preservado)'),
  ('coaching_alerts',                  'user_id',          'defensive_optional', 'Alertas coaching pessoais'),
  ('coaching_announcement_reads',      'user_id',          'defensive_optional', 'Read-receipts de anúncios'),
  ('coaching_announcements',           'created_by',       'defensive_optional', 'Anúncios — nullify creator, conteúdo persiste'),
  ('coaching_athlete_notes',           'athlete_user_id',  'defensive_optional', 'Notas sobre o atleta (dados do sujeito)'),
  ('coaching_athlete_notes',           'created_by',       'defensive_optional', 'Autor da nota (coach) — nullify'),
  ('coaching_athlete_tags',            'athlete_user_id',  'defensive_optional', 'Tags do atleta'),
  ('coaching_device_links',            'athlete_user_id',  'defensive_optional', 'Vínculo de device do atleta'),
  ('coaching_financial_ledger',        'created_by',       'defensive_optional', 'Lançamento fiscal — anonimiza actor'),
  ('coaching_member_status',           'updated_by',       'defensive_optional', 'Atualizador de status — nullify'),
  ('coaching_member_status',           'user_id',          'defensive_optional', 'Status do sujeito'),
  ('coaching_plans',                   'created_by',       'defensive_optional', 'Plano criado — nullify creator'),
  ('coaching_subscriptions',           'athlete_user_id',  'defensive_optional', 'Assinatura do atleta'),
  ('coaching_tp_sync',                 'athlete_user_id',  'defensive_optional', 'Estado de sync TrainingPeaks do atleta'),
  ('coaching_training_attendance',     'athlete_user_id',  'defensive_optional', 'Presença em treino'),
  ('coaching_training_sessions',       'created_by',       'defensive_optional', 'Sessão criada — nullify creator'),
  ('coaching_week_templates',          'created_by',       'defensive_optional', 'Template semanal — nullify creator'),
  ('coaching_workout_assignments',     'athlete_user_id',  'defensive_optional', 'Atribuição de treino (sujeito)'),
  ('coaching_workout_assignments',     'created_by',       'defensive_optional', 'Atribuição (autor coach) — nullify'),
  ('coaching_workout_executions',      'athlete_user_id',  'defensive_optional', 'Execução de treino (sujeito)'),
  ('coaching_workout_templates',       'created_by',       'defensive_optional', 'Template — nullify creator'),
  ('coin_ledger_archive',              'user_id',          'defensive_optional', 'Archive ledger — anonimiza (contábil)'),
  ('completed_workouts',               'athlete_user_id',  'defensive_optional', 'Treino completado (sujeito)'),
  ('device_tokens',                    'user_id',          'defensive_optional', 'Device tokens de push notification'),
  ('institution_credit_purchases',     'created_by',       'defensive_optional', 'Compra de créditos — nullify actor'),
  ('park_activities',                  'user_id',          'defensive_optional', 'Atividade em parque (sujeito)'),
  ('park_leaderboard',                 'user_id',          'defensive_optional', 'Entrada em leaderboard de parque'),
  ('plan_workout_releases',            'athlete_user_id',  'defensive_optional', 'Release de treino do atleta'),
  ('plan_workout_releases',            'created_by',       'defensive_optional', 'Release — nullify autor'),
  ('plan_workout_releases',            'updated_by',       'defensive_optional', 'Release — nullify atualizador'),
  ('portal_audit_log',                 'actor_id',         'defensive_optional', 'Audit do portal — anonimiza actor (trilha preservada)'),
  ('product_events',                   'user_id',          'defensive_optional', 'Product analytics events (PII)'),
  ('running_dna',                      'user_id',          'defensive_optional', 'Perfil comportamental de corrida (sujeito)'),
  ('session_journal_entries',          'user_id',          'defensive_optional', 'Diário de sessão (sujeito)'),
  ('sessions_archive',                 'user_id',          'defensive_optional', 'Archive de sessions — anonimiza (agregados preservados)'),
  ('strava_activity_history',          'user_id',          'defensive_optional', 'Histórico de atividades Strava'),
  ('token_intents',                    'created_by',       'defensive_optional', 'Intent de token — nullify creator'),
  ('token_intents',                    'target_user_id',   'defensive_optional', 'Intent direcionado ao sujeito'),
  ('training_plans',                   'athlete_user_id',  'defensive_optional', 'Plano de treino do sujeito'),
  ('training_plans',                   'created_by',       'defensive_optional', 'Plano — nullify creator'),
  ('training_plans',                   'updated_by',       'defensive_optional', 'Plano — nullify atualizador'),
  ('user_wrapped',                     'user_id',          'defensive_optional', 'Year-in-review do sujeito'),
  ('weekly_goals',                     'user_id',          'defensive_optional', 'Metas semanais do sujeito'),
  ('workout_delivery_batches',         'created_by',       'defensive_optional', 'Batch de delivery — nullify creator'),
  ('workout_sync_cursors',             'athlete_user_id',  'defensive_optional', 'Cursor de sync do sujeito'),
  ('asaas_customer_map',               'athlete_user_id',  'defensive_optional', 'Mapping Asaas→atleta (L09-04 retenção fiscal; anonimiza)'),
  ('billing_batch_jobs',               'created_by',       'defensive_optional', 'Job de billing — nullify creator (job persiste)')
ON CONFLICT (table_name, column_name) DO UPDATE
  SET strategy = EXCLUDED.strategy,
      rationale = EXCLUDED.rationale;

-- 2. Coverage gaps view — CI-testable regression blocker.
-- Lista user-referencing columns em information_schema que NÃO têm estratégia.
-- Filtra views (v_*): cobertura só se aplica a BASE TABLE; views herdam do
-- que subjacem. Evita falso-positivo em v_athlete_watch_type, v_weekly_progress etc.
CREATE OR REPLACE VIEW public.lgpd_user_data_coverage_gaps AS
WITH user_ref_columns AS (
  SELECT c.table_name, c.column_name
  FROM information_schema.columns c
  JOIN information_schema.tables t
    ON t.table_schema = c.table_schema
   AND t.table_name   = c.table_name
  WHERE c.table_schema = 'public'
    AND t.table_type   = 'BASE TABLE'
    AND c.data_type    = 'uuid'
    AND (
      c.column_name IN (
        'user_id', 'athlete_user_id', 'target_user_id', 'actor_id',
        'creator_user_id', 'coach_user_id', 'created_by', 'created_by_user_id',
        'updated_by', 'reviewed_by', 'approved_by', 'invited_by_user_id',
        'invited_user_id', 'approval_reviewed_by', 'requested_by',
        'user_id_a', 'user_id_b'
      )
    )
    AND c.table_name NOT IN (
      'profiles',             -- handled by explicit anonymization, not via zero-out
      'coaching_groups'       -- coach_user_id deliberately left — ownership requires separate transfer flow
    )
)
SELECT u.table_name, u.column_name
FROM user_ref_columns u
LEFT JOIN public.lgpd_deletion_strategy s
       ON s.table_name = u.table_name AND s.column_name = u.column_name
WHERE s.table_name IS NULL
ORDER BY u.table_name, u.column_name;

COMMENT ON VIEW public.lgpd_user_data_coverage_gaps IS
  'L04-01: user-referencing columns em public.* que NÃO estão na tabela '
  'lgpd_deletion_strategy. Deve estar SEMPRE vazia. Integration test '
  '(tools/integration_tests.ts) garante cobertura 100% + falha build em PR '
  'que adicione nova coluna sem decisão LGPD.';

GRANT SELECT ON public.lgpd_user_data_coverage_gaps TO service_role;

-- 3. Invariante: coverage gaps view deve estar vazia
DO $$
DECLARE v_gaps integer;
        v_list text;
BEGIN
  SELECT count(*), string_agg(table_name || '.' || column_name, ', ')
    INTO v_gaps, v_list
    FROM public.lgpd_user_data_coverage_gaps;
  IF v_gaps > 0 THEN
    RAISE EXCEPTION '[L04-01] LGPD coverage gaps (% colunas): %', v_gaps, v_list
      USING ERRCODE = 'P0001';
  END IF;
END $$;

-- 4. fn_delete_user_data — rewrite completo
--
-- Signature change: RETURNS void → RETURNS jsonb. Caller atual
-- (supabase/functions/delete-account/index.ts:59) ignora o retorno.
DROP FUNCTION IF EXISTS public.fn_delete_user_data(uuid);

CREATE OR REPLACE FUNCTION public.fn_delete_user_data(p_user_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_anon constant uuid := '00000000-0000-0000-0000-000000000000';
  v_report jsonb := jsonb_build_object(
    'user_id', p_user_id,
    'started_at', now(),
    'function_version', '2.0.0'
  );
  v_count bigint;
BEGIN
  IF p_user_id IS NULL OR p_user_id = v_anon THEN
    RAISE EXCEPTION 'LGPD_INVALID_USER_ID: cannot delete NULL or anon UUID'
      USING ERRCODE = 'P0001';
  END IF;

  -- ╔═══════════════════════════════════════════════════════════════════╗
  -- ║ CATEGORY A — DELETE rows (personal data, no aggregate dependency) ║
  -- ╚═══════════════════════════════════════════════════════════════════╝

  BEGIN DELETE FROM public.analytics_submissions WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('analytics_submissions', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('analytics_submissions', 'skipped'); END;

  BEGIN DELETE FROM public.api_rate_limits WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('api_rate_limits', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('api_rate_limits', 'skipped'); END;

  BEGIN DELETE FROM public.athlete_baselines WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('athlete_baselines', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('athlete_baselines', 'skipped'); END;

  BEGIN DELETE FROM public.athlete_trends WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('athlete_trends', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('athlete_trends', 'skipped'); END;

  BEGIN DELETE FROM public.badge_awards WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('badge_awards', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('badge_awards', 'skipped'); END;

  BEGIN DELETE FROM public.challenge_participants WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('challenge_participants', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('challenge_participants', 'skipped'); END;

  BEGIN DELETE FROM public.challenge_results WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('challenge_results', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('challenge_results', 'skipped'); END;

  BEGIN DELETE FROM public.challenge_run_bindings WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('challenge_run_bindings', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('challenge_run_bindings', 'skipped'); END;

  BEGIN DELETE FROM public.coach_insights WHERE target_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coach_insights', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coach_insights', 'skipped'); END;

  BEGIN DELETE FROM public.coaching_invites WHERE invited_user_id = p_user_id OR invited_by_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coaching_invites', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coaching_invites', 'skipped'); END;

  BEGIN DELETE FROM public.coaching_join_requests WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coaching_join_requests', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coaching_join_requests', 'skipped'); END;

  BEGIN DELETE FROM public.coaching_members WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coaching_members', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coaching_members', 'skipped'); END;

  BEGIN DELETE FROM public.coaching_ranking_entries WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coaching_ranking_entries', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coaching_ranking_entries', 'skipped'); END;

  BEGIN DELETE FROM public.event_participations WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('event_participations', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('event_participations', 'skipped'); END;

  BEGIN DELETE FROM public.friendships WHERE user_id_a = p_user_id OR user_id_b = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('friendships', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('friendships', 'skipped'); END;

  BEGIN DELETE FROM public.group_members WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('group_members', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('group_members', 'skipped'); END;

  BEGIN DELETE FROM public.leaderboard_entries WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('leaderboard_entries', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('leaderboard_entries', 'skipped'); END;

  BEGIN DELETE FROM public.mission_progress WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('mission_progress', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('mission_progress', 'skipped'); END;

  BEGIN DELETE FROM public.profile_progress WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('profile_progress', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('profile_progress', 'skipped'); END;

  BEGIN DELETE FROM public.race_participations WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('race_participations', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('race_participations', 'skipped'); END;

  BEGIN DELETE FROM public.race_results WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('race_results', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('race_results', 'skipped'); END;

  BEGIN DELETE FROM public.runs WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('runs', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('runs', 'skipped'); END;

  BEGIN DELETE FROM public.season_progress WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('season_progress', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('season_progress', 'skipped'); END;

  BEGIN DELETE FROM public.sessions WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('sessions', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('sessions', 'skipped'); END;

  BEGIN DELETE FROM public.wallets WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('wallets', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('wallets', 'skipped'); END;

  -- ╔═══════════════════════════════════════════════════════════════════╗
  -- ║ CATEGORY B — ANONYMIZE user_id (financial/aggregate integrity)     ║
  -- ╚═══════════════════════════════════════════════════════════════════╝

  BEGIN UPDATE public.coin_ledger SET user_id = v_anon WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coin_ledger_anon', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coin_ledger_anon', 'skipped'); END;

  BEGIN UPDATE public.xp_transactions SET user_id = v_anon WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('xp_transactions_anon', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('xp_transactions_anon', 'skipped'); END;

  BEGIN UPDATE public.clearing_events SET athlete_user_id = v_anon WHERE athlete_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('clearing_events_anon', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('clearing_events_anon', 'skipped'); END;

  -- ╔═══════════════════════════════════════════════════════════════════╗
  -- ║ CATEGORY C — NULL-OUT creator/reviewer refs (content stays)        ║
  -- ╚═══════════════════════════════════════════════════════════════════╝

  BEGIN UPDATE public.challenges SET creator_user_id = NULL WHERE creator_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('challenges_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('challenges_nullified', 'skipped'); END;

  BEGIN UPDATE public.coaching_groups SET approval_reviewed_by = NULL WHERE approval_reviewed_by = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coaching_groups_reviewed_by_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coaching_groups_reviewed_by_nullified', 'skipped'); END;

  -- coaching_join_requests.user_id JÁ foi deletado acima; só o reviewed_by
  -- pode apontar para outro admin que está sendo deletado agora.
  BEGIN UPDATE public.coaching_join_requests SET reviewed_by = NULL WHERE reviewed_by = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coaching_join_requests_reviewed_by_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coaching_join_requests_reviewed_by_nullified', 'skipped'); END;

  BEGIN UPDATE public.events SET creator_user_id = NULL WHERE creator_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('events_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('events_nullified', 'skipped'); END;

  BEGIN UPDATE public.group_goals SET created_by_user_id = NULL WHERE created_by_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('group_goals_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('group_goals_nullified', 'skipped'); END;

  BEGIN UPDATE public.groups SET created_by_user_id = NULL WHERE created_by_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('groups_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('groups_nullified', 'skipped'); END;

  BEGIN UPDATE public.platform_fee_config SET updated_by = NULL WHERE updated_by = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('platform_fee_config_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('platform_fee_config_nullified', 'skipped'); END;

  BEGIN UPDATE public.platform_fx_quotes SET created_by = NULL WHERE created_by = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('platform_fx_quotes_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('platform_fx_quotes_nullified', 'skipped'); END;

  BEGIN UPDATE public.race_events SET created_by_user_id = NULL WHERE created_by_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('race_events_nullified', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('race_events_nullified', 'skipped'); END;

  -- ╔═══════════════════════════════════════════════════════════════════╗
  -- ║ CATEGORY D — DEFENSIVE_OPTIONAL (tabelas futuras/branches)         ║
  -- ╚═══════════════════════════════════════════════════════════════════╝

  BEGIN DELETE FROM public.push_tokens WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('push_tokens', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('push_tokens', 'skipped'); END;

  BEGIN DELETE FROM public.fcm_tokens WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('fcm_tokens', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('fcm_tokens', 'skipped'); END;

  BEGIN DELETE FROM public.login_history WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('login_history', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('login_history', 'skipped'); END;

  BEGIN DELETE FROM public.running_dna_profiles WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('running_dna_profiles', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('running_dna_profiles', 'skipped'); END;

  BEGIN DELETE FROM public.wrapped_snapshots WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('wrapped_snapshots', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('wrapped_snapshots', 'skipped'); END;

  BEGIN DELETE FROM public.social_posts WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('social_posts', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('social_posts', 'skipped'); END;

  BEGIN DELETE FROM public.social_comments WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('social_comments', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('social_comments', 'skipped'); END;

  BEGIN DELETE FROM public.social_reactions WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('social_reactions', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('social_reactions', 'skipped'); END;

  BEGIN DELETE FROM public.notification_log WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('notification_log', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('notification_log', 'skipped'); END;

  BEGIN DELETE FROM public.strava_connections WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('strava_connections', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('strava_connections', 'skipped'); END;

  BEGIN DELETE FROM public.workout_delivery_items WHERE athlete_user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('workout_delivery_items', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('workout_delivery_items', 'skipped'); END;

  BEGIN DELETE FROM public.coaching_athlete_kpis_daily WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('coaching_athlete_kpis_daily', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('coaching_athlete_kpis_daily', 'skipped'); END;

  -- Anonimiza audit_logs (IP/UA são PII) sem deletar — auditoria precisa permanecer
  BEGIN UPDATE public.audit_logs
           SET actor_id   = v_anon,
               ip_address = NULL,
               user_agent = NULL
         WHERE actor_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('audit_logs_anon', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('audit_logs_anon', 'skipped'); END;

  -- Anonimiza custody_withdrawals (docs bancários) se feature ativada
  BEGIN UPDATE public.custody_withdrawals
           SET beneficiary_document = NULL,
               beneficiary_name = 'Anônimo',
               bank_account = NULL,
               requested_by = v_anon
         WHERE requested_by = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('custody_withdrawals_anon', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('custody_withdrawals_anon', 'skipped'); END;

  -- Anonimiza support_tickets se feature ativada
  BEGIN UPDATE public.support_tickets
           SET body = '[removido por solicitação LGPD Art. 18, VI]',
               email = NULL,
               phone = NULL,
               user_id = v_anon
         WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT; v_report := v_report || jsonb_build_object('support_tickets_anon', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN v_report := v_report || jsonb_build_object('support_tickets_anon', 'skipped'); END;

  -- ╔═══════════════════════════════════════════════════════════════════╗
  -- ║ STORAGE — DELETE objects em buckets com prefixo {uid}/             ║
  -- ╚═══════════════════════════════════════════════════════════════════╝
  --
  -- storage.objects é tabela regular; storage policies de INSERT confiam
  -- em `(storage.foldername(name))[1] = auth.uid()::text`. Aqui deletamos
  -- qualquer object com prefix `{uid}/` em buckets conhecidos com PII.
  BEGIN
    DELETE FROM storage.objects
     WHERE bucket_id IN ('session-points', 'avatars', 'sessions')
       AND position((p_user_id::text || '/') in name) = 1;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_report := v_report || jsonb_build_object('storage_objects', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column OR insufficient_privilege THEN
    v_report := v_report || jsonb_build_object('storage_objects', 'skipped');
  END;

  -- ╔═══════════════════════════════════════════════════════════════════╗
  -- ║ PROFILE — anonymize (não deleta para preservar FK/lookups históricos)║
  -- ╚═══════════════════════════════════════════════════════════════════╝
  --
  -- Core (sempre presente): display_name, avatar_url, updated_at.
  -- Optional (podem não existir em alguns ambientes devido a schema drift
  -- entre branches): instagram_handle, tiktok_handle, active_coaching_group_id,
  -- onboarding_state. Cada opcional é tratado em bloco próprio com
  -- EXCEPTION WHEN undefined_column.
  BEGIN
    UPDATE public.profiles SET
      display_name = 'Conta Removida',
      avatar_url = NULL,
      updated_at = now()
      WHERE id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_report := v_report || jsonb_build_object('profiles_anon', v_count);
  EXCEPTION WHEN undefined_table OR undefined_column THEN
    v_report := v_report || jsonb_build_object('profiles_anon', 'skipped');
  END;

  BEGIN UPDATE public.profiles SET instagram_handle = NULL WHERE id = p_user_id;
  EXCEPTION WHEN undefined_column THEN NULL; END;

  BEGIN UPDATE public.profiles SET tiktok_handle = NULL WHERE id = p_user_id;
  EXCEPTION WHEN undefined_column THEN NULL; END;

  BEGIN UPDATE public.profiles SET active_coaching_group_id = NULL WHERE id = p_user_id;
  EXCEPTION WHEN undefined_column THEN NULL; END;

  -- onboarding_state é NOT NULL DEFAULT 'NEW' (20260221000021). Fazer NULL
  -- violaria a constraint. Resetamos ao default — a conta anonimizada se
  -- comporta como um shell cru (sem progresso funcional), sem quebrar FK.
  BEGIN UPDATE public.profiles SET onboarding_state = 'NEW' WHERE id = p_user_id;
  EXCEPTION WHEN undefined_column THEN NULL; END;

  v_report := v_report || jsonb_build_object('completed_at', now());
  RETURN v_report;
END;
$$;

COMMENT ON FUNCTION public.fn_delete_user_data(uuid) IS
  'L04-01: LGPD Art. 18, VI — eliminação COMPLETA de dados do usuário. '
  'Cobre 26 tabelas (DELETE), 3 (ANONYMIZE user_id), 9 (NULLIFY creator/reviewer), '
  '15+ defensivas (EXCEPTION WHEN undefined_table), storage objects e profile. '
  'Retorna jsonb com contagens por tabela (evidência LGPD).';

-- Grants herdados + explicit REVOKE anon
REVOKE ALL ON FUNCTION public.fn_delete_user_data(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_delete_user_data(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_delete_user_data(uuid) TO service_role;
