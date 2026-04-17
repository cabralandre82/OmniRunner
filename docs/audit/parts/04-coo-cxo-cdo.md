I now have enough data to generate PART 4.

# PARTE 4 de 8 — LENTES 6 (COO: Operações & Runbooks), 7 (CXO: Experiência) e 8 (CDO: Dados & Analytics)

Auditoria de **40 itens**.

---

## LENTE 6 — COO (Chief Operating Officer): Operações, Incident Response, Ciclo de Vida

### 🔴 [6.1] **Zero runbook financeiro** — custódia, clearing, swap, withdraw

**Achado** — `docs/` contém `ROLLBACK_RUNBOOK.md`, `OS06_RELEASE_RUNBOOK.md`, `WORKOUT_DELIVERY_RUNBOOK.md` mas **não existe**:

- `CUSTODY_INCIDENT_RUNBOOK.md` — o que fazer quando `check_custody_invariants()` retorna violações?
- `CLEARING_STUCK_RUNBOOK.md` — settlement em `pending` há 24 h
- `WITHDRAW_STUCK_RUNBOOK.md` — withdraw em `processing` há 48 h ([2.3])
- `CHARGEBACK_RUNBOOK.md` — Stripe abriu dispute, como reverter moedas emitidas? ([2.13])
- `GATEWAY_OUTAGE_RUNBOOK.md` — Asaas/Stripe/MP fora
- `WEBHOOK_BACKLOG_RUNBOOK.md` — fila de webhooks parada ([2.13])

**Risco** — Operações financeiras dependem de decisões ad-hoc às 3 da manhã. Probabilidade muito alta de **decisão errada** durante incident → **perda financeira irreversível** em produto que lida com dinheiro real.

**Correção** — Criar os 6 runbooks acima, cada um seguindo estrutura:

```markdown
# CUSTODY_INCIDENT_RUNBOOK

## Sintoma
- Dashboard: /api/health retorna status="degraded" com invariants.violations > 0
- Alertas Sentry: "check_custody_invariants violation detected"

## Diagnóstico (≤ 5 min)
1. SELECT * FROM check_custody_invariants();  -- lista violações
2. Identificar group_id afetado
3. SELECT * FROM custody_accounts WHERE group_id = X;
4. Comparar com SELECT SUM(delta_coins) FROM coin_ledger WHERE issuer_group_id = X;

## Remediação por tipo
### Tipo "committed < 0"
- Provável causa: execute_burn_atomic falhou em [2.2]
- Rollback: ... (scripts SQL específicos)

## Criticidade
- P1 se total_deposited_usd < total_committed em grupo ativo

## Quem chamar
- On-call SRE + CFO Lead (valores > US$ 1.000)
```

**Teste** — Game-day trimestral simulando 3 cenários acima.

---

### 🔴 [6.2] Health check exibe **contagem exata de violações** (info leak operacional)

**Achado** — `portal/src/app/api/health/route.ts:44`:

```44:44:portal/src/app/api/health/route.ts
        invariants: invariantsOk ? "healthy" : `${invariantCount} violation(s)`,
```

Endpoint é público (nenhum auth). Atacante monitora: "7 violations" → sabe que plataforma está comprometida → timing de ataque + extorsão ("pague ou divulgo").

**Risco** — Information disclosure. Também expõe latência de DB (`latencyMs`) que ajuda fingerprinting.

**Correção** —

```typescript
const body = allOk
  ? { status: "ok", ts: Date.now() }
  : { status: dbOk ? "degraded" : "down", ts: Date.now() };

// Full details only when ?secret=... matches env
const full = new URL(req.url).searchParams.get("secret") === process.env.HEALTH_SECRET;
if (full) {
  body.checks = { db: ..., invariants: ..., invariantCount };
  body.latencyMs = latencyMs;
}
```

E adicionar endpoint separado `/api/internal/health-detailed` protegido por JWT platform_admin.

