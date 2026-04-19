---
id: L01-01
audit_ref: "1.1"
lens: 1
title: "POST /api/custody/webhook — Webhook de custódia (Stripe + MercadoPago)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "idempotency", "webhook", "security-headers", "portal", "replay-attack"]
files:
  - portal/src/app/api/custody/webhook/route.ts
  - portal/src/lib/webhook.ts
  - supabase/migrations/20260419170000_l01_custody_webhook_dedup.sql
correction_type: code
test_required: true
tests:
  - portal/src/lib/webhook.test.ts
  - portal/src/app/api/custody/webhook/route.test.ts
linked_issues: []
linked_prs:
  - 3818b17
owner: backend-platform
runbook: docs/runbooks/GATEWAY_OUTAGE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Hardening completo do receiver `POST /api/custody/webhook` em três
  camadas independentes — qualquer uma sozinha já reduz superfície de
  ataque, juntas dão defesa em profundidade.

  ## 1. Detecção autoritativa de gateway
  - O cabeçalho `x-gateway` enviado pelo cliente é **ignorado**
    completamente. Antes ele influenciava qual secret seria usado para
    verificar a assinatura, criando vetor de "header smuggling": atacante
    com proxy mal configurado que conseguisse injetar `x-gateway:
    mercadopago` numa request originalmente Stripe forçava o caminho de
    verificação MP (mais fraco).
  - Gateway agora vem APENAS de qual cabeçalho de assinatura está
    presente: `stripe-signature` → Stripe; `x-signature` → MercadoPago;
    ambos OU nenhum → **400 BAD_REQUEST** com `metric
    custody.webhook.rejected{reason=ambiguous_gateway}`.
  - Teste positivo: requisição assinada por Stripe com `x-gateway:
    mercadopago` ainda é validada como Stripe e prossegue (não é
    rejeitada — ignorando, não confiando).

  ## 2. MercadoPago — janela de timestamp + manifest v2
  - Novo `verifyMercadoPagoSignature` em `portal/src/lib/webhook.ts`
    parseia `x-signature: ts=<unix>,v1=<hex>`, valida janela de tolerância
    de 300 s (alinhado com Stripe), e assina o manifest v2 oficial:
    `id:<data.id>;request-id:<x-request-id>;ts:<ts>;`
  - Quando `x-request-id` ou `data.id` faltam (test panel da MP, alguns
    eventos administrativos), faz fallback para `<ts>.<raw body>` —
    ainda timestamp-bound (replay > 5 min é rejeitado).
  - Auto-converte timestamps em milissegundos para segundos
    (>= 1e12 → divide por 1000) — a doc da MP é inconsistente histori-
    camente, ficamos pragmáticos.
  - Tolerante a whitespace e ordem dos componentes do header.
  - Substituiu o uso anterior do `verifyHmacSignature` genérico (que
    não tinha proteção de replay alguma — flat HMAC do body).

  ## 3. Receiver-side dedup por (gateway, event_id)
  - Nova migration `20260419170000_l01_custody_webhook_dedup.sql`:
    - `public.custody_webhook_events` com PK composite `(gateway,
      event_id)` (PK = primitivo de dedup; segundo arrival = unique
      violation = replay).
    - `fn_record_custody_webhook_event(p_gateway, p_event_id,
      p_payment_reference, p_payload)` SECURITY DEFINER com
      search_path travado e `lock_timeout=2s` — INSERT … ON CONFLICT
      DO NOTHING + RETURNING decide replay vs nova em uma roundtrip.
    - `fn_mark_custody_webhook_event_processed(gateway, event_id)`
      atualiza `processed_at` após `confirmDepositByReference` ter
      sucesso — permite query forense
      `WHERE processed_at IS NULL AND received_at < now() - 5min`.
    - `fn_prune_custody_webhook_events(p_keep_days int default 30)`
      manual / future cron (Stripe retenta até 3d, MP até 72h, 30d dá
      headroom forense).
    - RLS forced + service-role only.
    - Indexes: `received_at DESC` para triagem; partial
      `(gateway, received_at) WHERE processed_at IS NULL` para o
      backlog query.
    - Self-test em 5 etapas dentro do `BEGIN`/`COMMIT` da migration.
  - Route handler: replay → 200 OK com `replayed: true, event_id` e
    métrica `custody.webhook.replayed{gateway}`. **Não invoca**
    `confirmDepositByReference`, **não** escreve audit log, **não**
    incrementa `custody.webhook.confirmed`. Dedup table missing
    (legacy install sem a migration aplicada) → degrada com warn log
    e prossegue (não 500-a webhooks de clientes pagantes).
  - Complementa (não substitui) a UNIQUE em
    `custody_deposits.payment_reference`: o dedup do receiver fecha
    a janela onde o reference ainda não é conhecido (gateway pode
    enviar o `evt_…` antes do `pi_…` aparecer no payload de
    follow-ups).

  ## 4. Defense-in-depth bonuses
  - **Body cap de 64 KiB**: rejeita via 413 PAYLOAD_TOO_LARGE tanto via
    `content-length` declarado quanto via `Buffer.byteLength` real
    (defesa contra atacante que mente no header e contra
    `request.text()` sem limite do framework).
  - **Envelope canônico** `apiError` com `request_id` propagado
    (L13-06/L14-05).
  - **Logs estruturados** com tags `gateway`, `event_id`,
    `payment_reference`, `request_id` para queries em log aggregator.
  - **Métricas categorizadas** por reason (`signature`,
    `body_too_large`, `ambiguous_gateway`, `invalid_json`,
    `no_event_id`, `no_payment_reference`, `dedup`).
  - **503 quando secret missing** — antes era 400 vazio quando o env
    var estava unset, o que mascarava config drift como "cliente
    mandou request errada".

  ## 5. Tests
  - **`webhook.test.ts`** (+14 = 25 total): MP v2 happy path, fallback
    com x-request-id missing, fallback com data.id missing, mismatch
    com dataId/xRequestId errados (verificador detecta substituição),
    replay > 300s rejeitado, tolerância custom, secret errado, ts/v1
    components missing, v1 vazio, ts não-numérico, ms→s auto-convert,
    whitespace/ordem tolerantes, fallback com payload tamperado.
  - **`route.test.ts`** (novo, 18 cases): rejeição sem signature
    headers, rejeição com ambos (header smuggling), `x-gateway`
    ignorado, Stripe end-to-end, Stripe assinatura errada → 401,
    Stripe ts stale → 401, MP v2 end-to-end, MP replay 401, MP
    assinatura errada 401, dedup replay short-circuit, dedup RPC
    error → 500, dedup table missing → degrada, 413 com
    content-length forjado, 413 com body real grande, missing
    event_id, JSON inválido, already_confirmed sem audit log,
    Stripe secret missing → 503.

  ## 6. Resultado
  - Suite portal **1275/0 (4 todos)**, lint clean, audit verify
    348/348.
  - Migration self-test confirma dedup primitive.
  - Runbook canônico: `docs/runbooks/GATEWAY_OUTAGE_RUNBOOK.md` §8
    (gateway detection table, replay window matrix, queries
    operacionais para `custody_webhook_events`, symptom→fix matrix
    de 6 entries, rollback strategy).
---
# [L01-01] POST /api/custody/webhook — Webhook de custódia (Stripe + MercadoPago)
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed (2026-04-17)
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
- `2026-04-17` — **Fixed** (`3818b17`): authoritative gateway detection
  (ignora `x-gateway`), MercadoPago timestamp window + manifest v2,
  receiver-side dedup via `custody_webhook_events`, body cap 64 KiB,
  envelope canônico, 33 testes, runbook §8 estendido.