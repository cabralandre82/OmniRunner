# GATEWAY_OUTAGE_RUNBOOK

> **Trigger**: Asaas/Stripe/MercadoPago API down OU error rate > 50% por
> ≥ 5min consecutivos.
> **Severidade**: P1 (degradação visível mas dinheiro existente está
> seguro).
> **Tempo alvo**: ack < 10min, mitigação < 15min.
> **Linked findings**: L06-01, L06-05 (edge functions sem retry), L06-06
> (kill switches), **L01-01 (custody webhook receiver hardening)**,
> **L01-09 (`POST /api/checkout` proxy hardening)**.
> **Última revisão**: 2026-04-17

---

## 1. Sintoma

- Sentry alert: `gateway_error_rate > 0.5` na route
  `/api/billing/asaas/*` ou edges `payout-asaas`, `asaas-webhook`.
- StatusGator / Asaas status page (status.asaas.com) mostra incident.
- Ticket support: "não consigo pagar".
- Painel `financial-ops.json` panel "Withdraw availability" cai.

## 2. Diagnóstico (≤ 5min)

### 2.1 Confirmar que é gateway, não nosso código
```bash
# Asaas
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" \
  -H "access_token: $ASAAS_PROD_API_KEY" \
  https://api.asaas.com/v3/myAccount/status

# Stripe
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" \
  -u "$STRIPE_SECRET_KEY:" https://api.stripe.com/v1/balance
```

| Resposta | Conclusão |
|---|---|
| HTTP 5xx OU timeout > 10s | Gateway down — seguir runbook |
| HTTP 200 < 1s | Gateway OK — problema é nosso (SAIR deste runbook, abrir incident interno) |
| HTTP 401/403 | Credenciais (passo 2.2) |

### 2.2 Credenciais válidas?
```sql
-- Asaas: secret no vault
SELECT public.fn_ppc_get_api_key('<GROUP_ID>'::uuid, 'gateway_outage_diag') IS NOT NULL AS has_key;
```
Se `false` → ver L01-17 / `docs/audit/runbooks/L01-17-asaas-vault-rotation.md`.

### 2.3 Quantas operações estão sendo afetadas?
```sql
-- Edge function failures last 15min (assume L06-09 instrumentado)
SELECT route, status_code, COUNT(*) AS errors
FROM public.edge_function_metrics
WHERE created_at > now() - interval '15 minutes'
  AND status_code >= 500
GROUP BY route, status_code
ORDER BY errors DESC;
```

## 3. Mitigação (≤ 10min)

### 3.1 Habilitar kill switch para evitar fila lixo

UI (preferido): `/platform/feature-flags` → toggle `custody.deposits.enabled`
e `custody.withdrawals.enabled` para OFF, motivo "Asaas down".

SQL (off-hours):
```sql
UPDATE public.feature_flags
SET enabled = false,
    reason = 'GATEWAY_OUTAGE_RUNBOOK: Asaas down',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key IN ('custody.deposits.enabled', 'custody.withdrawals.enabled')
  AND scope = 'global';

-- Confirma estado + audit
SELECT key, enabled, reason FROM public.feature_flags
WHERE key LIKE 'custody.%' OR key = 'distribute_coins.enabled';

SELECT changed_at, flag_key, action, old_enabled, new_enabled, reason
FROM public.feature_flag_audit
WHERE changed_at > now() - interval '15 minutes'
ORDER BY changed_at DESC;
```

Routes `/api/custody/withdraw` e `/api/custody/deposit` retornam 503
com `Retry-After: 60` quando flag é false.

> **Fail-open**: se a flag não existir (setup novo), `isSubsystemEnabled`
> retorna `true` por design (sistema continua operando). Para fail-closed
> imediato use Vercel env var `KILL_SWITCH_DEPOSIT_CREATE=true` +
> redeploy (2-3min) em paralelo ao incident.

### 3.2 Banner público de degradação

```sql
UPDATE public.feature_flags
SET enabled = true,
    reason = 'GATEWAY_OUTAGE_RUNBOOK: gateway down, mostrar banner público',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key = 'banner.gateway_outage' AND scope = 'global';
```

Portal lê via `isFeatureEnabled('banner.gateway_outage')` e renderiza
mensagem do `metadata->>i18n_key`.

Mensagem padrão (i18n key `banner.gateway_outage_message`):
> "Estamos enfrentando intermitência no provedor de pagamentos.
> Depósitos e saques podem demorar mais que o normal. Saldo existente
> está seguro. Acompanhe em status.omnirunner.app."

### 3.3 Pausar crons que dependem do gateway

