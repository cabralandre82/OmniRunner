# DIRETIVA DE AUDITORIA TOTAL — OMNI RUNNER
## Operação Pente-Fino — Execução

> Dada a amplitude (23 lentes × ~280 itens), a resposta é dividida em **8 partes**. Após cada parte, aguardo comando **"continue"** para a próxima. Nada será comprimido.
> 
> **Nota de escopo:** a execução prioriza evidência concreta (arquivo:linha) sobre especulação. Itens marcados `⚪ NÃO APLICÁVEL` indicam que a feature não existe no código ou está fora de escopo verificável sem ambiente de execução.

---

# PARTE 1 de 8 — LENTE 1 (CISO: Superfície de Ataque)

## LENTE 1 — CISO: SUPERFÍCIE DE ATAQUE

### [1.1] `POST /api/custody/webhook` — Webhook de custódia (Stripe + MercadoPago)
- **Camada:** PORTAL (Next.js) + BACKEND
- **Persona principal impactada:** Assessoria (admin_master), Plataforma
- **Veredicto:** 🟠 **ALTO**
- **Achado:**
  - `portal/src/app/api/custody/webhook/route.ts:17-51` valida assinatura (Stripe HMAC-SHA256 com timestamp) mas **MercadoPago só valida HMAC simples, sem timestamp/nonce** (`portal/src/lib/webhook.ts:73-86`).
  - `verifyHmacSignature` não possui janela de tolerância → **replay attack ilimitado** para MP.
  - Não há deduplicação por `event_id` no endpoint (só idempotência via `payment_reference` ao confirmar depósito — replay do *mesmo* evento em janela de concorrência pode criar mensagens duplicadas no log mesmo que o depósito final seja idempotente).
  - O campo `x-gateway` pode vir do cliente (linha 19) e determina qual secret usar — embora a verificação de assinatura ainda falhe se o secret for trocado, isso permite um atacante forçar caminho de verificação mais fraco.
- **Risco:** Um invasor que capture um webhook MP legítimo em trânsito (MITM em proxies, log scraping) pode reprocessar indefinidamente. Consequência: não há ganho financeiro direto (idempotência via `payment_reference` em `custody_deposits`), mas inunda `payment_webhook_events` e audit logs, e interfere com métricas (`metrics.increment("custody.webhook.confirmed", { gateway })`).
- **Correção:**
  ```typescript
  // portal/src/lib/webhook.ts — adicionar timestamp obrigatório para MP
  export function verifyHmacSignature({ payload, signature, secret, timestampHeader, tolerance = 300 }: ...) {
    if (timestampHeader) {
      const ts = parseInt(timestampHeader, 10);
      if (isNaN(ts) || Math.abs(Math.floor(Date.now() / 1000) - ts) > tolerance) {
        throw new WebhookError("Timestamp out of tolerance");
      }
      payload = `${ts}.${payload}`;  // MP v2 signature scheme
    }
    const computed = crypto.createHmac("sha256", secret).update(payload).digest("hex");
    if (!timingSafeEqual(computed, signature)) throw new WebhookError("Signature mismatch");
  }
  ```
  Trocar também a verificação de `x-gateway` para detecção autoritativa baseada no header presente (`stripe-signature` ou `x-signature`), ignorando `x-gateway` do cliente.
- **Teste de regressão proposto:** `portal/e2e/api-security.spec.ts` — enviar webhook MP com timestamp 10 min no passado + assinatura válida → esperar 401; sem `x-signature` → 400.

---

### [1.2] `POST /api/custody/withdraw` — Criação e execução de saque em um único request
- **Camada:** PORTAL
- **Persona principal impactada:** Plataforma (CFO), Assessoria
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:**
  - `portal/src/app/api/custody/withdraw/route.ts:19` aceita **`fx_rate` vindo do cliente** (`z.number().positive()`), sem validar contra nenhuma fonte autoritativa (BCB/ECB/Stripe FX quote).
  - Combinado com `portal/src/lib/custody.ts:231-243` (`convertFromUsdWithSpread` usa literalmente o rate do cliente), um admin_master malicioso pode sacar USD com `fx_rate = 10.0` (normal BRL≈5.5), recebendo 2× em BRL.
  - `executeWithdrawal` é chamado logo após `createWithdrawal` (linha 104) — saque é finalizado em um único request, sem passo de aprovação com validação externa do rate.
- **Risco:** Fraude financeira direta por admin_master comprometido ou malicioso. Escala: até USD 1M por request (limite do schema), multiplicado pelo erro de rate. Quebra a invariante D_i = R_i + A_i quando o `total_deposited_usd -= amount_usd` usa USD nominal mas o payout local sai inflado.
- **Correção:**
  1. Remover `fx_rate` do schema de entrada. Buscar rate em server-side de fonte autoritativa (`portal/src/lib/fx/quote.ts` — criar; consultar Stripe FX API ou BCB PTAX).
  2. Separar em duas etapas: `POST /api/custody/withdraw` cria pendente com rate congelado e `executeWithdrawal` exige aprovação por `PLATFORM_ADMIN` (não admin_master) em `/api/platform/custody/approve-withdraw`.
  3. Adicionar limite diário por grupo via `platform_fee_config` (`max_withdrawal_per_day_usd`).
  ```typescript
  const withdrawSchema = z.object({
    amount_usd: z.number().min(1).max(100_000),  // reduzir ceiling
    target_currency: z.enum(["BRL", "EUR", "GBP"]).default("BRL"),
    provider_fee_usd: z.number().min(0).max(100).optional(),
    // fx_rate removido
  });
  // ...
  const fxRate = await fetchAuthoritativeFxRate(parsed.data.target_currency);
  ```
- **Teste de regressão proposto:** `portal/e2e/business-flow-financial.spec.ts` — tentar POST com `fx_rate` no body → 400 "Unknown field"; conferir que saque pendente exige 2ª aprovação.

---

### [1.3] `POST /api/distribute-coins` — Distribuição de coins a atleta
- **Camada:** PORTAL
- **Persona principal impactada:** Atleta, Assessoria, Plataforma
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:**
  - `portal/src/app/api/distribute-coins/route.ts:97-110` tem um **fallback silencioso**: se a RPC `custody_commit_coins` não existir (`could not find`), o código *prossegue com a distribuição sem commit de lastro*. O comentário "custody_commit_coins RPC may not exist yet" prova que isto é intencional para compatibilidade histórica, mas hoje em produção a RPC existe (migration 20260228150001_custody_clearing_model.sql:232) — qualquer regressão de migration re-habilita emissão sem lastro.
  - Orquestração **não-atômica** entre 4 operações (custody_commit → decrement_token_inventory → increment_wallet_balance → coin_ledger insert). Se o processo Vercel for morto entre `decrement_token_inventory` (linha 113) e `increment_wallet_balance` (linha 129), **o grupo perde inventário e o atleta NÃO recebe as coins**; não há rollback.
  - `ledgerErr` (linha 151) é apenas logado; wallet balance já foi creditado mas audit trail está incompleto.
