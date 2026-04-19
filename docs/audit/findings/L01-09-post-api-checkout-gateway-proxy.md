---
id: L01-09
audit_ref: "1.9"
lens: 1
title: "POST /api/checkout — Gateway proxy"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "rate-limit", "portal", "edge-function", "idempotency", "fail-fast"]
files:
  - portal/src/app/api/checkout/route.ts
  - portal/src/lib/schemas.ts
correction_type: code
test_required: true
tests:
  - portal/src/app/api/checkout/route.test.ts
  - portal/src/lib/schemas.test.ts
linked_issues: []
linked_prs:
  - 644ed89
owner: backend-platform
runbook: docs/runbooks/GATEWAY_OUTAGE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Hardening do proxy `POST /api/checkout` em sete camadas — todas
  defensivas (Edge Functions `create-checkout-{session,mercadopago}`
  já validam tudo internamente e ficaram intocadas).

  ## Context: o que estava errado

  O portal aceitava qualquer `product_id` `min(1)` string (incluindo
  `"prod-1"`, `"../../etc/passwd"`, ou UUIDs aleatórios) e encaminhava
  blindly à Edge Function. Mesmo com rate limit de 5/60s por usuário,
  isso permitia: (a) probe de IDs/format válidos sem custo na vítima
  porque o erro só aparece após cross-region invocation; (b) abuso
  econômico — cada call à Edge Function consome quota Supabase + uma
  call eventual à Stripe/MP API; (c) sem idempotency, double-click no
  botão "Comprar" cria 2 `billing_purchases` rows + 2 sessões Stripe
  pendentes (UX ruim, contabilidade poluída); (d) o atacante não-admin
  consegue forçar Edge calls (Edge rejeita com 403, mas só após o
  invocation cost).

  ## 1. Schema `.strict()` + UUID
  - `checkoutSchema` agora exige `product_id.uuid()` (era `min(1)`),
    `gateway` whitelist (`mercadopago | stripe`), e `.strict()` rejeita
    campos extras. 5 novos casos em `schemas.test.ts`.

  ## 2. Body cap (4 KiB)
  - Schema é só duas strings curtas, 4 KiB dá 100x headroom. Reject
    via 413 PAYLOAD_TOO_LARGE em DUAS gates: `content-length` declarado
    e `Buffer.byteLength` real (atacante mente no header).

  ## 3. Pre-validate produto (fail-fast)
  - Service-role query: `select id, is_active, currency, price_cents
    from billing_products where id = ?`.
    - missing → **404 NOT_FOUND**
    - `is_active=false` → **410 GONE** (semantic > 400 — produto
      *existiu*, sumiu agora; ajuda CDN cache decisions e UX).
    - DB error → 500 INTERNAL_ERROR + métrica
      `checkout.proxy.blocked{reason=product_lookup_error}`.
  - Resultado: zero Edge invocations gastas em produto inválido.

  ## 4. Pre-validate role (fail-fast)
  - Service-role query: `select role from coaching_members where
    group_id = cookie AND user_id = caller`. Não-`admin_master` →
    **403 FORBIDDEN** + métrica
    `checkout.proxy.blocked{reason=not_admin_master}`.
  - Edge Function continua fazendo a mesma validação (defense-in-depth,
    NÃO foi substituída — só adiantada para o portal).

  ## 5. Idempotency (`withIdempotency` wrapper, L18-02)
  - Toda dispatch agora roda dentro de `withIdempotency` com
    namespace `checkout.proxy`, `actorId = user.id`, e
    `requestBody = { product_id, group_id, gateway }` canonicalizado.
  - Cliente envia `x-idempotency-key` (UUID v4 ou opaque
    `[A-Za-z0-9_-]{8,128}`); replay → cache hit retorna a mesma
    `checkout_url` + `purchase_id`. Sem duplicação de
    `billing_purchases`.
  - Header NÃO é obrigatório (back-compat com clientes legacy); rate
    limit 5/60s é o piso de proteção quando `x-idempotency-key`
    ausente.

  ## 6. Envelope canônico
  - `apiError`/`apiOk` com `request_id` propagado (L13-06/L14-05).
    Resposta de sucesso: `{ ok: true, data: { checkout_url,
    purchase_id, gateway } }`.
  - Resposta de erro: `{ ok: false, error: { code, message,
    request_id, details? } }`.
  - Edge responses (`{ ok: false, error: { code, message } }` E
    legacy `{ message }`) são dobradas para o envelope canônico — o
    cliente não precisa mais switchar shape.

  ## 7. Edge call hardening
  - **AbortController + 15s timeout** — antes era unbounded fetch (Edge
    travado = request portal travado). Timeout → **504 GATEWAY_TIMEOUT**
    + métrica `checkout.proxy.gateway_error{reason=timeout}`.
  - **Network error** → **504 GATEWAY_UNREACHABLE** +
    `gateway_error{reason=network}`.
  - **Non-JSON response** (Edge crashado ou WAF intercepting) → **502
    GATEWAY_BAD_RESPONSE** com excerpt dos primeiros 200 chars do body
    para triagem.
  - **Edge 4xx error envelope** → status preservado, `code`
    preservado, `message` preservada — cliente final vê erro idêntico
    ao que a Edge Function emitiu.
  - **`x-request-id` propagado** ao Edge para tracing end-to-end.

  ## 8. Métricas observáveis (gateway dimension em todas)
  - `checkout.proxy.validated{gateway}` — passou pré-validações,
    chegou no idempotency wrapper.
  - `checkout.proxy.blocked{reason}` — rejeitado pré-Edge.
    Reasons: `rate_limit | no_group | body_too_large | invalid_json
    | schema | membership_error | not_admin_master |
    product_lookup_error | product_not_found | product_inactive`.
  - `checkout.proxy.gateway_called{gateway}` — Edge respondeu 2xx.
  - `checkout.proxy.gateway_error{gateway, reason}` — Edge falhou.
    Reasons: `timeout | network | non_json | <edge_code> | http_<status>`.

  ## 9. Tests
  - **`schemas.test.ts`** (+5 = 23 total no describe checkout):
    UUID, gateway override, rejeição de UUID inválido,
    `.strict()`, gateway desconhecido.
  - **`route.test.ts`** (+17 = 23 total): auth 401, rate-limit 429
    com Retry-After, schema 400 missing/non-UUID/extra-fields/JSON
    inválido/body grande, cookie missing 400, role 403/no-membership
    403/membership-error 500, product 404/410/lookup-error 500,
    happy paths Stripe e MP, x-request-id propagation, withIdempotency
    invocation contract, Edge timeout 504, Edge network 504, Edge
    non-JSON 502, Edge 4xx propagation, Edge legacy `{message}`
    fallback.

  ## 10. Resultado
  Suite portal **1295/0 (4 todos)**, lint clean. Sem mudança em Edge
  Functions, sem migração SQL. Risco residual: rate limit ainda no
  in-process LRU (L13-03 cobriu sharding p/ portal multi-instance);
  upgrade para Redis token bucket é trabalho de Onda 2.
---
# [L01-09] POST /api/checkout — Gateway proxy
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed (2026-04-17)
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
- `2026-04-17` — **Fixed** (`644ed89`): hardening em 7 camadas — schema
  `.strict()` + UUID, body cap 4 KiB, pre-validação fail-fast (produto +
  role admin_master), idempotency wrapper, envelope canônico, Edge
  timeout 15s + propagação de request-id, métricas observáveis. 22
  testes adicionais, suite 1295/0.