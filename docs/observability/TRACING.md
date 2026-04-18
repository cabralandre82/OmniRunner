# Distributed tracing — runbook (L20-03)

> **Lente:** 20 — SRE
> **Audit:** L20-03 — Sem tracing distribuído (OpenTelemetry)
> **Status:** fixed (Wave 1)
> **Owner:** SRE
> **Last updated:** 2026-04-17

## TL;DR

Toda request que atravessa **Mobile → Portal → Supabase RPC → Edge Function → Webhook → DB** carrega o mesmo `trace_id` (32 hex chars). Se um pagamento "demorou 15 segundos", você acha o gargalo em < 60s pulando entre logs e Sentry pelo `trace_id`.

| Camada           | Implementação                            | Header out          | Span name conv.       |
| ---------------- | ---------------------------------------- | ------------------- | --------------------- |
| **Flutter**      | `TracedHttpClient` (Sentry SDK)          | `sentry-trace`, `baggage` | `http.client GET ...` |
| **Portal API**   | Sentry/Next instrumentation auto-detect  | propaga out via `traceparent()` | `withSpan("rpc emit_coins_atomic", "db.rpc", ...)` |
| **Audit log**    | `audit.metadata.trace_id` auto           | n/a                 | `audit ${action}`     |
| **Logger**       | `level: ..., trace_id: ..., span_id: ...` | n/a                | n/a                   |
| **Edge Func**    | Sentry deno-runtime (próxima onda)       | TBD                 | TBD                   |

---

## 1 — Por que existe

Antes de L20-03, um relato de "pagamento lento" forçava o oncall a:

1. Vasculhar logs do portal por timestamp ± window de 30s.
2. Cruzar com Sentry buscando exceptions próximas.
3. Correlacionar à mão com `audit_log` filtrando por `actor_id`.
4. Adivinhar se o gargalo foi mobile, network, portal, RPC, edge function ou Asaas.

Tempo médio de triagem: **~25 min** (medido em retro de 3 incidentes em 2026-Q1).

Com tracing distribuído:

1. Cliente fala "trace_id `abc123...`" (UI mostra) ou support extrai do `audit_log`.
2. Sentry → `https://sentry.io/.../trace/abc123...` mostra a árvore inteira.
3. Cada span tem duração + atributos (db, http, etc.) → gargalo evidente.

Tempo médio esperado: **< 2 min**.

---

## 2 — Como achar um trace_id

### 2.1 — Cliente reportando lentidão

Se a UI ainda exibe a resposta da API, o cabeçalho `X-Trace-Id` (echoed pelo route handler do Portal) traz o trace_id. O suporte deve pedir esse header (ou uma screenshot do Network tab).

Exemplo de request → response do `POST /api/distribute-coins`:

```
HTTP/2 200
content-type: application/json
x-trace-id: a1b2c3d4e5f6...32hex
```

### 2.2 — Pivotando do log para o trace

Logs estruturados emitidos por `portal/src/lib/logger.ts` carregam `trace_id` quando há span ativo:

```json
{"level":"error","msg":"emit_coins_atomic failed","ts":"2026-04-17T...","trace_id":"a1b2...","span_id":"0f1e...","groupId":"..."}
```

Cole o `trace_id` na URL: `https://sentry.io/organizations/<org>/performance/trace/<trace_id>/`.

### 2.3 — Pivotando do banco (audit_log) para o trace

`portal_audit_log.metadata.trace_id` é populado automaticamente pelo `auditLog()` quando há span ativo:

```sql
select id, actor_id, action, metadata->>'trace_id' as trace_id, created_at
  from public.portal_audit_log
 where action = 'coins.distribute'
   and created_at > now() - interval '1 hour'
 order by created_at desc;
```

A partir do `trace_id` retornado, abra a árvore no Sentry.

### 2.4 — Pivotando do Sentry (erro) para o log

Todo Sentry event (erro ou transaction) tem `trace_id` no breadcrumb panel. Use esse valor para grep nos logs (Loki/CloudWatch/Vercel logs):

```
{job="portal"} | json | trace_id="a1b2..."
```

---

## 3 — Como instrumentar novo código

