---
id: L01-01
audit_ref: "1.1"
lens: 1
title: "POST /api/custody/webhook — Webhook de custódia (Stripe + MercadoPago)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "idempotency", "webhook", "security-headers", "mobile", "portal"]
files:
  - portal/src/app/api/custody/webhook/route.ts
  - portal/src/lib/webhook.ts
  - portal/e2e/api-security.spec.ts
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
# [L01-01] POST /api/custody/webhook — Webhook de custódia (Stripe + MercadoPago)
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL (Next.js) + BACKEND
**Personas impactadas:** Assessoria (admin_master), Plataforma
## Achado
`portal/src/app/api/custody/webhook/route.ts:17-51` valida assinatura (Stripe HMAC-SHA256 com timestamp) mas **MercadoPago só valida HMAC simples, sem timestamp/nonce** (`portal/src/lib/webhook.ts:73-86`).
  - `verifyHmacSignature` não possui janela de tolerância → **replay attack ilimitado** para MP.
  - Não há deduplicação por `event_id` no endpoint (só idempotência via `payment_reference` ao confirmar depósito — replay do *mesmo* evento em janela de concorrência pode criar mensagens duplicadas no log mesmo que o depósito final seja idempotente).
  - O campo `x-gateway` pode vir do cliente (linha 19) e determina qual secret usar — embora a verificação de assinatura ainda falhe se o secret for trocado, isso permite um atacante forçar caminho de verificação mais fraco.
## Risco / Impacto

Um invasor que capture um webhook MP legítimo em trânsito (MITM em proxies, log scraping) pode reprocessar indefinidamente. Consequência: não há ganho financeiro direto (idempotência via `payment_reference` em `custody_deposits`), mas inunda `payment_webhook_events` e audit logs, e interfere com métricas (`metrics.increment("custody.webhook.confirmed", { gateway })`).

## Correção proposta

```typescript
  // portal/src/lib/webhook.ts — adicionar timestamp obrigatório para MP
  export function verifyHmacSignature({ payload, signature, secret, timestampHeader, tolerance = 300 }: ...) {
    if (timestampHeader) {
      const ts = parseInt(timestampHeader, 10);
      if (isNaN(ts) || Math.abs(Math.floor(Date.now() / 1000) - ts) > tolerance) {
        throw new WebhookError("Timestamp out of tolerance");
      }
      payload = `${ts}.${payload}`;  // MP v2 signature scheme
    }
    const computed = crypto.createHmac("sha256", secret).update(payload).digest("hex");
    if (!timingSafeEqual(computed, signature)) throw new WebhookError("Signature mismatch");
  }
  ```
  Trocar também a verificação de `x-gateway` para detecção autoritativa baseada no header presente (`stripe-signature` ou `x-signature`), ignorando `x-gateway` do cliente.

## Teste de regressão

`portal/e2e/api-security.spec.ts` — enviar webhook MP com timestamp 10 min no passado + assinatura válida → esperar 401; sem `x-signature` → 400.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.1).