```sql
-- Lista crons que tocam Asaas/Stripe
SELECT jobid, jobname, schedule
FROM cron.job
WHERE command LIKE '%asaas%' OR command LIKE '%stripe%' OR command LIKE '%payout%';

-- Pausar (NÃO unschedule — só temporariamente)
SELECT cron.alter_job(<JOBID>, schedule => '0 0 31 2 *');  -- 31 fev = nunca
```

Anotar `<JOBID>` original para restaurar em §6.

### 3.4 Edge functions com retry escalado (se L06-05 implementado)

Verificar circuit-breaker em `supabase/functions/_shared/asaas.ts`.
Se ainda em estado `closed`, aguardar — abrirá automaticamente após N
falhas. Se já `open`, edge functions retornam 503 imediato sem chamar
Asaas (correto).

## 4. Aguardar resolução do gateway

- Subscrever updates: status.asaas.com / status.stripe.com.
- Postar em `#incidents` cada 30min com status.
- Se outage > 4h, considerar migrar emissões NOVAS para fallback
  (Stripe se Asaas down, MercadoPago se Stripe down) — só se tier
  premium do produto justifica complexidade. Para v1, **aguardar é OK**.

## 5. Restart pós-recovery

Verificar que o gateway voltou (passo 2.1) e estável por ≥ 10min antes
de:

### 5.1 Drenar fila de webhooks acumulados
```sql
-- Quantos webhooks chegaram durante outage?
SELECT COUNT(*), MIN(created_at), MAX(created_at)
FROM public.payment_webhook_events
WHERE created_at > '<OUTAGE_START_UTC>' AND processed = false;
```

Ver `WEBHOOK_BACKLOG_RUNBOOK.md` para drenagem ordenada.

### 5.2 Reabrir kill switches
UI: toggle `custody.deposits.enabled` e `custody.withdrawals.enabled`
para ON com motivo "gateway recovered, smoke OK".

SQL:
```sql
UPDATE public.feature_flags
SET enabled = true,
    reason = 'GATEWAY_OUTAGE_RUNBOOK: gateway recovered, smoke OK',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key IN ('custody.deposits.enabled', 'custody.withdrawals.enabled')
  AND scope = 'global';
```

Smoke test:
```bash
# Criar deposit teste 1 BRL pelo portal staging-mirroring-prod
# Aguardar webhook → processado → deposit confirmed
```

### 5.3 Reativar crons
```sql
SELECT cron.alter_job(<JOBID>, schedule => '<ORIGINAL_SCHEDULE>');
```

### 5.4 Remover banner
```sql
UPDATE public.feature_flags
SET enabled = false,
    reason = 'GATEWAY_OUTAGE_RUNBOOK: incident resolved, hide banner',
    updated_by = auth.uid(),
    updated_at = now()
WHERE key = 'banner.gateway_outage' AND scope = 'global';
```

## 6. Validação pós-incident

- [ ] Smoke test E2E: deposit + withdraw em staging passou
- [ ] `payment_webhook_events WHERE processed=false` count → < 10
- [ ] Sentry error rate em `/api/billing/*` → baseline (< 1%)
- [ ] `check_custody_invariants()` → 0 rows
- [ ] Cron jobs voltaram a `active=true` e `last_status='succeeded'`

## 7. Postmortem

Obrigatório se:
- Outage > 1h, OU
- Algum withdraw stuck causou loss/refund manual, OU
- Algum cliente pediu reembolso por SLA quebrado

Atenção especial no postmortem:
- A automação de kill switch funcionou? (Idealmente alguém adicionou
  alerta que ATIVA o kill switch automaticamente quando error_rate > 0.7
  por 10min — backlog se ainda não existe.)

## Apêndice — referência rápida

| Provider | Status page | API health endpoint |
|---|---|---|
| Asaas | https://status.asaas.com | `GET /v3/myAccount/status` |
| Stripe | https://status.stripe.com | `GET /v1/balance` |
| MercadoPago | https://status.mercadopago.com | `GET /users/me` |

| Métrica | Threshold P1 | Onde ver |
|---|---|---|
| Gateway error rate | > 50% por 5min | Sentry / Grafana panel withdraw availability |
| Webhook delivery lag | > 10min | `MAX(now() - created_at) WHERE processed=false` |
| In-flight withdraws | > 30 | `COUNT(*) WHERE status='processing'` |

## 8. Custody webhook receiver — `/api/custody/webhook` (L01-01)

> Quick reference para o caminho `Stripe + MercadoPago → custody deposit
> confirm`. Para o caminho Asaas billing, ver `ASAAS_WEBHOOK_RUNBOOK.md`.

### 8.1 Como o receiver decide qual gateway é

