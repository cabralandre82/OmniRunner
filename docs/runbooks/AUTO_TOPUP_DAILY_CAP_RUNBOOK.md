# AUTO_TOPUP_DAILY_CAP_RUNBOOK

> **Tópico**: cap diário de cobrança auto-topup em
> `billing_auto_topup_settings` (L12-05 — antifraude / hardening do cron).
> **Severidade-alvo**: P2 (assessoria reclama de cap apertado em pico
> legítimo) ou P1 (cap bloqueando rampa fraudulenta detectada).
> **Linked findings**: L12-05, L05-09 (mesmo padrão para custody),
> L17-01 (withErrorHandler), L01-04 (idempotency).
> **Última revisão**: 2026-04-21

---

## 1. Modelo mental (leia antes de qualquer query)

Post L12-05, todo grupo com auto-topup habilitado em
`billing_auto_topup_settings` tem:

| Coluna | Default | Limites | Descrição |
| --- | --- | --- | --- |
| `daily_charge_cap_brl` | **R$ 500,00** | 0 – 100.000 | Teto diário em BRL para `source='auto_topup'` |
| `daily_max_charges` | **3** | 1 – 24 | Teto diário em **contagem** (cron é hourly, máx absoluto = 24) |
| `daily_limit_timezone` | `America/Sao_Paulo` | qualquer IANA | Janela "hoje" |

**O que conta para o cap**: `billing_purchases` com
`source='auto_topup' AND status IN ('pending','paid','fulfilled')
AND currency='BRL'` criadas dentro da janela TZ.

**O que NÃO conta**: `cancelled` (Stripe declined ou rollback);
`source='manual'`; `currency != 'BRL'` (cap é BRL-only — USD seria
inflar o teto sem conversão definida).

**O que dispara o bloqueio**: `fn_apply_auto_topup_daily_cap`,
chamada dentro de `auto-topup-check` Edge Function **antes** de
`stripe.paymentIntents.create`. RAISE `P0010` →
`{ triggered: false, reason: "daily_cap_reached" }`.

**Por que existe**: o cron rodava de hora em hora. Se settings
ficassem mal-configurados (bug ou conta admin_master comprometida)
ou se o `auto-topup-check` fosse invocado inline por N debits em
paralelo (race no `last_triggered_at`), o cliente podia ver até
24 cobranças/dia. Refund manual via Stripe + ticket de suporte é
caro e desgasta a relação. Cap conservador (R$ 500/dia, 3
cobranças/dia) cobre 95% dos casos legítimos.

---

## 2. Cenário A — Assessoria contesta cap apertado

> *"Estamos com 3 cobranças disparadas hoje porque temporada de provas, e a 4ª foi bloqueada. Precisamos liberar."*

### 2.1 Inspecionar a janela atual

Via SQL (se ainda não há endpoint REST exposto):

```sql
SELECT * FROM public.fn_check_auto_topup_daily_window(
  p_group_id := '<group-uuid>',
  p_charge_amount_brl := 0
);
```

Devolve `current_count_today`, `daily_max_charges`,
`current_total_brl`, `daily_charge_cap_brl`, `would_exceed_count`,
`would_exceed_total`, `window_start_utc`, `window_end_utc`,
`timezone`.

### 2.2 Inspecionar histórico recente

```sql
SELECT * FROM public.billing_purchases
WHERE group_id = '<group-uuid>'
  AND source = 'auto_topup'
  AND status IN ('pending', 'paid', 'fulfilled')
ORDER BY created_at DESC
LIMIT 20;
```

### 2.3 Decidir: aumentar o cap ou aguardar

**Aumentar APENAS quando**:

- Volume é coerente com histórico de 30 dias do mesmo cliente.
- Existe pico legítimo (temporada de provas, campeonato,
  agregação de novos atletas) confirmado pela assessoria.
- O atleta admin_master já passou em revisão de segurança no
  trimestre (sem flags de credential-stuffing — L10-09).

**NÃO aumentar quando**:

- Cliente não responde verificação extra.
- Há atividade anômala em `audit_logs.action='auth.login'`
  (geolocation drift, novos UA).
- O ticket veio por canal não-verificado.

### 2.4 Aplicar o aumento (audit-trailed)

Via portal admin_master, ou direto via SQL como service_role:

```sql
SELECT * FROM public.fn_set_auto_topup_daily_cap(
  p_group_id        := '<group-uuid>',
  p_new_cap_brl     := 1500.00,
  p_new_max_charges := 6,
  p_actor_user_id   := '<staff-uuid>',
  p_reason          := 'SUP-1234 — temporada de provas Q2; cliente confirmou volume; CFO ciente',
  p_timezone        := NULL,                    -- preserva o atual
  p_idempotency_key := 'sup-1234-cap-bump-q2'
);
```