### 3.1 — Wrap a RPC ou external HTTP call em `withSpan`

```ts
import { withSpan } from "@/lib/observability/tracing";

const { data, error } = await withSpan(
  "rpc execute_swap",
  "db.rpc",
  async (setAttr) => {
    const result = await db.rpc("execute_swap", { p_order_id: id, ... });
    if (result.error) setAttr("db.error_code", result.error.code);
    setAttr("db.row_count", Array.isArray(result.data) ? result.data.length : 1);
    return result;
  },
  {
    "db.system": "postgresql",
    "db.operation": "rpc:execute_swap",
    "omni.order_id": id,
  },
);
```

**Convenções de atributos** (siga rigorosamente para discover queries consistentes):

| Key                      | Quando usar                                           |
| ------------------------ | ----------------------------------------------------- |
| `db.system`              | sempre `"postgresql"` para Supabase                   |
| `db.operation`           | `"rpc:fn_name"`, `"select:table"`, `"insert:table"`   |
| `db.error_code`          | sqlstate (`P0001`, `55P03`, etc.) quando `error`      |
| `db.row_count`           | número de rows afetadas/retornadas                    |
| `http.method`/`http.url` | para outbound `fetch()`                               |
| `omni.actor_id`          | UUID do usuário (NÃO PII se for UUID)                 |
| `omni.group_id`          | UUID do grupo                                         |
| `omni.amount`            | valor monetário ou de coin (sempre número)            |
| `omni.kill_switch`       | `true` quando feature flag bloqueou a request         |

### 3.2 — Operações suportadas (`SpanOp`)

Use o tipo literal exportado em `tracing.ts`:

- `db.rpc`, `db.select`, `db.insert`, `db.update`, `db.delete`
- `http.client`
- `audit.write`
- `feature_flag.check`
- `swap.execute`, `custody.deposit`, `custody.withdraw`, `distribute.coins`, `billing.webhook`

Falta uma op? Adicione em `tracing.ts` E atualize esta tabela no mesmo PR.

### 3.3 — Outbound HTTP para serviços first-party

Para um `fetch()` chamando edge function ou outro serviço próprio:

```ts
import { traceparent } from "@/lib/observability/tracing";

const res = await fetch("https://omnirunner.app/api/internal/something", {
  headers: {
    "content-type": "application/json",
    ...traceparent(), // sentry-trace + baggage
  },
  body: JSON.stringify(payload),
});
```

**Não envie** `traceparent()` para terceiros (Asaas, Strava, Sentry, Google APIs). Eles ignoram o header e isso é leak de telemetria.

### 3.4 — Mobile (Flutter) HTTP

Use `TracedHttpClient` para qualquer call que vá para Portal/Supabase:

```dart
import 'package:omni_runner/core/http/traced_http_client.dart';

final client = TracedHttpClient();
final res = await client.get(Uri.parse('$portalUrl/api/distribute-coins'));
```

Para `SupabaseClient.functions.invoke()`:

```dart
final headers = TracedHttpClient.currentTraceHeaders();
final res = await db.functions.invoke(
  'champ-create',
  body: payload,
  headers: headers,
);
```

A allowlist de hosts está em `TracedHttpClient.defaultFirstPartyAllowlist` e é aplicada no `Sentry.init` em `main.dart`. Para **mudar** a allowlist (ex: adicionar staging URL), edite o constant — NÃO mute em runtime.

---

## 4 — Limites e custo

### 4.1 — Sampling

A taxa amostragem é controlada em `portal/src/lib/observability/sentryTuning.ts` (L20-04):

| Severity | Sample rate | Exemplo de rota                    |
| -------- | ----------- | ---------------------------------- |
| P1       | 100%        | `/api/custody/*`, `/api/swap/*`    |
| P2       | 50%         | `/api/coaching/*`, `/api/sessions/*` |
| P3       | 10%         | tudo o mais                        |
| P4       | 0%          | `/api/health`, `/_next/*`          |

Se o sample resultou em `parentSampled=false`, **nenhum span filho é enviado** (mesmo que você chame `withSpan`). Isso é OK — é o trade-off custo/sinal.

