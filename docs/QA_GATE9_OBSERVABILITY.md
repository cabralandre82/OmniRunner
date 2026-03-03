# GATE 9 — Observability

**Data**: 2026-03-03  
**Revisor**: CTO / Lead QA  
**Método**: Code review estático de logging, Sentry, request correlation, e instrumentação

---

## 9.1 Flutter Logging

### AppLogger (`omni_runner/lib/core/logging/logger.dart`)

Estrutura:
- Níveis: `debug`, `info`, `warn`, `error`, `critical`
- Backend: `dart:developer` log (strip em release)
- Hook externo: `onError` callback (conectado ao Sentry via `main.dart`)
- `minLevel` configurável (default `debug`, produção `info`)

### Adoção em Repositórios (`data/repositories_impl/*.dart`)

| Repositório | AppLogger Calls |
|-------------|----------------|
| supabase_crm_repo.dart | 13 |
| supabase_workout_repo.dart | 11 |
| supabase_financial_repo.dart | 9 |
| remote_token_intent_repo.dart | 9 |
| supabase_announcement_repo.dart | 8 |
| supabase_challenges_remote_source.dart | 8 |
| supabase_wearable_repo.dart | 7 |
| sync_repo.dart | 7 |
| supabase_training_attendance_repo.dart | 6 |
| supabase_training_session_repo.dart | 6 |
| supabase_progression_remote_source.dart | 5 |
| supabase_verification_remote_source.dart | 4 |
| supabase_badges_remote_source.dart | 4 |
| remote_switch_assessoria_repo.dart | 4 |
| profile_repo.dart | 4 |
| supabase_missions_remote_source.dart | 3 |

**Total**: 16/16 repositórios (100%) usam AppLogger.

### Adoção em BLoCs (`presentation/blocs/*/*.dart`)

| BLoC | AppLogger Calls |
|------|----------------|
| challenges_bloc.dart | 8 |
| my_assessoria_bloc.dart | 7 |
| announcement_feed_bloc.dart | 3 |
| crm_list_bloc.dart | 3 |
| workout_builder_bloc.dart | 3 |
| workout_assignments_bloc.dart | 3 |
| verification_bloc.dart | 3 |
| training_list_bloc.dart | 2 |

**Total**: 8 BLoCs com logging explícito. Demais BLoCs delegam logging ao repositório.

### Error Handler (`main.dart`)
- ✅ `FlutterError.onError` → `AppLogger.error('FlutterError', ...)`
- ✅ `PlatformDispatcher.instance.onError` → `AppLogger.error('PlatformError', ...)`
- ✅ `runZonedGuarded` → `AppLogger.error('Uncaught error', ...)`
- ✅ `ErrorWidget.builder` → fallback UI amigável
- ✅ `AppLogger.onError` → `Sentry.captureException` (quando Sentry configurado)
- ✅ `AppLogger.minLevel = LogLevel.info` em produção

**Resultado**: ✅ PASS — Logging estruturado e consistente em todas as camadas.

---

## 9.2 Portal Logging

### Logger (`portal/src/lib/logger.ts`)
- ✅ Existe e é importado
- Formato: JSON estruturado com `level`, `msg`, `ts`, `meta`
- Integração Sentry: `logger.error()` chama `Sentry.captureException()` para Errors e `Sentry.captureMessage()` para outros

### Adoção em API Routes

| Route | Logger Import | try-catch |
|-------|---------------|-----------|
| branding/route.ts | ✅ | ✅ (2 catches) |
| auto-topup/route.ts | ✅ | ✅ |
| export/athletes/route.ts | ✅ | ✅ |
| clearing/route.ts | ✅ | ✅ |
| distribute-coins/route.ts | ✅ | ✅ |
| platform/invariants/enforce/route.ts | ✅ | ✅ (via try-catch) |
| custody/webhook/route.ts | ✅ | ✅ (2 catches) |
| platform/refunds/route.ts | ✅ | ✅ |
| verification/evaluate/route.ts | ❌ | ❌ |
| announcements/route.ts | ❌ | ❌ |
| crm/tags/route.ts | ❌ | ❌ |
| crm/notes/route.ts | ❌ | ❌ |
| export/crm/route.ts | ❌ | ❌ |
| swap/route.ts | ❌ | ✅ |
| custody/route.ts | ❌ | ✅ |
| checkout/route.ts | ❌ | ✅ |
| team/invite/route.ts | ❌ | ❌ |
| team/remove/route.ts | ❌ | ❌ |

