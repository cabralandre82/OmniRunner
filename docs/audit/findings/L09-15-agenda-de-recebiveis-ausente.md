---
id: L09-15
audit_ref: "9.15"
lens: 9
title: "Portal financeiro sem agenda de recebíveis — coach voa no escuro"
severity: high
status: fix-pending
wave: 0
discovered_at: 2026-04-24
fixed_at: null
closed_at: null
tags: ["finance", "ux", "coach", "billing", "agenda", "forecast"]
files:
  - supabase/migrations/20260424170000_l09_15_financial_agenda.sql
  - portal/src/app/api/financial/generate-cycle/route.ts
  - portal/src/app/api/financial/generate-cycle/route.test.ts
  - portal/src/app/(portal)/financial/agenda/page.tsx
  - portal/src/app/(portal)/financial/page.tsx
correction_type: code
test_required: true
tests:
  - portal/src/app/api/financial/generate-cycle/route.test.ts
linked_issues: []
linked_prs: []
owner: platform-finance
runbook: null
effort_points: 3
blocked_by: ["L09-13"]
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L09-15] Portal financeiro sem agenda de recebíveis — coach voa no escuro

> **Lente:** 9 — CRO/Finance · **Severidade:** 🟠 High · **Onda:** 0 · **Status:** fix-pending

**Camada:** Portal (Next.js) + DB RPC
**Personas impactadas:** coach/admin (não tem como planejar cobrança),
assessoria (não consegue responder "quanto entra em caixa na próxima
semana?"), plataforma (fricção alta na conversão de trial → paid:
assessoria que não vê agenda duvida do produto)

## Achado

O estudo de prontidão de go-to-market do financeiro (2026-04-24)
identificou que o portal não tem nenhuma superfície de **agenda de
recebíveis**:

- `/financial` — 4 KPIs agregados (receita do mês, ativos, inadimplentes,
  crescimento %). Zero granularidade temporal.
- `/financial/subscriptions` — tabela plana com coluna "Próximo
  Vencimento" lida linha a linha. Não agrupa, não ordena por data, não
  projeta.
- `/financial/plans` — CRUD de planos. Não é agenda.

O dado existe desde L23-09 (2026-04-21):
`public.athlete_subscription_invoices` tem `due_date` indexado
(`athlete_sub_invoices_status_due_idx WHERE status IN ('pending',
'overdue')`). RLS `athlete_sub_invoices_staff_read` permite ao
admin_master/coach ler as rows do próprio grupo. Falta só a UI.

Sintomas que o coach relata hoje:

- "Quanto eu vou receber na semana que vem?" — precisa abrir
  Asaas.com.br em paralelo.
- "Quem está prestes a vencer?" — não consegue filtrar, só scrolla
  a lista.
- "Vou viajar, posso cobrar tudo antecipado?" — sem forma de saber o
  que está pendente sem clicar atleta por atleta.
- "Quanto cai em abril?" — soma mental das mensalidades * atletas
  ativos (e erra porque não considera cancelados recentes).

## Impacto

- **Go-to-market**: bloqueio direto. Assessoria demo que abre o portal
  e não vê agenda não fecha contrato — assume que o produto "não é
  sério" no financeiro.
- **Retenção de assinatura**: coach que não vê aging detalhado deixa
  inadimplente passar de 30 dias → vira perda efetiva. Sem agenda,
  o ponto de intervenção (5-10 dias após vencimento) não tem sinal
  visual.
- **DRE/Forecast**: impossível projetar MRR dos próximos 3 meses sem
  agrupamento por período.
- **Superfícies dependentes**: "Minhas mensalidades" do atleta (L09-16
  futuro) e "Aging por faixa" (L09-17 futuro) ambas pressupõem a
  mesma view de agenda.

High (não critical) porque há workaround (coach abre Asaas em paralelo)
e porque o dado já existe — o gap é só de superfície. Mas é o item #1
que bloqueia a mensagem "portal financeiro pronto pra ir a mercado".

## Correção proposta

### 1. DB: RPC scoped + view de projeção

Migration `20260424170000_l09_15_financial_agenda.sql`:

**RPC `fn_subscription_admin_generate_cycle_scoped(p_group_id, p_period_month)`**:

Hoje `fn_subscription_generate_cycle` é service_role only (chamada
por cron). Coach/admin precisa forçar geração pra demo/backfill sem
esperar dia 1 do próximo mês. RPC:

- SECURITY DEFINER.
- Valida `auth.uid()` é `admin_master` ou `coach` de `p_group_id`.
- Valida `p_period_month` é primeiro dia do mês (espelha CHECK da
  tabela).
