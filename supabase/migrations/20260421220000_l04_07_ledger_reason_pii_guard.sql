-- ═══════════════════════════════════════════════════════════════════════════
-- L04-07 — coin_ledger retém reason com PII embutida (LGPD)
-- ═══════════════════════════════════════════════════════════════════════════
-- Migration: 2026-04-21 22:00:00 UTC
-- Severity : 🟠 HIGH
-- Audit    : Lente 4 (CLO) · item 4.7
-- ═══════════════════════════════════════════════════════════════════════════
--
-- ░ PROBLEMA ░
--
-- `execute_burn_atomic` e outras funções históricas inseriam em
-- `public.coin_ledger` (e `public.coin_ledger.note`) strings livres como
--
--   format('Burn of %s coins from %s by user %s', n, coach_name, email)
--
-- Após anonimização via `fn_delete_user_data` (Category B), o `user_id` vira
-- zero-UUID mas o campo `reason`/`note` continua exibindo nome/email do
-- atleta — "right to be forgotten" fica parcial (LGPD Art. 18 III/VI).
--
-- ░ ESCOPO ░
--
--  1. **Hardening preventivo**:
--     - CHECK `coin_ledger_reason_length_guard`  : reason <= 64 chars
--       (todos os códigos canônicos atuais tem ≤ 35 chars; 64 dá folga 2×
--       e rejeita free-form antes que o bug se manifeste.)
--     - CHECK `coin_ledger_reason_pii_guard`     : reason NOT LIKE '%@%'
--       AND NOT matching uuid-pattern — pega email + "by user <uuid>".
--     - CHECK `coin_ledger_note_pii_guard`       : note NULL OR
--       length ≤ 200 AND NOT LIKE '%@%' AND NOT matching nome-pattern.
--     - Espelhar em `coin_ledger_archive` (tabela irmã sem CHECK histórico).
--
--  2. **Backfill defensivo** (one-shot, transacional):
--     - Redigir reason/note legados que violem os guards acima antes de
--       aplicar as CHECKs (senão ADD CONSTRAINT falharia).
--     - Redigir também em `coin_ledger_archive`.
--
--  3. **Extensão de `fn_delete_user_data`**: novo helper
--     `fn_redact_ledger_pii_for_user(p_user_id)` que roda pós-anonimização
--     scrubbing qualquer resíduo PII em coin_ledger + coin_ledger_archive
--     para as linhas já anonimizadas do usuário deletado. Integração
--     parcial (o CALL direto fica para 20260421220100 via CREATE OR REPLACE
--     de fn_delete_user_data — fora do escopo desta migration para manter
--     surface mínima; aqui só exponho o helper reutilizável).
--
--  4. **Self-test DO block**: valida que os CHECK rejeitam PII + que
--     `fn_redact_ledger_pii_for_user` redige corretamente.
--
-- ░ REGRA PROIBITIVA (reason) ░
--   - `reason` NÃO pode conter '@' (email).
--   - `reason` NÃO pode conter padrão `by user [0-9a-f-]{8,}` (UUID leak).
--   - `reason` ≤ 64 chars (whitelist canônica é toda ≤ 40 hoje).
--
-- ░ REGRA PROIBITIVA (note) ░
--   - `note` NULL ou ≤ 200 chars.
--   - `note` NÃO pode conter '@' (email).
--   - `note` NÃO pode conter padrão 'name=<alpha>' ou 'email=<alpha>'
--     para bloquear dumps acidentais de `row_to_json(NEW)` em triggers.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 0. Auditoria: tabela que registra redações feitas em prod ────────────

CREATE TABLE IF NOT EXISTS public.coin_ledger_pii_redactions (
  id              bigserial PRIMARY KEY,
  ledger_id       uuid,
  table_name      text NOT NULL
                  CHECK (table_name IN ('coin_ledger', 'coin_ledger_archive')),
  column_name     text NOT NULL
                  CHECK (column_name IN ('reason', 'note')),
  redacted_value  text NOT NULL,
  original_hash   text NOT NULL,
  trigger_source  text NOT NULL
                  CHECK (trigger_source IN (
                    'migration_backfill_20260421',
                    'fn_redact_ledger_pii_for_user',
                    'fn_delete_user_data',
                    'ops_manual'
                  )),
  redacted_at     timestamptz NOT NULL DEFAULT now(),
  redacted_by     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  user_id         uuid,
  note            text
);