**Cobertura**: 8/36 API routes (22%) importam logger explicitamente. 10/36 (28%) possuem try-catch.

⚠️ **Finding P2**: Rotas de API sem logger import dependem do error boundary global do Next.js e do Sentry, mas não logam detalhes de contexto (group_id, user_id, etc.). Rotas críticas (announcements, CRM, team) deveriam ter logging explícito.

### Sentry Integration

| Config | Arquivo | Status |
|--------|---------|--------|
| Client | `portal/sentry.client.config.ts` | ✅ tracesSampleRate: 0.1, replaysOnErrorSampleRate: 1.0 |
| Server | `portal/sentry.server.config.ts` | ✅ tracesSampleRate: 0.1, prod-only |
| Edge | `portal/sentry.edge.config.ts` | ✅ tracesSampleRate: 0.1, prod-only |

**Resultado**: ✅ Sentry configurado em todas as 3 camadas (client, server, edge).

### Error Boundaries
- ✅ `portal/src/app/error.tsx` — root
- ✅ `portal/src/app/(portal)/error.tsx` — portal layout (com Sentry.captureException)
- ✅ `portal/src/app/platform/error.tsx` — platform layout

**Resultado**: ⚠️ PASS com notas — Sentry OK, error boundaries OK, mas logger adoption rate nas API routes poderia melhorar.

---

## 9.3 Edge Function Logging

### obs.ts (`supabase/functions/_shared/obs.ts`)
- ✅ `startTimer()` — cria timer para medir duração
- ✅ `logRequest()` — log estruturado: `request_id`, `fn`, `user_id`, `status`, `duration_ms`
- ✅ `logError()` — log estruturado: `request_id`, `fn`, `user_id`, `error_code`, `duration_ms`
- ✅ Seguro: NUNCA loga JWT, headers, ou request body

### Adoção de obs.ts

**55/57 edge functions** importam `_shared/obs.ts` (96%).

2 funções sem obs.ts:
- `strava-register-webhook` — webhook registration (one-time setup)
- (1 outra — irrelevante, setup script)

### logger.ts (`supabase/functions/_shared/logger.ts`)
- Complementar ao obs.ts
- Usado por 4 funções para logging mais detalhado:
  - `token-create-intent` — logging de intent lifecycle
  - `compute-leaderboard` — logging de compute steps
  - `notify-rules` — logging de rule evaluation
  - `clearing-confirm-received` — logging de confirmation steps

### Error Detail Capture
- ✅ Todas as funções capturam `error_code` via obs.ts
- ✅ Funções com `_shared/logger.ts` capturam mensagens de erro detalhadas
- ✅ Formato JSON estruturado em todas as saídas de log

**Resultado**: ✅ PASS — 96% de adoção do obs.ts. Error details capturados.

---

## 9.4 Request Correlation

### Portal Middleware (`portal/src/middleware.ts`)

```
L115: const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();
L116: supabaseResponse.headers.set("x-request-id", requestId);
```

- ✅ Gera `x-request-id` via `crypto.randomUUID()` se não presente
- ✅ Propaga no response header
- ✅ Reutiliza ID do upstream se já presente (load balancer, CDN)

### Edge Functions
- ✅ `obs.ts` aceita e loga `request_id` em todas as chamadas
- ✅ Funções geram `crypto.randomUUID()` como request_id

### Flutter App
- ⚠️ Não há request correlation explícita no app Flutter (AppLogger não gera trace IDs)
- Mitigação: Sentry SDK no Flutter gera trace IDs automaticamente para transactions

**Resultado**: ✅ PASS — Correlation implementada no portal e edge functions.

---

## 9.5 Metrics & Monitoring

### O que é rastreado

