# Chaos de Rede — Relatório de Resiliência de Rede

**Escopo:** Análise de timeouts, retry, loading, offline e deduplicação de respostas.

**Repositório:** `/home/usuario/project-running`

---

## 1. TIMEOUT handling

### 1.1 Edge functions — timeouts em chamadas externas

| Arquivo | Chamada externa | Timeout | Impacto |
|---------|-----------------|---------|---------|
| `webhook-mercadopago/index.ts` | `fetch(https://api.mercadopago.com/v1/payments/...)` | **Nenhum** | Request pode hangar até limite da EF (60s default) | **MAJOR** |
| `strava-webhook/index.ts` | `fetch(strava oauth/token)`, `fetch(activity)`, `fetch(streams)` | **Nenhum** | Idem; webhook Strava pode retry, causando duplicatas parciais | **MAJOR** |
| `strava-webhook/index.ts` | `fetch(strava streams)` | **Nenhum** | Streams podem ser grandes; timeout provável em conexões lentas | **MAJOR** |
| `create-checkout-mercadopago/index.ts` | `fetch(MercadoPago API)` | **Nenhum** | Checkout pode demorar indefinidamente | **MAJOR** |
| `trainingpeaks-sync/index.ts` | `fetch(TrainingPeaks API)` por item (N+1) | **Nenhum** | 50 syncs × ~2–5s cada = 100–250s; EF timeout 60s | **CRITICAL** |
| `trainingpeaks-oauth/index.ts` | `fetch(TrainingPeaks token, me)` | **Nenhum** | OAuth pode hangar | **MAJOR** |
| `strava-register-webhook/index.ts` | `fetch(Strava API)` | **Nenhum** | Idem | **MAJOR** |
| `auto-topup-cron/index.ts` | `fetch` interno | **Nenhum** | Cron pode não completar | **MINOR** |
| `send-push/index.ts` | `fetch(FCM)` | **Nenhum** | Push pode demorar | **MINOR** |

**Conclusão:** Nenhuma edge function configura `AbortSignal.timeout()` ou `signal` em `fetch`. Supabase Edge Functions têm timeout padrão (~60s); chamadas lentas consumirão todo o orçamento.

### 1.2 Flutter — Supabase e HTTP

| Arquivo | Contexto | Timeout |
|---------|----------|---------|
| `settings_screen.dart` | Ping RPCs (Supabase) | `.timeout(const Duration(seconds: 10))` ✅ |
| `athlete_championships_screen.dart` | Chamadas RPC | `.timeout(const Duration(seconds: 10))` ✅ |
| `athlete_championship_ranking_screen.dart` | Idem | `.timeout(const Duration(seconds: 10))` ✅ |
| `supabase_challenges_remote_source.dart` | Sync challenge | `.timeout(10s)`, `.timeout(15s)` ✅ |
| `remote_auth_datasource.dart` | Request close, OAuth completer | `5s`, `3min`, `5min` ✅ |
| **Supabase client default** | Todas as demais chamadas | **Nenhum timeout explícito** | **MAJOR** |
| `ble_heart_rate_source.dart` | Scan BLE | `Duration(seconds: 15)`, `10s` ✅ |
| `run_summary_screen.dart`, `map_screen.dart`, `run_details_screen.dart`, `run_replay_screen.dart` | Map load | `6s` timer → fallback UI ✅ |

**Conclusão:** Algumas telas e blocos críticos têm timeout. A maioria das chamadas Supabase (`.from().select()`, `.rpc()`) não tem timeout configurado; em rede lenta ou inacessível, o app pode ficar em loading indefinido.

### 1.3 Portal (Next.js)

| Contexto | Timeout |
|----------|---------|
| `createServiceClient()` | `fetch` padrão do Next; sem `AbortController` ou timeout custom | **Nenhum** |
| `portal/src/lib/supabase/service.ts` | `cache: "no-store"` mas sem timeout | **Nenhum** |
| Páginas server-side | `await db.from(...).select()` | Depende do default do Supabase JS | **MAJOR** |
| `tools/perf_seed.ts`, `tools/integration_tests.ts` | `AbortSignal.timeout(5000)` | ✅ Apenas em ferramentas |
| `tools/edge_function_smoke_tests.ts` | `setTimeout(ctrl.abort, 2000)` | ✅ Testes |

**Conclusão:** Portal não configura timeout em chamadas Supabase. Em rede instável, páginas podem carregar por muito tempo ou travar.

---

## 2. RETRY logic

### 2.1 Flutter — retry em chamadas de API