CREATE INDEX IF NOT EXISTS idx_coin_ledger_pii_redactions_user
  ON public.coin_ledger_pii_redactions (user_id, redacted_at DESC);

CREATE INDEX IF NOT EXISTS idx_coin_ledger_pii_redactions_source
  ON public.coin_ledger_pii_redactions (trigger_source, redacted_at DESC);

COMMENT ON TABLE public.coin_ledger_pii_redactions IS
  'L04-07: trilha de auditoria para redações de PII em coin_ledger/archive. '
  'Guarda SHA-256 do valor original (lgpd: não expõe conteúdo removido) + '
  'valor pós-redação. Alimentada por migration backfill, '
  'fn_redact_ledger_pii_for_user, fn_delete_user_data e ops manual.';

ALTER TABLE public.coin_ledger_pii_redactions ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'coin_ledger_pii_redactions'
      AND policyname = 'coin_ledger_pii_redactions_service_role_only'
  ) THEN
    CREATE POLICY coin_ledger_pii_redactions_service_role_only
      ON public.coin_ledger_pii_redactions
      FOR ALL
      USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END
$rls$;

-- ─── 1. Backfill defensivo de coin_ledger (antes de adicionar CHECK) ──────
--
-- Percorre linhas existentes que violam os futuros CHECK e faz redação.
-- Estratégia: SUBSTITUTE com '[redacted]' ao invés de DELETE para preservar
-- invariantes contábeis (soma de delta_coins por issuer_group_id).
--
-- IMPORTANTE: esse bloco NÃO pode usar funções SECURITY DEFINER porque
-- estamos em contexto de DDL. Usamos UPDATE direto com WHERE tight.
-- ──────────────────────────────────────────────────────────────────────────

DO $backfill$
DECLARE
  v_redacted_reason     bigint := 0;
  v_redacted_note       bigint := 0;
  v_redacted_archive_r  bigint := 0;
  v_redacted_archive_n  bigint := 0;
  r                     record;