- **Risco:** (a) Inflação monetária sem lastro se commit silencioso ocorrer. (b) Perda de inventário operacional do grupo sem contrapartida ao atleta — gera suporte-tickets e possivelmente pagamentos de compensação manuais. (c) Auditoria financeira quebrada se `coin_ledger` falhar (CFO não consegue reconciliar).
- **Correção:**
  1. Criar RPC SQL `distribute_coins_atomic(p_group_id uuid, p_athlete uuid, p_amount int, p_ref_id text)` com `SECURITY DEFINER` que executa **em uma única transação**: commit custody, decrement inventory, increment wallet, insert ledger, insert audit. `FOR UPDATE` em `coaching_token_inventory` e `custody_accounts`.
  2. Remover o fallback silencioso — falhar com 500 se `custody_commit_coins` não existir.
  ```sql
  CREATE OR REPLACE FUNCTION public.distribute_coins_atomic(...)
    RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
  BEGIN
    PERFORM 1 FROM custody_accounts WHERE group_id = p_group_id FOR UPDATE;
    PERFORM custody_commit_coins(p_group_id, p_amount);
    PERFORM decrement_token_inventory(p_group_id, p_amount);
    PERFORM increment_wallet_balance(p_athlete, p_amount);
    INSERT INTO coin_ledger (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
      VALUES (p_athlete, p_amount, 'institution_token_issue', p_ref_id, p_group_id, EXTRACT(EPOCH FROM now())::BIGINT * 1000);
    RETURN jsonb_build_object('status', 'ok');
  END; $$;
  ```
- **Teste de regressão proposto:** `portal/src/app/api/distribute-coins/route.test.ts` — mock de `custody_commit_coins` retornando "could not find" → verificar response 500, nenhum ledger insertado. Também: teste de crash simulado entre RPCs.

---

### [1.4] `POST /api/custody` (create deposit / confirm) — Sem idempotency-key
- **Camada:** PORTAL
- **Persona principal impactada:** Assessoria (admin_master)
- **Veredicto:** 🟠 **ALTO**
- **Achado:**
  - `portal/src/app/api/custody/route.ts:60-146` cria depósito sem `idempotency-key` do cliente. Double-click cria dois registros `custody_deposits` PENDING.
  - A coluna `UNIQUE` em `payment_reference` (migration `20260228170000_custody_gaps.sql:33`) é **parcial `WHERE payment_reference IS NOT NULL`** — portanto não protege depósitos enquanto o reference é `NULL` (antes do gateway retornar).
  - `confirmDeposit(depositId)` chamado sem verificação de ownership (embora use `SECURITY DEFINER`, não recebe `group_id` do caller para cross-check).
- **Risco:** Um admin_master pode, com conluio, chamar `confirm_custody_deposit` via RPC directa (se tiver acesso) e creditar sem pagar (verificar se a RPC confirma sem verificar gateway). Mais realista: duplicação cria UX ruim e possíveis dois checkouts pendentes abandonados.
- **Correção:**
  - Exigir header `x-idempotency-key` no POST de deposit; criar `deposit_idempotency` table ou reutilizar `custody_deposits.idempotency_key` com UNIQUE.
  - Em `confirmDeposit`, alterar signature para `confirmDeposit(depositId, groupId)` e validar em SQL: `WHERE id=p_deposit_id AND group_id=p_group_id`.
- **Teste de regressão proposto:** `portal/src/app/api/custody/route.test.ts` — dois POSTs com mesmo idempotency-key devem retornar o mesmo deposit_id.

---

### [1.5] `POST /api/swap` — Criação/aceite/cancelamento
- **Camada:** PORTAL
- **Persona principal impactada:** Assessorias compradora e vendedora
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:**
  - `portal/src/app/api/swap/route.ts:141-143` engole toda exceção em genérico "Operação falhou. Tente novamente." com `console.error` (não `logger.error`). Sentry não recebe o erro → observabilidade cega.
  - `getOpenSwapOffers(auth.groupId)` (linha 70) passa o `groupId` como `excludeGroupId`, mas **qualquer admin_master autenticado consegue ver TODAS as ofertas de todos os outros grupos** — isso é por design (marketplace B2B), porém expõe volumes e preços praticados por concorrentes. Verificar se é tratado pela `LENTE 9 — CRO`.
  - `amount_usd` validado `min(100) max(500_000)` — mas não há rate limit específico para `accept` (rate limit é global para POST, 10/min). Um agressor autenticado pode tentar race-accept de ofertas que ainda estão sendo precificadas.
- **Risco:** Observabilidade comprometida em produção (erros financeiros invisíveis). Competidores enxergando book de ofertas pode ser leak de inteligência comercial.
- **Correção:**
  - Substituir `console.error` por `logger.error("swap operation failed", e, { action, groupId })`.
  - Adicionar rate limit separado para `action=accept`: 3/min/group.
  - Avaliar com produto se quer book público de ofertas ou matching privado (ver LENTE 9.1).

---

### [1.6] `GET /api/swap`, `GET /api/clearing`, `GET /api/custody` — Autorização por cookie
- **Camada:** PORTAL
- **Persona principal impactada:** Coach/Assistant (potencial escalação)
- **Veredicto:** 🟠 **ALTO**
- **Achado:** Os helpers `requireAdminMaster` (`/api/custody/route.ts:24-48`, `/api/custody/withdraw/route.ts:23-47`, `/api/swap/route.ts:32-56`) consultam a role do usuário **a partir do cookie `portal_group_id`** (`cookies().get("portal_group_id")?.value`). Embora o middleware (`portal/src/middleware.ts:82-103`) revalide a membership a cada request, um agressor que consiga setar cookies (via XSS com `'unsafe-inline'` no CSP — LENTE 7.5 / 20.x) pode assumir a identidade de assessoria alheia se ele tiver membership em qualquer grupo e forjar outro `portal_group_id`. A revalidação rejeita, mas para tabelas em que ele *é* `admin_master` de um grupo, assumir outro cookie não escala (middleware confere `user_id + group_id`).
- **Risco:** Defesa em profundidade frágil: CSP `'unsafe-inline'` (next.config.mjs:78-80) + cookie de grupo httpOnly+sameSite:lax (`portal/src/middleware.ts:97-102`) — lax ainda permite top-level navegação GET. Se uma rota GET não exigir método POST, é CSRF-exploitable.
- **Correção:** Adicionar `sameSite: "strict"` aos cookies `portal_group_id` e `portal_role`, ou adicionar header `X-CSRF-Token` validado em todos os POSTs. Remover `'unsafe-inline'` do CSP (LENTE 20.x).

