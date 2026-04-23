# CUSTODY_DAILY_CAP_RUNBOOK

> **Tópico**: cap diário de depósito em `custody_accounts` (L05-09 — antifraude / AML).
> **Severidade-alvo**: P2 (assessoria reclama de cap apertado durante operação legítima)
> ou P1 (cap não está bloqueando uma rampa fraudulenta detectada).
> **Linked findings**: L05-09, L01-04 (idempotency + ownership), L18-01
> (wallet mutation guard), L03-13 (reverse_custody_deposit_atomic).
> **Última revisão**: 2026-04-21

---

## 1. Modelo mental (leia antes de qualquer query)

Post L05-09, todo grupo (`coaching_groups.id`) tem um **cap diário de
depósito** em `custody_accounts.daily_deposit_limit_usd` (default
**US$ 50.000/dia**, configurável por platform admin). A janela é definida
pela `daily_limit_timezone` da própria conta (default `America/Sao_Paulo`
— produto BR-first).

**O que conta para o cap**: depósitos com `status IN ('pending', 'confirmed')`
criados dentro da janela (`window_start_utc <= created_at < window_end_utc`).

**O que NÃO conta**: `failed`, `refunded` (já revertidos via L03-13 ou
nunca completaram). Isso permite que reversões via
`reverse_custody_deposit_atomic` liberem orçamento dentro do mesmo dia.

**O que dispara o bloqueio**: `fn_apply_daily_deposit_cap`, chamada
automaticamente dentro de `fn_create_custody_deposit_idempotent` no
**miss-path** (chave de idempotência nova). Replays idempotentes da
mesma chave **não re-cobram** o cap (o budget já foi consumido na
criação original).

**Erro emitido**: `SQLSTATE P0010` com mensagem
`DAILY_DEPOSIT_CAP_EXCEEDED: ...`. O endpoint `POST /api/custody`
mapeia para HTTP **422** com `error.code = "DAILY_DEPOSIT_CAP_EXCEEDED"`.

---

## 2. Cenário A — Assessoria contesta cap apertado

> *"Tentamos depositar US$ 80k para um campeonato e o sistema bloqueou. Nosso cap está em US$ 50k. Precisamos de espaço hoje."*

### 2.1 Inspecionar a janela atual

```bash
curl -X GET "$PORTAL_URL/api/platform/custody/$GROUP_ID/daily-cap" \
  -H "Cookie: sb-access-token=$ADMIN_TOKEN"
```

Resposta:

```json
{
  "ok": true,
  "data": {
    "account": {
      "group_id": "...",
      "daily_deposit_limit_usd": 50000,
      "daily_limit_timezone": "America/Sao_Paulo",
      "daily_limit_updated_at": "2026-04-15T18:00:00Z",
      "daily_limit_updated_by": "platform-admin-uuid"
    },
    "window": {
      "current_total_usd": 47500,
      "daily_limit_usd": 50000,
      "available_today_usd": 2500,
      "would_exceed": false,
      "window_start_utc": "2026-04-21T03:00:00Z",
      "window_end_utc": "2026-04-22T03:00:00Z",
      "timezone": "America/Sao_Paulo"
    },
    "history": [/* últimas 20 mudanças */]
  }
}
```

### 2.2 Decidir: aumentar o cap ou aguardar

**Critérios para AUMENTAR** (case-by-case, NUNCA blanket):

- Assessoria com volume sazonal documentado (Black Friday, time trial, championship reveal).
- KYC/AML do grupo concluído (verificar `coaching_groups.kyc_status` quando L09-02 estiver fixed).
- Histórico de depósitos limpo nos últimos 90 dias (sem `custody_dispute_cases` em estado `escalated_cfo`).
- Aumento limitado: **≤ 3× o cap atual** por mudança. Aumentos maiores
  exigem aprovação dual (CFO + CISO).

**Critérios para NÃO AUMENTAR** (esperar a próxima janela):

- Conta criada nas últimas 72 h.
- Última disputa `custody_dispute_cases` aberta com `kind='chargeback'` há < 30 dias.
- IP/device fingerprint da requisição é novo para o grupo.

### 2.3 Aumentar o cap (com audit obrigatório)

```bash
curl -X PATCH "$PORTAL_URL/api/platform/custody/$GROUP_ID/daily-cap" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(uuidgen)" \
  -H "Cookie: sb-access-token=$ADMIN_TOKEN" \
  -d '{
    "daily_deposit_limit_usd": 150000,
    "reason": "Black Friday — assessoria sazonal de alto volume; ticket SUP-1234"
  }'
```