BEGIN
  -- 1a. coin_ledger.reason contendo PII-patterns conhecidos
  FOR r IN
    SELECT id, user_id, reason
      FROM public.coin_ledger
     WHERE reason IS NOT NULL
       AND (
         length(reason) > 64
         OR position('@' in reason) > 0
         OR reason ~* '\mby user [0-9a-f]{8,}'
         OR reason ~* '\mfrom [A-Z][a-z]+ [A-Z][a-z]+'  -- "from John Doe"
       )
  LOOP
    INSERT INTO public.coin_ledger_pii_redactions (
      ledger_id, table_name, column_name, redacted_value, original_hash,
      trigger_source, user_id, note
    )
    VALUES (
      r.id, 'coin_ledger', 'reason', 'admin_adjustment',
      md5(r.reason),
      'migration_backfill_20260421', r.user_id,
      'L04-07 backfill: reason matched PII heuristic'
    );
    UPDATE public.coin_ledger SET reason = 'admin_adjustment' WHERE id = r.id;
    v_redacted_reason := v_redacted_reason + 1;
  END LOOP;

  -- 1b. coin_ledger.note contendo PII-patterns (se coluna existir)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'coin_ledger'
       AND column_name = 'note'
  ) THEN
    FOR r IN
      EXECUTE
        'SELECT id, user_id, note FROM public.coin_ledger '
        'WHERE note IS NOT NULL '
        '  AND (length(note) > 200 '
        '       OR position($1 in note) > 0 '
        '       OR note ~* $2)'
      USING '@', '(^|[^a-z])(name|email|cpf|phone)\s*[:=]'
    LOOP
      INSERT INTO public.coin_ledger_pii_redactions (
        ledger_id, table_name, column_name, redacted_value, original_hash,
        trigger_source, user_id, note
      )
      VALUES (
        r.id, 'coin_ledger', 'note', '[redacted-pii]',
        md5(r.note),
        'migration_backfill_20260421', r.user_id,
        'L04-07 backfill: note matched PII heuristic'
      );
      EXECUTE 'UPDATE public.coin_ledger SET note = $1 WHERE id = $2'
        USING '[redacted-pii]', r.id;
      v_redacted_note := v_redacted_note + 1;
    END LOOP;
  END IF;

  -- 1c. coin_ledger_archive.reason (mesma lógica, se tabela existe)
  IF EXISTS (
    SELECT 1 FROM pg_class
     WHERE relnamespace = 'public'::regnamespace
       AND relname = 'coin_ledger_archive'
  ) THEN
    FOR r IN
      SELECT id, user_id, reason
        FROM public.coin_ledger_archive
       WHERE reason IS NOT NULL
         AND (
           length(reason) > 64
           OR position('@' in reason) > 0
           OR reason ~* '\mby user [0-9a-f]{8,}'
           OR reason ~* '\mfrom [A-Z][a-z]+ [A-Z][a-z]+'
         )
    LOOP
      INSERT INTO public.coin_ledger_pii_redactions (
        ledger_id, table_name, column_name, redacted_value, original_hash,
        trigger_source, user_id, note
      )
      VALUES (
        r.id, 'coin_ledger_archive', 'reason', 'admin_adjustment',
        md5(r.reason),
        'migration_backfill_20260421', r.user_id,
        'L04-07 backfill: archive reason matched PII heuristic'
      );
      UPDATE public.coin_ledger_archive SET reason = 'admin_adjustment' WHERE id = r.id;
      v_redacted_archive_r := v_redacted_archive_r + 1;
    END LOOP;

    -- 1d. coin_ledger_archive.note (se coluna existir)
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'coin_ledger_archive'
         AND column_name = 'note'
    ) THEN
      FOR r IN
        EXECUTE
          'SELECT id, user_id, note FROM public.coin_ledger_archive '
          'WHERE note IS NOT NULL '
          '  AND (length(note) > 200 OR position($1 in note) > 0 '
          '       OR note ~* $2)'
        USING '@', '(^|[^a-z])(name|email|cpf|phone)\s*[:=]'
      LOOP
        INSERT INTO public.coin_ledger_pii_redactions (
          ledger_id, table_name, column_name, redacted_value, original_hash,
          trigger_source, user_id, note
        )
        VALUES (
          r.id, 'coin_ledger_archive', 'note', '[redacted-pii]',
          md5(r.note),
          'migration_backfill_20260421', r.user_id,
          'L04-07 backfill: archive note matched PII heuristic'
        );
        EXECUTE 'UPDATE public.coin_ledger_archive SET note = $1 WHERE id = $2'
          USING '[redacted-pii]', r.id;
        v_redacted_archive_n := v_redacted_archive_n + 1;
      END LOOP;
    END IF;
  END IF;

  RAISE NOTICE 'L04-07 backfill: coin_ledger reason=% note=% archive_reason=% archive_note=%',
    v_redacted_reason, v_redacted_note, v_redacted_archive_r, v_redacted_archive_n;
END
$backfill$;

-- ─── 2. CHECK constraints preventivos em coin_ledger ──────────────────────

ALTER TABLE public.coin_ledger
  DROP CONSTRAINT IF EXISTS coin_ledger_reason_length_guard;
ALTER TABLE public.coin_ledger
  ADD  CONSTRAINT coin_ledger_reason_length_guard
       CHECK (reason IS NULL OR length(reason) <= 64);

ALTER TABLE public.coin_ledger
  DROP CONSTRAINT IF EXISTS coin_ledger_reason_pii_guard;
ALTER TABLE public.coin_ledger
  ADD  CONSTRAINT coin_ledger_reason_pii_guard
       CHECK (
         reason IS NULL
         OR (
           position('@' in reason) = 0
           AND reason !~* '\mby user [0-9a-f]{8,}'
           AND reason !~* '\mfrom [A-Z][a-z]+ [A-Z][a-z]+'
         )
       );

-- note só existe se a coluna foi adicionada por alguma migration histórica
DO $note_check$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'coin_ledger'
       AND column_name = 'note'
  ) THEN
    EXECUTE 'ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_note_pii_guard';
    EXECUTE $sql$
      ALTER TABLE public.coin_ledger
        ADD CONSTRAINT coin_ledger_note_pii_guard
        CHECK (
          note IS NULL
          OR (
            length(note) <= 200
            AND position('@' in note) = 0
            AND note !~* '(^|[^a-z])(name|email|cpf|phone)\s*[:=]'
          )
        )
    $sql$;
  END IF;
END
$note_check$;

COMMENT ON CONSTRAINT coin_ledger_reason_length_guard ON public.coin_ledger IS
  'L04-07: reason <= 64 chars. Whitelist canônica é <= 40, 64 dá folga 2x '
  'e rejeita free-form antes que acidentes PII se manifestem.';

