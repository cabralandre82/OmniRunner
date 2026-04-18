---
id: L02-07
audit_ref: "2.7"
lens: 2
title: "execute_swap — Buyer funding não é lockado corretamente"
severity: medium
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "migration", "ux", "reliability", "adr"]
files:
  - docs/adr/008-swap-as-off-platform-credit-cession.md
  - supabase/migrations/20260417280000_swap_external_payment_ref.sql
  - portal/src/lib/swap.ts
  - portal/src/app/api/swap/route.ts
  - portal/src/lib/swap.test.ts
  - portal/src/app/api/swap/route.test.ts
  - tools/integration_tests.ts
correction_type: process
test_required: true
tests:
  - portal/src/lib/swap.test.ts
  - portal/src/app/api/swap/route.test.ts
  - tools/integration_tests.ts
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L02-07] execute_swap — Buyer funding não é lockado corretamente
> **Lente:** 2 — CTO · **Severidade:** 🟡 Medium · **Onda:** 1 (antecipada de 2) · **Status:** 🟢 fixed
**Camada:** BACKEND + DOCS
**Personas impactadas:** Eng (decisão de modelo), Security/Compliance (auditoria), CFO (reconciliação), Admin Master (operação do swap)

## Achado original
`20260228170000:229-246`: o seller tem `v_seller_avail < v_amount` verificado, mas o **buyer recebe `v_net` sem checar se o buyer tem USD para pagar**. No modelo atual, buyer recebe credit `D_buyer += net` sem débito correspondente — o swap é uma **cessão de crédito de custódia**, não uma transferência monetária bilateral.

Sem decisão registrada, dois leitores razoáveis do código discordam:
- **Cessão**: "buyer recebe lastro; pagamento é off-platform; ledger só cuida de custódia digital" (intenção real, alinhada a ADR-007 §6).
- **Venda**: "buyer está enriquecendo sem débito; isso é um bug que infla custódia."

## Risco original
- Compliance pode interpretar como pagamento sem ressarcimento (licença não-prevista).
- Admin_master de buyer com má-fé aceita ofertas sem nunca pagar o seller off-platform → custódia "infla" perante contabilidade real.
- Disputa "eu paguei"/"não recebi" sem campo de referência é manual e demorada.
- CFO reconcilia transferências PIX/wire reportadas pelos clubes vs. swaps no ledger sem identificador comum.

## Correção implementada

### 1. ADR-008 formaliza o modelo

Criada [`docs/adr/008-swap-as-off-platform-credit-cession.md`](../../adr/008-swap-as-off-platform-credit-cession.md) com:

- **Decisão #1**: swap é oficialmente **cessão de crédito de custódia entre assessorias parceiras**.
- **Decisão #2**: fluxo financeiro é **assimétrico-por-design** (buyer ganha lastro líquido sem débito on-platform; pagamento é bilateral off-platform).
- **Decisão #3**: campo `external_payment_ref` opcional, fortemente recomendado, para auditoria/reconciliação.
- **Decisão #4**: política operacional CFO (SLA 7 dias para revisão de swaps sem ref; runbook de disputa).
- **Decisão #5**: rejeição explícita de migração para gateway Stripe/MP (justificativa: custo, latência, KYC duplicado, classificação jurídica errada).
- **Decisão #6**: defesas técnicas existentes preservadas (L01-46, L05-01, L05-02, L06-06, L11-04).
- **Métricas de sucesso** definidas (≥80% accepts com ref em 6m; 0 disputas não-resolvíveis em <7d em 12m).

### 2. Migration `20260417280000_swap_external_payment_ref.sql`

- **Coluna `external_payment_ref text NULL`** em `swap_orders` com COMMENT semântico.
- **CHECK constraint `swap_orders_external_payment_ref_chk`**: aceita NULL ou string de 4-200 chars sem control chars (`!~ '[\x00-\x1f]'`). Defesa contra log poisoning + payloads gigantes.
- **Refactor `execute_swap`**: assinatura amplia para `(uuid, uuid, text DEFAULT NULL)`. Nova SQLSTATE `P0006 SWAP_PAYMENT_REF_INVALID` para validação de length e control chars. Persiste no `UPDATE swap_orders SET external_payment_ref = COALESCE(p_external_payment_ref, external_payment_ref)` (não sobrescreve se NULL no settle).
- **Mantém TODA semântica L05-01/L05-02**: SQLSTATE distinguíveis (P0001-P0006), expires_at defesa, lock ordering UUID-determinístico, lock_timeout=2s.
- **GRANTs corretos**: `service_role` + `authenticated`; REVOKE PUBLIC + anon.
- **Invariants `DO $invariants$`**: valida coluna, constraint, signature da função, smoke E2E (accept com ref persiste; ref com control char raise P0006). Cleanup ao final.