`reason` precisa ter ≥ 10 chars (postmortem obrigatório). Recomendado
incluir o ticket de suporte para forensics.

A mudança grava 1 linha em `custody_daily_cap_changes` + 1 linha em
`portal_audit_log` com `action = 'platform.custody.daily-cap.set'`.

---

## 3. Cenário B — Detectamos uma rampa fraudulenta em andamento

> *"Sentry alertou: grupo XYZ depositou US$ 49k em 2 minutos. Suspeita de account takeover."*

### 3.1 Bloquear depósitos imediatamente

Reduza o cap para **0** (bloqueia tudo) e marque a conta como blocked:

```bash
curl -X PATCH "$PORTAL_URL/api/platform/custody/$GROUP_ID/daily-cap" \
  -d '{
    "daily_deposit_limit_usd": 0,
    "reason": "INC-2026-0421-001 ATO suspeito; bloqueando depósitos pendente investigação"
  }'
```

Em paralelo, marque `custody_accounts.is_blocked=true` via SQL (se
ainda não tiver endpoint dedicado):

```sql
UPDATE public.custody_accounts
   SET is_blocked = true,
       blocked_reason = 'INC-2026-0421-001 ATO suspeito'
 WHERE group_id = '$GROUP_ID';
```

### 3.2 Reverter depósitos suspeitos

Use `reverse_custody_deposit_atomic` (L03-13) para cada deposit que
você quer estornar. Ele subtrai do `total_deposited_usd` (e ajusta
revenue) atomicamente.

```sql
SELECT public.reverse_custody_deposit_atomic(
  p_deposit_id   := '$DEPOSIT_ID',
  p_actor_user_id := '$YOUR_USER_ID',
  p_reason       := 'INC-2026-0421-001 fraud reversal'
);
```

Após reverso, esses depósitos viram `refunded` e **liberam o budget do
cap diário** (não contam mais para a janela). Útil porque o legítimo
usuário pode reentrar mais tarde sem ter "perdido" sua janela.

### 3.3 Restaurar o cap original

Quando a investigação termina:

```bash
curl -X PATCH "$PORTAL_URL/api/platform/custody/$GROUP_ID/daily-cap" \
  -d '{
    "daily_deposit_limit_usd": 50000,
    "reason": "INC-2026-0421-001 resolvido; cap restaurado para o default"
  }'
```

---

## 4. Cenário C — Backfill de cap para um grupo existente

Default da migration: 50_000 USD/dia + TZ `America/Sao_Paulo`. Para
ajustar em massa após uma análise de risco:

```sql
-- AVISO: bypassa fn_set_daily_deposit_cap → não grava audit.
-- Use APENAS para backfills históricos com aprovação CFO + CISO.
-- Para mudanças operacionais use o endpoint PATCH (com audit).
UPDATE public.custody_accounts ca
   SET daily_deposit_limit_usd = CASE
         WHEN coh.kyc_tier = 'tier1_full' THEN 200000.00
         WHEN coh.kyc_tier = 'tier2_basic' THEN 50000.00
         ELSE 5000.00
       END,
       daily_limit_updated_at = now(),
       daily_limit_updated_by = NULL
  FROM public.coaching_groups coh
 WHERE coh.id = ca.group_id
   AND ca.daily_deposit_limit_usd = 50000.00;  -- só toca quem está no default

-- Para audit do backfill, insira manualmente UMA linha agregada:
INSERT INTO public.custody_daily_cap_changes (
  group_id, previous_cap_usd, new_cap_usd, actor_user_id, reason
)
SELECT ca.group_id, 50000.00, ca.daily_deposit_limit_usd, NULL,
       'L05-09 backfill 2026-04-21: cap por kyc_tier (CFO ticket FIN-2026-XXX)'
  FROM public.custody_accounts ca
 WHERE ca.daily_limit_updated_at >= now() - interval '5 minutes';
```

---

## 5. Monitoring & alerting

### 5.1 Top groups close to cap (CFO dashboard)

