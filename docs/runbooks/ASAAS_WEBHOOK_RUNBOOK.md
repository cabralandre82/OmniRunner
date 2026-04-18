# ASAAS_WEBHOOK_RUNBOOK

> **Trigger**: 401 spike no `asaas-webhook` Edge Function, falha de
> verificação de signature, ou aumento de inserts em
> `billing_webhook_dead_letters` (provider=`asaas`).
> **Severidade**: P1 quando bloqueia confirmação de pagamento (athletes
> com `coaching_subscriptions.status` parado em `grace`/`late`); P2
> quando isolado a uma única assessoria.
> **Tempo alvo**: ack < 15 min, root cause < 1 h, drenagem completa < 4 h.
> **Linked findings**: L01-17 (vault), L01-18 (auth hardening), L06-01
> (operational runbooks), L20-03 (tracing end-to-end).
> **Última revisão**: 2026-04-17

---

## 1. Sintomas

| Sinal | Significado provável |
|---|---|
| 401 spike (Sentry / log) | Token rotacionado em Asaas mas não em vault, OU atacante tentando forjar |
| `payment_webhook_events.processed=false` crescendo | Auth ok mas processing quebrou (DB lock, RPC mudou) |
| `billing_webhook_dead_letters` recebendo `provider=asaas` | Exceção mid-process — cobertura por bug ou Asaas mudou schema |
| `coaching_subscriptions.status='grace'` para tudo de um grupo | Webhooks chegam mas auth falha → status nunca avança |
| Asaas dashboard mostra "Webhook bloqueado" | Asaas suspendeu nossa URL após 100+ erros consecutivos |

## 2. Diagnóstico (≤ 10 min)

### 2.1 Volume e janela

```sql
-- DLQ por hora, últimas 24h
SELECT date_trunc('hour', created_at) AS hour,
       COUNT(*) AS dlq_count,
       COUNT(*) FILTER (WHERE error_message ILIKE '%vault%') AS vault_errors,
       COUNT(*) FILTER (WHERE error_message ILIKE '%token%') AS token_errors
  FROM public.billing_webhook_dead_letters
 WHERE provider = 'asaas'
   AND created_at > now() - interval '24 hours'
 GROUP BY 1 ORDER BY 1 DESC;
```

```sql
-- Auth failures por grupo (Sentry/log → JSON)
-- Buscar logs com message='asaas-webhook auth_failed' e agrupar por reason
-- Reasons possíveis: missing_token, missing_stored_token, weak_stored_token,
-- token_mismatch, signature_invalid
```

### 2.2 É auth ou processing?

```sql
-- Distribuição de status nos últimos 1000 events
SELECT processed, COUNT(*), MAX(error_message) AS sample_error
  FROM public.payment_webhook_events
 WHERE created_at > now() - interval '6 hours'
 GROUP BY 1;
```

- `processed=false` + sem error_message → handler não chegou ao update (auth ok mas DB falhou)
- DLQ alto + `payment_webhook_events` baixo → auth falhando (events nem entram)

### 2.3 Token / signature health-check

```sql
-- Quais grupos têm webhook configurado?
SELECT cg.id, cg.name,
       (ppc.webhook_token_secret_id IS NOT NULL) AS has_token,
       ppc.webhook_id,
       ppc.connected_at,
       ppc.is_active
  FROM public.coaching_groups cg
  LEFT JOIN public.payment_provider_config ppc
    ON ppc.group_id = cg.id AND ppc.provider = 'asaas'
 ORDER BY ppc.connected_at DESC NULLS LAST
 LIMIT 20;
```

```sql
-- Acessos a vault token nas últimas 6h (todos devem ser action='read'
-- com actor_role='service_role')
SELECT secret_kind, action, actor_role, COUNT(*), MAX(accessed_at)
  FROM public.payment_provider_secret_access_log
 WHERE accessed_at > now() - interval '6 hours'
 GROUP BY 1, 2, 3
 ORDER BY 4 DESC;
```

Se aparecer `actor_role` ≠ `service_role` para `read` → escalation
imediata para SRE: alguém está vazando token via auth.uid != null path.

## 3. Cenários comuns

### 3.1 Token rotacionado em Asaas mas não em vault

**Sintoma**: 401 spike concentrado em UM grupo, log reason=`token_mismatch`.

**Fix**:

1. Confirmar com cliente/assessoria que rotaciou.
2. Pegar o NOVO token no painel Asaas (Configurações → Webhooks).
3. Refazer setup via `asaas-sync` com `action=setup_webhook` (gera novo
   webhook_id + token + grava em vault). NÃO tentar atualizar token
   manualmente em SQL — `fn_ppc_save_webhook_token` é a única via
   auditada.

