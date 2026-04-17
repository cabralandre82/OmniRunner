---
id: L01-18
audit_ref: "1.18"
lens: 1
title: "Asaas Webhook — supabase/functions/asaas-webhook/index.ts"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["webhook", "security-headers", "edge-function", "performance"]
files:
  - supabase/functions/asaas-webhook/index.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L01-18] Asaas Webhook — supabase/functions/asaas-webhook/index.ts
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** BACKEND (Edge Function)
**Personas impactadas:** Assessoria, Plataforma
## Achado
`supabase/functions/asaas-webhook/index.ts:102-104`: aceita `asaas-access-token` do header **OU `accessToken` do payload** (caminho fraco — se o atacante conseguir disparar o endpoint com payload que imita evento Asaas + field `accessToken`, e o token for uma string comum, match ocorre). Como o token é por-grupo e armazenado no DB, um leak do DB expõe todos.
  - Não há HMAC assinado — só um token bearer-style. Asaas suporta HMAC em webhooks mais recentes; não está em uso aqui.
  - Linha 130-135: idempotência por `eventId = "${event}_${paymentId|subId|hash}"`. Hash usa `JSON.stringify(payload).slice(0, 64)` — **colisão trivial** se payloads similares forem enviados (slice de 64 chars de um JSON grande colide facilmente). Não é um risco de exploração, mas pode causar duplicatas ou falsos-positivos de replay.
## Risco / Impacto

Replay / token-reuse em caso de leak DB. Reprocessamento de evento confirmando pagamento (se o DB ainda não marcou `processed`).

## Correção proposta

1. Remover path de `accessToken` no body.
  2. Adicionar suporte a HMAC-SHA256 do Asaas (usando `asaas-signature` header quando disponível).
  3. Trocar hash de fallback por `sha256(payload)` em vez de `slice(0,64)`.
  ```typescript
  const eventKey = asaasPaymentId ?? asaasSubId
    ?? createHash("sha256").update(JSON.stringify(payload)).digest("hex");
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.18]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.18).