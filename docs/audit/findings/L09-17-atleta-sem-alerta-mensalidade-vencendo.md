---
id: L09-17
audit_ref: "9.17"
lens: 9
title: "Atleta sem alerta in-app quando mensalidade está próxima do vencimento"
severity: medium
status: fixed
wave: 0
discovered_at: 2026-04-24
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["finance", "flutter", "atleta", "billing", "engagement", "retention"]
files:
  - omni_runner/lib/domain/policies/financial_alert_policy.dart
  - omni_runner/lib/presentation/widgets/financial_alert_banner.dart
  - omni_runner/lib/presentation/screens/athlete_dashboard_screen.dart
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/policies/financial_alert_policy_test.dart
linked_issues: []
linked_prs: ["252d227"]
owner: platform-finance
runbook: null
effort_points: 2
blocked_by: ["L09-16"]
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L09-17] Atleta sem alerta in-app quando mensalidade está próxima do vencimento

> **Lente:** 9 — CRO/Finance · **Severidade:** 🟡 Medium · **Onda:** 0 · **Status:** fix-pending

**Camada:** App Flutter (`omni_runner`)
**Personas impactadas:** atleta pagante (não recebe lembrete e
esquece de pagar), assessoria (inadimplência sobe), suporte
(pergunta recorrente "vocês não avisam?")

## Achado

Com L09-13, L09-14, L09-15 e L09-16 fechados, o atleta já tem a
tela `/financial/my-invoices` para consultar mensalidades. **Mas
ele precisa abrir a tela ativamente pra descobrir que tem algo
vencendo** — não há nenhum elemento de UI que chame atenção para
uma invoice `pending` próxima do vencimento ou `overdue`.

Resultado: o atleta abre o app para ver treino, ranking, desafios,
mas passa batido pelo financeiro até receber mensagem do coach
(ou até o acesso ser suspenso). A tela existe mas é passiva.

Fontes de dado já disponíveis no app (tudo entregue em L09-16):

- `AthleteSubscriptionInvoiceService.listMyInvoices(uid)` devolve
  as invoices do próprio atleta via RLS.
- Entity `AthleteSubscriptionInvoice` já tem `isPayable`,
  `isOverdue` e `daysUntilDue(now:)`.

O que falta é:

1. **Política** de quando mostrar alerta (quais estados e janelas
   viram banner), centralizada numa função testável.
2. **Widget de banner** in-app que aparece no dashboard do
   atleta quando a política dispara, com CTA que leva a
   `/financial/my-invoices`.

Notificação push real (FCM/APNs) é um passo grande que exige:

- Decisão de vendor (Firebase Messaging já presente? OneSignal?).
- Fluxo opt-in/opt-out LGPD.
- Quiet hours e throttling (para não virar spam).
- Cron/trigger server-side que dispara o push (e não o próprio
  app Flutter).

Este finding cobre o **primeiro degrau**: alerta in-app (aparece
quando o app está aberto). Push real fica para finding futuro
(L09-18, quando houver decisão de produto sobre vendor e opt-in).

## Impacto

- **Retenção**: atleta lembrado paga; esquecido atrasa e
  eventualmente vira churn.
- **Inadimplência**: aging tende a crescer sem reforço ativo.
- **MRR**: cada 1% de atraso evitado = impacto direto no caixa.
- **Suporte**: pergunta crônica "vocês não me avisam?" se
  elimina com o banner.
- **UX**: o coach vê agenda (L09-15), o atleta vê mensalidades
  (L09-16), mas o atleta **só descobre se abrir a tela certa**;
  alerta no dashboard fecha o loop de visibilidade.

Medium (não high) porque:

- A tela L09-16 já existe e o atleta pode consultar ativamente.
- Workaround operacional continua sendo o ping do coach.
- Impacto é em ativação/engajamento, não em acesso a dados.

Mas é `medium` (e não `low`) porque ativa o uso da feature mais
recente e tem correlação direta com MRR.

## Correção proposta

### 1. Policy `FinancialAlertPolicy`

`lib/domain/policies/financial_alert_policy.dart` — pure function
testável, sem dependência de Flutter / Supabase.

Input: `List<AthleteSubscriptionInvoice>` + `now` (injetável).

Output: `FinancialAlert?` (null = sem alerta; preenchido = banner
visível), com campos:

- `level`: `info` | `warning` | `danger` (guia a cor do banner).
- `invoice`: invoice mais urgente (alimenta o CTA "Pagar").
- `title`: string curta pra o banner.
- `subtitle`: string pt-BR explicando o estado.

