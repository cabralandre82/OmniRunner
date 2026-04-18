-- ──────────────────────────────────────────────────────────────────────────
-- L01-02 — Server-side authoritative FX quotes (remove fx_rate cliente)
--
-- Referência auditoria:
--   docs/audit/findings/L01-02-post-api-custody-withdraw-criacao-e-execucao-de.md
--   docs/audit/parts/01-ciso.md [1.2]
--
-- Problema:
--   POST /api/custody/withdraw aceitava `fx_rate` no body (z.number().positive()).
--   Um admin_master malicioso podia sacar USD com rate inflado (ex: BRL=10 em vez de 5.25),
--   gerando payout local 2× maior em BRL ― fraude financeira direta.
--
-- Correção (esta migration):
--   1. Cria `platform_fx_quotes` ― source of truth de cotações BRL/EUR/GBP → USD,
--      gerenciado pela plataforma (platform_admin). Portal lê rate server-side,
--      cliente nunca envia.
--   2. Seed com rates iniciais conservadores (ajustáveis por platform_admin).
--   3. RLS: leitura para authenticated (portal exibe no UI); escrita só para
--      platform_admin. RPC `refresh_fx_quote` (futura, L01-02 follow-up) fará
--      refresh automático via cron.
--   4. Função `get_latest_fx_quote(currency)` — helper que retorna rate + staleness
--      em uma chamada, consumida pelo portal via lib/fx/quote.ts.
-- ──────────────────────────────────────────────────────────────────────────

-- 1. Tabela de cotações autoritativas
CREATE TABLE IF NOT EXISTS public.platform_fx_quotes (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  currency_code  text NOT NULL
                   CHECK (currency_code IN ('BRL', 'EUR', 'GBP')),
  rate_per_usd   numeric(18, 8) NOT NULL
                   CHECK (rate_per_usd > 0),
  source         text NOT NULL DEFAULT 'seed'
                   CHECK (source IN ('seed', 'manual', 'ptax', 'ecb', 'stripe', 'exchangerate-api')),
  fetched_at     timestamptz NOT NULL DEFAULT now(),
  is_active      boolean NOT NULL DEFAULT true,
  note           text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     uuid REFERENCES auth.users(id),
  -- Bounds de sanidade (rejeita rates absurdos por acidente/ataque)
  CONSTRAINT fx_rate_reasonable_bounds CHECK (
    (currency_code = 'BRL' AND rate_per_usd BETWEEN 1.0  AND 20.0) OR
    (currency_code = 'EUR' AND rate_per_usd BETWEEN 0.5  AND 2.0)  OR
    (currency_code = 'GBP' AND rate_per_usd BETWEEN 0.4  AND 2.0)
  )
);

-- Uma única cotação ativa por moeda (UNIQUE parcial, permite histórico completo)
CREATE UNIQUE INDEX IF NOT EXISTS platform_fx_quotes_active_uq
  ON public.platform_fx_quotes (currency_code)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS platform_fx_quotes_currency_fetched
  ON public.platform_fx_quotes (currency_code, fetched_at DESC);

COMMENT ON TABLE public.platform_fx_quotes IS
  'L01-02: cotações FX autoritativas gerenciadas pela plataforma. '
  'Portal lê rate server-side via get_latest_fx_quote(); cliente NUNCA envia fx_rate.';
COMMENT ON CONSTRAINT fx_rate_reasonable_bounds ON public.platform_fx_quotes IS
  'L01-02: rejeita rates absurdos por acidente ou comprometimento de API externa.';

-- 2. RLS
ALTER TABLE public.platform_fx_quotes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform_fx_quotes_read" ON public.platform_fx_quotes;
CREATE POLICY "platform_fx_quotes_read" ON public.platform_fx_quotes
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "platform_fx_quotes_admin_write" ON public.platform_fx_quotes;
CREATE POLICY "platform_fx_quotes_admin_write" ON public.platform_fx_quotes
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

GRANT SELECT ON TABLE public.platform_fx_quotes TO authenticated;
GRANT ALL    ON TABLE public.platform_fx_quotes TO service_role;

-- 3. Helper RPC: retorna rate + idade em segundos
CREATE OR REPLACE FUNCTION public.get_latest_fx_quote(p_currency text)
  RETURNS TABLE (
    rate_per_usd   numeric,
    source         text,
    fetched_at     timestamptz,
    age_seconds    integer
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT
    q.rate_per_usd,
    q.source,
    q.fetched_at,
    GREATEST(0, EXTRACT(EPOCH FROM (now() - q.fetched_at))::integer) AS age_seconds
  FROM public.platform_fx_quotes q
  WHERE q.currency_code = upper(p_currency)
    AND q.is_active = true
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_latest_fx_quote(text) IS
  'L01-02: retorna cotação ativa + age. Portal valida staleness via lib/fx/quote.ts.';

GRANT EXECUTE ON FUNCTION public.get_latest_fx_quote(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_latest_fx_quote(text) TO service_role;

-- 4. Seed inicial (rates conservadores de 2026-04-17 — platform_admin deve
-- ajustar/refresh via UI /platform/fx). `fetched_at` marcado como agora para
-- evitar que staleness check rejeite de cara.
INSERT INTO public.platform_fx_quotes (currency_code, rate_per_usd, source, is_active, note)
VALUES
  ('BRL', 5.2500, 'seed', true, 'Seed inicial (L01-02 migration). Refresh via /platform/fx.'),
  ('EUR', 0.9200, 'seed', true, 'Seed inicial (L01-02 migration). Refresh via /platform/fx.'),
  ('GBP', 0.7900, 'seed', true, 'Seed inicial (L01-02 migration). Refresh via /platform/fx.')
ON CONFLICT DO NOTHING;

-- 5. Invariante: depois do seed, deve haver exatamente 1 ativo por moeda
DO $$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(t, ', ') INTO v_missing
  FROM unnest(ARRAY['BRL', 'EUR', 'GBP']) t
  WHERE NOT EXISTS (
    SELECT 1 FROM public.platform_fx_quotes q
    WHERE q.currency_code = t AND q.is_active = true
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '[L01-02] Moedas sem cotação ativa após seed: %', v_missing
      USING ERRCODE = 'P0001';
  END IF;
END $$;