### 4.2 — Cardinalidade de atributos

**NUNCA** coloque high-cardinality value como `name` do span. Use atributos:

- ❌ `withSpan(\`fetch user ${userId}\`, "db.select", ...)`
- ✅ `withSpan("fetch user", "db.select", ..., { "omni.user_id": userId })`

Cardinalidade em `name` quebra agregações de p99 e infla custo do Sentry.

### 4.3 — PII

`trace_id` por si só não é PII. **Atributos** podem ser. Regras:

- UUIDs (actor_id, group_id, athlete_user_id) → OK, são opacos.
- Email, CPF, nome → ❌ NUNCA.
- IBAN, número de cartão, token → ❌ NUNCA.
- `external_payment_ref` (livre) → ❌ pode conter PII; só logar hash se necessário.

---

## 5 — Operação durante incidente

### 5.1 — "P0 Pagamento travou para todos"

1. Sentry → ordene transações por p95 desc, filtre últimas 5 min.
2. Pegue a transaction mais lenta na rota afetada (`/api/custody/withdraw`, `/api/distribute-coins`, etc.).
3. Abra a trace tree: identifique o span que toma > 80% do tempo.
   - Se for `db.rpc` → consulta lock_timeout, deadlock, sequential scan.
   - Se for `http.client` → terceiro fora (Asaas, Stripe).
   - Se for `audit.write` → custody saturada.
4. Pivote pelo `trace_id` no log aggregator para ver mensagens estruturadas dentro do span.

### 5.2 — "Cliente reclama de lentidão pontual"

1. Peça `X-Trace-Id` ou screenshot da resposta API.
2. Cole no `https://sentry.io/.../trace/<id>/`.
3. Se trace ausente → Sentry sample dropped (sample rate da rota é < 100%). Fallback: pegue `actor_id` + janela de tempo, busque em `portal_audit_log` filtrando por `metadata->>'trace_id'`.

### 5.3 — "Edge function não aparece no trace"

Edge functions (Deno runtime) ainda não estão instrumentadas. Próxima onda (L20-XX TBD). Workaround: o `audit_log` registrado pela edge function carrega o `trace_id` do request HTTP que a chamou (via header `sentry-trace` se a edge function for chamada com `traceparent()` headers do portal).

---

## 6 — Limitações conhecidas

| Limitação                                              | Impacto       | Plano                                       |
| ------------------------------------------------------ | ------------- | ------------------------------------------- |
| Edge functions sem auto-instrumentação                 | Spans saltados em chamadas portal → edge | Wave 2 (Sentry Deno SDK ou OTLP exporter)   |
| Asaas webhooks chegam sem `sentry-trace` header        | Trace começa do zero no portal            | Wait — Asaas não suporta propagar trace IDs |
| `pg_cron` jobs não criam trace                         | Sweep `fn_expire_swap_orders` invisível   | Pequeno: jobs curtos, baixo risco           |
| Sample = 0% para P4 → trace ausente em rotas low-value | Esperado                                  | Não mudar (custo)                           |

---

## 7 — Checklist de PR

Antes de aprovar PR que toca route handler crítico (custody, swap, distribute-coins, billing):

- [ ] RPCs Supabase envoltos em `withSpan` com `db.system`/`db.operation`/`db.row_count`?
- [ ] Outbound `fetch()` para serviços first-party usa `...traceparent()`?
- [ ] Erros propagam para o span (re-throw após `setStatus`)?
- [ ] Logs estruturados emitidos via `logger.{info,warn,error}` (NÃO `console.log` direto, senão sem `trace_id`)?
- [ ] Audit log usa `auditLog()` (NÃO insert direto em `portal_audit_log`)?

---

## 8 — Referências

- ADR-008 (swap as off-platform credit cession) — exemplo de span name `swap.execute`.
- L20-04 — `tracesSampler` adaptativo (sentryTuning.ts)
- L20-05 — Severity tags (alert routing)
- [Sentry — Distributed tracing](https://docs.sentry.io/concepts/key-terms/tracing/distributed-tracing/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/) — `traceparent`/`tracestate` headers
- [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/) — `db.*`, `http.*` attribute keys