**Teste** — `health.test.ts`: GET sem secret → body tem apenas `status` e `ts`; com secret → inclui detalhes.

---

### 🟠 [6.3] `reconcile-wallets-cron` sem **alerta** em drift > 0

**Achado** — `supabase/functions/reconcile-wallets-cron/index.ts` corrige drift e loga. Não há alerta se drift > 0, apenas log `console.error` que exige monitor externo já configurado. Até hoje o `docs/` não indica que esse log esteja conectado a Datadog/PagerDuty.

**Risco** — Drift = indicador #1 de bug na RPC `execute_burn_atomic` ou corrupção; passa despercebido.

**Correção** —

```typescript
if (wallets_corrected > 0) {
  await fetch(Deno.env.get("SLACK_ALERT_WEBHOOK")!, {
    method: "POST",
    body: JSON.stringify({
      text: `:rotating_light: Wallet drift detected: ${wallets_corrected} wallets corrected. ` +
            `Investigate execute_burn_atomic / fn_increment_wallets_batch.`,
    }),
  });
  // Also bump Sentry alert
}
```

Mais: se `wallets_corrected > threshold` (ex.: > 10), **abortar** a correção e criar incident, porque pode indicar bug sistêmico.

---

### 🟠 [6.4] `pg_cron` jobs sem monitoramento de execução

**Achado** — `grep "cron.schedule" supabase/migrations/*.sql` lista: `auto_topup_cron`, `lifecycle_cron`, `clearing_cron`, `verification_cron`, `swap_expire`, `reconcile-wallets-cron`. Não há tabela `cron_job_runs` registrando sucesso/falha. `cron.job_run_details` existe em pg_cron mas:

- Nenhum alerta quando job falha por > 2 ciclos seguidos
- Nenhum dashboard mostrando última execução de cada job

**Risco** — `reconcile-wallets-cron` para; ninguém nota; drift acumula 3 meses → auditoria revela US$ 50k faltantes.

**Correção** —

```sql
CREATE OR REPLACE FUNCTION public.fn_check_cron_health()
RETURNS TABLE(jobname text, last_success timestamptz, minutes_since_success numeric, status text)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    j.jobname,
    MAX(r.end_time) FILTER (WHERE r.status='succeeded') AS last_success,
    EXTRACT(EPOCH FROM (now() - MAX(r.end_time) FILTER (WHERE r.status='succeeded')))/60,
    CASE
      WHEN MAX(r.end_time) FILTER (WHERE r.status='succeeded') < now() - interval '2 hours' THEN 'STALE'
      WHEN BOOL_OR(r.status='failed' AND r.end_time > now() - interval '1 hour') THEN 'FAILING'
      ELSE 'OK'
    END
  FROM cron.job j
  LEFT JOIN cron.job_run_details r ON r.jobid = j.jobid
  GROUP BY j.jobname;
$$;
```

Incluir em `/api/internal/health-detailed` (ver [6.2]).

---

### 🟠 [6.5] Edge Functions **sem retry em falha de pg_net**

**Achado** — `supabase/migrations/20260221000001_auto_topup_cron.sql:56` usa `pg_net` para chamar Edge Function. Se falhar (timeout, 503), **não há retry automático**; o cron espera o próximo ciclo (1 hora).

**Risco** — Auto-topup perde a janela; cliente fica sem moeda; frustração. Pior, `lifecycle-cron` adiar não é crítico, mas `reconcile-wallets-cron` adiar **é**.

**Correção** — Wrapper SQL com retry:

```sql
CREATE OR REPLACE FUNCTION public.fn_invoke_edge_with_retry(
  p_url text, p_body jsonb, p_max_attempts int DEFAULT 3
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_attempt int := 0; v_status int;
BEGIN
  LOOP
    v_attempt := v_attempt + 1;
    SELECT status_code INTO v_status FROM net.http_post(
      url := p_url, body := p_body,
      headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.service_key'))
    );
    EXIT WHEN v_status = 200 OR v_attempt >= p_max_attempts;
    PERFORM pg_sleep(v_attempt * 5);
  END LOOP;
  IF v_status <> 200 THEN
    INSERT INTO cron_failures (job, url, final_status, attempted_at) VALUES (...);
  END IF;
END;$$;
```

