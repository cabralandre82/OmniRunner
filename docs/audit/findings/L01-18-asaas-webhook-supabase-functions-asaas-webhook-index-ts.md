---
id: L01-18
audit_ref: "1.18"
lens: 1
title: "Asaas Webhook — supabase/functions/asaas-webhook/index.ts"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["webhook", "security-headers", "edge-function", "performance", "idempotency"]
files:
  - supabase/functions/asaas-webhook/index.ts
  - supabase/functions/_shared/asaas_webhook_auth.ts
  - supabase/functions/_shared/asaas_webhook_auth.test.ts
  - supabase/migrations/20260417290000_billing_webhook_dead_letters.sql
  - tools/edge_function_smoke_tests.ts
  - .github/workflows/supabase.yml
  - docs/runbooks/ASAAS_WEBHOOK_RUNBOOK.md
correction_type: feature
test_required: true
tests:
  - supabase/functions/_shared/asaas_webhook_auth.test.ts
  - tools/integration_tests.ts
  - tools/edge_function_smoke_tests.ts
linked_issues: []
linked_prs:
  - "commit:HEAD"
owner: backend-platform
runbook: docs/runbooks/ASAAS_WEBHOOK_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Hardening completo do receiver `asaas-webhook` (Edge Function). Os
  três achados originais foram corrigidos + dois bugs colaterais
  descobertos durante o trabalho.

  ## Mudanças

  ### 1. Auth — header-only (defense-in-depth)
  Removido o path `payload.accessToken` que aceitava token via body.
  Agora apenas `asaas-access-token` (header) é considerado. Por que
  isso importa: um token leak via JSON dump (logs, DLQ, replicação
  lógica) é uma superfície de exposição DIFERENTE de um leak de
  coluna DB. Tratar os dois caminhos como equivalentes diluía o
  ganho do vault (L01-17).

  ### 2. Constant-time comparison
  `safeEq()` em `_shared/asaas_webhook_auth.ts`. Mesmo que timing
  attacks sobre HTTPS sejam teóricos, é prática estabelecida e custo
  zero. Bonus: rejeita imediatamente em mismatch de length (length
  não é segredo) e nunca short-circuita por byte divergente.

  ### 3. HMAC-SHA256 forward-compat
  Se o request inclui header `asaas-signature`, validamos HMAC do raw
  body usando o mesmo `webhook_token` de vault como key. Asaas hoje
  (2026-04) NÃO assina payloads — só envia bearer token. Mas:
    - Quando ligar (eventual), zero código a mudar — opt-in
      transparente. Resposta inclui `signatureVerified: true` no log.
    - Outros gateways (Mercado Pago já usa, Stripe sempre usou) ficam
      cobertos pelo mesmo padrão se replicado.
    - Fail-closed: signature presente mas inválida → 401 mesmo que
      o token esteja ok.

  ### 4. Idempotency hash colidível → SHA-256
  `JSON.stringify(payload).slice(0, 64)` colidia trivialmente para
  payloads que compartilhassem 64 chars de prefixo (ex: dois
  PAYMENT_RECEIVED de pagamentos diferentes mas com mesma ordem de
  campos JSON antes do `payment.id`). Substituído por
  `sha256Hex(rawBody)` — ordem de preferência:
    1. `${event}_${paymentId}` (caso comum, ~99.5%)
    2. `${event}_${subscriptionId}` (SUBSCRIPTION_INACTIVATED/DELETED)
    3. `${event}_${sha256(rawBody)}` (fallback; só colide se SHA-256
       quebrar)

  ### 5. Bug fix: DLQ scope (event + payload em catch)
  No código original, `event` e `payload` eram declarados DENTRO do
  `try { ... }` interno. O catch externo referenciava esses nomes
  para popular `billing_webhook_dead_letters`, causando
  `ReferenceError` em TODA exceção. Resultado: DLQ sempre falhava
  silenciosamente (envolvido em try/catch best-effort). Movidos
  para escopo externo com defaults seguros.

  ### 6. Tabela `billing_webhook_dead_letters` materializada
  Três Edge Functions já INSERTavam nessa tabela mas ela não existia
  no schema (nenhuma migration a criava). Migration
  `20260417290000_billing_webhook_dead_letters.sql` cria a tabela
  com:
    - CHECK constraints em provider/status
    - 4 índices (provider+created, status pending parcial, group_id
      parcial, provider+event_type)
    - RLS habilitada (service_role write, admin lê próprio grupo)
    - Coluna `headers` para forensics (sanitizada antes de insert —
      authorization, cookie, x-signature, x-request-id, asaas-access-token,
      asaas-signature são strippados pelo handler)

  ### 7. Logging estruturado
  Substituído `console.error` por `_shared/logger` com JSON
  estruturado. Cada log de auth carrega `request_id, group_id,
  event, reason, signature_verified` — pivot direto no Sentry/Logflare.
  Resposta 401 NUNCA disclose qual reason específica falhou (anti
  enumeration: cliente vê só "Unauthorized").

  ## Helpers extraídos para teste

  Toda a lógica de auth + idempotency vive em
  `_shared/asaas_webhook_auth.ts` como funções puras (Web Crypto +
  TextEncoder, sem DB / sem network). Permite teste exaustivo:
    - 33 testes Deno (RFC 4231 HMAC vector, SHA-256 known vectors,
      collision-resistance, missing/weak/mismatched/empty token,
      signature-tamper, body-tamper, idempotency fallback chain,
      empty-string edge cases).

  Wired em CI via novo job `edge-function-deno-tests` em
  `.github/workflows/supabase.yml` (Deno 2.x setup, roda contra
  `_shared/` recursivo — descobrirá testes futuros automaticamente).

  ## Validação

  - **Deno typecheck**: `deno check supabase/functions/_shared/asaas_webhook_auth.ts
    supabase/functions/asaas-webhook/index.ts` — clean.
  - **Deno test**: 33/33 verde (28 ms).
  - **DB migration**: aplicada local — `billing_webhook_dead_letters`
    table + RLS verificadas via `pg_class.relrowsecurity`.
  - **Integration tests**: 155/155 verde (`tools/integration_tests.ts`)
    — nenhuma regressão em RPCs financeiras.
  - **Smoke tests**: `tools/edge_function_smoke_tests.ts` reconhece
    novo helper em `_shared/asaas_webhook_auth.ts` (8 exports
    detected) e auth do `asaas-webhook` continua válida.

  ## Runbook

  `docs/runbooks/ASAAS_WEBHOOK_RUNBOOK.md` cobre 5 cenários (token
  rotation, vault inacessível, atacante, signature opt-in, DLQ
  enchendo) + replay procedure + métricas SLO + queries quick-ref.
  Linkado em `docs/runbooks/README.md`.

  ## Limitações conhecidas (next waves)

  - Sem rate limit por grupo no edge function (Asaas pode mandar
    rajadas legítimas em billing batch). Cobertura via `_shared/rate_limit.ts`
    quando virar problema.
  - Replay de DLQ é manual (sem retry com backoff automático). L06-05
    rastreia.
  - Sem alarme automático para DLQ count > N — TODO em
    `observability/alerts/` linkando ao novo runbook.
---

# Achado
`supabase/functions/asaas-webhook/index.ts:106-107`: aceitava
`asaas-access-token` do header **OU `accessToken` do payload** —
caminho fraco (token leak em log/dump expunha a mesma superfície
que leak DB). Sem HMAC. Idempotency hash usava
`JSON.stringify(payload).slice(0, 64)` — colidia trivialmente.

# Risco / Impacto
Replay / token-reuse em caso de leak DB ou JSON dump.
Reprocessamento de evento confirmando pagamento (se `processed=false`
ainda). Idempotency colisão silenciosamente dropava events legítimos.

# Correção implementada
Header-only auth (constant-time), HMAC-SHA256 forward-compat,
SHA-256 idempotency hash, DLQ table materializada, scope bug fix,
33 testes Deno + CI job + runbook. Ver bloco `note:` acima.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.18]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.18).
- `2026-04-17` — Corrigido (feature; promovido para `fixed`).