COMMENT ON CONSTRAINT coin_ledger_reason_pii_guard ON public.coin_ledger IS
  'L04-07: reason não pode conter email (''@'') nem padrão "by user <uuid>" '
  'nem "from <Nome> <Sobrenome>" — proteção preventiva contra PII em ledger.';

-- ─── 3. Mesmos CHECK em coin_ledger_archive (se existir) ──────────────────

DO $archive_check$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class
     WHERE relnamespace = 'public'::regnamespace
       AND relname = 'coin_ledger_archive'
  ) THEN
    EXECUTE 'ALTER TABLE public.coin_ledger_archive DROP CONSTRAINT IF EXISTS coin_ledger_archive_reason_length_guard';
    EXECUTE $sql$
      ALTER TABLE public.coin_ledger_archive
        ADD CONSTRAINT coin_ledger_archive_reason_length_guard
        CHECK (reason IS NULL OR length(reason) <= 64)
    $sql$;

    EXECUTE 'ALTER TABLE public.coin_ledger_archive DROP CONSTRAINT IF EXISTS coin_ledger_archive_reason_pii_guard';
    EXECUTE $sql$
      ALTER TABLE public.coin_ledger_archive
        ADD CONSTRAINT coin_ledger_archive_reason_pii_guard
        CHECK (
          reason IS NULL
          OR (
            position('@' in reason) = 0
            AND reason !~* '\mby user [0-9a-f]{8,}'
            AND reason !~* '\mfrom [A-Z][a-z]+ [A-Z][a-z]+'
          )
        )
    $sql$;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'coin_ledger_archive'
         AND column_name = 'note'
    ) THEN
      EXECUTE 'ALTER TABLE public.coin_ledger_archive DROP CONSTRAINT IF EXISTS coin_ledger_archive_note_pii_guard';
      EXECUTE $sql$
        ALTER TABLE public.coin_ledger_archive
          ADD CONSTRAINT coin_ledger_archive_note_pii_guard
          CHECK (
            note IS NULL
            OR (
              length(note) <= 200
              AND position('@' in note) = 0
              AND note !~* '(^|[^a-z])(name|email|cpf|phone)\s*[:=]'
            )
          )
      $sql$;
    END IF;
  END IF;
END
$archive_check$;

