# Omni Runner — Alert Policy

> **Audit ref:** L20-05 — Alerts sem canal de severidade.
> **Source of truth do tagging:** [`portal/src/lib/observability/sentryTuning.ts`](../../portal/src/lib/observability/sentryTuning.ts)
> **Companion docs:** `docs/observability/SLO.md`, `docs/runbooks/`, `docs/postmortems/README.md`.

## Problema que esta policy resolve

Antes desta policy, Sentry enviava email para um catch-all. Resultado:

- Incidente **P1 financeiro** (custody/withdraw down) chegava no mesmo
  inbox que **P4 console.warn** de página de marketing.
- Sinal-ruído baixo → on-call "ignora notificações" como hábito → real
  P1 perde 30min até alguém olhar.
- Sem onde anexar runbook → on-call descobre o caminho debaixo de
  pressão.

## Modelo

Cada evento Sentry recebe um tag `severity` (P1..P4) automaticamente via
`enrichWithSeverity` (rodando em `beforeSend` + `beforeSendTransaction`).
A classificação vem da rota afetada — código canônico em
`portal/src/lib/observability/sentryTuning.ts`.

### Tabela de severidades

| Tag | Definição | Rotas (exemplos) | Notification | Response time SLA |
|---|---|---|---|---|
| **P1** | Money/security/auth — wake someone up | `/api/custody/*`, `/api/swap/*`, `/api/withdraw`, `/api/distribute-coins`, `/api/billing/*`, `/api/auth/*` | PagerDuty page → on-call cellphone | 5min ack, 30min mitigation |
| **P2** | Critical user paths | `/api/coaching/*`, `/api/sessions/*`, `/api/runs/*`, `/api/platform/*` | Slack `#incidents` (no pager, no email) | 1h ack, 4h mitigation |
| **P3** | Default — everything else | tudo não-classificado | Sentry digest email (1×/dia, 09:00 UTC) | next business day |
| **P4** | Pure noise — never alert | `/api/health`, `/api/liveness`, `/_next/*`, `/monitoring`, `/favicon` | Sentry only (no notification) | N/A |

### Source of truth

A classificação está em `portal/src/lib/observability/sentryTuning.ts`,
função `classifySeverity(pathname)`. Modificar a regra requer:

1. PR com mudança em `sentryTuning.ts` + teste atualizado em
   `sentryTuning.test.ts`.
2. PR com correspondente atualização desta tabela.
3. CODEOWNERS approval (platform team).
4. Sincronizar Sentry alert rules (passo manual no dashboard) com a
   nova classificação dentro de 7 dias.

## Sentry alert rules (a configurar — Sentry UI)

Estes são os alert rules que devem existir no Sentry depois desta
policy. Como Sentry alert config NÃO é IaC nativo, documentamos aqui
e validamos manualmente trimestralmente.

### Rule 1 — P1 page on-call
- **Trigger**: error event ingestion AND tag `severity == P1`
- **Aggregation**: 1 event in 1 minute
- **Action**: PagerDuty integration `omni-runner-oncall` (high urgency)
- **Throttle**: 5 events em 5min para mesma issue (anti-flood)
- **Owner**: platform team

### Rule 2 — P2 Slack #incidents
- **Trigger**: error event ingestion AND tag `severity == P2`
- **Aggregation**: 5 events in 5 minutes (deduplica burst)
- **Action**: Slack `#incidents` channel
- **Throttle**: 1 message per 30min para mesma issue
- **Owner**: platform team

### Rule 3 — P3 daily digest
- **Trigger**: error event ingestion AND tag `severity == P3`
- **Aggregation**: digest format (Sentry built-in)
- **Action**: email para `platform-eng@omnirunner.com` 09:00 UTC
- **Owner**: platform team

### Rule 4 — P4 silent
- **Trigger**: error event ingestion AND tag `severity == P4`
- **Action**: NONE — apenas storage para troubleshooting (não consome
  on-call attention)
- **Filter**: NÃO criar issues no Sentry para `P4` (usar inbound
  filters → discard).

### Rule 5 — SLO burn rate (P1 critical SLOs)
Quando Pyrra/Sloth gerar regras Prometheus a partir de `slo.yaml`, mais
um conjunto de alerts entra em jogo (multi-window multi-burn-rate). Ver
detalhe em `docs/observability/SLO.md`.

## Convenções para devs

### Quando emitir log/error com severity custom
99% dos casos: deixar a classificação automática agir — ela inferre da
rota.

Casos extraordinários (override manual):

```typescript
import * as Sentry from "@sentry/nextjs";

// Erro síncrono claramente P1 mesmo em rota P3 (e.g. detected fraud):
Sentry.withScope((scope) => {
  scope.setTag("severity", "P1");
  scope.setTag("subsystem", "fraud-detection");
  Sentry.captureException(error, { extra: { ... } });
});
```

### Quando NÃO emitir nada
- Validation errors (4xx) já são handle-able — não enviar para Sentry
  unless rate exceeds threshold (handled em rate-limit lib).
- User cancel / abort (e.g. `AbortError`) — NÃO é erro do nosso lado.

### Quando criar runbook novo
Sempre que um alerta P1/P2 disparar pela primeira vez SEM runbook
correspondente. Documentar a investigação em `docs/runbooks/<área>-<ação>.md`
durante o postmortem (vira action item automático).

## On-call rotation (a configurar — PagerDuty)

| Cobertura | Schedule |
|---|---|
| Primary on-call | rotação semanal entre platform team |
| Secondary on-call | rotação semanal (fallback) |
| Manager on-call | apenas para SEV-0 com customer escalation |

Hand-off: segunda 09:00 UTC. Owner saindo deve postar em Slack
`#platform-ops`:
> Hand-off: nada quente. SLOs em 99.94% (deposit), 99.97% (withdraw).
> Próximo: @next-oncall.

## Testar a policy (smoke quarterly)

Trimestralmente, rodar drill de alerting:

1. Forçar erro P1 em ambiente staging (e.g. `throw new Error("smoke
   test P1")` em `/api/swap/test`).
2. Cronometrar:
   - **Tempo até PagerDuty page** (target: < 60s).
   - **Tempo até on-call ack** (target: < 5min).
   - **Tempo até on-call entrar em runbook** (target: < 10min).
3. Repetir para P2 (Slack-only): confirmar não pagou ninguém.
4. Repetir para P4: confirmar zero notificação.
5. Documentar em `docs/postmortems/YYYY-MM-DD-alert-drill.md`.

## Histórico de revisões

| Data | Mudança | Razão |
|---|---|---|
| 2026-04-17 | Versão inicial — 4 níveis (P1..P4), ladder por rota | L20-05 fechado |