---

### 🟠 [6.6] **Sem feature flags** para desligar subsistemas

**Achado** — Em caso de bug em swap/clearing/custody, a única forma de desligar é deploy. Não há tabela `feature_flags` consultada no início de cada Edge/Route Handler.

**Risco** — Bug descoberto 02:00, deploy demora 20 min, perda estimada US$ X/min.

**Correção** —

```sql
CREATE TABLE public.feature_flags (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT true,
  updated_by uuid,
  updated_at timestamptz DEFAULT now()
);
INSERT INTO feature_flags(key, enabled) VALUES
  ('swap.enabled', true),
  ('custody.deposits.enabled', true),
  ('custody.withdrawals.enabled', true),
  ('clearing.interclub.enabled', true),
  ('distribute_coins.enabled', true),
  ('auto_topup.enabled', true);
```

```typescript
export async function assertFeature(key: string) {
  const { data } = await db.from("feature_flags").select("enabled").eq("key", key).maybeSingle();
  if (!data?.enabled) throw new FeatureDisabledError(key);
}
```

Adicionar no começo de cada endpoint financeiro. UI `/platform/flags` para admin_master toggle imediato.

---

### 🟠 [6.7] **Global error** do Next.js não reporta a Sentry

**Achado** — `portal/src/app/global-error.tsx:1-53` é um Client Component mas **nunca chama** `Sentry.captureException(error)`. Recomendação Sentry+Next oficial é:

```typescript
'use client';
import * as Sentry from '@sentry/nextjs';
import { useEffect } from 'react';

export default function GlobalError({ error, reset }) {
  useEffect(() => { Sentry.captureException(error); }, [error]);
  return <html>...</html>;
}
```

**Risco** — Erro fatal na root layout (ex.: `createClient` falhando) é mostrado ao usuário mas **nunca chega ao Sentry** → time de SRE acredita "está tudo bem", usuários silenciosamente frustrados.

**Correção** — Aplicar snippet acima. Mesmo para `portal/src/app/(portal)/error.tsx`.

---

### 🟠 [6.8] `delete-account` executa `deleteUser` **sem audit_log**

**Achado** — `supabase/functions/delete-account/index.ts` nunca escreve em `audit_logs` antes nem depois. Após exclusão não há trilha de "fulano solicitou auto-exclusão em 2026-04-15".

**Risco** — Investigação futura (fraude, dispute) sem trilha.

**Correção** — `INSERT INTO audit_logs(action, actor_id, target_user_id, metadata, created_at) VALUES ('user.self_delete.initiated', uid, uid, jsonb_build_object('ip', ip, 'ua', ua), now())` antes e `'user.self_delete.completed'` depois. Como audit_log retém apenas `user_id` (anonimizado) pelo [4.7], manter `metadata->>'email_hash'` (SHA-256 do email original).

---

### 🟡 [6.9] Métricas (`portal/src/lib/metrics.ts`) só geram **log JSON**, sem exporter real

**Achado** — `metrics.ts:LogMetricsCollector` registra via `logger.info`. Não há Prometheus/StatsD/Datadog na prática.

**Risco** — Em produção os "metrics" são apenas linhas no Vercel logs — caros, não agregam, sem alerting.

**Correção** — Trocar por `@opentelemetry/api-metrics` + exporter OTLP, apontar para Grafana Cloud ou Datadog. Ou, mínimo, criar `DatadogMetricsCollector` chamando `datadogRum.addTiming(...)`.

---

### 🟡 [6.10] Não há **SLO** documentado

