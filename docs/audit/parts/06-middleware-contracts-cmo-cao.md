# PARTE 6 de 8 — LENTES 13 (Middleware & Routing), 14 (API Contracts & Versioning), 15 (CMO: Marketing/Growth) e 16 (CAO: Parcerias B2B)

Auditoria de **25 itens**.

---

## LENTE 13 — Middleware & Routing (profundo)

### 🔴 [13.1] `ADMIN_ONLY_ROUTES` + `ADMIN_PROFESSOR_ROUTES` — **ordem importa, e está errada**

**Achado** — `portal/src/middleware.ts:16-23` define:

```16:23:portal/src/middleware.ts
const ADMIN_ONLY_ROUTES = [
  "/credits/history",
  "/credits/request",
  "/billing",
  "/settings",
];

const ADMIN_PROFESSOR_ROUTES = ["/engagement/export", "/settings/invite"];
```

Como linhas 149 e 155 usam `pathname.startsWith(r)` **em sequência**, o `/settings` (ADMIN_ONLY_ROUTES) captura **primeiro** `/settings/invite`. Um `coach` que deveria ter acesso a `/settings/invite` (ADMIN_PROFESSOR_ROUTES) recebe `403`.

**Risco** — Bug funcional: coaches são bloqueados de enviar convites, UI oferece o botão mas API/middleware retorna 403. Suporte recebe tickets "não consigo convidar".

**Correção** — Verificar exceções **antes** do prefixo genérico:

```typescript
const isAdminProfessorRoute = ADMIN_PROFESSOR_ROUTES.some((r) => pathname.startsWith(r));
const isAdminOnlyRoute =
  !isAdminProfessorRoute &&
  ADMIN_ONLY_ROUTES.some((r) => pathname.startsWith(r));

if (isAdminProfessorRoute) {
  if (role !== "admin_master" && role !== "coach") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
} else if (isAdminOnlyRoute) {
  if (role !== "admin_master") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
}
```

Ou usar regex mais específico: `const ADMIN_ONLY_ROUTES = [/^\/settings$/, /^\/settings\/(?!invite).+/]`.

**Teste** — `middleware.test.ts`: user com role `coach` acessando `/settings/invite` → 200/allowed; acessando `/settings/general` → 403.

---

### 🔴 [13.2] Nome da constante ainda em **português** (`ADMIN_PROFESSOR_ROUTES`)

**Achado** — Linha 23 ainda usa `PROFESSOR`, apesar da migration `20260304050000_fix_coaching_role_mismatch.sql` renomear role `professor → coach`. É inconsistência que revela que a migração não foi propagada ao código TypeScript.

**Risco** — Dev novo vai procurar `ADMIN_COACH_ROUTES`, não encontra, implementa errado. Sintoma de **debt semântico** generalizado (verificar outros lugares).

**Correção** — Rename + grep do repo inteiro:

```bash
rg -l "professor|assessoria|assistente" portal/src omni_runner/lib supabase
```

Mapear legacy Portuguese → English consistently.

---

### 🔴 [13.3] Middleware executa **query DB** a cada request autenticado

**Achado** — Linhas 81-88: `SELECT role FROM coaching_members WHERE user_id=X AND group_id=Y` a **cada request**. Linhas 49-53: `SELECT platform_role FROM profiles WHERE id=X` a cada request em `/platform/**`.

Para uma navegação normal em `/platform/dashboard` que traz 15 RSCs + 8 chamadas `/api/*`, são **23 queries a `profiles`** — cada uma com round-trip Supabase ~50 ms.

**Risco** — Latência percebida em dashboard administrativo pior que produto. Em pico, esgota pool de conexões Supabase (default 15 conexões por instância).

**Correção** —

1. **Edge cache em cookie assinado** (JWT-claim-lite):

```typescript
// Include platform_role and membership inside the supabase JWT as custom claims
// via a DB function + auth.jwt() hook (Supabase "Add custom claims" feature).
// Then read from JWT on every request with zero DB hit.
```

2. **Se manter query**, cachear em Redis por 60 s:

```typescript
const cacheKey = `auth:${user.id}:${groupId}`;
const cached = await getRedis().get(cacheKey);
if (cached) { role = cached; } else {
  // ... query ...
  await getRedis().setex(cacheKey, 60, membership.role);
}
```

3. **Invalidation**: ao mudar `platform_role` ou `coaching_members.role`, invalidar via trigger SQL + `PERFORM pg_notify('cache_invalidate', …)`.

**Teste** — `middleware.perf.test.ts`: navegar 5 páginas → total de DB queries cachadas via spy deve ser ≤ 1 (depois cache hit) em request 2+.

---

### 🟠 [13.4] `/select-group` **não está em AUTH_ONLY_PREFIXES nem PUBLIC** → comportamento indefinido

**Achado** — Lógica de multi-membership (linhas 138-144) redireciona para `/select-group` sem cookie. Na próxima request, middleware vê user autenticado, cookie ausente, e re-entra no branch `!groupId || !role` → `memberships.length > 1` → **redireciona de novo para `/select-group`**. Só retorna `supabaseResponse` se `pathname === "/select-group"` (linha 139).

Isso **funciona**, mas é frágil: se `/select-group` page fizer um `fetch("/api/...")` sem cookie, a API recebe request com `portal_group_id` ausente. API pode retornar 400 ou assumir comportamento inesperado.

**Correção** — Adicionar `/select-group` em `PUBLIC_ROUTES` (exige auth user mas não exige group) e documentar contrato.

---

### 🟠 [13.5] Cookies **sem `Secure`** explícito

**Achado** — Linhas 97-102, 125-136: `supabaseResponse.cookies.set(...)` sem `secure: true`. Em Vercel produção pode receber flag auto, mas **não em staging** com domínio customizado HTTP→HTTPS redirect.

**Risco** — Cookie leak sobre HTTP em redirect intermediário (DNS poisoning MitM).

**Correção** —

```typescript
const isProd = process.env.NODE_ENV === "production";
const cookieOpts = {
  path: "/",
  httpOnly: true,
  sameSite: "lax" as const,
  secure: isProd,
  maxAge: 60 * 60 * 8,
};
```

---

### 🟠 [13.6] `x-request-id` **não propagado ao supabase/lib downstream**

**Achado** — Linhas 161-162 setam no `supabaseResponse.headers` (resposta). Mas o header **não é injetado no `request`** — RSCs e API handlers fazendo `createServerClient()` não têm acesso ao request-id.

**Correção** —

```typescript
const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();
const requestHeaders = new Headers(request.headers);
requestHeaders.set("x-request-id", requestId);

const response = NextResponse.next({ request: { headers: requestHeaders } });
response.headers.set("x-request-id", requestId);
```

Depois RSC lê via `headers().get("x-request-id")`.

---

### 🟠 [13.7] `PUBLIC_ROUTES` contém `/api/custody/webhook` sem **IP allow-list**

**Achado** — Linha 4: webhook exposto em endpoint público. Relacionado a [1.17] — MP webhook não tem HMAC.

**Correção** — Middleware checar `request.ip` contra allow-list configurada por gateway:

```typescript
if (pathname === "/api/custody/webhook") {
  const ip = request.ip ?? request.headers.get("x-forwarded-for")?.split(",")[0];
  if (!PAYMENT_GATEWAY_IPS.includes(ip)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
}
```

Lista mantida em env: Stripe publica ranges; MP publica em doc.

---

### 🟡 [13.8] PUBLIC_PREFIXES `/challenge/`, `/invite/` podem colidir com `/api/challenge/`

**Achado** — `pathname.startsWith("/challenge/")` também retorna `true` para `/challenge/123/admin-only-action`? Se existir, admin action vira pública.

**Correção** — Regex explícito `^/challenge/[a-z0-9-]+$` ou `/challenge` SOMENTE GET.

---

### 🟡 [13.9] Middleware **redirect chain** em single-membership causa duplo round-trip

**Achado** — Linhas 124-137: cria redirect set-cookie, browser vai, middleware roda de novo, agora encontra cookie. Dois requests para um primeiro acesso. UX: 200 ms extra.