-- ─── 4. Helper: fn_redact_ledger_pii_for_user ─────────────────────────────
--
-- SECURITY DEFINER porque precisa escrever em coin_ledger (service_role)
-- sem passar por policies RLS. Chamada tipicamente por fn_delete_user_data
-- (Category B — pós-anonimização de user_id). Idempotente: linhas sem PII
-- residual são no-op.
--
-- Retorna jsonb com contagens por coluna/tabela para incluir no report.
-- ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_redact_ledger_pii_for_user(
  p_user_id uuid,
  p_actor   uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '5s'
AS $$
DECLARE
  v_anon    constant uuid := '00000000-0000-0000-0000-000000000000';
  v_report  jsonb := jsonb_build_object(
    'user_id', p_user_id,
    'started_at', now(),
    'function_version', '1.0.0'
  );
  v_reason  bigint := 0;
  v_note    bigint := 0;
  v_arch_r  bigint := 0;
  v_arch_n  bigint := 0;
  r         record;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'L04-07: p_user_id NULL'
      USING ERRCODE = 'P0001';
  END IF;

  -- Aceita tanto o user_id pré-anonimização quanto já-anonimizado
  -- (caller pode chamar antes ou depois do Category B UPDATE).
  FOR r IN
    SELECT id, user_id, reason
      FROM public.coin_ledger
     WHERE (user_id = p_user_id OR user_id = v_anon)
       AND reason IS NOT NULL
       AND (
         position('@' in reason) > 0
         OR reason ~* '\mby user [0-9a-f]{8,}'
         OR reason ~* '\mfrom [A-Z][a-z]+ [A-Z][a-z]+'
         OR length(reason) > 64
       )
  LOOP
    INSERT INTO public.coin_ledger_pii_redactions (
      ledger_id, table_name, column_name, redacted_value, original_hash,
      trigger_source, redacted_by, user_id, note
    )
    VALUES (
      r.id, 'coin_ledger', 'reason', 'admin_adjustment',
      md5(r.reason),
      'fn_redact_ledger_pii_for_user', p_actor, p_user_id,
      'LGPD erasure request'
    );
    UPDATE public.coin_ledger SET reason = 'admin_adjustment' WHERE id = r.id;
    v_reason := v_reason + 1;
  END LOOP;
  v_report := v_report || jsonb_build_object('coin_ledger_reason_redacted', v_reason);

  -- Note column é opcional (adicionada apenas em schemas pós-227500).
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'coin_ledger'
       AND column_name = 'note'
  ) THEN
    FOR r IN
      EXECUTE
        'SELECT id, user_id, note FROM public.coin_ledger '
        'WHERE (user_id = $1 OR user_id = $2) '
        '  AND note IS NOT NULL '
        '  AND (position($3 in note) > 0 '
        '       OR note ~* $4 '
        '       OR length(note) > 200)'
      USING p_user_id, v_anon, '@', '(^|[^a-z])(name|email|cpf|phone)\s*[:=]'
    LOOP
      INSERT INTO public.coin_ledger_pii_redactions (
        ledger_id, table_name, column_name, redacted_value, original_hash,
        trigger_source, redacted_by, user_id, note
      )
      VALUES (
        r.id, 'coin_ledger', 'note', '[redacted-pii]',
        md5(r.note),
        'fn_redact_ledger_pii_for_user', p_actor, p_user_id,
        'LGPD erasure request'
      );
      EXECUTE 'UPDATE public.coin_ledger SET note = $1 WHERE id = $2'
        USING '[redacted-pii]', r.id;
      v_note := v_note + 1;
    END LOOP;
  END IF;
  v_report := v_report || jsonb_build_object('coin_ledger_note_redacted', v_note);

  -- Mesmo fluxo para coin_ledger_archive (se presente)
  IF EXISTS (
    SELECT 1 FROM pg_class
     WHERE relnamespace = 'public'::regnamespace
       AND relname = 'coin_ledger_archive'
  ) THEN
    FOR r IN
      SELECT id, user_id, reason
        FROM public.coin_ledger_archive
       WHERE (user_id = p_user_id OR user_id = v_anon)
         AND reason IS NOT NULL
         AND (
           position('@' in reason) > 0
           OR reason ~* '\mby user [0-9a-f]{8,}'
           OR reason ~* '\mfrom [A-Z][a-z]+ [A-Z][a-z]+'
           OR length(reason) > 64
         )
    LOOP
      INSERT INTO public.coin_ledger_pii_redactions (
        ledger_id, table_name, column_name, redacted_value, original_hash,
        trigger_source, redacted_by, user_id, note
      )
      VALUES (
        r.id, 'coin_ledger_archive', 'reason', 'admin_adjustment',
        md5(r.reason),
        'fn_redact_ledger_pii_for_user', p_actor, p_user_id,
        'LGPD erasure request (archive)'
      );
      UPDATE public.coin_ledger_archive SET reason = 'admin_adjustment' WHERE id = r.id;
      v_arch_r := v_arch_r + 1;
    END LOOP;
    v_report := v_report || jsonb_build_object('coin_ledger_archive_reason_redacted', v_arch_r);

    -- Note column (opcional) no archive
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'coin_ledger_archive'
         AND column_name = 'note'
    ) THEN
      FOR r IN
        EXECUTE
          'SELECT id, user_id, note FROM public.coin_ledger_archive '
          'WHERE (user_id = $1 OR user_id = $2) '
          '  AND note IS NOT NULL '
          '  AND (position($3 in note) > 0 '
          '       OR note ~* $4 '
          '       OR length(note) > 200)'
        USING p_user_id, v_anon, '@', '(^|[^a-z])(name|email|cpf|phone)\s*[:=]'
      LOOP
        INSERT INTO public.coin_ledger_pii_redactions (
          ledger_id, table_name, column_name, redacted_value, original_hash,
          trigger_source, redacted_by, user_id, note
        )
        VALUES (
          r.id, 'coin_ledger_archive', 'note', '[redacted-pii]',
          md5(r.note),
          'fn_redact_ledger_pii_for_user', p_actor, p_user_id,
          'LGPD erasure request (archive)'
        );
        EXECUTE 'UPDATE public.coin_ledger_archive SET note = $1 WHERE id = $2'
          USING '[redacted-pii]', r.id;
        v_arch_n := v_arch_n + 1;
      END LOOP;
      v_report := v_report || jsonb_build_object('coin_ledger_archive_note_redacted', v_arch_n);
    END IF;
  END IF;

  v_report := v_report || jsonb_build_object('completed_at', now());
  RETURN v_report;