### 3. Portal lib (`portal/src/lib/swap.ts`)

- `SwapOrder` interface ganha `external_payment_ref: string | null`.
- `SwapErrorCode` ganha `"payment_ref_invalid"` mapeando P0006.
- Constantes `SWAP_PAYMENT_REF_MIN_LEN=4` e `SWAP_PAYMENT_REF_MAX_LEN=200` espelham CHECK constraint.
- Função pure `isValidSwapPaymentRef(ref)` para validação client-side antes do round-trip.
- `acceptSwapOffer(orderId, buyerGroupId, externalPaymentRef?)`: terceiro parâmetro opcional. Valida localmente antes de chamar RPC. Sempre passa `p_external_payment_ref: ref ?? null` (consistência de assinatura RPC).

### 4. Portal API route (`portal/src/app/api/swap/route.ts`)

- `acceptSchema` ganha `external_payment_ref: z.string().min(4).max(200).regex(/^[^\x00-\x1f]+$/).optional()` (validação tripla: min, max, control chars).
- `swapErrorToResponse` mapeia `payment_ref_invalid` → HTTP 400.
- `POST` propaga `data.external_payment_ref` para `acceptSwapOffer`.
- **WARN log estruturado** quando ref ausente: `logger.warn("swap.accept_without_external_payment_ref", { order_id, buyer_group_id, actor_id, adr: "ADR-008" })`. Pivot para futura métrica `swap_accept_without_ref_total`.
- `auditLog.metadata` ganha `external_payment_ref` e `has_payment_ref` (boolean rápido para query/dashboard).

### 5. Tests

- `portal/src/lib/swap.test.ts`: +5 cases — propaga ref válida; rejeita ref curta/longa/com control char client-side; mapeia P0006 vindo do servidor.
- `portal/src/app/api/swap/route.test.ts`: +5 cases — accept com ref e audit metadata; accept sem ref com audit `has_payment_ref=false`; Zod rejeita ref curta + control char; HTTP 400 quando server retorna `payment_ref_invalid`.
- `tools/integration_tests.ts`: +3 cases — `execute_swap` persiste ref no settle; rejeita ref com control char com `P0006`; CHECK constraint rejeita INSERT direto com ref < 4 chars.

### 6. Validações executadas

- ✅ Migration aplica em DB limpo (`bash tools/validate-migrations.sh`).
- ✅ `bash tools/validate-migrations.sh --run-tests` → 155 passed / 0 failed (3 novos para L02-07 + 152 existentes).
- ✅ `npx vitest run` portal → 817 passed | 4 todo / 90 test files.
- ✅ `npx tsc --noEmit` portal → 0 errors.
- ✅ `npx eslint src/lib/swap.ts src/app/api/swap/route.ts` → 0 warnings.

## Garantias finais

- **Modelo formalizado**: ADR-008 elimina ambiguidade "cessão vs venda" para sempre. Onboarding/security review/compliance audit têm fonte canônica.
- **Auditabilidade reforçada**: `external_payment_ref` serve como pivot de reconciliação com extratos bancários reais.
- **Backward compatible**: campo opcional, clientes existentes não quebram. Apenas emite WARN observability.
- **Defesa em camadas**: validação Zod (route) + isValidSwapPaymentRef (client lib) + CHECK constraint (DB) + raise P0006 em execute_swap. Mesma regra em 4 lugares = sempre consistente.
- **Observability**: WARN log estruturado vira sinal proativo para CFO + base para métrica futura.
- **Sem regressão**: TODAS as defesas L01-46, L05-01, L05-02 continuam ativas e testadas.
- **Smoke testado em DB real**: invariants block valida fim-a-fim quando há groups; testes integration cobrem o caminho.

## Limitações conhecidas (declaradas no ADR-008)

- **Não impede fraude no acto** — admin_master pode preencher ref bogus. Mitigação: comparação CFO com extratos bancários (sample mensal).
- **Educação operacional** — admin_masters precisam ser treinados sobre importância do campo.
- **Solução longo prazo** (out of scope desta ADR): integração com PSP para validação automática de ref.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — anchor `[2.7]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.7).
- `2026-04-17` — Fix implementado: ADR-008 + coluna `external_payment_ref` + refactor `execute_swap` (P0006) + portal lib/route com validação tripla + 13 novos tests (5 lib + 5 route + 3 integration). Antecipado para Wave 1 por sinergia com L05-01/L05-02 já completados.