**Achado** — `docs/` não define SLO por endpoint/módulo. Ex.: "/api/custody/withdraw: P99 < 500 ms, error rate < 0.1%". Sem SLO, time priori­za incorretamente.

**Correção** — `docs/SLO.md` listando os 15 endpoints críticos + thresholds de erro + SLA de incidentes.

---

### 🟡 [6.11] Secret rotation sem playbook

**Achado** — `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_WEBHOOK_SECRET`, `MP_WEBHOOK_SECRET`, `ASAAS_API_KEY` são env vars. Não há runbook de rotação, intervalo recomendado, passos para rotação sem downtime.

**Correção** — Runbook `docs/SECRET_ROTATION_RUNBOOK.md`. Todos rotacionados a cada 90 dias (180 para service_role se bloqueio dificultar).

---

### 🟡 [6.12] `/api/liveness` trivial mas `/api/readiness` inexistente

**Achado** — `portal/src/app/api/liveness/route.ts` existe; não há `/api/readiness` (que verifica conectividade a DB + Redis + Stripe sem executar custody invariants).

**Correção** — `readiness` checa `db.from("profiles").select("id").limit(1)` + `getRedis().ping()` + Stripe API heartbeat. Kubernetes/Vercel usa `liveness` (apenas servidor up) vs `readiness` (pode aceitar tráfego).

---

### 🟡 [6.13] Logs estruturados **sem request_id propagado** do portal

**Achado** — Edge Functions geram `requestId = crypto.randomUUID()`. Portal Next.js `logger` não recebe/gera `x-request-id`. Correlação cross-serviço impossível.

**Correção** — Middleware do Next injetar `x-request-id` se não vier do cliente, propagar em toda chamada `fetch(supabase, ...)`.

---

## LENTE 7 — CXO (Chief Experience Officer): UX, Acessibilidade, Internacionalização

### 🔴 [7.1] Mensagens de erro **em português hardcoded no backend**

**Achado** —

```143:143:portal/src/app/api/swap/route.ts
    return NextResponse.json({ error: "Operação falhou. Tente novamente." }, { status: 422 });
```

Vários endpoints retornam strings pt-BR hardcoded. Frontend mobile (`omni_runner`) tem i18n (`app_localizations_en.dart`, `app_localizations_pt.dart`) mas quando bate na API recebe pt-BR só.

**Risco** — Usuário inglês (expansão internacional) vê mensagem em português → percepção de produto amador.

**Correção** — API sempre retorna `{ error: { code: "SWAP_OPERATION_FAILED" } }`. Cliente traduz via tabela i18n.

**Teste** — Contract test: todas as rotas `/api/*` retornam `error.code` (upper snake), não `error` string.

---

### 🔴 [7.2] **Onboarding não distingue** papéis (atleta, coach, admin_master)

**Achado** — `portal/src/components/onboarding/onboarding-overlay.tsx` tem um único fluxo. Coach amador precisa aprender conceitos "custody, clearing, swap" ao mesmo tempo que vê a UI. Atleta vê a mesma coisa.

**Risco** — Churn alto no D1/D7. Especialmente treinadores sem formação financeira se sentem perdidos.

**Correção** — Fluxos diferentes:

- **Coach iniciante**: 5 passos simples (criar grupo, convidar atleta, criar challenge, distribuir badges, ver dashboard). Custódia/swap só aparecem após primeiro pagamento real.
- **Coach profissional (marketplace)**: onboarding financeiro completo com vídeo de 2 min explicando custody = "dinheiro que você já recebeu e pode usar para distribuir".
- **Atleta**: 3 passos (conectar Strava/healthkit, entrar em grupo via convite, primeira corrida).
- **Admin master**: dashboard de CFO, sem onboarding de atleta.

---

### 🟠 [7.3] App mobile **sem modo offline robusto** para corridas

**Achado** — `omni_runner/lib/data/datasources/drift_database.dart` grava localmente, mas `auto_sync_manager.dart` assume conexão frequente. Se atleta treina 10 dias em lugar remoto (trilha serra), retorno → **10 sessões pendentes** aparecem juntas, risco de perder se reinstalar app antes do sync.

