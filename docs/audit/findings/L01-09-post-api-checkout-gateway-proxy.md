---
id: L01-09
audit_ref: "1.9"
lens: 1
title: "POST /api/checkout — Gateway proxy"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "rate-limit", "mobile", "portal", "edge-function", "migration"]
files:
  - portal/src/app/api/checkout/route.ts
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
# [L01-09] POST /api/checkout — Gateway proxy
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL + BACKEND (Edge Functions)
**Personas impactadas:** Atleta (comprador de produto/coins)
## Achado
`portal/src/app/api/checkout/route.ts:35-52` aceita `product_id` do cliente e encaminha a Edge Function. **Não valida que o produto existe/está ativo antes de enviar**. Se a Edge Function não validar, cria payment intent com product_id inválido.
  - Sessão é obtida via `supabase.auth.getSession()` (linha 37) e o access_token é encaminhado — ok.
  - Rate limit `checkout:${user.id}` — 5/60s (boa defesa).
## Risco / Impacto

Depende da Edge Function (`create-checkout-session` / `create-checkout-mercadopago`). Se a função confiar no `product_id` sem validar `is_active` e `price_cents`, é possível "comprar" produto desativado ou manipular preço (se a função aceitar `price` do body).

## Correção proposta

Pré-validar no portal:
  ```typescript
  const { data: product } = await createServiceClient()
    .from("billing_products")
    .select("id, is_active, price_cents")
    .eq("id", productId)
    .eq("is_active", true)
    .maybeSingle();
  if (!product) return NextResponse.json({ error: "Product not available" }, { status: 404 });
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.9).