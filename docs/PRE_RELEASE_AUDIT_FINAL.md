# AUDITORIA PRE-RELEASE FINAL — OMNI RUNNER v0.94.0

**Data:** 2026-03-08
**Auditor:** IA atuando como Principal Engineer + Lead QA + CTO + CFO + UX Lead
**Escopo:** Flutter App (599 arquivos Dart, 129K LOC) + Portal Next.js (355 arquivos TS/TSX) + Supabase Backend (131 migrações + 28 Edge Functions)
**Build analisado:** `app-prod-release.apk` (138.8MB)

---

## RESUMO EXECUTIVO

| Dimensão | Score | Veredicto |
|----------|-------|-----------|
| Code Health | 92/100 | 0 erros, 0 warnings. 630 infos (maioria cosmético) |
| Segurança de Segredos | 98/100 | .env no .gitignore, 0 secrets em código |
| Arquitetura & DI | 62/100 | 5 rotas mortas, 50 telas com Supabase direto |
| Schema & RLS | 70/100 | 3 tabelas sem RLS, funções sem search_path |
| Motor Financeiro | 55/100 | issuer_group_id nunca preenchido, webhook bypass |
| Auth & Autorização | 65/100 | Webhook bloqueado, 3 API routes sem auth |
| Integridade de Dados | 82/100 | Drift sólido, mas sem FKs e 3 uniques faltando |
| UX/UI | 68/100 | ~400 strings hardcoded, exceções raw no UI |
| Performance | 60/100 | Portal sem cache, queries unbounded, N+1 |
| Lógica de Negócio | 80/100 | 1 bug crítico (elevação), desafios sem refund |
| Prontidão de Mercado | 54/100 | Privacy policy stub, sem screenshots, cold-start |
| **SCORE GERAL** | **68/100** | **CONDITIONAL GO para beta fechado** |

---

## BLOQUEADORES CRÍTICOS (P0) — 10 itens

Estes devem ser corrigidos ANTES de qualquer release, mesmo beta:

### 1. [FINANCIAL] `issuer_group_id` nunca preenchido no coin_ledger
- **Arquivo:** `supabase/functions/token-consume-intent/index.ts:250`
- **Impacto:** Todo o sistema de clearing/compensação interclub está silenciosamente desabilitado. Toda moeda emitida é tratada como "legacy" sem emissor.
- **Fix:** Adicionar `issuer_group_id: intent.group_id` no INSERT + backfill migration

### 2. [AUTH] Webhook de custódia bloqueado pelo middleware
- **Arquivo:** `portal/src/middleware.ts:4`
- **Impacto:** Stripe/MercadoPago POSTs para `/api/custody/webhook` recebem redirect 307 para /login. Confirmação de depósitos quebrada em produção.
- **Fix:** Adicionar `"/api/custody/webhook"` ao `PUBLIC_ROUTES`

### 3. [FINANCIAL] Bypass de autenticação do webhook Asaas
- **Arquivo:** `supabase/functions/asaas-webhook/index.ts:107-118`
- **Impacto:** 3 condições permitem webhooks não autenticados: groupId null, webhook_token null, config não encontrada. Atacante pode forjar PAYMENT_CONFIRMED.
- **Fix:** Rejeitar webhooks quando groupId é null ou webhook_token não configurado

### 4. [BUSINESS] Bug de elevação — championship soma distância em vez de elevação
- **Arquivo:** `supabase/functions/champ-update-progress/index.ts:168-170`
- **Impacto:** Campeonatos com métrica "elevation" produzem ranking idêntico a "distance". Resultados incorretos.
- **Fix:** Adicionar coluna `total_elevation_m` ao sessions, computar elevação real, corrigir query

### 5. [DATABASE] `coin_ledger_archive` sem RLS
- **Arquivo:** `supabase/migrations/20260320000000`
- **Impacto:** Dados financeiros históricos acessíveis por qualquer usuário autenticado
- **Fix:** `ALTER TABLE coin_ledger_archive ENABLE ROW LEVEL SECURITY` + policies

### 6. [DATABASE] `fn_remove_member` e `fn_join_as_professor` sem search_path
- **Arquivos:** `supabase/migrations/20260321000000:344,378`
- **Impacto:** SECURITY DEFINER sem search_path = vulnerável a search_path hijacking
- **Fix:** Adicionar `SET search_path = public, pg_temp`