**Risco** — Atleta perde treino → quebra trust no produto. Atleta profissional perde dado científico.

**Correção** —

1. Warning visível: "Você tem 10 sessões não sincronizadas. Conecte-se à internet."
2. Export manual: botão "Enviar por email (.fit)" que envia do dispositivo.
3. Queue persistente em SQLite (já tem) + retry exponential backoff + notificação push se > 3 dias.

---

### 🟠 [7.4] Flutter deep link Strava OAuth **sem state validation** (CSRF)

**Achado** — Já citado em PARTE 1 [1.20] — `omni_runner/lib/core/deep_links/deep_link_handler.dart`. Crítico UX também: atleta tenta conectar, é redirecionado de volta, o app abre mas **não confirma sucesso** porque state não é verificado. Comportamento indeterminado.

**Correção** — Gerar `state = secureRandom(32)` antes do OAuth, armazenar em `FlutterSecureStorage`, verificar match no callback. UX: toast "Conectado ao Strava ✓" só quando state confere.

---

### 🟠 [7.5] Portal **sem acessibilidade (a11y)** declarada

**Achado** — `grep -r "aria-" portal/src --include="*.tsx"` retorna ~70 matches mas auditoria superficial: botões principais de custódia (`Distribuir`, `Aceitar swap`) não têm `aria-label` quando só há ícone, `<table>` sem `<caption>`, nenhum `role="alert"` nos toasts.

**Risco** — Lei Brasileira de Inclusão (LBI 13.146/2015). Demandas judiciais de acessibilidade crescem 30% a.a.

**Correção** —

1. Rodar `axe-core` CI em páginas principais.
2. Adicionar `eslint-plugin-jsx-a11y`.
3. Documentar WCAG 2.1 AA como objetivo em `docs/a11y.md`.

---

### 🟠 [7.6] Timezone **sem configuração** do usuário

**Achado** — `sessions.start_time_ms` é UTC timestamp. Portal renderiza datas com `new Date(ms).toLocaleString("pt-BR")` → respeita timezone do browser, mas:

- Atleta no Brasil em fuso `America/Noronha` vê "3:00 AM" quando rodou às "4:00 AM locais".
- Portal admin vendo atletas de grupos em múltiplos países mistura fusos.

**Correção** — Campo `profiles.timezone text DEFAULT 'America/Sao_Paulo'` detectado no primeiro login. Backend formata datas server-side quando necessário.

---

### 🟡 [7.7] Ícones sem fallback (mobile offline)

**Achado** — Se atleta está offline, avatares de grupo (URLs Supabase Storage) falham e mostram ícone padrão; mas não há placeholder de blur-hash ou cache agressivo.

**Correção** — `cached_network_image` (já usado?) com `placeholder` = iniciais do grupo.

---

### 🟡 [7.8] **Dark mode** parcial

**Achado** — `omni_runner/lib/core/theme/` tem themes mas auditoria rápida sugere que portal web não tem dark mode. Corredores treinam cedo/tarde — dark mode é esperado.

**Correção** — Adicionar `next-themes` no portal + dark tokens no Tailwind config.

---

### 🟡 [7.9] Notificações push: **sem deep link preciso**

**Achado** — `omni_runner/lib/core/push/push_navigation_handler.dart` abre a tela home ou última tela. Notificação "Você tem novo workout delivery" não abre direto o item.

**Correção** — Payload push incluir `data: { route: "/workout-delivery/123" }` e handler navegar com `context.go(route)`.

---

### 🟡 [7.10] **Empty states** genéricos

**Achado** — Páginas "Sem challenges ativos" mostram texto mas não sugerem próximo passo. Boas UX: "Você não tem challenges. [Criar novo] ou [Aceitar convite]".