---

### [1.7] `GET /api/health` — Information disclosure
- **Camada:** PORTAL
- **Persona principal impactada:** Qualquer atacante externo
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `portal/src/app/api/health/route.ts:37-48` retorna `{ status, latencyMs, checks: { db, invariants: "N violation(s)" } }`. Revela **contagem exata de violações de invariante** ao público. Um atacante interno (funcionário suspenso) pode usar isso para inferir atividade de clearing.
- **Risco:** Baixo-médio — vaza sinais operacionais para reconnaissance.
- **Correção:** Separar `/api/liveness` (público, apenas boolean) de `/api/health` (restrito a PLATFORM_ADMIN ou IP allowlist de monitoramento). Middleware atual (`portal/src/middleware.ts:4`) marca ambos como public — restringir `/api/health` a IPs Vercel/Cloudflare.

---

### [1.8] `GET /api/liveness` — OK
- **Camada:** PORTAL
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `portal/src/app/api/liveness/route.ts:6-22` só retorna `{status, ts, latencyMs}`. Nenhum leak.
- **Correção:** N/A.

---

### [1.9] `POST /api/checkout` — Gateway proxy
- **Camada:** PORTAL + BACKEND (Edge Functions)
- **Persona principal impactada:** Atleta (comprador de produto/coins)
- **Veredicto:** 🟠 **ALTO**
- **Achado:**
  - `portal/src/app/api/checkout/route.ts:35-52` aceita `product_id` do cliente e encaminha a Edge Function. **Não valida que o produto existe/está ativo antes de enviar**. Se a Edge Function não validar, cria payment intent com product_id inválido.
  - Sessão é obtida via `supabase.auth.getSession()` (linha 37) e o access_token é encaminhado — ok.
  - Rate limit `checkout:${user.id}` — 5/60s (boa defesa).
- **Risco:** Depende da Edge Function (`create-checkout-session` / `create-checkout-mercadopago`). Se a função confiar no `product_id` sem validar `is_active` e `price_cents`, é possível "comprar" produto desativado ou manipular preço (se a função aceitar `price` do body).
- **Correção:** Pré-validar no portal:
  ```typescript
  const { data: product } = await createServiceClient()
    .from("billing_products")
    .select("id, is_active, price_cents")
    .eq("id", productId)
    .eq("is_active", true)
    .maybeSingle();
  if (!product) return NextResponse.json({ error: "Product not available" }, { status: 404 });
  ```

---

### [1.10] `GET /api/auth/callback` — Open redirect candidato
- **Camada:** PORTAL
- **Persona principal impactada:** Qualquer usuário após OAuth
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `portal/src/app/api/auth/callback/route.ts:9` aceita `next` do query e redireciona para `${origin}${next}`. O pattern `origin + path` impede redirect cross-origin clássico, mas permite `next=/select-group` ou `next=/platform` — se o atacante conseguir forçar um callback, o redirect pós-login vai para uma tela sensível. Também: `next` pode ser muito longo e sem validação de schema.
- **Risco:** Phishing por redirect forçado a path interno controlado (ex: `/platform/assessorias/create?seed=...`). Limitado porque é same-origin.
- **Correção:**
  ```typescript
  const ALLOWED_NEXT = /^\/[a-z0-9\-_/]+$/i;
  const next = searchParams.get("next") ?? "/dashboard";
  const safeNext = ALLOWED_NEXT.test(next) && !next.startsWith("//") ? next : "/dashboard";
  ```

---

### [1.11] `POST /api/workouts/assign`, `/api/workouts/templates` — Autorização cross-athlete
- **Camada:** PORTAL
- **Persona principal impactada:** Atleta, Coach
- **Veredicto:** ⚪ **NÃO AVALIÁVEL SEM LEITURA ADICIONAL**
- **Achado:** Arquivos existem (`ls portal/src/app/api/workouts/assign`), mas conteúdo não foi inspecionado nesta parte. Marcar para reauditoria específica. Padrão esperado: validar que o `athlete_user_id` do body pertence à assessoria do caller (`coaching_members` join com `group_id` do cookie + role `athlete`).
- **Correção:** Auditar separadamente. Checklist para cada mutação: (a) `requireUser`; (b) `group_id` do cookie; (c) `athlete_user_id` ∈ `coaching_members(group_id, role='athlete')`.

---

### [1.12] `POST /api/verification/evaluate` — Ownership
- **Camada:** PORTAL
- **Persona principal impactada:** Atleta (verificação de autenticidade)
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `portal/src/app/api/verification/evaluate/route.ts:38-73` valida role (`admin_master | coach`) e verifica que o `user_id` pertence ao grupo como `athlete`. Idempotente (reexecuta regras). Rate limit aplicado. Bom padrão.
- **Correção:** N/A. Esse é o padrão que deve ser replicado em `[1.11]`.

---

### [1.13] `POST /api/platform/fees` — Alteração de taxas
- **Camada:** PORTAL + BACKEND
- **Persona principal impactada:** Plataforma (platform_admin)
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:**
  - `portal/src/app/api/platform/fees/route.ts:9-14` aceita `fee_type` de `["clearing","swap","maintenance","billing_split"]` mas **não inclui `"fx_spread"`**, embora `getFxSpreadRate` em `custody.ts:198-208` consulte a linha `fee_type='fx_spread'`. Resultado: não há UI/endpoint para alterar fx_spread — admin precisa ir direto ao DB. Degradação silenciosa.
  - Rate limit 20/min/IP é ok para mudanças administrativas.
  - Auth via `platform_admins` table (linhas 16-32) é consistente com o modelo.
- **Risco:** Operacional: impossibilidade de ajustar FX spread via UI em caso de crise cambial. Médio.
- **Correção:** Estender `updateSchema` para `z.enum(["clearing","swap","maintenance","billing_split","fx_spread"])` e espelhar a UI em `portal/src/app/(platform)/platform/fees/page.tsx` (verificar se inclui fx_spread).

