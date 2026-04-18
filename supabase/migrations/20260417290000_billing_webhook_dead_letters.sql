-- ══════════════════════════════════════════════════════════════════════════
-- L01-18 — billing_webhook_dead_letters table
--
-- Referência auditoria:
--   docs/audit/findings/L01-18-asaas-webhook-supabase-functions-asaas-webhook-index-ts.md
--   docs/audit/parts/01-ciso.md [1.18]
--
-- Problema:
--   Três Edge Functions (asaas-webhook, webhook-mercadopago, webhook-payments)
--   já INSERT em `public.billing_webhook_dead_letters` no catch-all do handler
--   para preservar requests que falharam mid-process. Mas a tabela NUNCA foi
--   criada por uma migration — todos esses inserts falharam silenciosamente
--   (best-effort try/catch no edge function), perdendo evidência forense
--   de cada falha de webhook. Auditoria pós-incidente cega.
--
-- Correção:
--   Criar a tabela com schema explícito + RLS + índices para query por
--   provider/event_type/created_at. Service_role-only writes; admin lê
--   apenas do próprio grupo (best-effort, group_id pode ser NULL quando
--   o webhook falha ANTES de identificar o grupo).
--
-- Compat:
--   Idempotente (CREATE TABLE IF NOT EXISTS). Edge functions já fazem
--   o INSERT — esta migration apenas materializa o destino.
--
-- Linked:
--   - L20-01 (financial-ops dashboard) — DLQ count é uma métrica chave;
--     dashboard JSON já querya esta tabela mas ficava "0" sempre.
-- ══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.billing_webhook_dead_letters (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider        text NOT NULL CHECK (provider IN ('asaas', 'mercadopago', 'stripe', 'pagseguro', 'other')),
  group_id        uuid REFERENCES public.coaching_groups(id) ON DELETE SET NULL,
  event_type      text,
  event_id        text,
  payload         jsonb,
  headers         jsonb,
  error_message   text,
  error_code      text,
  retry_count     integer NOT NULL DEFAULT 0,
  status          text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'replayed', 'discarded', 'investigating')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  resolved_at     timestamptz,
  resolved_by     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  resolution_note text
);

COMMENT ON TABLE public.billing_webhook_dead_letters IS
  'L01-18: dead-letter queue para webhooks de billing que falharam mid-process. '
  'Service_role insere via Edge Functions (asaas-webhook, webhook-mercadopago, '
  'webhook-payments). Operador trata via admin UI ou runbook (replay/discard). '
  'group_id pode ser NULL quando a falha ocorreu ANTES da identificação do grupo.';

COMMENT ON COLUMN public.billing_webhook_dead_letters.payload IS
  'Body bruto do webhook (jsonb). Pode conter PII de pagador — tratar com cuidado em logs.';

COMMENT ON COLUMN public.billing_webhook_dead_letters.headers IS
  'Headers do request (sem authorization/cookie/x-signature/x-request-id, removidos pelo handler).';

COMMENT ON COLUMN public.billing_webhook_dead_letters.status IS
  'pending=aguarda análise, replayed=re-enfileirado e processado, discarded=descartado pelo operador, investigating=em triagem.';

-- ──────────────────────────────────────────────────────────────────────────
-- Índices
-- ──────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_bwdl_provider_created
  ON public.billing_webhook_dead_letters (provider, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_bwdl_status_pending
  ON public.billing_webhook_dead_letters (status, created_at DESC)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_bwdl_group
  ON public.billing_webhook_dead_letters (group_id, created_at DESC)
  WHERE group_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bwdl_event_type
  ON public.billing_webhook_dead_letters (provider, event_type, created_at DESC);

-- ──────────────────────────────────────────────────────────────────────────
-- RLS
-- ──────────────────────────────────────────────────────────────────────────
--
-- Política: service_role tem ALL (Edge Function escreve, admin UI usa
-- service_role para gerenciar via RPC futura). admin_master/coach lê
-- apenas DLQ do próprio grupo (e nunca rows com group_id NULL — essas
-- são triagem cross-tenant para a equipe Omni).
ALTER TABLE public.billing_webhook_dead_letters ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.billing_webhook_dead_letters FROM PUBLIC;
REVOKE ALL ON public.billing_webhook_dead_letters FROM anon;

GRANT SELECT ON public.billing_webhook_dead_letters TO authenticated;
GRANT ALL    ON public.billing_webhook_dead_letters TO service_role;

DROP POLICY IF EXISTS "bwdl_admin_own_group_select" ON public.billing_webhook_dead_letters;
CREATE POLICY "bwdl_admin_own_group_select"
  ON public.billing_webhook_dead_letters FOR SELECT USING (
    group_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_webhook_dead_letters.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ──────────────────────────────────────────────────────────────────────────
-- Invariantes de saída
-- ──────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_has_table boolean;
  v_has_rls   boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'billing_webhook_dead_letters'
  ) INTO v_has_table;
  IF NOT v_has_table THEN
    RAISE EXCEPTION '[L01-18] invariant failed: billing_webhook_dead_letters não criada';
  END IF;

  SELECT relrowsecurity INTO v_has_rls
    FROM pg_class
   WHERE relname = 'billing_webhook_dead_letters' AND relnamespace = 'public'::regnamespace;
  IF NOT COALESCE(v_has_rls, false) THEN
    RAISE EXCEPTION '[L01-18] invariant failed: RLS desabilitada em billing_webhook_dead_letters';
  END IF;
END $$;