**Correção** — Set cookie no **mesmo response** + let RSC ler via `cookies()` imediatamente (cookies set no middleware response propagam ao RSC da mesma navigation em Next.js 14+). Eliminar redirect:

```typescript
supabaseResponse.cookies.set("portal_group_id", groupId, cookieOpts);
supabaseResponse.cookies.set("portal_role", role, cookieOpts);
return supabaseResponse;  // no redirect
```

Verificar se Next 14.2.x entrega cookie na mesma navigation.

---

## LENTE 14 — API Contracts & Versioning

### 🔴 [14.1] **74 route handlers, 46 documentados** em OpenAPI

**Achado** — `find portal/src/app/api -name route.ts` → 74 arquivos. `grep '"/api' openapi.json` → 46 matches. **~28 endpoints não documentados**.

**Risco** — Parceiros B2B chamam endpoints sem contrato. Devs mudam signature, clientes quebram sem aviso.

**Correção** — Contract-first:

1. Adotar **tRPC** (type-safe RPC gerando client TS) OU
2. Gerar OpenAPI a partir dos Zod schemas com `@asteasolutions/zod-to-openapi`:

```typescript
// portal/src/lib/openapi.ts
import { OpenAPIRegistry, OpenApiGeneratorV31 } from "@asteasolutions/zod-to-openapi";
import { distributeCoinsSchema, custodyDepositSchema, ... } from "./schemas";

export const registry = new OpenAPIRegistry();
registry.registerPath({
  method: "post", path: "/api/distribute-coins",
  request: { body: { content: { "application/json": { schema: distributeCoinsSchema } } } },
  responses: { 200: { description: "ok" }, 422: { description: "validation" } },
});
// ... for all 74

// Regenerate openapi.json in CI; fail if drift
```

CI step: `diff public/openapi.json <(npm run generate-openapi)` → falha se diff.

---

### 🔴 [14.2] **Sem versionamento** de path (`/api/v1`)

**Achado** — Rotas são `/api/custody`, `/api/swap`, `/api/distribute-coins`. Primeira mudança quebra:

- App mobile versão < atual em campo
- Integração de parceiro B2B
- Scripts internos de BI

**Correção** — Migration gradual:

1. Mover endpoints financeiros críticos (`/api/custody`, `/api/swap`, `/api/distribute-coins`, `/api/clearing`, `/api/custody/withdraw`) para `/api/v1/...`.
2. Retornar header `Sunset: Wed, 01 Jan 2027 00:00:00 GMT` nas rotas sem versão.
3. Responses incluem `X-Api-Version: 1`.

---

### 🔴 [14.3] `/api/docs` **carrega Swagger-UI de `unpkg` sem SRI**

**Achado** — `portal/src/app/api/docs/route.ts:29-30`:

```29:30:portal/src/app/api/docs/route.ts
  <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js" crossorigin></script>
  <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-standalone-preset.js" crossorigin></script>
```

**Sem integridade (SRI)**. CDN unpkg comprometido → atacante injeta JS em `/api/docs` (página que admins fazem login para explorar API) → rouba cookies, service-role via network inspection.

Adicionalmente, `script-src 'unsafe-inline'` já é relaxada [1.31] — então script inline dentro da página também é executado.

**Correção** —

```html
<script
  src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js"
  integrity="sha384-..."
  crossorigin="anonymous"
></script>
```

Melhor: self-host em `/public/vendor/swagger-ui/...` (download artefatos, commit, imutável).

---

### 🟠 [14.4] Rate-limit **por IP** em swap/custody vs **por user/group**

**Achado** — `portal/src/app/api/swap/route.ts:60,76` faz `rateLimit("swap:" + ip, …)`. IP atrás de CGN/NAT móvel é compartilhado entre milhares.

**Risco** — Vários grupos compartilham mesmo IP → um grupo ativo bloqueia outros.

**Correção** —

```typescript
const key = `swap:${auth.groupId ?? ip}`;
const rl = await rateLimit(key, { maxRequests: 30, windowMs: 60_000 });
```

---

### 🟠 [14.5] Respostas de erro **não padronizadas** (`error: string` vs `error: { code, message }`)