**Correção** — Component `<EmptyState title action1 action2 illustration />` reaproveitado.

---

### 🟡 [7.11] Loading states inconsistentes

**Achado** — Algumas listas mostram skeleton, outras spinner, outras branco. Mesma tela entre mobile/web. Coerência.

**Correção** — Design system: todas as listas usam `<SkeletonCard rows={5} />`.

---

### 🟡 [7.12] **Copy financeiro** confunde atleta

**Achado** — UI usa "Coins", "Badges", "Créditos", "Inventário" — quatro nomes para conceitos próximos. Atleta não entende diferença entre "moedas no wallet" e "badges de conquista".

**Correção** — Glossário visual + tooltip em cada contexto: "Moedas: usadas para pagar prêmios. Badges: conquistas não-monetárias."

---

### 🟡 [7.13] Confirmações destrutivas sem **confirm dialog**

**Achado** — "Excluir conta", "Cancelar championship", "Cancelar swap" — auditoria mobile sugere que alguns botões disparam ação direto após tap.

**Correção** — Modal obrigatório com "Digite CONFIRMAR" ou double-tap, com texto explicando consequência ("Esta ação é irreversível").

---

## LENTE 8 — CDO (Chief Data Officer): Dados, Analytics & BI

### 🔴 [8.1] `ProductEventTracker.trackOnce` tem **race TOCTOU**

**Achado** — `omni_runner/lib/core/analytics/product_event_tracker.dart:60-78`:

```60:78:omni_runner/lib/core/analytics/product_event_tracker.dart
      final existing = await sl<SupabaseClient>()
          .from(_table)
          .select('id')
          .eq('user_id', uid)
          .eq('event_name', eventName)
          .limit(1);

      if ((existing as List).isNotEmpty) { … return; }

      await sl<SupabaseClient>().from(_table).insert({
        'user_id': uid,
        'event_name': eventName,
        'properties': properties ?? {},
      });
```

Se duas chamadas concorrentes ocorrem (ex: conexão instável, double-tap, sync ao voltar online): ambas leem empty, ambas inserem → **`first_challenge_created` registrado 2 vezes**.

**Risco** — Métricas de funil **infladas** → decisões de produto erradas. "70 % dos usuários concluíram onboarding" pode ser 50 %.

**Correção** — Índice único + upsert:

```sql
CREATE UNIQUE INDEX idx_product_events_once
  ON product_events(user_id, event_name)
  WHERE event_name LIKE 'first_%' OR event_name = 'onboarding_completed';
```

```dart
await sl<SupabaseClient>().from(_table).upsert({
  'user_id': uid, 'event_name': eventName, 'properties': properties ?? {}
}, onConflict: 'user_id,event_name', ignoreDuplicates: true);
```

**Teste** — `product_events_once.test.dart`: 10 chamadas paralelas para o mesmo `first_*` → `SELECT COUNT(*)` == 1.

---

### 🔴 [8.2] `product_events.properties jsonb` aceita **qualquer payload** — PII leak risk

**Achado** — Dart code: `track("session_submitted", {"pace": 5.3, "location": sessionLatLng})`. Nenhuma validação Zod/JSON Schema no SQL. Devs distraídos podem colocar `email`, `cpf`, polyline completa.

**Risco** — Violação LGPD no produto de analytics, que é distribuído a stakeholders de marketing/BI.

**Correção** — RLS na tabela `product_events` permitindo apenas colunas-whitelist; trigger de validação:

```sql
CREATE OR REPLACE FUNCTION fn_validate_product_event() RETURNS trigger AS $$
DECLARE allowed text[] := ARRAY['step','method','challenge_id','championship_id','role','count','duration_ms'];
BEGIN
  IF NEW.properties IS NOT NULL THEN
    IF EXISTS (
      SELECT k FROM jsonb_object_keys(NEW.properties) k WHERE k NOT IN (SELECT unnest(allowed))
    ) THEN
      RAISE EXCEPTION 'Invalid property key in product_events' USING ERRCODE='PE001';
    END IF;
  END IF;
  RETURN NEW;
END;$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_product_event BEFORE INSERT ON product_events
  FOR EACH ROW EXECUTE FUNCTION fn_validate_product_event();
```