```bash
curl -sX POST "$SUPABASE_URL/functions/v1/asaas-sync" \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"action":"setup_webhook","group_id":"<UUID>","notification_email":"ops@cliente.com"}'
```

4. Após setup, replay dos eventos pendentes (próxima seção).

### 3.2 Vault inacessível (P0001/P0002/P0003 nas RPCs)

**Sintoma**: log reason=`missing_stored_token` ou `vault_error`, todos
os grupos.

**Fix**:

1. Checar saúde do `pgsodium` (extensão de vault):
   ```sql
   SELECT extname, extversion FROM pg_extension
    WHERE extname IN ('supabase_vault', 'pgsodium');
   ```
2. Tentar leitura direta (somente service_role):
   ```sql
   SELECT count(*), bool_and(decrypted_secret IS NOT NULL)
     FROM vault.decrypted_secrets
    WHERE name LIKE 'asaas:webhook_token:%';
   ```
3. Se `bool_and=false` → corrupção; abrir P0 com Supabase support e
   re-rodar `asaas-sync setup_webhook` para todos os grupos afetados
   (rotação compulsória).

### 3.3 Atacante tentando forjar (token leaked)

**Sintoma**: 401 com reason=`token_mismatch` E `missing_token` de IPs
não-Asaas.

**Diagnóstico** (Cloudflare/proxy log):
```
SELECT remote_ip, COUNT(*)
  FROM api_access_log
 WHERE path = '/functions/v1/asaas-webhook'
   AND status = 401
   AND ts > now() - interval '1 hour'
 GROUP BY 1 ORDER BY 2 DESC LIMIT 20;
```

Se IPs não casam com a faixa Asaas (`52.67.0.0/16`, `54.232.0.0/16`,
`18.230.0.0/15` aproximadamente — confirmar com Asaas):

1. **Não bloqueie por IP no Edge Function** — a auth por token já
   protege, e Asaas pode mudar IPs.
2. Se um token específico está sendo testado em loop, ative kill switch:
   ```sql
   UPDATE public.feature_flags SET enabled = false
    WHERE key = 'billing.asaas.webhook' AND scope = 'group'
      AND scope_id = '<group_id>';
   ```
   (ver L06-06 — kill switches operacionais).
3. Rotação preventiva do token (mesma flow do 3.1).
4. Investigação forense: como vazou? DB dump, log dump, pessoa
   com acesso a `vault.secrets`?

### 3.4 Asaas começou a enviar `asaas-signature` (forward-compat)

**Sintoma**: log mostra `signature_verified=true` em todos os events ok,
ou (mais raro) reason=`signature_invalid` em alguns.

`signature_invalid` significa: o token bate, mas o HMAC não. Possíveis
causas:
- Body modificado em trânsito (proxy reescrevendo) — improvável.
- Token usado para HMAC ≠ token usado no header (Asaas usa secret
  separado para signing).