A função grava 1 row em `billing_auto_topup_cap_changes` com
`previous_*`, `new_*`, `actor_user_id`, `reason` e
`idempotency_key` para auditoria.

---

## 3. Cenário B — Cap bloqueou ataque suspeito

> *"Vimos N pings de `billing_auto_topup_blocked_daily_cap` no painel para o mesmo grupo em <1h."*

### 3.1 Investigar

```sql
-- Auto-topup blocks recentes
SELECT properties->>'group_id' AS group_id,
       properties->>'charge_amount_brl' AS amount,
       properties->>'hint' AS hint,
       count(*) AS blocks
  FROM public.product_events
 WHERE event_name = 'billing_auto_topup_blocked_daily_cap'
   AND created_at > now() - interval '6 hours'
 GROUP BY 1, 2, 3
 ORDER BY blocks DESC;

-- Login activity para o admin_master do grupo
SELECT * FROM public.audit_logs
WHERE actor_id = (
  SELECT user_id FROM public.coaching_members
  WHERE group_id = '<group-uuid>' AND role = 'admin_master' LIMIT 1
)
  AND action LIKE 'auth.%'
  AND created_at > now() - interval '24 hours'
ORDER BY created_at DESC;
```

### 3.2 Conter

1. **Desabilitar auto-topup imediatamente** (não exige reason — é
   o caminho normal de toggle):

   ```sql
   UPDATE public.billing_auto_topup_settings
      SET enabled = false, updated_at = now()
    WHERE group_id = '<group-uuid>';
   ```

2. **Resetar credenciais do admin_master** via fluxo de password
   reset normal + invalidar sessões ativas.
3. **Notificar a assessoria** por canal verificado.
4. **Abrir ticket interno** com link para os blocks de
   `product_events`.

### 3.3 Pós-mortem

- Reduzir o cap de volta ao default (R$ 500 / 3 cobranças) com
  reason explicando o incidente.
- Verificar se `fn_set_auto_topup_daily_cap` foi chamado por algum
  user não-esperado nos últimos 30 dias:

  ```sql
  SELECT changed_at, actor_user_id, previous_cap_brl, new_cap_brl, reason
    FROM public.billing_auto_topup_cap_changes
   WHERE group_id = '<group-uuid>'
   ORDER BY changed_at DESC;
  ```

---

## 4. Cenário C — Edge function falha em deploy progressivo

> *"Vejo no log: `L12-05 fn_apply_auto_topup_daily_cap not deployed; skipping cap check`."*

Isso é **fail-soft intencional**: se a migration ainda não chegou
ao DB (deploy partial), o edge function emite WARN e segue. Ação:

1. Confirmar se a migration `20260421200000_l12_05_auto_topup_daily_cap.sql`
   está aplicada:

   ```sql
   SELECT * FROM supabase_migrations.schema_migrations
   WHERE name LIKE '%l12_05%';
   ```

2. Se ausente, rodar `supabase db push` ou `supabase migration up`.
3. Re-verificar o log — o WARN deve sumir.

---

## 5. Mapa rápido (TL;DR)

| Pergunta | Resposta |
| --- | --- |
| **Onde está o cap?** | `billing_auto_topup_settings.daily_charge_cap_brl` + `.daily_max_charges` |
| **Quem audita mudanças?** | `billing_auto_topup_cap_changes` (RLS: admin_master OU platform admin) |
| **Quem dispara o bloqueio?** | `fn_apply_auto_topup_daily_cap` dentro de `auto-topup-check` |
| **Erro HTTP?** | Edge devolve `{ triggered: false, reason: 'daily_cap_reached' }`; cron tenta de novo na próxima hora |
| **Como mudar via UI?** | `/portal/settings` → "Limites diários de antifraude (avançado)" — exige reason >= 10 chars |
| **Como mudar via API?** | `POST /api/auto-topup` com `daily_*` + `daily_cap_change_reason` (>=10 chars). Suporta `x-idempotency-key` |
| **Como debugar?** | `SELECT * FROM fn_check_auto_topup_daily_window(group, 0);` |

---

## 6. Tests de regressão

| Local | O que cobre |
| --- | --- |
| `tools/test_l12_05_auto_topup_daily_cap.ts` | Schema, RPCs, guardrail, audit, idempotência (26 testes) |
| `portal/src/app/api/auto-topup/route.test.ts` | API route → RPC mapping, error code translation |
| `portal/src/lib/schemas.test.ts` | Zod superRefine (reason obrigatória), bounds |
| `supabase/migrations/.../self_test DO block` | Schema regression detector (in-migration) |