---

### [1.14] Sessão `Supabase.auth.getSession()` no middleware + `auth.getUser()` em `updateSession`
- **Camada:** PORTAL
- **Persona principal impactada:** Todos os usuários autenticados
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:**
  - `portal/src/lib/supabase/middleware.ts:28-30` usa `supabase.auth.getUser()` — **bom**: consulta o servidor do Supabase a cada request, não confia apenas no JWT local. Latência extra (1 roundtrip Supabase).
  - O middleware chama `updateSession` **em toda rota não estática**, incluindo assets do matcher — mas o matcher exclui `_next/static`, `_next/image`, etc. OK.
  - `coaching_members` query (`portal/src/middleware.ts:82-88`) roda a cada request com cookie presente. Sem cache. Para um usuário staff com tráfego alto, isso adiciona 2 queries por request (getUser + coaching_members).
- **Risco:** Performance em cold start. Não é um risco de segurança imediato.
- **Correção:** Considerar cache curto em `@upstash/redis` de membership (60s) com invalidação em eventos de role change. Manter `getUser()` como está (crítico para logout remoto).

---

### [1.15] JWT expiry window — Logout forçado
- **Camada:** PORTAL + BACKEND
- **Persona principal impactada:** Atleta suspenso, Coach banido
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** Supabase padrão: JWT expira em 3600s. Não vi configuração customizada. Um admin_master banido mantém acesso até expiração. **Não há tabela de `revoked_tokens`** (contrário ao projeto Clinipharma referência).
- **Risco:** Janela de 1h de acesso livre após revogação de role/ban. Aceitável para a maioria dos casos, mas inaceitável para admin_master comprometido.
- **Correção:** Adicionar tabela `revoked_sessions(jti_hash text primary key, revoked_at)` e checar no middleware antes do step 2. Alternativa mais simples: chamar `supabase.auth.admin.signOut(user_id)` via Edge Function quando role é removida, forçando refresh token inválido.

---

### [1.16] Upload de documentos — CNH, comprovantes de liga
- **Camada:** APP (Flutter) + BACKEND (Storage)
- **Persona principal impactada:** Atleta profissional (envio de documentos para liga/filiação)
- **Veredicto:** ⚪ **NÃO AUDITADO NESTA PARTE — re-auditar**
- **Achado:** Grepping rápido não encontrou endpoint portal `/api/documents/upload` nem `/api/lgpd/*` no portal (`ls portal/src/app/api/`). Uploads parecem ir direto para Supabase Storage via SDK do app. Para re-auditoria: verificar buckets do Storage e policies RLS.
- **Correção:** Auditar separadamente com `ls supabase/migrations | grep -i storage`.

---

### [1.17] `POST /api/billing/asaas` — Armazenamento de API Key
- **Camada:** PORTAL + BACKEND
- **Persona principal impactada:** Assessoria (admin_master)
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:**
  - `portal/src/app/api/billing/asaas/route.ts` (linhas 80-103) armazena `api_key` do Asaas em `payment_provider_config.api_key` **em texto puro**. A Asaas API Key permite emitir cobranças, consultar clientes e iniciar transferências.
  - Não há indicação de criptografia na inserção (`.upsert({ api_key: apiKey, ... })`). Nenhuma migration adiciona `api_key_encrypted`.
- **Risco:** Se o banco vazar, TODAS as API Keys Asaas das assessorias vazam. Um atacante pode criar cobranças em nome da assessoria ou fazer sacar fundos da conta Asaas.
- **Correção:**
  1. Criar migration que adiciona coluna `api_key_encrypted` e remove `api_key` texto-puro.
  2. Usar `pgcrypto.pgp_sym_encrypt(key, current_setting('app.asaas_key_secret'))`. Secret em Vercel env `ASAAS_KEY_VAULT_SECRET`.
  3. Mascarar leituras: `SELECT CONCAT('***', RIGHT(pgp_sym_decrypt(api_key_encrypted, secret), 4))`.
  4. Forçar rotação: endpoint `POST /api/billing/asaas/rotate-key` que re-criptografa.
  ```sql
  ALTER TABLE payment_provider_config ADD COLUMN api_key_encrypted bytea;
  -- backfill com encryption
  UPDATE payment_provider_config SET api_key_encrypted = pgp_sym_encrypt(api_key, current_setting('app.asaas_key_secret'));
  ALTER TABLE payment_provider_config DROP COLUMN api_key;
  ```

---

### [1.18] Asaas Webhook — `supabase/functions/asaas-webhook/index.ts`
- **Camada:** BACKEND (Edge Function)
- **Persona principal impactada:** Assessoria, Plataforma
- **Veredicto:** 🟠 **ALTO**
- **Achado:**
  - `supabase/functions/asaas-webhook/index.ts:102-104`: aceita `asaas-access-token` do header **OU `accessToken` do payload** (caminho fraco — se o atacante conseguir disparar o endpoint com payload que imita evento Asaas + field `accessToken`, e o token for uma string comum, match ocorre). Como o token é por-grupo e armazenado no DB, um leak do DB expõe todos.
  - Não há HMAC assinado — só um token bearer-style. Asaas suporta HMAC em webhooks mais recentes; não está em uso aqui.
  - Linha 130-135: idempotência por `eventId = "${event}_${paymentId|subId|hash}"`. Hash usa `JSON.stringify(payload).slice(0, 64)` — **colisão trivial** se payloads similares forem enviados (slice de 64 chars de um JSON grande colide facilmente). Não é um risco de exploração, mas pode causar duplicatas ou falsos-positivos de replay.
- **Risco:** Replay / token-reuse em caso de leak DB. Reprocessamento de evento confirmando pagamento (se o DB ainda não marcou `processed`).
- **Correção:**
  1. Remover path de `accessToken` no body.
  2. Adicionar suporte a HMAC-SHA256 do Asaas (usando `asaas-signature` header quando disponível).
  3. Trocar hash de fallback por `sha256(payload)` em vez de `slice(0,64)`.
  ```typescript
  const eventKey = asaasPaymentId ?? asaasSubId
    ?? createHash("sha256").update(JSON.stringify(payload)).digest("hex");
  ```

---