| Headers presentes                    | Decisão                                  |
|--------------------------------------|------------------------------------------|
| `stripe-signature` apenas            | gateway = `stripe`                       |
| `x-signature` apenas                 | gateway = `mercadopago`                  |
| ambos                                | **400 BAD_REQUEST** (anti header smuggling) |
| nenhum                               | **400 BAD_REQUEST**                      |

`x-gateway` enviado pelo cliente é **ignorado** — herança removida em
L01-01 porque permitia forçar o caminho de verificação mais fraco.

### 8.2 Replay window

| Gateway     | Tolerância | Cabeçalho     | Manifest assinado                                    |
|-------------|-----------|---------------|------------------------------------------------------|
| Stripe      | 300 s     | `t=…,v1=…`    | `<ts>.<raw body>`                                    |
| MercadoPago | 300 s     | `ts=…,v1=…`   | `id:<data.id>;request-id:<x-request-id>;ts:<ts>;` (v2)<br>fallback `<ts>.<raw body>` |

Webhook fora da janela → **401 UNAUTHORIZED** + `metric
custody.webhook.rejected{reason=signature}`. Bom indicador de:
- relógio do servidor / VPC drift > 5 min — verificar NTP via
  `chronyc tracking` no host.
- gateway está retentando um webhook muito antigo (> 5 min) que vinha
  travado em backlog — neste caso a assinatura antiga está expirada e o
  gateway deveria reassinar; reportar ao support do gateway.

Para emergência onde precisamos aceitar um webhook fora da janela
(forensics ou recuperação de incident), **não** alargar `tolerance` em
produção — preferir reproduzir manualmente o `confirmDepositByReference`
via console:
```typescript
import { confirmDepositByReference } from "@/lib/custody";
await confirmDepositByReference("<payment_reference>");
```

### 8.3 Receiver-side dedup (`custody_webhook_events`)

Toda chamada ao receiver bem-sucedida insere uma row em
`public.custody_webhook_events (gateway, event_id) PRIMARY KEY`. Replays
de mesma (gateway, event_id) **não invocam** `confirmDepositByReference`
nem auditam — apenas tickam a métrica `custody.webhook.replayed`.

Queries operacionais úteis:
```sql
-- Webhooks recebidos nas últimas 24h por gateway
SELECT gateway, count(*) AS received,
       count(*) FILTER (WHERE processed_at IS NOT NULL) AS processed
  FROM public.custody_webhook_events
  WHERE received_at > now() - interval '24 hours'
  GROUP BY gateway;

-- Eventos recebidos mas nunca marcados como processados
-- (indica que confirmDepositByReference falhou após dedup) — investigar
SELECT gateway, event_id, payment_reference, received_at
  FROM public.custody_webhook_events
  WHERE processed_at IS NULL
    AND received_at < now() - interval '5 minutes'
  ORDER BY received_at;

-- Suspeita de replay flood (mesmo event_id chegando muito): NÃO existe
-- — o PK garante 1 row por (gateway, event_id). O contador de replays
-- vive só na métrica.
```

### 8.4 Symptom → fix matrix

| Sintoma                                                  | Diagnóstico                                       | Mitigação |
|----------------------------------------------------------|---------------------------------------------------|-----------|
| Spike de 401 em `/api/custody/webhook`                    | Verificar relógio do host + ts dos payloads recentes | Se NTP drifting, reiniciar `chronyd`; se gateway atrasado, esperar |
| Spike de 400 com `BAD_REQUEST: Both stripe-signature…`    | Proxy mal configurado encaminhando ambos os headers | Auditar L7 LB / WAF; remover header parasita |
| Spike de `custody.webhook.replayed{gateway=stripe}`       | Stripe está retentando porque algum webhook anterior recebeu não-2xx | Conferir 5xx do receiver; estabilizar dependências |
| 413 PAYLOAD_TOO_LARGE                                     | Provedor mandou payload > 64 KiB (incomum)        | Investigar se é teste/prober ou body real anormal — se real, considerar elevar `MAX_WEBHOOK_BODY_BYTES` |
| `processed_at IS NULL` para event antigo                  | `confirmDepositByReference` falhou após dedup     | Reprocessar via shell com `confirmDepositByReference("<ref>")` |
| `metric custody.webhook.error{reason=dedup}` aparecendo   | `fn_record_custody_webhook_event` indisponível ou timeout | Verificar lock_timeout em PG; verificar saúde do schema |

### 8.5 Rollback do hardening (last resort)

Se uma regressão grave aparece, o caminho seguro de rollback é reverter
o commit do receiver — **NÃO** desativar dedup ou tolerance em produção.
A migration `20260419170000_l01_custody_webhook_dedup.sql` é seguro
manter mesmo após revert do código (a tabela vira write-only do código
antigo; sem prejuízo).