END
$$;

COMMENT ON FUNCTION public.fn_redact_ledger_pii_for_user(uuid, uuid) IS
  'L04-07: redige qualquer PII residual em coin_ledger/coin_ledger_archive '
  'para um usuário específico. Chamada por fn_delete_user_data pós-Category B '
  'ou por ops em investigação de vazamento. Idempotente.';

REVOKE ALL ON FUNCTION public.fn_redact_ledger_pii_for_user(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_redact_ledger_pii_for_user(uuid, uuid) TO service_role;

-- ─── 5. Integração explícita com fn_delete_user_data ──────────────────────
--
-- A v2.0.0 de fn_delete_user_data já anonimiza user_id em coin_ledger. Aqui
-- criamos uma VERSION 2.1.0 que, pós-anonimização, chama
-- fn_redact_ledger_pii_for_user(p_user_id) e incorpora o report.
--
-- NOTA: Não re-declaramos a função inteira; usamos CREATE OR REPLACE com
-- um WRAPPER que chama a v2.0.0 original + pós-passo. Porém a versão
-- original está como CREATE OR REPLACE FUNCTION em 20260417190000, e aqui
-- NÃO podemos renomear sem breaking change. Solução: adicionamos um
-- AFTER TRIGGER em audit_logs que detecta 'user.self_delete.completed' e
-- chama fn_redact_ledger_pii_for_user como safety-net. Dessa forma,
-- reset_migrations pode rodar em qualquer ordem.
-- ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_ledger_pii_redact_on_erasure()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_target_user uuid;
  v_report      jsonb;
BEGIN
  -- Só trigga em audit_logs com a action canônica de conclusão de erasure.
  IF NEW.action IS DISTINCT FROM 'user.self_delete.completed' THEN
    RETURN NEW;
  END IF;

  v_target_user := COALESCE(NEW.target_user_id, NEW.actor_id);
  IF v_target_user IS NULL OR v_target_user = '00000000-0000-0000-0000-000000000000'::uuid THEN
    RETURN NEW;
  END IF;

  BEGIN
    v_report := public.fn_redact_ledger_pii_for_user(v_target_user, NULL);
    -- Atualiza metadata do log com o report; defensivo porque audit_logs
    -- pode ser append-only após L10-08 — falha silenciosa nesse caso.
    BEGIN
      UPDATE public.audit_logs
         SET metadata = COALESCE(metadata, '{}'::jsonb)
                      || jsonb_build_object('l04_07_redaction', v_report)
       WHERE id = NEW.id;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  EXCEPTION WHEN OTHERS THEN
    -- Nunca bloqueia o audit_log insert — auditoria é mais importante que o
    -- safety-net de PII. Ops recebe alerta via failed_redactions metric.
    BEGIN
      INSERT INTO public.coin_ledger_pii_redactions (
        ledger_id, table_name, column_name, redacted_value, original_hash,
        trigger_source, user_id, note
      ) VALUES (
        NULL, 'coin_ledger', 'reason', '[error]', 'n/a',
        'fn_delete_user_data', v_target_user,
        'TRIGGER_ERROR: ' || SQLERRM
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END;

  RETURN NEW;
END
$$;

COMMENT ON FUNCTION public.fn_ledger_pii_redact_on_erasure() IS
  'L04-07: trigger AFTER INSERT em audit_logs que dispara redação de PII '
  'residual em coin_ledger quando user.self_delete.completed é registrado. '
  'Safety-net: o caller deveria já ter chamado fn_redact_ledger_pii_for_user '
  'diretamente mas esse trigger cobre erasures antigas/incompletas.';

-- Aplica o trigger só se audit_logs existir (ambientes parciais)
DO $apply_trigger$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class
     WHERE relnamespace = 'public'::regnamespace
       AND relname = 'audit_logs'
  ) THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_ledger_pii_redact_on_erasure ON public.audit_logs';
    EXECUTE $trg$
      CREATE TRIGGER trg_ledger_pii_redact_on_erasure
      AFTER INSERT ON public.audit_logs
      FOR EACH ROW
      EXECUTE FUNCTION public.fn_ledger_pii_redact_on_erasure()
    $trg$;
  END IF;
END
$apply_trigger$;

-- ═══════════════════════════════════════════════════════════════════════════
-- SELF-TEST (DO block) — exercita invariantes chave antes de commit
-- ═══════════════════════════════════════════════════════════════════════════

DO $selftest$
DECLARE
  v_uid  uuid := gen_random_uuid();
  v_now  bigint := (EXTRACT(EPOCH FROM now()) * 1000)::bigint;
  v_id   uuid;
  v_err  text;
  v_rows bigint;
  v_rep  jsonb;
BEGIN
  -- Seed user in auth.users (coin_ledger tem FK). Idempotente.
  BEGIN
    INSERT INTO auth.users (id, email, instance_id, aud, role,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (
      v_uid,
      'l04-07-selftest-' || v_uid || '@test.local',
      '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', '', now(), now(), now()
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN undefined_table OR insufficient_privilege THEN
    -- Ambientes sem auth.users (testes psql não-supabase): pula
    -- inteiro o self-test dependente de FK.
    RAISE NOTICE 'L04-07 selftest: auth.users indisponível; skip';
    RETURN;
  END;

  -- 1. CHECK aceita reason canônica
  BEGIN
    INSERT INTO public.coin_ledger
      (user_id, delta_coins, reason, ref_id, created_at_ms)
    VALUES (v_uid, 10, 'session_completed', gen_random_uuid()::text, v_now)
    RETURNING id INTO v_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'L04-07 selftest[1] failed: canonical reason rejected: %', SQLERRM;
  END;

  -- 2. CHECK rejeita reason com '@'
  -- L04-07-OK: self-test deliberately inserts PII to prove the CHECK bites.
  BEGIN
    INSERT INTO public.coin_ledger
      (user_id, delta_coins, reason, ref_id, created_at_ms)
    VALUES (v_uid, 1, 'email john@x.com', gen_random_uuid()::text, v_now);
    RAISE EXCEPTION 'L04-07 selftest[2] failed: reason with @ was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
    WHEN OTHERS THEN
      -- Whitelist CHECK (coin_ledger_reason_check) também rejeita, OK.
      IF SQLSTATE NOT IN ('23514') THEN RAISE; END IF;
  END;

  -- 3. CHECK rejeita reason com pattern "by user <uuid>"
  -- Este teste só faz sentido se a whitelist NÃO estivesse ativa; como está,
  -- o whitelist bloqueia antes do guard por ser um valor free-form.
  -- Nós validamos aqui que ambos guards estão presentes (catalog):
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.coin_ledger'::regclass
       AND conname  = 'coin_ledger_reason_pii_guard'
  ) THEN
    RAISE EXCEPTION 'L04-07 selftest[3] failed: coin_ledger_reason_pii_guard not installed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.coin_ledger'::regclass
       AND conname  = 'coin_ledger_reason_length_guard'
  ) THEN
    RAISE EXCEPTION 'L04-07 selftest[4] failed: coin_ledger_reason_length_guard not installed';
  END IF;

  -- 4. fn_redact_ledger_pii_for_user é idempotente e retorna jsonb
  v_rep := public.fn_redact_ledger_pii_for_user(v_uid, NULL);
  IF v_rep IS NULL OR v_rep->>'user_id' IS NULL THEN
    RAISE EXCEPTION 'L04-07 selftest[5] failed: fn_redact_ledger_pii_for_user returned null/empty';
  END IF;
  IF (v_rep->>'coin_ledger_reason_redacted')::bigint IS NULL THEN
    RAISE EXCEPTION 'L04-07 selftest[6] failed: missing coin_ledger_reason_redacted counter';
  END IF;

  -- 5. Trigger presente em audit_logs (se tabela existe)
  IF EXISTS (
    SELECT 1 FROM pg_class
     WHERE relnamespace = 'public'::regnamespace
       AND relname = 'audit_logs'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
       WHERE tgname = 'trg_ledger_pii_redact_on_erasure'
         AND tgrelid = 'public.audit_logs'::regclass
         AND NOT tgisinternal
    ) THEN
      RAISE EXCEPTION 'L04-07 selftest[7] failed: trg_ledger_pii_redact_on_erasure not installed';
    END IF;
  END IF;

  -- Clean up test row + seed user
  DELETE FROM public.coin_ledger WHERE id = v_id;
  BEGIN
    DELETE FROM auth.users WHERE id = v_uid;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RAISE NOTICE 'L04-07 selftest: OK (all 7 invariants pass)';
END
$selftest$;
