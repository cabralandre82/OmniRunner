# Product events — schema runbook

> **Findings:** L08-01 (TOCTOU race) + L08-02 (PII leak via free-form jsonb)
> **Severidade base:** P3 (manutenção); P2 se PII detectado em produção.
> **Tempo alvo:** ack < 4 h, mitig < 24 h.

## Quando este runbook se aplica

1. Você precisa **adicionar um novo product event** (mobile, portal, ou
   futura origem — Edge Function, worker, Glue job).
2. Você precisa **adicionar uma nova property key** a um event
   existente.
3. CI / produção começou a logar `[analytics] dropping invalid
   product event "..."` ou `Dropping invalid product event "..."`
   (Dart) com volume sustentado → drift entre client whitelist e
   trigger Postgres.
4. Sentry / log search pegou `SQLSTATE PE001..PE005` em produção →
   alguém tentou enviar payload fora do schema (provavelmente
   regressão em outro PR — bisecte).
5. Auditoria detectou um valor PII em `product_events.properties`
   (CPF, email, lat/lng, polyline, comment livre) — ver seção
   "Resposta a incidente PII" abaixo.

## Arquitetura de defesa (recap)

```
┌──────────────────────────────────────────────────────────────┐
│ Client (Dart, TS, Edge Function, ...)                        │
│   ProductEvents.validate(name, props)   ← fail-fast helper   │
│   ProductEventTracker.track / trackOnce ← drop-and-warn      │
└──────────────────────────────────────────────────────────────┘
                          │ supabase-js / supabase_flutter
                          ▼
┌──────────────────────────────────────────────────────────────┐
│ Postgres                                                     │
│   trg_validate_product_event BEFORE INSERT/UPDATE            │
│     → fn_validate_product_event() raises PE001..PE005        │
│   idx_product_events_user_event_once UNIQUE PARTIAL INDEX    │
│     → blocks duplicate first_*/onboarding_completed (23505)  │
└──────────────────────────────────────────────────────────────┘
```

A camada **Postgres é canônica**. O client whitelist serve para fail
fast em dev/CI e para evitar round-trip; mas mesmo se um client
estiver desatualizado, **nenhuma linha inválida chega na tabela** —
o trigger é a verdade.

## Adicionar um novo event_name

Quatro lugares para atualizar (mantenha alfabético em todos eles):

1. **Postgres trigger** —
   `supabase/migrations/20260421100000_l08_product_events_hardening.sql`
   → array `v_allowed_events` na função `fn_validate_product_event()`.
   Não criar nova migration apenas para incluir um nome — em vez
   disso, criar uma migration "diff" que faz `CREATE OR REPLACE
   FUNCTION fn_validate_product_event()` com a lista atualizada.
2. **Dart constants** —
   `omni_runner/lib/core/analytics/product_event_tracker.dart`
   → `Set<String> ProductEvents.allowedNames` + uma constante
   estática (`static const newEvent = 'snake_case_name';`).
3. **TS constants** —
   `portal/src/lib/product-event-schema.ts`
   → array `PRODUCT_EVENT_NAMES`.
4. **Este runbook** — adicione 1 linha na tabela "Inventário" abaixo
   com origem, propósito e propriedades emitidas.

### Caso especial: novo evento one-shot

Se o evento é **one-shot** (um por usuário, ex.: `first_X` ou
"completion" milestone):

- Use o prefixo `first_` se possível — o predicate da unique partial
  index já pega `first_%`.
- Se não usar `first_`, **edite o predicate**:

  ```sql
  DROP INDEX public.idx_product_events_user_event_once;
  CREATE UNIQUE INDEX idx_product_events_user_event_once
    ON public.product_events(user_id, event_name)
    WHERE event_name LIKE 'first_%'
       OR event_name = 'onboarding_completed'
       OR event_name = 'seu_novo_one_shot';
  ```

- E em Dart, edite `ProductEvents._isOneShot` para incluir o novo nome:

  ```dart
  static bool _isOneShot(String eventName) {
    return eventName.startsWith('first_') ||
        eventName == onboardingCompleted ||
        eventName == seuNovoOneShot;
  }
  ```

## Adicionar uma nova property key

Mesmos quatro lugares:

1. `v_allowed_keys` no trigger Postgres.
2. `Set<String> ProductEvents.allowedPropertyKeys` no Dart.
3. `PRODUCT_EVENT_PROPERTY_KEYS` no TS.
4. Este runbook (seção "Inventário de keys" abaixo).

### Política de aprovação

Toda nova key precisa passar 3 critérios — se falhar qualquer um,
**não adicione**:

- [ ] Não é PII (não é CPF, email, telefone, nome, endereço,
      lat/lng, polyline, comment livre).
- [ ] Tipo é primitivo (string ≤ 200 chars, number, boolean, null) —
      se precisa de array/objeto, repensar (use múltiplos events ou
      uma chave `count` em vez do array).
- [ ] Tem revisão humana de Privacy/DPO (qualquer membro de
      `@platform-privacy` no GitHub) registrada no PR.

## Inventário (snapshot 2026-04-21)

### Eventos

| event_name                    | Origem  | One-shot? | Propósito                                            |
|-------------------------------|---------|-----------|------------------------------------------------------|
| `billing_checkout_returned`   | Portal  | não       | Stripe/Asaas checkout volta com `success`/`cancelled`|
| `billing_credits_viewed`      | Portal  | não       | `/credits` visitada                                  |
| `billing_purchases_viewed`    | Portal  | não       | `/billing` visitada                                  |
| `billing_settings_viewed`     | Portal  | não       | `/settings` visitada                                 |
| `first_challenge_created`     | Mobile  | **sim**   | Primeiro desafio criado por usuário                  |
| `first_championship_launched` | Mobile  | **sim**   | Primeiro campeonato lançado por staff                |
| `flow_abandoned`              | Mobile  | não       | Step de onboarding/criação abandonado                |
| `onboarding_completed`        | Mobile  | **sim**   | Onboarding concluído (qualquer rota)                 |

