---
id: L20-05
audit_ref: "20.5"
lens: 20
title: "Alerts sem canal de severidade"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["webhook", "observability"]
files:
  - portal/src/lib/observability/sentryTuning.ts
  - portal/src/lib/observability/sentryTuning.test.ts
  - portal/sentry.client.config.ts
  - portal/sentry.server.config.ts
  - portal/sentry.edge.config.ts
  - docs/observability/ALERT_POLICY.md
correction_type: process
test_required: true
tests:
  - portal/src/lib/observability/sentryTuning.test.ts
  - docs/observability/ALERT_POLICY.md
linked_issues: []
linked_prs:
  - "commit:75e4a7f"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Helper enrichWithSeverity (beforeSend + beforeSendTransaction) tagga todo evento Sentry com severity P1..P4 derivada da rota. ALERT_POLICY.md documenta routing target: P1=PagerDuty, P2=Slack #incidents, P3=daily digest, P4=silent. Sentry alert rules são config-as-doc (não IaC) — checklist trimestral em ALERT_POLICY.md valida sincronização."
---
# [L20-05] Alerts sem canal de severidade
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** observabilidade / processo
**Personas impactadas:** Plataforma (SRE), DevOps, on-call

## Achado
Sentry enviava emails para catch-all sem distinguir severidade. Resultado:
- Incidente P1 financeiro (`/api/custody/withdraw` 503) chegava no mesmo
  inbox que P4 console.warn de marketing.
- Sinal-ruído baixo → on-call ignora notificações como hábito → real P1
  perde 30min até atenção.
- Sem onde anexar runbook → on-call descobre debaixo de pressão.

## Risco / Impacto
- MTTD (mean time to detect) elevado em P1 financeiro.
- Burnout de on-call por flood de alertas irrelevantes.
- Perda de oportunidade de mitigation antes do impacto crescer.

## Correção implementada

### 1. Tag `severity` automático (código)
`portal/src/lib/observability/sentryTuning.ts` exporta:
- `classifySeverity(pathname)` → `P1` | `P2` | `P3` | `P4`
- `enrichWithSeverity(event)` → mutates evento Sentry adicionando
  `tags.severity` derivado de `event.request.url` ou `event.transaction`

Usado em `beforeSend` + `beforeSendTransaction` nos 3 runtimes (client/
server/edge). Toda issue Sentry agora chega com tag `severity:P1` etc.

### 2. Ladder de classificação
| Tag | Rotas | Notification |
|---|---|---|
| **P1** | `/api/custody/*`, `/api/swap/*`, `/api/withdraw`, `/api/distribute-coins`, `/api/billing/*`, `/api/auth/*` | PagerDuty page |
| **P2** | `/api/coaching/*`, `/api/sessions/*`, `/api/runs/*`, `/api/platform/*` | Slack `#incidents` |
| **P3** | default | Daily digest email |
| **P4** | `/api/health`, `/api/liveness`, `/_next/*`, `/monitoring`, `/favicon` | Silent (storage only) |

### 3. Política completa (docs)
`docs/observability/ALERT_POLICY.md` documenta:
- Routing targets (PagerDuty / Slack / email)
- Response time SLAs por severidade
- Sentry alert rules templates (5 rules: P1 page, P2 Slack, P3 digest,
  P4 silent, SLO burn rate)
- On-call rotation conventions
- Override pattern para casos extraordinários (`scope.setTag("severity", "P1")`)
- Quarterly drill protocol

### 4. Override manual (escape hatch)
Para erros que precisam ser P1 mesmo em rota P3 (e.g. fraude detectada):
```typescript
Sentry.withScope((scope) => {
  scope.setTag("severity", "P1");
  scope.setTag("subsystem", "fraud-detection");
  Sentry.captureException(error);
});
```

## Limitações conhecidas
- Sentry alert rules NÃO são IaC nativo. ALERT_POLICY.md serve como
  spec; configuração no dashboard é checklist manual trimestral.
  Follow-up: avaliar Sentry Terraform provider quando GA.
- Mobile (Flutter) ainda não tem severity tagging. Próxima rodada:
  port `classifySeverity` para Dart e usar como `beforeSend` no
  `sentry_flutter`.

## Teste de regressão
- `vitest run src/lib/observability/sentryTuning.test.ts` — 20 testes
- ALERT_POLICY.md inclui drill protocol trimestral (smoke test do
  routing).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.5]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.5).
- `2026-04-17` — Correção implementada: severity tag automático nos 3 runtimes Sentry, ALERT_POLICY.md completo (routing + SLAs + drill protocol). Promovido a `fixed`.