- Executa o mesmo INSERT ... ON CONFLICT DO NOTHING que o cron faz,
  **filtrado por `group_id = p_group_id`**.
- Retorna `jsonb {inserted, skipped, total_active_subs}`.

**View `v_financial_agenda`** (opcional; só se melhorar legibilidade):

Não incluir agora. Fazer o SELECT inline na page server-component —
estrutura do portal prefere queries explícitas a views (padrão
`/financial/page.tsx` + `/financial/subscriptions/page.tsx`).

### 2. API route — admin-only, throttled

`portal/src/app/api/financial/generate-cycle/route.ts`:

- POST body: `{ period_month?: string }` (default: início do mês corrente).
- Auth: reusa o padrão `/api/custody/withdraw` — busca `coaching_members`,
  checa `role === 'admin_master'`. Coach simples não libera (evita que
  qualquer coach do grupo gere invoices sem coordenação).
- Chama a RPC via `createClient` (user-scoped, RLS aplica).
- Response: `{ ok, inserted, skipped, total_active_subs, period }`.
- Wrapped em `withErrorHandler` (L17-01).

### 3. Page `/financial/agenda`

Server-component lendo `athlete_subscription_invoices` com join em
`coaching_plans` (via `subscription_id → plan_id`? — checar; como
assinatura nova não tem plan_id direto, mostra só o athlete + valor).

Layout:

```
┌─ Agenda de Recebíveis ──────────────────────────────────┐
│  Período: [abril 2026 ▼]                                 │
│                                                          │
│  ┌─ KPIs ────┬──────────┬──────────┬────────────────┐  │
│  │ 7 dias    │ 30 dias  │ Vencidas │ Total do mês   │  │
│  │ R$ 2.400  │ R$ 9.800 │ R$ 600   │ R$ 12.800      │  │
│  └───────────┴──────────┴──────────┴────────────────┘  │
│                                                          │
│  [Forçar geração do ciclo] (admin only, CTA se vazio)   │
│                                                          │
│  ┌─ Lista ─────────────────────────────────────────────┐ │
│  │ 05/mai (qua) · R$ 200 · João · Pending              │ │
│  │ 05/mai (qua) · R$ 200 · Maria · Pending             │ │
│  │ 10/mai (seg) · R$ 250 · Pedro · Pending             │ │
│  │ 15/abr (ter) · R$ 150 · Ana · **Overdue (10d)**     │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

- KPI "7 dias": soma `amount_cents` onde `due_date BETWEEN today AND today+7`.
- KPI "30 dias": idem, +30.
- KPI "Vencidas": soma `amount_cents WHERE status='overdue'` (qualquer
  due_date passado não pago).
- KPI "Total do mês": soma de todas invoices do `period_month` do filtro.

Empty state (zero invoices no mês):

> "Nenhuma fatura para abril ainda. Se hoje é antes do dia 1, as
> faturas serão geradas automaticamente. Para gerar agora
> (demo/backfill), clique abaixo."

### 4. Link no dashboard financeiro

`/financial/page.tsx` ganha um terceiro card linkando pra `/financial/agenda`.

## Teste de regressão

### Unit (vitest) — API route:

- 401 sem auth.
- 400 sem `portal_group_id`.
- 403 se role !== 'admin_master'.
- 400 se `period_month` inválido (não-primeiro-dia-do-mês).
- 200 com body que reflete `{ok, inserted, skipped}` quando RPC
  retorna sucesso.
- 500 wrapped corretamente se RPC lança (via withErrorHandler).

### Manual:

- Admin master clica "Forçar geração" → vê resposta "10 inseridas,
  0 puladas" → F5 → lista popula com invoices pending.
- Não-admin acessa `/financial/agenda` → vê agenda read-only, sem
  botão de geração.

## Cross-refs

- L09-13 (fixed) — `fn_subscription_generate_cycle` agora roda via
  cron; a RPC admin deste finding é um caminho paralelo pra forçar
  manualmente.
- L09-14 (fixed) — `fn_subscription_mark_overdue` popula o status
  `overdue`, consumido pelo KPI "Vencidas" desta agenda.
- L23-09 (fixed) — schema base.
- L09-16 (futuro) — "Minhas mensalidades" do atleta (Flutter). Reusa
  o schema.
- L09-17 (futuro) — aging detalhado por faixa de dias.

## Histórico

- `2026-04-24` — Descoberto na análise de prontidão do financeiro;
  foi o gap #1 listado pelo user ("tem agenda?").