Regras:

1. Se houver **`overdue`** → `level=danger` (vermelho), invoice
   mais atrasada (maior dias de atraso).
2. Senão se houver **`pending` com `daysUntilDue <= 3`** →
   `level=danger` (vermelho), invoice mais próxima.
3. Senão se houver **`pending` com `daysUntilDue <= 7`** →
   `level=warning` (amarelo), invoice mais próxima.
4. Caso contrário → null (nenhum alerta; banner some).

A lógica é inteiramente baseada em `daysUntilDue` e `status`, o
que permite testar exaustivamente sem mock de Supabase.

### 2. Widget `FinancialAlertBanner`

`lib/presentation/widgets/financial_alert_banner.dart` —
StatefulWidget.

Responsabilidades:

- No `initState`, chama
  `sl<AthleteSubscriptionInvoiceService>().listMyInvoices(uid)`.
- Aplica `FinancialAlertPolicy.computeAlert`.
- Se retorna null: `SizedBox.shrink()` (zero impacto visual).
- Se retorna algo: `Card` colorido conforme `level`, com título,
  subtítulo e tap → `context.push(AppRoutes.myInvoices)`.
- Falhas silenciosas: qualquer erro (rede, RLS, PGRST205)
  degrada pra banner oculto. Log em `AppLogger.warn`, mas NUNCA
  quebra o dashboard.
- Sem botão de dismiss: o banner só some quando a cobrança é
  paga (ou quando a policy para de disparar). Uma flag local
  de "já fechei" pode virar finding futuro se virar fricção.

### 3. Integração no dashboard

`AthleteDashboardScreen` — insere o banner logo abaixo do
header (saudação + subtitle), acima do `_FirstStepsCard`.

Posicionamento escolhido porque:

- Topo = atenção imediata sem rolar.
- Acima dos primeiros passos: financeiro vence primeiros passos
  em prioridade de ativação (se tem cobrança vencida, não faz
  sentido convidar a criar desafio).
- Não compete com o grid: o banner só aparece quando a policy
  dispara, então não é ruído visual.

## Teste de regressão

### Unit (flutter_test) — policy:

- Lista vazia → null.
- Só invoices `paid` → null.
- Só invoices `cancelled` → null.
- `pending` com `daysUntilDue = 10` → null.
- `pending` com `daysUntilDue = 7` → warning.
- `pending` com `daysUntilDue = 4` → warning.
- `pending` com `daysUntilDue = 3` → danger.
- `pending` com `daysUntilDue = 0` → danger.
- `overdue` → danger (independente de dias).
- Mix (overdue + pending imediato) → escolhe a overdue mais
  atrasada.
- Mix (2 pending, um em 2 dias, outro em 6) → escolhe o de 2
  dias (danger).

### Manual:

- Atleta sem invoices: banner não aparece.
- Atleta com invoice paid recente: banner não aparece.
- Atleta com invoice pending vencendo em 5 dias: banner amarelo.
- Atleta com invoice overdue: banner vermelho.
- Tocar no banner: navega para `/financial/my-invoices`.
- Erro de rede: banner não aparece, resto do dashboard segue OK.

## Cross-refs

- L09-16 (fixed) — entity + service + tela que esta feature
  alimenta. Banner reusa tudo.
- L09-15 (fixed) — agenda do coach; simétrico pelo lado staff.
- L09-18 (futuro) — push notification server-side, usando a
  mesma regra da `FinancialAlertPolicy` no worker de cron.

## Histórico

- `2026-04-24` — Descoberto como extensão natural da L09-16: a
  tela existe mas é passiva, atleta não é alertado.
- `2026-04-24` — **Corrigido em `252d227`**. Entrega:
  - `FinancialAlertPolicy` (domain/policies, função pura) com
    regras: overdue → danger; pending ≤3d → danger; pending ≤7d
    → warning; senão → null.
  - `FinancialAlertBanner` (presentation/widgets) lendo via
    `AthleteSubscriptionInvoiceService` (limit=6), degradando
    silenciosamente em erros.
  - Integrado no topo do `AthleteDashboardScreen`, acima de
    primeiros passos.
  - 18 unit tests exaustivos (casos triviais, janelas warning
    e danger, overdue, prioridade entre múltiplas invoices,
    `canPayInline`).
  - `flutter analyze` limpo (0 issues).