**Achado** —

```143:143:portal/src/app/api/swap/route.ts
    return NextResponse.json({ error: "Operação falhou. Tente novamente." }, { status: 422 });
```

vs

```87:88:portal/src/app/api/athletes/route.ts
      { ok: false, error: { code: "INTERNAL_ERROR" } },
```

Cliente não consegue tratar erros consistentemente.

**Correção** — Formato único `{ ok: false, error: { code, message, request_id } }` em todas as respostas de erro. Middleware de erro compartilhado:

```typescript
// portal/src/lib/api/errors.ts
export function apiError(code: string, message: string, status: number, reqId?: string) {
  return NextResponse.json(
    { ok: false, error: { code, message, request_id: reqId } },
    { status }
  );
}
```

---

### 🟠 [14.6] **Pagination** inconsistente (ou inexistente)

**Achado** — `GET /api/athletes` retorna todos (sem `limit`, `offset`, `cursor`). Grupo com 5000 atletas envia payload de MB.

**Correção** — Cursor-based pagination padrão:

```typescript
GET /api/v1/athletes?cursor=xyz&limit=50
→ { items: [...], next_cursor: "abc", has_more: true }
```

Limite máximo server-side 100.

---

### 🟡 [14.7] Sem **idempotency-key** header em POSTs financeiros

**Achado** — Relacionado a [1.5]. Padrão Stripe: `Idempotency-Key: <uuid>` header aceito em POST, retry seguro no cliente.

**Correção** —

```typescript
const idemKey = req.headers.get("idempotency-key");
if (!idemKey || !isUUID(idemKey)) {
  return apiError("IDEMPOTENCY_REQUIRED", "…", 400);
}
// Store {idem_key → response} for 24h; replay on retry
```

---

### 🟡 [14.8] **Content negotiation** inexistente

**Achado** — Todos endpoints hardcoded `application/json`. Export CSV precisa de endpoint separado `/api/export/...` vs `/api/... (Accept: text/csv)`.

**Correção** — Single endpoint, negocia via `Accept` header. OpenAPI doc descreve.

---

### 🟡 [14.9] **Sem quota por parceiro** (API key tier)

**Achado** — Mesmo se amanhã abrir API para parceiros, não há `api_keys` table com `tier` (free/pro/enterprise), quota diária, scopes.

**Correção** — Já coberto em LENTE 16 ([16.3]).

---

## LENTE 15 — CMO (Chief Marketing Officer): Marketing, Growth, Viralização

### 🟠 [15.1] **Zero UTM tracking** no produto

**Achado** — `grep "utm_source|utm_medium" portal/src omni_runner/lib` → **0 matches**. Campanhas de marketing não podem atribuir conversões.

**Risco** — CMO gasta R$ 50k em Google Ads → não consegue saber se CAC é R$ 10 ou R$ 500. Decisões de budget no escuro.

**Correção** —

```typescript
// portal/src/lib/attribution.ts
export function captureUtmFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const utm = ["source","medium","campaign","term","content"].reduce((acc, k) => {
    const v = params.get(`utm_${k}`);
    if (v) acc[k] = v;
    return acc;
  }, {} as Record<string, string>);
  if (Object.keys(utm).length) {
    document.cookie = `utm=${btoa(JSON.stringify({...utm, t: Date.now()}))}; path=/; max-age=${90*86400}`;
  }
}

// On signup, attach utm cookie to profile
```

```sql
ALTER TABLE profiles ADD COLUMN attribution jsonb;
-- Examples: {"source":"google","medium":"cpc","campaign":"brand","landing":"/","first_seen_at":"2026-04-15"}
```

---

### 🟠 [15.2] **Sem sistema de referral/convite viral**

**Achado** — Grep `referral|referrals|convide_amigo` → zero em SQL. Crescimento orgânico viral impossível.

**Risco** — CAC permanece alto; não há mecanismo para atleta trazer atleta (viralização natural em esporte social).

**Correção** —