---

### 🟠 [8.3] **Sem índice de analytics time-series** em `sessions`

**Achado** — `supabase/migrations/20260218000000_full_schema.sql:79-81` indexa por `user_id, start_time_ms DESC`. Mas queries do tipo "todas sessões da última hora em todos os grupos" (para dashboards realtime CDO) fazem seq scan.

**Correção** —

```sql
CREATE INDEX idx_sessions_start_time_brin
  ON public.sessions USING BRIN (start_time_ms);
-- BRIN é ideal para time-series, 99% menos espaço que B-tree
```

---

### 🟠 [8.4] Análise de sessions pelo `moving_ms` mas coluna aceita **NULL e 0**

**Achado** — `fn_compute_kpis_batch` faz `SUM(s.moving_ms / 1000.0)`. Sessão com `moving_ms IS NULL` → NULL + X = NULL; `COALESCE(SUM(...), 0)` salva. Mas um session com `moving_ms = 0` & distance > 0 (GPS bug) vira pace infinito em `fn_compute_skill_bracket`:

```103:106:supabase/migrations/20260312000000_fix_broken_functions.sql
      CASE WHEN total_distance_m > 0 AND moving_ms > 0
           THEN (moving_ms / 1000.0) / (total_distance_m / 1000.0)
```

Aqui protege o skill bracket, mas outros queries no portal podem não proteger.

**Correção** — Constraint SQL:

```sql
ALTER TABLE sessions ADD CONSTRAINT chk_sessions_coherence
  CHECK (
    (status < 3) OR
    (total_distance_m = 0 AND moving_ms = 0) OR
    (total_distance_m >= 100 AND moving_ms >= 60000)
  );
```

Sessões "status < 3" (incomplete) livres; sessões finalizadas precisam ter >= 100 m e >= 60 s. Relacionado a [5.13].

---

### 🟠 [8.5] Views de progressão **sem filtro de atletas inativos**

**Achado** — `v_user_progression`, `v_weekly_progress` (em 20260221000030). Atletas que pararam há 1 ano continuam sendo agregados no ranking de "atleta mais evoluído", distorcendo baselines.

**Correção** — Adicionar `WHERE last_session_at > now() - interval '90 days'` nas views (ou material view com refresh semanal).

---

### 🟠 [8.6] **Sem staging de data warehouse** — queries OLAP contra OLTP

**Achado** — Dashboards `/platform/*` rodam `SELECT` pesados diretamente em `custody_accounts`, `coin_ledger`, `sessions` via Supabase. Sem isolamento de carga.

**Risco** — Dashboard pesado em hora de pico trava RPC crítico (execute_burn_atomic espera por lock). Incidente em produção causado por BI.

**Correção** — Supabase Foreign Data Wrapper ou pg_logical replication para **réplica dedicada OLAP** (mesmo que seja o mesmo cluster Postgres com replica). Ou export incremental noturno para DuckDB/BigQuery.

---

### 🟠 [8.7] **Drift** potencial entre `coin_ledger` e `wallets` fora do horário do cron

**Achado** — `reconcile-wallets-cron` roda 1x/dia. Entre reconciliações, drift pode crescer invisível.

**Correção** — Acrescentar check em `check_custody_invariants()`:

```sql
-- ... existing checks, plus:
UNION ALL
SELECT 'wallet_vs_ledger' AS invariant, w.user_id::text,
       jsonb_build_object('wallet', w.balance_coins, 'ledger', COALESCE(sum_delta, 0))
FROM wallets w
LEFT JOIN (
  SELECT user_id, SUM(delta_coins) AS sum_delta FROM coin_ledger GROUP BY user_id
) l ON w.user_id = l.user_id
WHERE w.balance_coins <> COALESCE(l.sum_delta, 0);
```

