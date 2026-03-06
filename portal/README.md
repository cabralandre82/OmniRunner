# Omni Runner — Portal

Portal B2B para gestão de assessorias esportivas. Permite gerenciar atletas, distribuir créditos, acompanhar verificação e engajamento.

## Stack

- **Framework:** Next.js 14 (App Router)
- **Linguagem:** TypeScript
- **Estilo:** Tailwind CSS
- **Backend:** Supabase (PostgreSQL, Auth, Edge Functions)
- **Testes:** Vitest + Testing Library
- **Pagamentos:** Stripe / MercadoPago

## Setup Local

```bash
# 1. Instalar dependências
npm ci

# 2. Configurar variáveis de ambiente
cp .env.example .env.local
# Preencher NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY e SUPABASE_SERVICE_ROLE_KEY

# 3. Rodar em desenvolvimento
npm run dev
```

O portal estará disponível em `http://localhost:3000`.

## Variáveis de Ambiente

| Variável | Obrigatória | Descrição |
|----------|:-----------:|-----------|
| `NEXT_PUBLIC_SUPABASE_URL` | Sim | URL do projeto Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Sim | Chave anônima do Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Sim | Chave de serviço (server-only, nunca expor ao browser) |
| `NEXT_PUBLIC_SENTRY_DSN` | Não | DSN do Sentry (error tracking, apenas produção) |
| `SENTRY_ORG` | Não | Organização Sentry (para upload de sourcemaps) |
| `SENTRY_PROJECT` | Não | Projeto Sentry |
| `SENTRY_AUTH_TOKEN` | Não | Token de auth Sentry (CI only) |

## Testes

```bash
# Rodar todos os testes
npm test

# Rodar com watch mode
npm run test:watch

# Rodar com coverage
npm run test:coverage
```

## Build

```bash
npm run build
```

## Estrutura de Diretórios

```
src/
├── app/                    # App Router pages e layouts
│   ├── (portal)/           # Páginas autenticadas do portal
│   ├── api/                # API routes
│   ├── platform/           # Páginas do admin da plataforma
│   └── login/              # Página de login
├── components/             # Componentes reutilizáveis
│   ├── sidebar.tsx         # Navegação lateral
│   ├── header.tsx          # Header com ações
│   └── ui/                 # Design system (PageHeader, KpiCard, StatusBadge, etc.)
├── lib/                    # Utilitários e lógica compartilhada
│   ├── supabase/           # Clients Supabase (server, service)
│   ├── actions.ts          # Server Actions
│   ├── audit.ts            # Audit logging
│   ├── logger.ts           # Structured logging
│   ├── rate-limit.ts       # Rate limiter
│   └── schemas.ts          # Zod validation schemas
└── test/                   # Test helpers e setup
```

## Modelo B2B — Custódia & Clearing

O Portal opera como infraestrutura de custódia e compensação interclub:

- **1 Coin = US$1.00** de lastro fixo (backing)
- Clubes depositam USD → ganham direito de emitir coins
- Cada coin registra `issuer_group_id` para rastreabilidade
- Queima de coins gera clearing automático entre clubes
- Taxa de clearing (configurável) é retida pela plataforma

### Fluxo E2E

```
Clube deposita USD → Emite coins (limitado ao lastro) → Atleta recebe coins
    → Atleta queima coins (QR) → Backend executa burn_plan atômico
    → Clearing event gerado → Compensação interclub automática
```

### Invariantes Críticas

- `D >= R` (depósitos >= reservados)
- `R = M` (reservados = coins em circulação por emissor)
- Swap não reduz backing abaixo do reservado

## API Surface

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `/api/custody` | GET/POST | Consultar/criar depósitos de lastro |
| `/api/clearing` | GET | Listar compensações (creditor/debtor) |
| `/api/swap` | GET/POST | Ofertas de swap de lastro B2B |
| `/api/distribute-coins` | POST | Distribuir coins para atletas |
| `/api/platform/fees` | GET/POST | Gerenciar taxas (clearing %, swap %, billing_split %, manutenção $USD/atleta) |
| `/api/platform/invariants` | GET | Verificar invariantes do sistema |
| `/api/platform/feature-flags` | GET/POST | Feature flags da plataforma |
| `/api/platform/assessorias` | GET | Listar assessorias |
| `/api/platform/products` | GET/POST | Gerenciar produtos (mutações via Server Actions com `revalidatePath`) |
| `/api/platform/refunds` | GET/POST | Gerenciar reembolsos |
| `/api/platform/liga` | GET/POST | Administração de ligas |
| `/api/platform/support` | GET/POST | Tickets de suporte |
| `/api/checkout` | POST | Iniciar checkout Stripe |
| `/api/billing-portal` | POST | Portal de billing Stripe |
| `/api/branding` | GET/POST | Identidade visual |
| `/api/team/invite` | POST | Convidar membro |
| `/api/team/remove` | POST | Remover membro |
| `/api/export/athletes` | GET | Exportar CSV de atletas |
| `/api/verification/evaluate` | POST | Reavaliar verificação |
| `/api/gateway-preference` | POST | Preferência de gateway |
| `/api/auto-topup` | POST | Configurar recarga automática |
| `/api/health` | GET | Health check |

## CI/CD

O pipeline roda via GitHub Actions (`.github/workflows/portal.yml`):
1. **Lint & Typecheck** — `tsc --noEmit` + `next lint`
2. **Testes** — `vitest` com coverage report
3. **Build** — `next build`
4. **E2E** — Playwright (chromium)

Coverage reports são salvos como artifacts no CI.

## Segurança

- **CSP, HSTS, X-Frame-Options** — via `next.config.mjs` headers
- **Webhook validation** — `src/lib/webhook.ts` (Stripe HMAC-SHA256)
- **CSRF protection** — `src/lib/csrf.ts` (Origin/Referer check)
- **Rate limiting** — `src/lib/rate-limit.ts` (pluggable, Redis-ready)
- **RLS** — Row Level Security no Supabase
- **Audit logging** — `src/lib/audit.ts`

## Roles do Portal

| Role | Acesso |
|------|--------|
| `admin_master` | Acesso total (billing, team, settings, Saldo OmniCoins, Distribuir OmniCoins, Histórico de Cobranças) |
| `coach` | Atletas, Distribuir OmniCoins, Transferências OmniCoins, verificação, engajamento, treinos |
| `assistant` | Atletas, verificação, engajamento, treinos (somente leitura) |
| `platform_admin` | Admin da plataforma (assessorias, fees com rate_usd, invariantes, produtos, suporte) |