## 9. Checkout proxy — `/api/checkout` (L01-09)

> Quick reference para o caminho `Portal → Edge `create-checkout-*` →
> Stripe/MP`. Edge Functions ficaram intocadas; toda a defesa nova está
> na route handler.

### 9.1 Camadas de defesa (em ordem, fail-fast)

| # | Gate                       | Resposta na falha          | Métrica                                            |
|---|----------------------------|----------------------------|----------------------------------------------------|
| 1 | Auth                       | 401 UNAUTHORIZED           | —                                                  |
| 2 | Rate limit (5/60s/user)    | 429 + `Retry-After: 60`    | `checkout.proxy.blocked{reason=rate_limit}`        |
| 3 | Group cookie               | 400 BAD_REQUEST            | `…{reason=no_group}`                               |
| 4 | Body cap 4 KiB             | 413 PAYLOAD_TOO_LARGE      | `…{reason=body_too_large}`                         |
| 5 | JSON parse                 | 400 VALIDATION_FAILED      | `…{reason=invalid_json}`                           |
| 6 | Schema (UUID, .strict)     | 400 VALIDATION_FAILED      | `…{reason=schema}`                                 |
| 7 | Role = admin_master        | 403 FORBIDDEN              | `…{reason=not_admin_master\|membership_error}`     |
| 8 | Produto exists + active    | 404 NOT_FOUND \| 410 GONE  | `…{reason=product_not_found\|product_inactive\|product_lookup_error}` |
| 9 | Idempotency (L18-02)       | 400 IDEMPOTENCY_KEY_INVALID \| 409 CONFLICT | (replay → `x-idempotent-replay: true`) |
| 10| Edge dispatch (15s timeout)| 504 GATEWAY_TIMEOUT        | `checkout.proxy.gateway_error{reason=timeout}`     |
| 11| Edge response shape        | 502 GATEWAY_BAD_RESPONSE   | `…{reason=non_json}`                               |
| 12| Edge 4xx envelope          | propagated (status + code) | `…{reason=<edge_code>\|http_<status>}`             |

Sucesso: **200 OK** com `{ ok: true, data: { checkout_url, purchase_id,
gateway } }` + métrica `checkout.proxy.gateway_called{gateway}`.

### 9.2 Symptom → fix matrix

| Sintoma                                                | Diagnóstico                                                    | Mitigação |
|--------------------------------------------------------|----------------------------------------------------------------|-----------|
| Spike de 410 GONE                                      | admin_master está clicando produto recém-desativado            | UI deveria desabilitar produto inactive — abrir bug |
| Spike de 504 GATEWAY_TIMEOUT (gateway=stripe)          | Stripe API lenta OU Edge function travada                      | Confirmar via §2.1 + Stripe status; se Edge travada, redeploy |
| Spike de 502 GATEWAY_BAD_RESPONSE                      | Edge crashado / WAF intercepting                               | Ver `excerpt` no log estruturado; conferir Edge logs |
| Spike de `checkout.proxy.blocked{reason=schema}`       | Cliente desatualizado mandando product_id legacy (não-UUID)    | Verificar versão de Portal/mobile; coordenar release |
| Spike de `checkout.proxy.blocked{reason=not_admin_master}` | Tentativa de abuse OU bug em UI mostrando botão para não-admin | Auditar `coaching_members` por user_id; revisar UI gating |
| `checkout.proxy.gateway_called` baixo + `validated` alto | Idempotency replays — usuários clicando demais                | Sem ação; é o comportamento desejado, fechar incident |

### 9.3 Idempotency cheatsheet

Cliente DEVE enviar `x-idempotency-key: <UUID v4 ou opaque
[A-Za-z0-9_-]{8,128}>` no `POST /api/checkout`. O wrapper armazena a
resposta por **24h** (TTL default do `withIdempotency`). Replays no
window:

```bash
curl -X POST https://portal.omnirunner.app/api/checkout \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(uuidgen)" \
  -H "Cookie: …" \
  -d '{"product_id":"<uuid>","gateway":"stripe"}'
# → 200 OK com checkout_url
# Repetir EXATAMENTE o mesmo body + mesma key → mesma checkout_url,
#   header `x-idempotent-replay: true`
# Repetir mesma key com body diferente → 409 IDEMPOTENCY_KEY_CONFLICT
```

### 9.4 Rollback (last resort)

Reverter o commit `644ed89` é seguro a qualquer momento — não há
migration nova nem mudança em Edge Functions. Após revert, o portal
volta ao comportamento legacy (sem pre-validação, sem idempotency
proxy-side, sem timeout de 15s). Edge Functions continuam validando,
então não há risco financeiro — só volta o desperdício de invocations.