| Componente | Retry | Detalhes |
|------------|-------|----------|
| `supabase_wearable_repo.dart` | ✅ `_retry(fn, maxAttempts: 3)` | Para operações wearables; exponential backoff não explícito |
| `supabase_challenges_remote_source.dart` | ✅ `_syncWithRetry` | Retry com backoff para sync de challenges |
| `remote_profile_datasource.dart` | ✅ Retry read | "Fallback: trigger may not have fired yet. Retry read once" |
| `auth_gate.dart` | ✅ `_retryResolve` | Até 2 tentativas com delay crescente |
| `strava_http_client.dart` | ✅ `postWithRetry` | 5xx e network errors; exponential backoff |
| `strava_upload_repository_impl.dart` | ✅ `_uploadWithTokenRetry`, `_pollWithTokenRetry` | Retry em 401 (refresh token) |
| `watch_bridge_init.dart` | ✅ `_processWithRetry`, `_retryPendingSessions` | Queue de retry para sessões Watch |
| **Demais blocos/repos** | ❌ Nenhum | Uma falha = erro imediato ao usuário |

**Conclusão:** Retry existe em wearables, challenges, auth, Strava e Watch. A maioria dos repositórios (CRM, treinos, announcements, etc.) não tem retry; falha de rede resulta em erro direto.

### 2.2 Edge functions — retry em chamadas externas

| Função | Chamada | Retry |
|--------|---------|-------|
| `webhook-mercadopago` | MP API | ❌ Nenhum |
| `strava-webhook` | Strava API (token, activity, streams) | ❌ Nenhum |
| `trainingpeaks-sync` | TrainingPeaks API por item | ❌ Nenhum |
| `trainingpeaks-oauth` | TrainingPeaks token | ❌ Nenhum |
| `create-checkout-mercadopago` | MP API | ❌ Nenhum |
| `auto-topup-cron` | `INTER_CALL_DELAY_MS` entre chamadas | Não é retry; é throttle |

**Conclusão:** Edge functions não implementam retry para APIs externas. Falha transitória (5xx, timeout) = processamento perdido até novo webhook/cron.

### 2.3 Offline queue — retry

| Arquivo | Mecanismo |
|---------|-----------|
| `omni_runner/lib/core/offline/offline_queue.dart` | ✅ `replay()` com `_maxRetryCount = 3`, `_maxAgeDays = 7`; incrementa `retryCount` em falha; remove após 3 falhas |
| `omni_runner/lib/core/utils/offline_queue.dart` | Implementação mais simples; `drain()` retorna itens para processamento manual; sem retry automático |

**Conclusão:** `core/offline/offline_queue.dart` tem retry limitado (3x). Queue legada em `core/utils` não tem retry integrado.

---

## 3. LOADING STATES

### 3.1 Telas com loading

| Categoria | Telas | Indicador |
|-----------|-------|-----------|
| Staff | staff_disputes, staff_credits, staff_championship_*, staff_challenge_invites, staff_crm_list, staff_performance, staff_retention, staff_weekly_report, staff_setup, staff_workout_*, staff_training_* | `CircularProgressIndicator`, `_loading` state |
| Athlete | athlete_delivery, athlete_workout_day, athlete_my_evolution, athlete_device_link, athlete_championships, athlete_championship_ranking | Idem |
| Geral | today_screen, wallet, challenges_list, run_summary, wrapped, running_dna, etc. | Idem |

**Contagem:** >70 screens referenciam `CircularProgressIndicator` ou estado de loading. Cobertura ampla.

### 3.2 Telas sem loading ou com “raw snap”

| Contexto | Risco |
|----------|-------|
| `BlocBuilder` sem estado `Loading` em alguns blocs | UI pode mostrar dados antigos ou vazios antes de loaded |
| `StreamBuilder` / `FutureBuilder` sem `ConnectionState.waiting` handling | Spinner genérico ou nada |
| Portal | Server Components fazem `await`; usuário vê loading do Next até resposta | OK |
| Portal client actions | Botões que disparam `fetch` podem não mostrar loading durante request | **MINOR** |

### 3.3 Loading cancelável

| Área | Cancelável |
|------|------------|
| Flutter navigation | Pop fecha tela; request em andamento não é cancelado |
| Bloc subscriptions | `BlocProvider` dispose cancela subscription; `EventTransformer` não cancela HTTP |
| `Future` em initState | Sem `CancelableOperation` ou similar |
| Map load timeout | Timer cancela e mostra fallback; não cancela o load em si |

**Conclusão:** Loading states existem; cancelar operações em voo (ex: trocar de tela) não é sistematicamente tratado.

---

## 4. OFFLINE behavior

### 4.1 Flutter — Supabase inacessível

| Componente | Comportamento |
|------------|---------------|
| `OfflineQueue` (`core/offline/`) | Enfileira RPCs que falham; replay quando conectividade volta |
| `ConnectivityMonitor` | Detecta conectividade; pode disparar replay |
| Chamadas diretas Supabase | Falham com `SocketException` ou similar; tratamento depende do repo/tela |
| `ErrorState` / `AppErrorState` | Humaniza mensagens (timeout, network, 401, 403, 404, 500) |
| Cache local (Isar) | Dados em `isar_*_repo` disponíveis offline para leitura |
| Sessões de corrida | Gravadas localmente; sync quando online |

**Limitações:**
- Nem todas as operações falham graciosamente; muitas propagam exceção.
- Offline queue é usada principalmente para `fn_import_execution` e similares; outras RPCs não enfileiram.
- Sem estratégia global de “offline-first” em toda a navegação.

