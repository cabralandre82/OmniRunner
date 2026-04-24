---
id: L09-16
audit_ref: "9.16"
lens: 9
title: "Atleta sem tela 'Minhas mensalidades' — não vê o que deve nem o que pagou"
severity: high
status: fixed
wave: 0
discovered_at: 2026-04-24
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["finance", "flutter", "atleta", "billing", "transparency"]
files:
  - omni_runner/lib/domain/entities/athlete_subscription_invoice_entity.dart
  - omni_runner/lib/data/services/athlete_subscription_invoice_service.dart
  - omni_runner/lib/presentation/screens/athlete_my_invoices_screen.dart
  - omni_runner/lib/core/di/data_module.dart
  - omni_runner/lib/core/router/app_router.dart
  - omni_runner/lib/presentation/screens/more_screen.dart
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/entities/athlete_subscription_invoice_entity_test.dart
linked_issues: []
linked_prs: ["8b381e4"]
owner: platform-finance
runbook: null
effort_points: 3
blocked_by: ["L23-09"]
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L09-16] Atleta sem tela 'Minhas mensalidades' — não vê o que deve nem o que pagou

> **Lente:** 9 — CRO/Finance · **Severidade:** 🟠 High · **Onda:** 0 · **Status:** fix-pending

**Camada:** App Flutter (`omni_runner`)
**Personas impactadas:** atleta pagante (não tem visibilidade sobre a
própria cobrança), suporte (atleta vira ticket porque "não sabe se
pagou"), assessoria (perde credibilidade: portal tem agenda, mas o
atleta vê nada)

## Achado

O schema `athlete_subscription_invoices` (L23-09) já existe desde
2026-04-21 com a policy RLS `athlete_sub_invoices_athlete_read` que
permite a qualquer atleta ler `WHERE athlete_user_id = auth.uid()`.
A L09-13 (fixed 2026-04-24) agendou o cron que gera as invoices
mensalmente. A L09-15 (fixed 2026-04-24) entregou a visão de agenda
para o coach.

**Mas o atleta não tem superfície nenhuma**:

- Não existe tela no Flutter para listar as mensalidades.
- Não existe card no "Hoje" ou no dashboard com "você tem R$ 150
  vencendo dia 05".
- Não há notificação quando a invoice vai vencer ou venceu.
- O atleta só descobre que precisa pagar via WhatsApp do coach (se
  o coach lembrar) ou quando o acesso for suspenso.

Sintomas que o atleta relata hoje:

- "Paguei dia 03, por que o app diz que estou inadimplente?" — o
  status é atualizado via webhook do Asaas (L12-xx), mas sem tela
  o atleta não confirma.
- "Quanto eu já paguei esse ano?" — sem histórico, zero
  transparência.
- "Esqueci de pagar, dá pra pagar agora?" — sem link de cobrança
  visível, o atleta depende de ping do coach.
- "Cancelei mês passado, por que ainda aparece cobrança?" — sem
  ver as invoices cancelled, o atleta desconfia da operação.

## Impacto

- **Retenção**: atleta que se sente "no escuro" financeiramente
  desconfia da operação e sai na primeira oportunidade. MRR direto.
- **Volume de suporte**: ticket crônico "estou em dia?" /
  "não consegui pagar". Custo operacional contínuo.
- **Conversão de trial**: assessoria piloto que abre o app no
  celular do cliente e não vê o financeiro do atleta transmite
  falta de produto maduro.
- **Compliance LGPD**: dado pessoal-financeiro do titular sem
  acesso auto-servido formaliza um débito de transparência (BACEN
  e LGPD art. 18.II — o titular tem direito de acesso fácil aos
  próprios dados).
- **Simetria com L05-29**: o coach enxerga a agenda mas o atleta
  não enxerga o que deve; a app fica "coach-first" demais, hostil
  ao pagante.

High (não critical) porque há workaround operacional (perguntar ao
coach), mas é alto impacto em UX e suporte. Bloqueia o discurso de
"produto maduro" — o L09-15 fez metade do trabalho pelo lado do
coach, este finding fecha o loop pelo lado do atleta.

## Correção proposta

### 1. Entity `AthleteSubscriptionInvoice`

Espelho de `public.athlete_subscription_invoices` com os campos que
o atleta vê:

- `id`, `period_month`, `amount_cents`, `currency`
- `due_date`, `status` ('pending' | 'paid' | 'overdue' | 'cancelled')
- `paid_at` (null quando pending/overdue/cancelled)
- `external_invoice_url` (link de pagamento do Asaas — CTA "Pagar
  agora" para pending/overdue)

Getters derivados: `statusLabel`, `statusColor`, `isPayable`,
`isOverdue`, `daysUntilDue` (negativo se vencida).

Factory `fromJson` defensiva (tolera `paid_at` null, status
desconhecido → 'pending', amount_cents parse robusto).

### 2. Service `AthleteSubscriptionInvoiceService`

- `listMyInvoices({required String athleteUserId, int limit = 24})`
  — últimos 24 meses ordenados por `period_month DESC`.
- `.eq('athlete_user_id', uid)` explícito (redundante com RLS, mas
  ajuda o planner).
- Tolera `PGRST205` (migration não aplicada) devolvendo lista
  vazia — mesma convenção do `AthleteExportHistoryService`.

### 3. Screen `AthleteMyInvoicesScreen`

Rota: `/financial/my-invoices` (espelha `/financial/agenda` do
portal).

Layout:

```
┌─ Minhas mensalidades ────────────────────────────────┐
│  [Resumo do mês corrente]                            │
│  ┌─ Abril 2026 · R$ 200 · vence 05/05 ──────┐      │
│  │ Status: Pendente · vence em 11 dias     [Pagar]│ │
│  └─────────────────────────────────────────────┘   │
│                                                       │
│  ──── Histórico ────────────────────────────────     │
│  Março 2026  · R$ 200 · Paga (07/03)                 │
│  Fevereiro   · R$ 200 · Paga (05/02)                 │
│  Janeiro     · R$ 200 · Paga (06/01)                 │
│  ...                                                  │
└───────────────────────────────────────────────────────┘
```

- Card de destaque no topo para invoice "atual"
  (pending/overdue com due_date mais próxima do presente).
- Badge colorido por status: amarelo (pending), vermelho (overdue),
  verde (paid), cinza (cancelled).
- CTA "Pagar agora" quando `external_invoice_url` está presente e
  status é pending/overdue → abre o link no navegador externo.
- Empty state orientativo: "Você não tem mensalidades. Se faz
  parte de uma assessoria com cobrança, peça ao coach para
  iniciar sua assinatura."

### 4. Integração

- DI: registrar `AthleteSubscriptionInvoiceService` em `data_module.dart`
- Rota: `AppRoutes.myInvoices` em `app_router.dart`
- Link: nova seção "Financeiro" em `MoreScreen` (só para não-staff)
  com tile "Minhas mensalidades"

## Teste de regressão

### Unit (flutter_test) — entity:

- `fromJson` com row completa (todos os campos).
- `fromJson` com `paid_at` null (status pending/overdue/cancelled).
- `fromJson` com `status` desconhecido → normaliza para 'pending'.
- `fromJson` com amount_cents como int vs double.
- `fromJson` com `external_invoice_url` null.
- Getters: `isPayable` true para pending/overdue com URL, false
  para paid/cancelled.
- Getters: `daysUntilDue` calcula corretamente (passado, hoje,
  futuro).
- Getters: `statusLabel` pt-BR para cada status.

### Manual:

- Atleta com 1 invoice pending vê card de destaque + CTA "Pagar".
- Atleta com 3 meses pagos vê histórico.
- Atleta sem invoices vê empty state orientativo.
- CTA "Pagar" abre navegador no `external_invoice_url`.

## Cross-refs

- L05-29 (fixed) — padrão arquitetural espelhado (entity + service
  + screen + DI + router + MoreScreen) para "Meus envios ao
  relógio". Mesmo template.
- L23-09 (fixed) — schema base + RLS `athlete_sub_invoices_athlete_read`.
- L09-13 (fixed) — cron `fn_subscription_generate_cycle` popula
  as rows que esta tela lê.
- L09-14 (fixed) — cron `fn_subscription_mark_overdue` é o que
  faz o status virar 'overdue' (consumido pelo badge).
- L09-15 (fixed) — agenda do coach (simétrico, lado do staff).
- L09-17 (futuro) — push notification "fatura vence em 3 dias"
  (construído em cima desta tela; sem a tela a noti não teria
  destino).

## Histórico

- `2026-04-24` — Descoberto como gap simétrico a L09-15. Coach
  tem agenda, atleta não tem.
- `2026-04-24` — **Corrigido em `8b381e4`**. Entrega:
  - `AthleteSubscriptionInvoice` (entity com fromJson defensivo,
    getters `isPayable` / `isOverdue` / `daysUntilDue` /
    `statusLabel`).
  - `AthleteSubscriptionInvoiceService` (lê
    `athlete_subscription_invoices` via RLS `athlete_user_id =
    auth.uid()`, tolera PGRST205, ordenado por
    `period_month DESC` limit 24).
  - `AthleteMyInvoicesScreen` (card de destaque para próxima
    invoice aberta com CTA "Pagar agora" abrindo
    `external_invoice_url` no navegador; histórico com badges
    coloridos por status; empty state orientativo).
  - Rota `/financial/my-invoices` + nova seção "Financeiro" em
    `MoreScreen` (somente atletas).
  - 11 unit tests cobrindo parsing, status coercion, getters e
    `daysUntilDue` (passado/hoje/futuro).
  - `flutter analyze` limpo (só `info` do lint
    `prefer_const_literals_to_create_immutables` nos testes, mesma
    convenção do L05-29).