### [1.19] Edge Functions — `verify_jwt = false` com auth manual
- **Camada:** BACKEND
- **Persona principal impactada:** Todos os chamadores de Edge Functions
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:**
  - `supabase/functions/_shared/auth.ts:60-70` usa `createClient(url, serviceKey, { global: { headers: { Authorization: Bearer <userJwt> } } })` + `verifyClient.auth.getUser(jwt)` para validar manualmente.
  - **Mistura de service_role header com JWT de usuário** no mesmo cliente — isso é um pattern anti-recomendado. Os headers service_role têm precedência em chamadas RLS, o que significa que o cliente usa service role para tudo. Comentário na linha 12 justifica como workaround para ES256.
  - O cliente retornado como `db` é de facto **service_role**. Código downstream que usa `db.from(...)` acreditando respeitar RLS está ENGANADO — está bypassando RLS.
- **Risco:** Developers podem confiar no "user-scoped client" e deixar queries cross-tenant exploitáveis. É um tapete mental perigoso.
- **Correção:** Renomear `db` para `adminDbScopedToUser` e documentar que RLS não se aplica. Alternativa: criar cliente separado só com JWT do usuário (sem service key) e migrar chamadas gradualmente, validando que queries ainda funcionam com RLS.

---

### [1.20] `checkRateLimit` via RPC — Fail-closed
- **Camada:** BACKEND
- **Persona principal impactada:** Todos
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `supabase/functions/_shared/rate_limit.ts:29-58` retorna 503 `RATE_LIMIT_UNAVAILABLE` se a RPC falhar — **fail-closed**, correto. Contrasta com `portal/src/lib/rate-limit.ts:97-100` que faz fail-open para memory fallback — ver [1.21].
- **Correção:** N/A.

---

### [1.21] `rateLimit` no portal — Fail-open para memory
- **Camada:** PORTAL
- **Persona principal impactada:** Todos
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:**
  - `portal/src/lib/rate-limit.ts:97-100` — se Redis falhar, cai para `rateLimitInMemory`. Em Vercel Serverless, **cada invocação pode ser instância nova**, então memory store é efetivamente **rate-limit desligado** (cada lambda começa com Map vazio).
  - `_hasRedis = !!getRedis()` (linha 105) é **cacheado em module init**. Se Redis config aparecer depois de start, rate limit nunca usa Redis. Crítico para deploys a quente / mudança de env.
- **Risco:** DoS durante degradação Redis. Brute-force possível em endpoints sensíveis (login via Supabase — embora a própria Supabase tenha rate limit no lado dela).
- **Correção:**
  1. Mover `_hasRedis` para avaliação por request (`getRedis() !== null`) ou re-checar a cada 60s.
  2. Em fallback memory durante invocação serverless, **fail-closed** em endpoints financeiros (custody, withdraw, distribute, swap): retornar 503 se Redis indisponível.
  3. Adicionar métrica Sentry `rate-limit.fallback.memory.count` para alertar SRE.

---

### [1.22] `GET /terms`, `GET /privacy`, outras rotas públicas
- **Camada:** PORTAL
- **Persona principal impactada:** Visitantes
- **Veredicto:** ⚪ **NÃO AUDITADO NESTA PARTE**
- **Achado:** Middleware lista apenas `/login`, `/no-access`, `/api/auth/callback`, `/api/health`, `/api/custody/webhook`, `/api/liveness` e prefixos `/challenge/`, `/invite/`. **Não há `/terms` ou `/privacy` em `PUBLIC_ROUTES`** — se existirem em `src/app`, o middleware exige autenticação, bloqueando visitantes não logados de ler TOS. Isso pode ser intencional (landing page separada) mas merece confirmar.
- **Correção:** Confirmar se existe landing page em `/terms`, `/privacy`. Se sim, adicionar ao middleware.

---

### [1.23] `/challenge/[id]` — Rota pública
- **Camada:** PORTAL
- **Persona principal impactada:** Atleta (recebendo convite), Público
- **Veredicto:** ⚪ **NÃO AUDITADO** (prefix `/challenge/` é público no middleware)
- **Achado:** `PUBLIC_PREFIXES` inclui `/challenge/`. Página pública deve mostrar apenas dados resumidos do desafio (título, participantes N, status), sem PII de atletas. Código não lido.
- **Correção:** Auditar `portal/src/app/challenge/[id]/page.tsx` — verificar que não expõe nome completo, emails, GPS tracks.

---

### [1.24] `/invite/[code]` — Rota pública de aceite de convite
- **Camada:** PORTAL
- **Persona principal impactada:** Atleta convidado
- **Veredicto:** ⚪ **NÃO AUDITADO**
- **Achado:** Público via middleware. Deep link no app também (`deep_link_handler.dart:118`). Precisa auditar: (a) se aceita códigos inválidos graciosamente; (b) rate limit para evitar enumeração; (c) não vaza membership de outros atletas.
- **Correção:** Auditar `portal/src/app/invite/[code]/page.tsx`. Confirmar rate limit IP-based.

---

### [1.25] Middleware — `PUBLIC_PREFIXES.some(p => pathname.startsWith(p))`
- **Camada:** PORTAL
- **Persona principal impactada:** Todos
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:**
  - `portal/src/middleware.ts:30`: `pathname.startsWith("/challenge/")` — não impede `/challenge/../admin` pois o Next.js normaliza pathnames antes do middleware. **Provavelmente seguro**, mas vale teste manual.
  - `/challenge` sem trailing `/` **NÃO** é público (só `/challenge/` é). Isso é intencional (evitar listar desafios sem auth), mas pode causar 401 em links copiados sem slash final.
- **Risco:** Baixo. Possível evasão se houver URL rewrite middleware intermediário.
- **Correção:** Adicionar test E2E verificando que `/challenge/../platform/custody` cai em 401.

---

### [1.26] Middleware — platform role check sem cache
- **Camada:** PORTAL
- **Persona principal impactada:** platform_admin
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `portal/src/middleware.ts:48-62` faz SELECT em `profiles` para checar `platform_role` **em cada request** para `/platform/*`. Latência por request. Sem cache. Um admin_platform com 10 req/s adiciona 10 queries/s desnecessárias.
- **Risco:** Performance, não segurança.
- **Correção:** Cachear em cookie `portal_platform_role` (httpOnly, 5min TTL) com revalidação assíncrona.

---