Se for o segundo caso, Asaas precisará nos enviar o signing secret
separado. Hoje tratamos a verificação como opcional e o token único
serve como key. Acompanhar mudança de docs Asaas em
[docs.asaas.com/docs/about-webhooks](https://docs.asaas.com/docs/about-webhooks).

### 3.5 DLQ enchendo (auth ok mas handler quebra)

**Sintoma**: `billing_webhook_dead_letters` cresce, mas
`payment_webhook_events` recebe row (insert ok antes do crash).

**Diagnóstico**:
```sql
SELECT error_message, COUNT(*)
  FROM public.billing_webhook_dead_letters
 WHERE provider = 'asaas'
   AND status = 'pending'
   AND created_at > now() - interval '24 hours'
 GROUP BY 1 ORDER BY 2 DESC LIMIT 10;
```

Padrões comuns:
- `subscription_update: ...` → schema da tabela mudou ou trigger
  rejeitou. Checar migration recente.
- `maintenance_revenue: ...` → CHECK constraint em `platform_fee_config`
  ou `platform_revenue` violada. Pode ser dado inconsistente em fees.
- `Unknown subscription` → mapeamento `asaas_subscription_map` não
  bate. Backfill com `asaas-sync action=create_subscription` se
  legítimo, ou ignorar (DLQ status=`discarded`) se Asaas enviou para
  webhook errado.

## 4. Replay de eventos

### 4.1 Replay por DLQ (handler crashed)

Replay manual reposta no endpoint do webhook com o body persistido:

```sql
-- Pegar payloads pendentes ordenados por idade
SELECT id, payload, headers
  FROM public.billing_webhook_dead_letters
 WHERE provider = 'asaas' AND status = 'pending'
 ORDER BY created_at ASC LIMIT 10;
```

Para cada row, pegar o `payload` (JSON) e o `asaas-access-token`
correspondente ao `group_id`. NÃO replay com token de DLQ — o handler
filtra esse header antes de persistir, então use o token atual de
vault para o grupo:

```bash
# Carregue o token via fn_ppc_get_webhook_token (apenas service_role)
TOKEN=$(psql "$SUPABASE_DB_URL" -tA -c \
  "SELECT public.fn_ppc_get_webhook_token('$GROUP_ID', 'manual-replay');")

curl -sX POST "$SUPABASE_URL/functions/v1/asaas-webhook" \
  -H "asaas-access-token: $TOKEN" \
  -H "Content-Type: application/json" \
  --data @payload.json

# Após sucesso, marcar DLQ row como replayed
psql "$SUPABASE_DB_URL" -c \
  "UPDATE public.billing_webhook_dead_letters
      SET status='replayed', resolved_at=now(),
          resolved_by=NULL, resolution_note='manual replay $(date -Iseconds)'
    WHERE id='<DLQ_ID>';"
```

### 4.2 Replay por `payment_webhook_events` (não-processed)

Se o event entrou em `payment_webhook_events` mas falhou em
`processed=false`, pode-se rodar a lógica de processing diretamente
chamando o handler com o payload original (idempotency garantirá que
não duplica):

```bash
# Pega payload da row pending
psql "$SUPABASE_DB_URL" -tA -c \
  "SELECT payload FROM public.payment_webhook_events
    WHERE asaas_event_id='<EVENT_ID>'" > /tmp/p.json

# Replay (mesma curl da seção 4.1)
```

O handler reentrar no path duplicate-but-not-processed e re-tentará
processar com a lógica atual.

## 5. Métricas a observar (dashboard L20-01)

| Métrica | SLO | Ação se violado |
|---|---|---|
| Auth failure rate (401 por hora) | < 5/h | 3.1 — checar token rotation |
| DLQ insert rate | < 1/h | 3.5 — investigar exception |
| Webhook latency p95 | < 2 s | Vault read lento? Network? |
| `payment_webhook_events` backlog | < 100 unprocessed | WEBHOOK_BACKLOG_RUNBOOK |
| Vault `read` actions/h | matches webhook volume | Se diverge → leakage path |

## 6. Logs estruturados — campos chave

Toda log line do `asaas-webhook` tem:

```json
{
  "level": "info|warn|error",
  "timestamp": "2026-04-17T...",
  "message": "asaas-webhook auth_ok|auth_failed|...",
  "request_id": "<uuid>",
  "group_id": "<uuid>",
  "event": "PAYMENT_RECEIVED",
  "reason": "token_mismatch|signature_invalid|...",
  "signature_verified": false
}
```

Filtrar por `message="asaas-webhook auth_failed"` no Sentry/Logflare
dá visão do tipo de falha em segundos.

## 7. Pós-incidente

1. Postmortem em `docs/postmortems/YYYY-MM-DD-asaas-webhook-<slug>.md`
   (template em `docs/postmortems/README.md`).
2. Atualizar TRIAGE.md ou criar novo finding L01-XX se descoberto bug
   estrutural.
3. Marcar DLQ rows com `status='discarded'` + `resolution_note` se
   forem decisão consciente (ex: assessoria descontinuada).
4. Adicionar teste de regressão em
   `supabase/functions/_shared/asaas_webhook_auth.test.ts` ou
   `tools/integration_tests.ts` quando aplicável.

## 8. Quick-ref de SQLs

```sql
-- Forçar status para active (after manual reconciliation com Asaas):
UPDATE public.coaching_subscriptions
   SET status='active', last_payment_at=now()
 WHERE id='<SUB_ID>';

-- Limpar DLQ velho (>30d, status=replayed/discarded):
DELETE FROM public.billing_webhook_dead_letters
 WHERE status IN ('replayed', 'discarded')
   AND created_at < now() - interval '30 days';

-- Auditar quem leu o token (deve ser apenas service_role):
SELECT actor_role, COUNT(*) FROM public.payment_provider_secret_access_log
 WHERE secret_kind='webhook_token' AND action='read'
   AND accessed_at > now() - interval '7 days'
 GROUP BY 1;
```

## 9. Limitações conhecidas

- **Sem rate limit por grupo no edge function** — Asaas pode enviar
  rajadas legítimas (e.g., billing batch). Atualmente o único
  contenção é o lock no DB. Se virar problema, adicionar `rate_limit`
  do `_shared/`.
- **Sem alarme automático** para DLQ > N — TODO: criar alert policy
  no `observability/alerts/` linkando a este runbook.
- **Replay é manual** — sem fila de retry com backoff. Tracking em
  L06-05.