### 7. [AUTH] 3 API routes sem autenticação
- `/api/workouts/assign` — sem `getUser()`, sem role check
- `/api/financial/subscriptions` — sem `getUser()`, sem role check
- `/api/financial/plans` (DELETE) — sem `getUser()`
- **Fix:** Adicionar auth + role checks + rate limiting

### 8. [AUTH] `/api/set-group` aceita groupId/role do client sem validar membership
- **Arquivo:** `portal/src/app/api/set-group/route.ts:10-22`
- **Impacto:** Staff pode setar cookies para grupos que não pertence
- **Fix:** Validar membership antes de setar cookies, mudar para POST

### 9. [PERFORMANCE] Portal athletes page sem LIMIT
- **Arquivo:** `portal/src/app/(portal)/athletes/page.tsx:40-45`
- **Impacto:** Carrega TODOS os atletas. Grupo com 2000 atletas = OOM
- **Fix:** Adicionar `.range(0, 99)` + paginação

### 10. [FINANCIAL] `asaas-batch` não inclui maintenance fee no Split
- **Arquivo:** `supabase/functions/asaas-batch/index.ts:104-188`
- **Impacto:** Assinaturas criadas via batch não cobram taxa de manutenção. Plataforma perde receita.
- **Fix:** Adicionar query de maintenance fee igual ao `asaas-sync`

---

## PROBLEMAS HIGH (P1) — 23 itens

### Arquitetura
- 5 rotas mortas (crash por falta de DI): `/events`, `/groups`, `/events/race`, `/groups/events`, `/coach-insights`
- 50 telas com `sl<SupabaseClient>()` direto na presentation layer (~95 call sites)
- 4 telas importando data layer diretamente