### Keys de properties

| key              | Tipo          | Eventos típicos                                     |
|------------------|---------------|-----------------------------------------------------|
| `balance`        | number        | `billing_credits_viewed`                            |
| `challenge_id`   | string (UUID) | reservado p/ futuro                                 |
| `championship_id`| string (UUID) | reservado p/ futuro                                 |
| `count`          | number        | reservado / contadores                              |
| `duration_ms`    | number        | reservado / latências de step                       |
| `flow`           | string        | `flow_abandoned` (`onboarding`, `challenge_create`) |
| `goal`           | string        | `first_challenge_created`                           |
| `group_id`       | string (UUID) | `billing_*`                                         |
| `method`         | string        | `onboarding_completed`                              |
| `metric`         | string        | `first_championship_launched`                       |
| `outcome`        | string        | `billing_checkout_returned`                         |
| `products_count` | number        | `billing_credits_viewed`                            |
| `reason`         | string        | `flow_abandoned`                                    |
| `role`           | string        | `onboarding_completed`                              |
| `step`           | string        | `flow_abandoned`                                    |
| `template_id`    | string        | `first_championship_launched`                       |
| `total_count`    | number        | `billing_purchases_viewed`                          |
| `type`           | string        | `first_challenge_created`                           |

## Resposta a incidente PII

Se uma auditoria/scan detectou conteúdo PII em
`product_events.properties` (improvável depois do trigger, mas
possível se o trigger estiver desabilitado em algum período histórico):

1. **Stop-the-bleed.** Confirmar que o trigger está ativo em prod:

   ```sql
   SELECT tgname, tgenabled FROM pg_trigger
   WHERE tgname = 'trg_validate_product_event';
   -- tgenabled deve ser 'O' (origin) ou 'A' (always).
   ```

   Se `D` (disabled) ou ausente, reabilitar IMEDIATAMENTE:

   ```sql
   ALTER TABLE public.product_events
     ENABLE TRIGGER trg_validate_product_event;
   ```

2. **Quantificar exposição.** Identificar volume e janela:

   ```sql
   SELECT date_trunc('day', created_at) d, count(*)
   FROM public.product_events
   WHERE properties::text ~* '@|cpf|telefone|polyline|lat|lng'
   GROUP BY d
   ORDER BY d;
   ```

3. **Purgar.** Patch de migração:

   ```sql
   BEGIN;
   DELETE FROM public.product_events
   WHERE properties::text ~* '@|cpf|telefone|polyline|lat|lng';
   COMMIT;
   ```

   (Use `audit.log_lgpd_event` se já estiver configurado.)

4. **Notificar.** Se o volume é > 50 linhas OU janela > 7 dias OU
   contém CPF/email confirmado, abrir incidente LGPD per
   `docs/runbooks/ACCOUNT_DELETION_RUNBOOK.md` (mesma cadeia de
   notificação ANPD).

5. **Postmortem.** Adicionar item de ação: por que o trigger estava
   desabilitado? bisecte de quando.

## Resposta a TOCTOU em produção (L08-01)

Se métricas de funil voltaram a inflar (mais de uma linha
`first_*`/`onboarding_completed` por usuário):

1. **Confirmar o índice.** O índice unique partial deve estar lá:

   ```sql
   SELECT indexname, indexdef FROM pg_indexes
   WHERE indexname = 'idx_product_events_user_event_once';
   ```

   Se ausente, recriar:

   ```sql
   CREATE UNIQUE INDEX CONCURRENTLY idx_product_events_user_event_once
     ON public.product_events(user_id, event_name)
     WHERE event_name LIKE 'first_%' OR event_name = 'onboarding_completed';
   ```

2. **De-duplicar histórico.** Manter o evento mais antigo:

   ```sql
   DELETE FROM public.product_events pe
   USING (
     SELECT user_id, event_name, MIN(created_at) AS keep
     FROM public.product_events
     WHERE event_name LIKE 'first_%' OR event_name = 'onboarding_completed'
     GROUP BY user_id, event_name
     HAVING count(*) > 1
   ) dups
   WHERE pe.user_id = dups.user_id
     AND pe.event_name = dups.event_name
     AND pe.created_at <> dups.keep;
   ```

3. **Bisecte do client.** Confirmar que a versão do app que escreveu
   os duplicates é antiga (pré-L08-01). Forçar upgrade se a versão é
   >= L08-01 deploy date e ainda há duplicate — significa que o
   tracker está usando upsert, não plain insert + 23505 swallow:

   ```bash
   rg --type dart 'productevent.*(upsert|trackonce)' omni_runner/lib
   ```

4. **Republicar BI.** Avisar `#data-team` que dashboards de funil
   precisam re-roda do range afetado.

## CI / monitoramento

- **Per-PR:** `tools/test_l08_01_02_product_events_hardening.ts`
  roda contra Supabase local e detecta drift de whitelist
  cross-language.
- **Per-deploy:** dashboard Sentry `analytics.dropped_event` com
  alerta P3 se taxa > 1/min sustentada por 30min.
- **Drill trimestral:** rodar `psql -c "ALTER TABLE
  product_events DISABLE TRIGGER trg_validate_product_event"`
  em staging, fazer um deploy de prod simulado, confirmar que o
  scan automático (pg_cron `weekly-pii-scan` se existir, ou check
  manual) pega.

## Histórico

- **2026-04-21** — Runbook criado junto com fix L08-01 + L08-02.