```sql
SELECT ca.group_id,
       cg.name,
       w.current_total_usd,
       w.daily_limit_usd,
       w.available_today_usd,
       (w.current_total_usd / NULLIF(w.daily_limit_usd, 0))::numeric(5,4) AS pct_used
  FROM public.custody_accounts ca
  JOIN public.coaching_groups cg ON cg.id = ca.group_id
  LEFT JOIN LATERAL public.fn_check_daily_deposit_window(ca.group_id, 0) w ON TRUE
 WHERE w.daily_limit_usd > 0
 ORDER BY pct_used DESC NULLS LAST
 LIMIT 50;
```

### 5.2 Recent cap changes (auditoria)

```sql
SELECT cdc.changed_at,
       cg.name AS group_name,
       cdc.previous_cap_usd,
       cdc.new_cap_usd,
       cdc.actor_user_id,
       cdc.reason
  FROM public.custody_daily_cap_changes cdc
  JOIN public.coaching_groups cg ON cg.id = cdc.group_id
 WHERE cdc.changed_at >= now() - interval '30 days'
 ORDER BY cdc.changed_at DESC
 LIMIT 100;
```

### 5.3 Cap-blocked deposit attempts (Sentry breadcrumb)

`POST /api/custody` com 422 `DAILY_DEPOSIT_CAP_EXCEEDED` aparece em
Sentry como `api.custody.post` warning. Filtre por
`error.code = "DAILY_DEPOSIT_CAP_EXCEEDED"` para ver a frequência.
Spike inesperado = ou (a) campanha legítima não comunicada, ou (b)
fraude tentando.

---

## 6. FAQ

**Por que o cap default é US$ 50k?** É grande o suficiente para a
maioria das assessorias brasileiras (top 95º percentil de depósito
diário em 2026 ≈ US$ 18k). Pequeno o suficiente para limitar exposure
em caso de ATO. Aumente para grupos com KYC tier1 confirmado.

**Posso ter cap diferente para diferentes gateways (Stripe vs
MercadoPago)?** Não — o cap é por grupo, agnostic ao gateway. Se a
política exigir, abra um finding novo (provavelmente L09 série).

**Por que TZ é per-account em vez de global?** Porque assessorias podem
operar em TZ não-BR (assessoria portuguesa em Lisboa, e.g.). O
default `America/Sao_Paulo` cobre 99 % dos clientes; mudar TZ é raro
e exige um UPDATE manual (não exposto via endpoint hoje).

**E se eu precisar de cap por hora ou semana?** Não suportado por
L05-09. Cap diário é o sweet spot de defesa antifraude (granular o
suficiente para limitar dano, grosso o suficiente para não gerar
falsos positivos a cada hora). Caps adicionais entram em Onda 2.

---

## 7. Rollback (caso o cap esteja causando incidentes em produção)

Para desativar **temporariamente** o guardrail (sem reverter a
migration):

```sql
-- AVISO: zera defesa antifraude. Use APENAS sob aprovação CISO + CFO.
UPDATE public.custody_accounts
   SET daily_deposit_limit_usd = 999999999.99,
       daily_limit_updated_at = now(),
       daily_limit_updated_by = NULL;

-- Audit de rollback
INSERT INTO public.custody_daily_cap_changes (
  group_id, previous_cap_usd, new_cap_usd, actor_user_id, reason
)
SELECT id, 50000.00, 999999999.99, NULL,
       'L05-09 ROLLBACK 2026-04-XX: incident INC-XXXX, cap relaxado emergencialmente'
  FROM public.coaching_groups;
```

Para reverter a migration completamente, use:

```sql
DROP FUNCTION IF EXISTS public.fn_set_daily_deposit_cap(uuid, numeric, uuid, text);
DROP FUNCTION IF EXISTS public.fn_apply_daily_deposit_cap(uuid, numeric);
DROP FUNCTION IF EXISTS public.fn_check_daily_deposit_window(uuid, numeric);

-- Restaura fn_create_custody_deposit_idempotent à versão pré-L05-09
-- (migration 20260417260000_custody_deposit_idempotency.sql).

DROP TABLE IF EXISTS public.custody_daily_cap_changes;

ALTER TABLE public.custody_accounts
  DROP COLUMN IF EXISTS daily_limit_updated_by,
  DROP COLUMN IF EXISTS daily_limit_updated_at,
  DROP COLUMN IF EXISTS daily_limit_timezone,
  DROP COLUMN IF EXISTS daily_deposit_limit_usd;
```

**NÃO faça isso sem incident postmortem.** O cap é uma defesa em
profundidade — removê-la deixa a plataforma exposta a money-laundering
via volume splitting.
