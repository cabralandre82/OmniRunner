-- ──────────────────────────────────────────────────────────────────────────
-- L01-44 — Correção: migration drift em platform_fee_config.fee_type CHECK
--
-- Referência auditoria:
--   docs/audit/findings/L01-44-migration-drift-platform-fee-config-fee-type-check.md
--   docs/audit/findings/L01-13-post-api-platform-fees-alteracao-de-taxas.md
--   docs/audit/parts/01-ciso.md [1.44, 1.13]
--
-- Problema:
--   - 20260228150001: CREATE TABLE com CHECK(fee_type IN ('clearing','swap','maintenance'))
--   - 20260228170000: INSERT ('fx_spread', 0.75) → FALHA em fresh install (CHECK rejeita)
--   - 20260316000000: DROP/ADD CHECK adicionou 'billing_split' mas NÃO incluiu 'fx_spread'
--   - Nenhuma migration subsequente corrigiu o CHECK de platform_fee_config para fx_spread
--
--   Resultado: em produção a linha fx_spread pode estar ausente (se 170000 falhou)
--   ou presente por acidente (se CHECK foi flexibilizada antes de 170000 rodar).
--   Em qualquer fresh install ou disaster recovery, replay das migrations QUEBRA em 170000.
--
-- Correção:
--   (a) Esta migration: canonical source of truth — DROP/ADD CHECK com lista completa
--       + INSERT fx_spread idempotente. Safe em qualquer estado.
--   (b) Ajuste retroativo em 20260228170000_custody_gaps.sql que adiciona DROP/ADD CHECK
--       antes do INSERT, tornando fresh install idempotente. Como Supabase rastreia
--       migrations por filename, a edição não re-executa em DBs que já aplicaram.
--   (c) Portal: extensão do zod enum em /api/platform/fees para incluir fx_spread
--       (L01-13, cross-ref).
-- ──────────────────────────────────────────────────────────────────────────

-- 1. Recria CHECK com lista canônica (ordenada por uso histórico)
ALTER TABLE public.platform_fee_config
  DROP CONSTRAINT IF EXISTS platform_fee_config_fee_type_check;

ALTER TABLE public.platform_fee_config
  ADD CONSTRAINT platform_fee_config_fee_type_check
    CHECK (fee_type IN ('clearing', 'swap', 'maintenance', 'billing_split', 'fx_spread'));

COMMENT ON CONSTRAINT platform_fee_config_fee_type_check ON public.platform_fee_config IS
  'L01-44: lista canônica de fee_types válidos. Qualquer migration futura que adicione '
  'novo tipo DEVE: 1) DROP/ADD este CHECK estendido; 2) atualizar zod enum em '
  'portal/src/app/api/platform/fees/route.ts; 3) adicionar label em '
  'portal/src/app/platform/fees/page.tsx FEE_LABELS.';

-- 2. Seed defensivo de fx_spread (noop se já existe)
-- Default 0.75% baseado em 20260228170000:41
INSERT INTO public.platform_fee_config (fee_type, rate_pct, is_active)
VALUES ('fx_spread', 0.75, true)
ON CONFLICT (fee_type) DO NOTHING;

-- 3. Alinha CHECK de platform_revenue para consistência
-- (já está correto via 20260319000000_maintenance_fee_per_athlete.sql mas forçamos
-- idempotentemente para garantir em todos os ambientes)
DO $$
BEGIN
  ALTER TABLE public.platform_revenue
    DROP CONSTRAINT IF EXISTS platform_revenue_fee_type_check;

  ALTER TABLE public.platform_revenue
    ADD CONSTRAINT platform_revenue_fee_type_check
      CHECK (fee_type IN ('clearing', 'swap', 'maintenance', 'billing_split', 'fx_spread'));
EXCEPTION
  WHEN undefined_table THEN
    RAISE NOTICE 'platform_revenue not yet created, skipping constraint alignment';
END $$;

-- 4. Verificação de invariante: todos os fee_types esperados estão presentes
-- (não falha; apenas emite NOTICE para o log da migration)
DO $$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(t, ', ') INTO v_missing
  FROM unnest(ARRAY['clearing','swap','maintenance','billing_split','fx_spread']) t
  WHERE NOT EXISTS (
    SELECT 1 FROM public.platform_fee_config pfc WHERE pfc.fee_type = t
  );

  IF v_missing IS NOT NULL THEN
    RAISE NOTICE 'L01-44: fee_types ausentes em platform_fee_config: %', v_missing;
  END IF;
END $$;