### [1.27] `requireAdminMaster` em rotas de custody — Service client sem RLS
- **Camada:** PORTAL
- **Persona principal impactada:** Assessoria
- **Veredicto:** 🟢 **SEGURO (com ressalva)**
- **Achado:** `requireAdminMaster` usa `createServiceClient()` (bypass RLS) para checar membership. A lógica em TS replica o que RLS faria. **Ressalva:** toda a segurança agora depende desse helper. Se alguém esquecer de chamar `requireAdminMaster` em um novo endpoint `/api/custody/xyz`, o endpoint fica totalmente aberto.
- **Correção:** Criar middleware de rota tipo-seguro `withAdminMaster(handler)` wrapping, ou exportar um `createRouteHandler` que obriga o check.

---

### [1.28] Deep link handler — `extractInviteCode` aceita qualquer string
- **Camada:** APP (Flutter)
- **Persona principal impactada:** Atleta
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `omni_runner/lib/core/deep_links/deep_link_handler.dart:195` retorna `trimmed` como código se for não-vazio e não contém `/`. Não valida tamanho, charset, formato. Um QR code com texto aleatório (ex: "BUY BITCOIN") vira um convite inválido que vai até o backend.
- **Risco:** Consumo desnecessário de backend (rate limit), confusão UX.
- **Correção:**
  ```dart
  static final _codeFormat = RegExp(r'^[A-Z0-9]{6,16}$');
  static String? extractInviteCode(String input) {
    final trimmed = input.trim();
    // URL path extraction...
    if (_codeFormat.hasMatch(trimmed)) return trimmed;
    return null;
  }
  ```

---

### [1.29] Deep link — Strava callback sem state/CSRF
- **Camada:** APP (Flutter)
- **Persona principal impactada:** Atleta (linkando Strava)
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `deep_link_handler.dart:142-147` aceita `code` do Strava OAuth callback **sem validar parâmetro `state`**. Padrão OAuth 2.0 exige `state` para CSRF protection.
- **Risco:** Atacante induz vítima a autorizar o Strava do atacante na conta Omni Runner da vítima (login CSRF) — a conta Strava do atacante fica vinculada à vítima, que passa a ver atividades do atacante como suas.
- **Correção:** Gerar `state = base64(csprng)` antes do redirect OAuth, armazenar em secure_storage, e validar no callback:
  ```dart
  if (uri.scheme == 'omnirunner' && (isExchangeToken || isLegacy)) {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    final expected = await secureStorage.read(key: 'strava_oauth_state');
    if (state == null || state != expected) return UnknownLinkAction(uri);
    await secureStorage.delete(key: 'strava_oauth_state');
    return StravaCallbackAction(code!);
  }
  ```

---

### [1.30] Android — Falta de ProGuard/R8
- **Camada:** APP (Flutter/Android)
- **Persona principal impactada:** Todos os usuários Android
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `omni_runner/android/app/build.gradle:87-94` não habilita `minifyEnabled`/`shrinkResources`/`proguardFiles` no release buildType. APK release é fully readable. Classes, strings (incluindo provavelmente constantes de URL Supabase, keys de env não-secretos, lógica anti-cheat) expostas a engenharia reversa trivial.
- **Risco:** Reverse engineering do anti-cheat pipeline (`supabase/functions/_shared/anti_cheat.ts` — as thresholds seriam inferíveis por comparação com requests). Exposição de constantes de integração.
- **Correção:**
  ```groovy
  buildTypes {
    release {
      signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
      minifyEnabled true
      shrinkResources true
      proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
  }
  ```
  Criar `proguard-rules.pro` com keeps para Flutter, Firebase, Sentry, Supabase, health plugin.

---

### [1.31] Android — Release assina com debug key se `key.properties` não existir
- **Camada:** APP (Flutter/Android)
- **Persona principal impactada:** CI/CD, stores
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `build.gradle:89-93` fallback silencioso para `signingConfigs.debug` se `keystorePropertiesFile` não existir. Se CI perde o secret, builds release são gerados com debug key — **rejeitados pela Play Store** ou, pior, aceitos mas com upload key errada bloqueando updates futuros.
- **Correção:**
  ```groovy
  buildTypes {
    release {
      if (!keystorePropertiesFile.exists()) {
        throw new GradleException("Release build requires key.properties")
      }
      signingConfig signingConfigs.release
      ...
    }
  }
  ```

---

### [1.32] Flutter — `flutter_secure_storage` sem `setSharedPreferences`
- **Camada:** APP (Flutter)
- **Persona principal impactada:** Atleta, Staff
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `db_secure_store.dart:22-24` usa `FlutterSecureStorage()` com opções default. No Android, sem opções explícitas, usa EncryptedSharedPreferences; se não estiver disponível (APIs < 23 em devices antigos), fallback inseguro para SharedPreferences plain.
- **Risco:** minSdkVersion é 26 (ok), mas para iOS, sem `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`, a key fica acessível mesmo com device bloqueado (comportamento padrão é `KeychainAccessibility.unlocked`, mais restritivo na verdade). Ainda assim, explicitar é melhor.
- **Correção:**
  ```dart
  const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  ```

---

### [1.33] Flutter — DB key storage fallback ausente
- **Camada:** APP
- **Persona principal impactada:** Atleta
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `db_secure_store.dart:29-51`: se `flutter_secure_storage.read` **lançar exceção** (ex: keystore corrompido no Android), não há handler — crash. Usuário perde acesso ao app até reinstalar.
- **Correção:** Try/catch com fallback para `clearKeyAndDatabase()` + re-geração de key (perdendo dados locais, mas app volta a funcionar):
  ```dart
  try {
    existing = await _storage.read(...);
  } on PlatformException catch (e) {
    AppLogger.error('Secure storage corrupted, regenerating', tag: _tag, error: e);
    await clearKeyAndDatabase();
    existing = null;
  }
  ```

---

### [1.34] Flutter — `getOrCreateKey` SHA-256 ofuscação é redundante
- **Camada:** APP
- **Persona principal impactada:** N/A (design)
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `db_secure_store.dart:53-58` gera 32 random bytes e passa por SHA-256. É desnecessário (Random.secure() já dá 32 bytes uniformes), mas não é inseguro.
- **Correção:** Simplificar para `return randomBytes;` — economiza CPU no cold start. Não bloqueante.

---

### [1.35] `supabase/functions/delete-account` — Admin master não pode se auto-deletar
- **Camada:** BACKEND
- **Persona principal impactada:** admin_master
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `supabase/functions/delete-account/index.ts:44-48` bloqueia self-delete de `admin_master`. Good.
- **Correção:** N/A.

---