```sql
CREATE TABLE public.referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id uuid NOT NULL REFERENCES auth.users(id),
  referred_user_id uuid REFERENCES auth.users(id),
  referral_code text NOT NULL UNIQUE,
  channel text,  -- 'whatsapp','instagram','email','link'
  reward_referrer_coins int DEFAULT 10,
  reward_referred_coins int DEFAULT 5,
  status text DEFAULT 'pending' CHECK (status IN ('pending','activated','expired')),
  activated_at timestamptz,
  created_at timestamptz DEFAULT now()
);
```

Mobile: tela "Convide 3 amigos → ganhe 30 coins"; deep link `omnirunner://ref/CODE`.

---

### 🟠 [15.3] Social sharing **sem Open Graph dinâmico**

**Achado** — `grep 'og:image' portal/src` → minimo. Corrida compartilhada no WhatsApp/Instagram gera preview genérico.

**Correção** — Next.js App Router: `generateMetadata` por página + endpoint OG image dinâmico:

```typescript
// /app/run/[id]/opengraph-image.tsx
import { ImageResponse } from 'next/og';
export default async function Image({ params }) {
  const run = await fetchRun(params.id);
  return new ImageResponse(<div>{run.distance_km} km em {run.pace}</div>);
}
```

Viralização natural quando atleta compartilha corrida.

---

### 🟠 [15.4] **Sem email transactional platform**

**Achado** — Grep `resend|postmark|sendgrid|mailgun` em `portal/src` e Edge Functions → zero provider integrado. Supabase Auth envia email de confirmação via SMTP padrão (quota limitada).

**Risco** — Notificações importantes ("seu withdraw foi processado") não chegam ou caem em spam.

**Correção** — Integrar Resend ou Postmark; templates versionados em `supabase/email-templates/`; log de entregas.

---

### 🟡 [15.5] **Sem landing pages** SEO-otimizadas

**Achado** — Portal é "logged app first"; não tem `/running-with-coaches`, `/marathon-training-plan`, etc. Tráfego orgânico search zero.

**Correção** — `/app/(marketing)/[slug]/page.tsx` com MDX + schema.org SportsActivity + sitemap.xml.

---

### 🟡 [15.6] **Sem A/B testing framework**

**Achado** — Grep `flag|experiment|split|statsig|amplitude|growthbook` → zero. Pricing, onboarding, CTA textos — todos decididos por gut feeling.

**Correção** — GrowthBook (self-hosted) ou Flagsmith; experimentos logam variante em `product_events`.

---

### 🟡 [15.7] Wrapped (já existe) **não é compartilhável fora do app**

**Achado** — `supabase/functions/generate-wrapped/` e `wrapped_screen.dart` geram página interna. Sem URL pública `/wrapped/[user]/2026` com imagem social.

**Correção** — Exportar como página SEO-friendly + OG image; slug único, opt-in "compartilhar publicamente".

---

### 🟡 [15.8] **Sem push segmentation**

**Achado** — `supabase/functions/send-push` provavelmente envia broadcast ou user-specific. Sem segmentação por perfil (elites, iniciantes, coach, inativos 30 dias).

**Correção** — Tabela `user_segments` com queries SQL + UI `/platform/marketing/campaigns` para CMO disparar push para segmento.

---

## LENTE 16 — CAO (Chief Acquisitions Officer): Parcerias B2B, White-Label, Ecossistema

### 🟠 [16.1] Sem **white-label / branding** customizado por grupo

**Achado** — `portal/src/app/api/branding/` existe mas auditoria rápida sugere mínimo. Grupo grande (ex.: "Corredores do Morumbi" com 3000 atletas) quer app com cor/logo próprios no mobile.

**Correção** — `ALTER TABLE coaching_groups ADD COLUMN branding jsonb` com `{primary_color, logo_url, custom_domain}`. Flutter lê via `group_details` endpoint e aplica no ThemeData. Portal aplica via CSS var.

---

### 🟠 [16.2] Sem **custom domain** por assessoria

**Achado** — Todos acessam `portal.omnirunner.app`. Clube grande quer `portal.corredoresmorumbi.com.br`.

**Correção** —