### Auth & Segurança
- Staff routes sem role guard no Flutter router (atleta pode navegar para /staff/*)
- `api_rate_limits` tabela sem RLS
- `fn_approve_join_request`/`fn_request_join` sem search_path
- `increment_rate_limit`/`cleanup_rate_limits` sem search_path
- Portuguese roles ainda aceitos em `fn_request_join` (default 'atleta')

### Financeiro
- Clearing/custody exceptions silenciosamente engolidas no `execute_burn_atomic`
- `fn_sum_coin_ledger_by_group` sempre retorna 0 (consequência do P0 #1)
- `asaas-batch` marca jobs como "completed" mesmo com falhas parciais

### Performance
- Portal: 55+ páginas com `force-dynamic`, zero cache Next.js
- Redis cache infrastructure exists mas usado em apenas 1 rota
- Dashboard/Engagement carregam todas sessions sem LIMIT
- CRM hard-cap 500 sem paginação real
- `settle-challenge` sem timeout guard no loop principal
- `settle-challenge` N+1 (5-8 queries por desafio)

### Negócio
- iOS GPS sem `AppleSettings` — background tracking vai falhar
- Nenhum mecanismo de withdraw/cancel de desafio (coins trancadas 7 dias)
- Pending challenge expiry não faz refund de entry fees
- Sem grace period em payment failure (PAYMENT_OVERDUE → late imediato)
- Sem dunning sequence (atleta não é notificado de pagamento falhado)
- Sem guided tour para staff de assessoria (23 telas complexas sem guia)

---

## PROBLEMAS MEDIUM (P2) — 42 itens

### Arquitetura & Código
- Sem BlocObserver centralizado
- Hierarquia de failures duplicada (core/errors/ vs domain/failures/)
- PostgrestException exposta na presentation layer
- Padrão de Bloc provision inconsistente (router vs screen-internal)
- 188 catch blocks sem tipo específico (`avoid_catches_without_on_clauses`)
- 30 deprecated member usages (Radio.groupValue, Share.share, etc)
- 4 uses de BuildContext across async gaps

### Database
- `_role_migration_audit` sem RLS
- ~23 functions com `search_path = public` sem `pg_temp`
- `fn_request_join` regression — default ainda 'atleta'
- Zero foreign keys no Drift schema local
- 3 tabelas sem unique constraints compostos

### Financeiro
- ISSUE flow não-atômico (partial failure perde tokens)
- Webhook subscription update sem optimistic locking
- Asaas webhook sem dead-letter queue
- `billing_split` fee invisível no portal UI
- Fees page header diz "Taxa (%)" mas maintenance usa USD
- `GRANT ALL` em tabelas financeiras para `authenticated`
- Custody invariant check é tautologia (sempre true)
- Distributions page usa service-role client

### UX/UI
- ~400 strings hardcoded em português (infra l10n existe mas não usada)
- 12 telas expõem exceções raw para o usuário
- `AppEmptyState` usa cor quase-branca em fundo branco (light mode)
- Sem conflict resolution server→local no cache
- Sem cleanup de dados locais antigos (DB cresce indefinidamente)

### Performance
- Service/Admin Supabase clients recriados por request (não singleton)
- Championship ranking usa UPDATE individual por participante
- Profile screen carrega todas sessions para SUM (deveria usar aggregate)
- Workout delivery carrega 500 templates de uma vez
- `KEYS` command em `invalidatePattern()` (O(N) blocking)

### Negócio
- Sem link entre workout executado e session GPS
- Sem compliance feedback para coach CRM
- 3DS-required auto-topup falha silenciosamente
- Campeonato cancelado não faz refund de badge credits
- Days 4-6 sem nudge de onboarding (gap no periodo crítico de churn)
- Workout assign screen possivelmente orphaned
- Solo athletes excluídos da economia (0 coins, sem participar de staked challenges)

---

## PROBLEMAS LOW (P3) — 28 itens

(Detalhes nos relatórios individuais por fase)

---

## MÉTRICAS DO CODEBASE

| Métrica | Valor |
|---------|-------|
| Arquivos Dart (lib/) | 599 |
| Linhas de código Dart | 129,173 |
| Arquivos TS/TSX (portal) | 355 |
| Migrações SQL | 131 (todas aplicadas) |
| Edge Functions | 28 |
| Tabelas Supabase | 100+ |
| RLS Policies | ~200 |
| Dart analyze errors | 0 |
| Dart analyze warnings | 0 |
| Dart analyze infos | 630 |
| Portal ESLint errors | 0 |
| Secrets expostos | 0 |
| APK size | 138.8 MB |
| Dependencies (Flutter) | 37 diretas + 52 upgradable |
| Dependencies (Portal) | 9 produção |

---

## VEREDICTO FINAL

### Para Beta Fechado (Firebase App Distribution): CONDITIONAL GO

**Condições mínimas (fix P0 1-10 acima):**
1. Corrigir `issuer_group_id` no token-consume-intent
2. Unbloquear webhook de custódia no middleware
3. Corrigir auth bypass do Asaas webhook
4. Fix bug de elevação ou desabilitar métrica elevation
5. Adicionar RLS ao `coin_ledger_archive`
6. Adicionar `search_path` às SECURITY DEFINER functions
7. Adicionar auth às 3 API routes desprotegidas
8. Validar membership no `/api/set-group`
9. Adicionar paginação na athletes page do portal
10. Adicionar maintenance fee ao `asaas-batch`

**Estimativa:** 3-5 dias de trabalho focado

### Para Google Play / App Store: NO GO

**Requer adicionalmente:**
- Privacy policy completa (LGPD compliant)
- Terms of service
- Screenshots e feature graphic para store
- Resolver cold-start problem (demo data, welcome coins, Strava history import)
- Eliminar exceções raw do UI
- Guided tour para assessoria staff
- Grace period + dunning para pagamentos
- Refund de entry fees em desafios expirados

**Estimativa:** 4-6 semanas adicionais

---

## RECOMENDAÇÃO ESTRATÉGICA

> **Ship para coaches primeiro. Eles trazem os atletas. A app store pode esperar.**

1. **Semana 1:** Fix P0 (10 itens) → Build beta → Firebase App Distribution
2. **Semana 2-3:** Fix P1 mais críticos (auth, financial, iOS GPS) → Onboard 5-10 assessorias
3. **Mês 2:** Fix P2 + store assets + landing page → Expandir para 50+ assessorias
4. **Mês 3:** Resolver cold-start + privacy + store listing → Public release

---

*Relatório gerado automaticamente. Relatórios detalhados por fase disponíveis nos agentes de auditoria.*