Health-check captura drift em tempo real (não só 1x/dia).

---

### 🟠 [8.8] `audit_logs` sem retenção / particionamento

**Achado** — Tabela cresce indefinidamente. Sem particionamento por mês.

**Risco** — Após 2 anos: 100M+ rows, queries de compliance levam minutos, backups inchados.

**Correção** —

```sql
-- Partition by month
CREATE TABLE audit_logs_new (...) PARTITION BY RANGE (created_at);
-- Migrate data; create 24 monthly partitions ahead.
-- pg_cron: drop partitions older than 2 years (LGPD justifica retenção por auditoria fiscal; 5 anos para dados fiscais).
```

---

### 🟡 [8.9] Event schema sem **registry** / contract

**Achado** — `ProductEvents` é uma classe com constantes. Novos events são criados ad-hoc; sem canonical list nem doc do payload esperado.

**Correção** — `docs/analytics/EVENT_CATALOG.md` + Zod schemas em `portal/src/lib/analytics/events.ts` com tipagem compartilhada entre Flutter (code-gen) e portal.

---

### 🟡 [8.10] Sem **cohort analysis** estruturada

**Achado** — Grep não encontrou tabela `cohort_snapshots` nem views de coorte. Análise de retenção D1/D7/D30 feita ad-hoc.

**Correção** — Materialized view `mv_cohort_retention` refresh semanal.

---

### 🟡 [8.11] Feature flags (quando [6.6] implementar) **precisam** de metrics

**Achado** — Implementação proposta sem auditar quem mudou e quando.

**Correção** — Trigger em `feature_flags` gravando `audit_logs(action='feature_flag.toggled', …)`.

---

### 🟡 [8.12] Mobile: analytics **não enviados quando offline**

**Achado** — `_insert` falha silenciosamente. Eventos de onboarding offline são perdidos.

**Correção** — Queue local em Drift `pending_events`, flush ao conectar.

---

## RESUMO PARTE 4 (40 itens)

| Severidade | Quantidade | IDs |
|---|---|---|
| 🔴 CRÍTICO | 5 | 6.1, 6.2, 7.1, 7.2, 8.1, 8.2 |
| 🟠 ALTO | 12 | 6.3–6.8, 7.3–7.6, 8.3–8.8 |
| 🟡 MÉDIO | 13 | 6.9–6.13, 7.7–7.13, 8.9–8.12 |

### Pontos que devem ser "blockers de GA":

1. **[6.1] Runbooks financeiros** — lançar produto com dinheiro real sem runbook = negligência operacional.
2. **[6.2] Health info leak** — endpoint público revelando estado de invariantes financeiras.
3. **[7.2] Onboarding unificado** — coach amador (uma das personas **explicitamente pedidas** pelo usuário original) não tem fluxo adequado; churn massivo no D1 prejudica o PMF.
4. **[8.1] TOCTOU em `trackOnce`** — contaminação silenciosa de todas as métricas de produto; decisões sobre roadmap baseadas em dados errados.

---

**CONTINUA NA PARTE 5** — Lentes 9 (CRO — Regulatório financeiro), 10 (CSO — Security estratégica), 11 (Supply chain/dependências), 12 (Cron/Scheduling profundo), totalizando ~50 itens.

Digite **"continue"** para prosseguir para a PARTE 5.

 I'm noticing some security and data handling issues in the athlete listing endpoint. The query still accepts both English and Portuguese role values even though a migration was supposed to normalize them, which means it's still dealing with legacy data. There's no pagination limit, so it could potentially return thousands of athletes at once, and more critically, the endpoint doesn't verify the caller's role — anyone with a group membership cookie can access the full athlete list including display names, which seems like it should be restricted to coaches or assistants.

Now I'm shifting focus to check the operational side — looking at logging, metrics exposure, and error handling.