### 4.2 Portal — Supabase inacessível

| Contexto | Comportamento |
|----------|---------------|
| Server Components | `await db.from(...)` falha → página mostra erro ou loading infinito |
| Next.js | Erro não tratado → tela de erro genérica ou 500 |
| Client-side fetch em actions | Falha → estado de erro se implementado; caso contrário, silencioso |

**Conclusão:** Portal não tem modo offline; depende totalmente de rede para carregar.

### 4.3 Offline queue — correção

| Aspecto | Status |
|---------|--------|
| Enfileiramento | Apenas onde explicitamente chamado (ex: `OfflineQueue.enqueue`) |
| Replay | `replay()` chama `_client.rpc()`; se ainda offline, falha de novo e re-enfileira |
| Idempotência | RPCs como `fn_import_execution` têm `ON CONFLICT DO NOTHING`; replay duplicado é seguro |
| Ordem | Replay sequencial; ordem preservada |
| Malformed entries | `_loadItems` faz try/catch por entry; `jsonDecode` falha → entry ignorado |

**Conclusão:** Offline queue funciona para casos em que é usada; uso não é universal.

### 4.4 Navegação offline

- Telas que leem de Isar (ex: histórico, wallet cache) podem mostrar dados antigos.
- Telas que dependem apenas de Supabase mostram erro ou loading até timeout.
- Navegação em si funciona; o problema é o conteúdo das telas.

---

## 5. DUPLICATE RESPONSES

### 5.1 Webhook MercadoPago — pagamento duplicado

| Mecanismo | Implementação |
|-----------|---------------|
| L1 — `billing_events` | Dedup por `mp_payment_id` em metadata; insert com unique constraint |
| L2 — UPDATE | `WHERE status = 'pending'` evita re-transição |
| L3 — `fn_fulfill_purchase` | Checa `status = 'paid'` com `FOR UPDATE` |
| Resposta | Se já processado: `already_processed: true` |

**Conclusão:** Idempotência em 3 camadas; webhook duplicado não causa double fulfillment.

### 5.2 Webhook Strava — atividade duplicada

| Mecanismo | Implementação |
|-----------|---------------|
| Check pré-insert | `sessions.strava_activity_id` + `user_id` em `maybeSingle()` |
| Se `existing` | Retorna `{ ignored: true, reason: "duplicate" }` |
| Insert | Sem unique constraint explícito em sessions; dedup é lógica |

**Conclusão:** Verificação explícita antes de criar sessão; duplicatas são ignoradas.

### 5.3 Outros webhooks e operações

| Operação | Deduplicação |
|----------|--------------|
| Stripe (webhook-payments) | `stripe_event_id` UNIQUE em billing_events |
| Wearable import | `ON CONFLICT (athlete_user_id, provider_activity_id) DO NOTHING` |
| TrainingPeaks sync | Unique constraint `(assignment_id, athlete_user_id)` |
| QR check-in | Nonce + TTL + idempotency |
| Mark attendance | `ON CONFLICT (session_id, athlete_user_id) DO NOTHING` |
| Distribute coins | `x-idempotency-key` header; `ON CONFLICT (idempotency_key) DO NOTHING` |

**Conclusão:** Principais fluxos monetários e de dados têm deduplicação adequada.

---

## Resumo Executivo

### Pontos fortes

1. **Idempotência em webhooks** — MercadoPago, Strava, Stripe com dedup.
2. **Retry em fluxos críticos** — Wearables, challenges, auth, Strava, Watch.
3. **Offline queue** — Replay com retry limitado para RPCs enfileirados.
4. **Timeout em partes críticas** — BLE, map load, algumas RPCs Flutter.
5. **Loading states** — Amplamente presentes nas telas Flutter.

### Pontos fracos

1. **Edge functions sem timeout** — Fetch para MP, Strava, TrainingPeaks pode hangar.
2. **trainingpeaks-sync N+1** — 50 itens em série; alto risco de timeout da EF.
3. **Flutter Supabase sem timeout** — Maioria das chamadas sem limite.
4. **Portal sem timeout** — Chamadas Supabase sem AbortController.
5. **Retry limitado** — Maioria dos repos não retenta em falha de rede.

### Recomendações prioritárias

| # | Ação | Impacto |
|---|------|---------|
| 1 | Adicionar `AbortSignal.timeout(30_000)` em fetches das edge functions | Evitar hang em EF |
| 2 | Paralelizar ou limitar batch em `trainingpeaks-sync` (ex: 10 por vez, Promise.all) | Evitar timeout em 50 syncs |
| 3 | Configurar timeout no Supabase Flutter client (global ou por chamada) | Evitar loading infinito |
| 4 | Estender offline queue para mais RPCs (ex: mark_attendance, create_announcement) | Melhor UX offline |
| 5 | Retry com backoff em repos principais (CRM, treinos) | Maior resiliência a falhas transitórias |