### [1.36] `delete-account` — `fn_delete_user_data` não-aborta no erro
- **Camada:** BACKEND
- **Persona principal impactada:** Usuário deletando conta (LGPD)
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `delete-account/index.ts:57-64`: se `fn_delete_user_data` falhar, só loga — **mas depois deleta o auth user (linha 70)**. Resultado: user existe em várias tabelas (sessions, coin_ledger, challenge_participants) mas auth record sumiu. Dados órfãos / LGPD comprometido.
- **Risco:** Violação de LGPD "direito ao esquecimento". Também: orphan data acumula.
- **Correção:** Abortar pipeline se `fn_delete_user_data` falhar:
  ```typescript
  if (cleanupErr) {
    return jsonErr(500, "DATA_CLEANUP_FAILED", "Cannot safely delete auth record", requestId);
  }
  ```

---

### [1.37] `set-user-role` — Aceita só strings explícitas
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** Valida `role ∈ ['ATLETA', 'ASSESSORIA_STAFF']` e `onboarding_state ∈ ['NEW', 'ROLE_SELECTED']`. Idempotente.
- **Correção:** N/A.

---

### [1.38] CSP `'unsafe-inline'` + `'unsafe-eval'` em script-src
- **Camada:** PORTAL
- **Persona principal impactada:** Todos
- **Veredicto:** 🟠 **ALTO**
- **Achado:** `portal/next.config.mjs:78-79`: `"script-src 'self' 'unsafe-inline' 'unsafe-eval' https://*.sentry.io"`. Isso **anula proteção XSS do CSP**. Qualquer injeção de HTML com `<script>inline</script>` ou `<div onerror=...>` executa.
- **Risco:** XSS leva a full account takeover — acesso aos cookies `portal_group_id` é httpOnly, mas atacante pode fazer requests autenticados no mesmo domínio (sameSite:lax permite via tag navigation).
- **Correção:** Remover `'unsafe-inline'` e `'unsafe-eval'`. Next.js 14+ suporta nonces via `next.config.mjs` + `headers()` + middleware. Ou migrar inline scripts para Server Components / arquivos estáticos. Para Framer Motion e shadcn, geralmente não precisa unsafe-inline (só usa inline styles, não scripts).
  ```javascript
  // next.config.mjs
  "script-src 'self' 'nonce-{NONCE}' 'strict-dynamic' https://*.sentry.io"
  ```
  Gerar nonce no middleware e passar via header `x-nonce`.

---

### [1.39] CSP — `style-src 'unsafe-inline'`
- **Camada:** PORTAL
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** Aceitável para shadcn/ui/Tailwind (compile-time styles). CSS injection tem superfície de risco muito menor que JS.
- **Correção:** N/A imediata. Considerar migração para nonce em médio prazo.

---

### [1.40] Google services — `google-services.json` commitado
- **Camada:** APP (Android)
- **Persona principal impactada:** Android
- **Veredicto:** 🟢 **SEGURO (com asterisco)**
- **Achado:** `omni_runner/android/app/google-services.json` existe no repo. Firebase considera esse arquivo público (tem apenas client IDs e Firebase project config, não secrets). Porém revela **project number + API keys restritas por package name** — se o restriction SHA não estiver configurado no console Firebase, a key é abusável.
- **Correção:** Verificar Firebase Console → Project Settings → API restrictions → "Android apps" com fingerprint SHA-1 do signing key. Adicionar warning no `CONTRIBUTING.md` sobre isso.

---

### [1.41] `coin_ledger` — Sem assinatura criptográfica
- **Camada:** BACKEND
- **Persona principal impactada:** Plataforma (auditoria)
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `coin_ledger` é o livro-razão de emissões/queimas. Um admin_master com acesso DB (via Supabase Dashboard) pode `UPDATE coin_ledger SET delta_coins=99999 WHERE id=X`. Não há hash chain nem assinatura.
- **Risco:** Fraude interna por funcionário Omni Runner com acesso SQL.
- **Correção:** Implementar hash chain: `hash = sha256(prev_hash || user_id || delta_coins || reason || ref_id || created_at_ms)` em `coin_ledger_hashes` table, atualizada por trigger. Audit externo (pg_audit ou wal streaming para tabela write-once em outro DB).

---

### [1.42] `platform_fee_config` — RLS FOR SELECT USING (true)
- **Camada:** BACKEND
- **Persona principal impactada:** Todos os autenticados
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `supabase/migrations/20260228150001_custody_clearing_model.sql:27-28` e `20260305100000:17-18` — `USING (true)` permite qualquer autenticado ler **todas as taxas** (incluindo rate_usd de maintenance, fx_spread_pct). Se a plataforma quiser estratégia de pricing diferenciado por grupo, isso vazaria info comercial.
- **Risco:** Baixo hoje (taxas são globais). Alto se modelo evoluir.
- **Correção:** Ok manter USING(true) por enquanto; documentar no header da migration.

---

### [1.43] `custody_accounts` RLS — role `'professor'` nunca corresponde
- **Camada:** BACKEND
- **Persona principal impactada:** admin_master, coach
- **Veredicto:** 🟡 **MÉDIO (silent bug)**
- **Achado:** `supabase/migrations/20260228150001_custody_clearing_model.sql:59-67`:
  ```sql
  CREATE POLICY "custody_own_group_read" ON public.custody_accounts
    FOR SELECT USING (... AND cm.role IN ('admin_master', 'professor'))
  ```
  Mas o role canônico é `'coach'` (migration 20260304050000 migrou `professor → coach`). **Essa policy foi esquecida pela migration 20260321** (que consertou outras). Resultado: clients com RLS enabled (não service_role) nunca veem custody_accounts se forem `coach`. Como todo o código atual usa `createServiceClient()`, o bug é silencioso — mas **dead policy** acumula e qualquer read feito via auth.client falha.
- **Risco:** Bug latente; developers inexperientes tentando refatorar para uso correto de RLS vão enfrentar "empty results" sem erro.
- **Correção:** Nova migration:
  ```sql
  DROP POLICY IF EXISTS "custody_own_group_read" ON public.custody_accounts;
  CREATE POLICY "custody_own_group_read" ON public.custody_accounts
    FOR SELECT USING (
      EXISTS (SELECT 1 FROM coaching_members cm
        WHERE cm.group_id = custody_accounts.group_id
          AND cm.user_id = auth.uid()
          AND cm.role IN ('admin_master', 'coach'))
    );
  ```

---