1. `coaching_groups.custom_domain text UNIQUE`.
2. Next.js middleware mapeia Host → group_id.
3. Vercel API: adicionar domain programaticamente via API `POST /v9/projects/.../domains`.
4. Auto-provisionar SSL (Let's Encrypt via Vercel).

---

### 🔴 [16.3] **Sem API pública** para parceiros B2B

**Achado** — Grep `api_key|api_keys|partner_api` → zero tabelas. Expansão B2B exige integração com:

- Strava (já existe — como parceiro Omni)
- Garmin Connect
- Polar Flow
- Suunto
- Marca esportiva X para campanha conjunta
- ERP/CRM do cliente (assessoria grande com RD Station)

**Risco** — Bloqueio de parcerias estratégicas = limite de receita B2B.

**Correção** —

```sql
CREATE TABLE public.api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key_prefix text NOT NULL UNIQUE,  -- "or_live_XXXX" (first 8 chars visible)
  key_hash bytea NOT NULL,  -- SHA-256 of the full key
  group_id uuid REFERENCES coaching_groups(id),
  partner_name text,
  scopes text[] NOT NULL DEFAULT '{}',  -- 'athletes:read','sessions:read','coins:write'
  rate_limit_per_min int DEFAULT 60,
  quota_per_day int DEFAULT 10000,
  used_today int DEFAULT 0,
  valid_until timestamptz,
  revoked_at timestamptz,
  last_used_at timestamptz,
  created_by uuid,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix) WHERE revoked_at IS NULL;
```

+ Endpoint `/api/v1/...` com middleware que aceita `Authorization: Bearer or_live_XXX` OU cookie session. Header scopes checked.

---

### 🟠 [16.4] Sem **outbound webhooks** para parceiros

**Achado** — Sistema recebe webhooks (Stripe/MP/Asaas/Strava), mas não **emite**. Parceiro B2B que quer receber "quando atleta do meu clube completa corrida, me avise" não tem canal.

**Correção** —

```sql
CREATE TABLE public.outbound_webhooks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL,
  url text NOT NULL,
  secret text NOT NULL,  -- signed HMAC
  events text[] NOT NULL,  -- 'session.verified','coin.distributed','championship.ended'
  enabled boolean DEFAULT true,
  last_delivery_at timestamptz,
  last_delivery_status int,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE public.webhook_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id uuid REFERENCES outbound_webhooks(id),
  event text NOT NULL,
  payload jsonb NOT NULL,
  status_code int,
  attempt int DEFAULT 1,
  next_retry_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz DEFAULT now()
);
```

Cron `*/1 * * * *` processa `webhook_deliveries` onde `status_code != 200 AND attempt < 5` com backoff.

---

### 🟠 [16.5] **Integrações de marcas esportivas** sem schema

**Achado** — Nike, Asics, Mizuno patrocinam atletas — produto não tem `sponsorships` table nem `team_equipment_recommendations`.

**Correção** —

```sql
CREATE TABLE public.sponsorships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES coaching_groups(id),
  brand text NOT NULL,
  contract_start date,
  contract_end date,
  monthly_coins_to_athletes int DEFAULT 0,
  equipment_discount_pct numeric(4,1),
  partner_api_key_id uuid REFERENCES api_keys(id)
);
```

---

### 🟠 [16.6] **Strava / TrainingPeaks OAuth** sem telemetria de uso

**Achado** — `strava-webhook`, `trainingpeaks-sync` existem. Sem dashboard interno de: "% de atletas conectados ao Strava", "eventos/dia", "erros de sync".

**Risco** — Feature flagship ruim → churn sem diagnóstico.

**Correção** — Event `integration.strava.session_imported` + dashboard `/platform/integrations`.

---

### 🟡 [16.7] **TrainingPeaks** OAuth client credentials em env

**Achado** — Edge Function `trainingpeaks-oauth` usa `TP_CLIENT_ID` / `TP_CLIENT_SECRET`. Compartilhados globalmente — todos os clubes usam a mesma conexão.

**Correção** — Cada clube cria sua própria integração (se tier enterprise). Armazenar credentials encriptados em `integration_credentials` por group_id.

---

### 🟡 [16.8] Sem **marketplace** de treinos/planos

**Achado** — `training-plan` module existe (1500+ linhas de migration). Mas não há "comprar plano de maratona do Coach X" entre grupos.

**Correção** — `plan_listings` table + checkout com `platform_revenue` recebendo taxa de marketplace.

---

### 🟡 [16.9] **SSO SAML/OIDC** para enterprise

**Achado** — Supabase Auth suporta SAML Enterprise plan. Não configurado. Assessorias grandes com AD corporativo forçadas a criar login individual.

**Correção** — Em expansão enterprise: Supabase SSO + `identity_providers` table por group_id.

---

### 🟡 [16.10] **Sem tier "free trial" / sandbox** para parceiros

**Achado** — Integração B2B exige primeiro contrato, risco. Parceiro quer testar antes. Sem ambiente `sandbox.omnirunner.com`.

**Correção** — Supabase project separado para sandbox; API keys com prefix `or_test_`.

---

## RESUMO PARTE 6 (25 itens)

| Severidade | Quantidade | IDs |
|---|---|---|
| 🔴 CRÍTICO | 6 | 13.1, 13.2, 13.3, 14.1, 14.2, 14.3, 16.3 |
| 🟠 ALTO | 12 | 13.4–13.7, 14.4–14.6, 15.1–15.4, 16.1, 16.2, 16.4–16.6 |
| 🟡 MÉDIO | 7 | 13.8, 13.9, 14.7–14.9, 15.5–15.8, 16.7–16.10 |

### Decisões de produto/arquitetura exigidas antes de corrigir:

1. **[14.2] Versionamento de API** — quanto tempo manter `/api/...` sem versão durante transição? SLA para clientes mobile antigos? Decidir antes de escrever a primeira linha de `/api/v1/`.
2. **[16.3] API pública para parceiros** — modelo de pricing (grátis, por transação, por tier), SLA (99,9 %?), suporte 24/7? CAO precisa alinhar com CFO.
3. **[15.2] Referral system** — valor de recompensa, cap por usuário, fraud detection. Produto + growth + finance.
4. **[13.1] Bug de routing** — correção rápida (minutos), mas revela ausência de testes de middleware que cubram interseções de políticas.

---

**CONTINUA NA PARTE 7** — Lentes 17 (VP Engineering — organização do código), 18 (Principal Engineer — arquitetura em profundidade), 19 (DBA — SQL, performance, locking), 20 (SRE — observabilidade, incident, SLO), totalizando ~40 itens.

Digite **"continue"** para prosseguir para a PARTE 7.

 Looking at the middleware configuration, I'm noticing that the webhook endpoint for Stripe and Mercado Pago is marked as public, which creates a vulnerability since Mercado Pago webhooks don't have HMAC verification and lack replay protection. I'm also seeing that the admin routes still reference the Portuguese variable name "professor" instead of using a standardized English term.

The platform admin check runs a database query on every request without caching, adding at least 100ms of overhead, and the coaching members verification re-queries the database on every request if a cookie exists. The cookie security settings are problematic too—`sameSite: "lax"` leaves the system open to top-level CSRF attacks, and while `httpOnly` is set correctly, the `secure` flag isn't explicitly configured, relying instead on Vercel's environment settings.

There's also a UX issue where finding a single membership triggers an immediate redirect that causes an extra round-trip and loading flash, and the multi-membership flow redirects to `/select-group` without setting any group cookie, so users arrive at that page with no context. The request ID is generated but never attached as a header for downstream services to use, and the admin routes check uses `startsWith` on `/settings`, which could match unintended paths.

Looking at the API layer, the OpenAPI spec is incomplete—there are 74 route files but only 46 documented paths, and there's no API versioning scheme, so any breaking changes would immediately break all clients. The Swagger UI is loaded from an unpkg CDN without subresource integrity, creating a supply chain attack surface, and there's no version header enforcement or response versioning either.

Moving into the business lens, there's no marketing infrastructure at all—no UTM tracking, referral system, email platform integration, or attribution modeling beyond basic funnel events. On the partner side, there's no API key management, outbound webhooks, white-label capabilities, or integration documentation, though Strava and TrainingPeaks integrations show the pattern exists.