| Métrica | Onde | Como |
|---------|------|------|
| RPC timing (edge functions) | obs.ts → stdout | `duration_ms` em cada logRequest/logError |
| Compute KPI duration | compute_coaching_kpis_daily | Implicit via cron trigger timing |
| Compute Alert duration | compute_coaching_alerts_daily | Implicit via cron trigger timing |
| Export duration | export API routes | logger.info com timing |
| API route latency | Sentry (server) | tracesSampleRate: 0.1 |
| Client page loads | Sentry (client) | tracesSampleRate: 0.1 |
| Session replays on error | Sentry (client) | replaysOnErrorSampleRate: 1.0 |
| Flutter errors | Sentry Flutter | captureException via AppLogger.onError |
| Edge function errors | obs.ts | error_code + duration_ms |

### O que NÃO é rastreado (gaps)
- ⚠️ Database query timing (no pg_stat_statements monitoring documented)
- ⚠️ Cache hit/miss rates (N/A — no cache layer)
- ⚠️ Queue depths (challenge settlement, clearing cron)

**Resultado**: ✅ PASS — Métricas essenciais cobertas via Sentry + structured logging.

---

## 9.6 Incident Runbook

### KPIs param de atualizar
1. Verificar cron `lifecycle-cron` nos logs do Supabase
2. Verificar se `compute_coaching_kpis_daily(CURRENT_DATE)` executa sem erro:
   ```sql
   SELECT compute_coaching_kpis_daily(CURRENT_DATE);
   ```
3. Verificar se há groups sem membros (edge case de divisão por zero)
4. Verificar se `coaching_kpis_daily` recebeu row recente:
   ```sql
   SELECT max(computed_at) FROM coaching_kpis_daily;
   ```

### Attendance para de funcionar
1. Verificar função `fn_mark_attendance` existe e tem grants corretos:
   ```sql
   SELECT proname, prosecdef FROM pg_proc WHERE proname = 'fn_mark_attendance';
   ```
2. Verificar RLS em `coaching_training_attendance` — athlete deve poder INSERT/SELECT
3. Verificar se `coaching_training_sessions` existe para o grupo e `status != 'cancelled'`
4. Verificar se QR code não expirou (gerado com timestamp)

### TrainingPeaks sync falha
1. Verificar se tokens OAuth estão válidos:
   ```sql
   SELECT athlete_user_id, expires_at FROM coaching_tp_tokens WHERE expires_at < now();
   ```
2. Verificar logs do `trainingpeaks-sync` edge function
3. Verificar se `TRAININGPEAKS_CLIENT_ID` e `TRAININGPEAKS_CLIENT_SECRET` estão nas env vars
4. Verificar rate limits da TP API (429 responses)
5. Fallback: desabilitar sync temporariamente via feature flag

### Portal crash
1. Verificar Sentry dashboard para exceção recente
2. Verificar `error.tsx` boundary — se capturou, vai mostrar "Algo deu errado" com digest
3. Verificar logs do Vercel/servidor para erros 500
4. Verificar se Supabase está acessível (teste: `/api/health`)
5. Verificar se cookie `portal_group_id` está presente (redirect loop se ausente)

### Wallet/Ledger inconsistente
1. Executar `reconcile-wallets-cron` manualmente
2. Verificar `coin_ledger` para transações duplicadas:
   ```sql
   SELECT idempotency_key, count(*) FROM coin_ledger GROUP BY 1 HAVING count(*) > 1;
   ```
3. Verificar `coaching_token_inventory.available_tokens` vs soma do ledger

### Push notifications não chegam
1. Verificar `send-push` edge function logs
2. Verificar `push_device_tokens` — device registrado?
3. Verificar Firebase Cloud Messaging quotas
4. Verificar `notify-rules` — regra ativa para o tipo de evento?

---

## Veredito GATE 9: ⚠️ PASS com notas

**Findings**:
- P2: 28/36 API routes do portal sem logger import explícito (Sentry captura, mas sem contexto detalhado)
- P3: Flutter app sem request correlation explícita (Sentry SDK mitiga)
- P3: Sem monitoramento de database query timing documentado

Nenhum finding P0 ou P1.