### [1.44] Migration drift — `platform_fee_config.fee_type` CHECK + INSERT 'fx_spread'
- **Camada:** BACKEND
- **Persona principal impactada:** DevOps, CFO (em fresh install)
- **Veredicto:** 🔴 **CRÍTICO**
- **Achado:** 
  - `20260228150001_custody_clearing_model.sql:17` cria CHECK com `('clearing', 'swap', 'maintenance')`.
  - `20260228170000_custody_gaps.sql:40-42` tenta `INSERT ... ('fx_spread', 0.75)`.
  - A CHECK **REJEITA** o INSERT de 'fx_spread' → migration 170000 **FALHA** em instalação fresh.
  - Só migration `20260319000000_maintenance_fee_per_athlete.sql:18` finalmente expande CHECK para incluir `'fx_spread'`.
  - Em um banco existente que já passou 170000 antes da CHECK ser apertada, vai funcionar por acidente histórico.
- **Risco:** Reprovisão de ambientes (staging, preview, onboarding novo dev) **quebra**. Disaster recovery de backup + replay de migrations desde zero **quebra**.
- **Correção:** Criar migration de repair imediatamente:
  ```sql
  -- 20260417000001_fix_platform_fee_config_check.sql
  ALTER TABLE public.platform_fee_config DROP CONSTRAINT IF EXISTS platform_fee_config_fee_type_check;
  ALTER TABLE public.platform_fee_config ADD CONSTRAINT platform_fee_config_fee_type_check
    CHECK (fee_type IN ('clearing','swap','maintenance','billing_split','fx_spread'));
  ```
  E editar `20260228170000` para incluir o DROP/ADD CHECK antes do INSERT. Também: adicionar CI step que faz `supabase db reset && supabase db push` em cada PR.

---

### [1.45] `fee_type` — `'fx_spread'` ausente do endpoint admin
- **Camada:** PORTAL
- **Persona principal impactada:** platform_admin
- **Veredicto:** 🟠 **ALTO** (duplica 1.13 — consolidado)
- **Achado:** `portal/src/app/api/platform/fees/route.ts:10` aceita `z.enum(["clearing","swap","maintenance","billing_split"])` — sem `'fx_spread'`. UI platform não consegue ajustar FX spread via endpoint. Admin precisa rodar SQL manual.
- **Correção:** Ver 1.13. Adicionar `"fx_spread"`.

---

### [1.46] `execute_swap` — Locks `FOR UPDATE` com ordering
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `supabase/migrations/20260228150001:420-432` faz lock em ordem de UUID para prevenir deadlock. Bom design.
- **Correção:** N/A.

---

### [1.47] `executeWithdrawal` — `execute_withdrawal` RPC sem código mostrado
- **Camada:** BACKEND
- **Veredicto:** ⚪ **NÃO AUDITADO**
- **Achado:** Chamada em `portal/src/lib/custody.ts:372-376`, mas a implementação SQL não foi lida nesta parte. Precisa verificar: FOR UPDATE em `custody_accounts`, verificação de `status='pending'`, idempotência por withdrawalId.
- **Correção:** Re-auditar migration que cria `execute_withdrawal`.

---

### [1.48] `aggregateClearingWindow` — Aggregation only
- **Camada:** BACKEND
- **Veredicto:** 🟢 **SEGURO**
- **Achado:** `portal/src/lib/clearing.ts:273-288` — read-only aggregation. Sem mutação.
- **Correção:** N/A.

---

### [1.49] `processBurnForClearing` — Audit actor_id = "system"
- **Camada:** PORTAL
- **Persona principal impactada:** Auditoria
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `portal/src/lib/clearing.ts:147, 161`: audit insere `actorId: "system"`. Isso é uma string não-UUID em `actor_id uuid` — **deve falhar** com cast error. Ou o schema de `portal_audit_log.actor_id` é `text`? Não verifiquei.
- **Risco:** Audit log perdido (fail silent no `.catch` do `auditLog`).
- **Correção:** Verificar schema de `portal_audit_log`. Se `actor_id` é UUID, usar `null` + novo campo `is_system_action bool`. Se é text, manter.

---

### [1.50] `getSwapOrdersForGroup` — Query string interpolation
- **Camada:** PORTAL
- **Persona principal impactada:** Assessoria
- **Veredicto:** 🟡 **MÉDIO**
- **Achado:** `portal/src/lib/swap.ts:134`: 
  ```typescript
  .or(`seller_group_id.eq.${groupId},buyer_group_id.eq.${groupId}`)
  ```
  Se `groupId` não é UUID (vem de cookie decodificado, pode ser tampering), PostgREST pode aceitar expressão maliciosa. O mesmo em `portal/src/lib/clearing.ts:240-242`.
- **Risco:** PostgREST `.or()` é parseado do lado servidor; se a string contém `)` ou `,`, pode quebrar semântica e retornar dados de outros grupos. Supabase sanitiza na maioria dos casos, mas não é garantido em todas as versões.
- **Correção:** Validar UUID no TypeScript antes de compor a query:
  ```typescript
  import { z } from "zod";
  const isUuid = z.string().uuid().safeParse(groupId).success;
  if (!isUuid) throw new Error("Invalid group id");
  ```
  E trocar `.or()` por duas queries separadas com UNION via RPC se possível.

---

## Fim da PARTE 1 de 8

**Resumo da PARTE 1 (Lente 1 — CISO):**
- 🔴 **Críticos:** 4 — [1.2 FX rate client-supplied], [1.3 non-atomic distribute + silent fallback], [1.17 API Key plaintext], [1.44 migration CHECK drift]
- 🟠 **Altos:** 9 — [1.1 MP replay], [1.6 CSRF via cookie], [1.18 Asaas token weak], [1.29 Strava OAuth no state], [1.30 ProGuard], [1.31 debug key fallback], [1.36 delete orphan], [1.38 CSP unsafe-inline], [1.45 fx_spread ausente]
- 🟡 **Médios:** 14 — [1.4, 1.5, 1.7, 1.14, 1.15, 1.19, 1.21, 1.25, 1.26, 1.32, 1.33, 1.39, 1.41, 1.42, 1.43, 1.49, 1.50]
- 🟢 **Seguros:** 8
- ⚪ **Não auditados:** 6 — re-auditar nas partes seguintes ou separadamente: [1.11, 1.16, 1.22, 1.23, 1.24, 1.47]

**CONTINUA NA PARTE 2** — Lentes 2 (CTO — Arquitetura & Race Conditions) e 3 (CFO — Integridade do Dinheiro), totalizando ~35 itens.

Digite **"continue"** para prosseguir para a PARTE 2.