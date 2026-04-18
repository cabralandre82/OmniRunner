# ADR-008: Swap como Cessão de Crédito de Custódia (Pagamento Off-Platform)

**Status:** Accepted
**Date:** 2026-04-17
**Supersedes:** Esclarece [ADR-007 §6](./007-custody-clearing-model.md)
**Audit reference:** [L02-07](../audit/findings/L02-07-execute-swap-buyer-funding-nao-e-lockado-corretamente.md)

## Context

ADR-007 §6 introduziu o swap de lastro B2B descrevendo a operação como "Pagamento off-platform". A intenção foi documentada implicitamente, mas a auditoria L02-07 (Lente 2 — CTO) identificou ambiguidade real:

> `execute_swap` move `D_buyer += net` **sem cobrar nada** do buyer no banco de dados. No modelo atual, buyer recebe a credit `D_buyer += net` *sem* débito correspondente — o swap é uma **cessão de crédito de custódia**, não uma transferência monetária bilateral. Se essa é a intenção de produto (liquidez interclub), OK. Se é uma venda (buyer paga cash fora-do-sistema e recebe backing), **faltam validações**: comprovante externo, aprovação dupla, idempotência por order_id.

Sem decisão explícita registrada, dois leitores razoáveis do código discordam:

- **Leitor A (cessão)**: "buyer recebe lastro e a relação financeira é bilateral entre admin_masters; nosso ledger só cuida de custódia digital".
- **Leitor B (venda)**: "buyer está enriquecendo sem débito; isso é um bug que infla a custódia."

Sem ADR, qualquer auditoria, security review ou onboarding de eng novo entra nesse loop. O risco operacional é real:

1. **Compliance**: regulador pode interpretar swap como atividade de pagamento sem ressarcimento, exigindo licença não-prevista.
2. **Fraude**: admin_master de buyer com má-fé aceita ofertas sem nunca pagar o seller off-platform → custódia "infla" perante a contabilidade real do seller.
3. **Disputa**: sem campo de referência de pagamento, mediar conflito ("eu paguei", "não recebi") é manual e demorado.
4. **Auditoria contábil**: CFO precisa reconciliar transferências PIX/wire reportadas pelos clubes contra os swaps no ledger — sem identificador comum, virou trabalho braçal.

## Decision

### 1. Swap é, oficialmente, uma **cessão de crédito de custódia entre assessorias parceiras**

- O portal **não intermedeia o pagamento monetário** entre seller e buyer.
- O pagamento é **bilateral, off-platform, governed pela contratualidade entre as assessorias** (ex: PIX, wire, contrato de cessão de crédito assinado).
- O ledger de custódia trata o swap como **transferência de saldo digital** com taxa de plataforma.

### 2. O fluxo financeiro é assimétrico-por-design

- **Seller**: `D_seller -= amount_usd` (perde lastro), `platform_revenue += fee` (paga taxa do swap).
- **Buyer**: `D_buyer += (amount_usd - fee)` (ganha lastro líquido). **Sem débito on-platform.**
- A obrigação de **pagar o seller off-platform** fica documentada em campo de auditoria (`external_payment_ref`).

### 3. `external_payment_ref` (campo de proveniência opcional, fortemente recomendado)

- Coluna `swap_orders.external_payment_ref text NULL` adicionada.
- Portal aceita opcional no body do `accept` action (ex: `"PIX-202604171535-XYZ"`, `"WIRE-banco-itau-12345"`).
- Quando presente, vai para audit log E para `swap_orders.external_payment_ref` (selectable em queries de reconciliação).
- **Não bloqueia accept sem ref** (compatibilidade com clubes ainda não treinados), mas:
  - Emite log estruturado WARN quando `external_payment_ref` está ausente.
  - Métrica `swap_accept_without_ref_total` (Prometheus/observability) mensurável.
  - Permite alarme proativo ("X% dos swaps semana passada sem ref — investigar").

### 4. Política operacional (CFO)

- CFO mantém SLA de **revisar swaps sem `external_payment_ref` em 7 dias**.
- Disputa entre assessorias (paid/not-paid) escala para CFO com referência ao `swap_orders.id` + `cancellation` ou `dispute` runbook (futuro).
- Receita de fee é registrada apenas em `platform_revenue.fee_type='swap'` (seller paga; buyer não).

### 5. NÃO migramos para fluxo Stripe/MP de matching ativo

A alternativa avaliada — atrelar swap a checkout Stripe — foi descartada por:

- **Custo**: gateway cobra ~3-4% sobre transação. Inviabiliza spread de 1% que sustenta o swap como produto.
- **Latência**: checkout adiciona >24h de hold + 3-5 dias para liquidação. Quebra o caso de uso de "liquidez instantânea".
- **Compliance KYC duplicado**: assessorias já passam por KYC para custodiar lastro; gateway exige outro KYC sobre cada cessão individual.
- **Conformidade jurídica**: swap entre assessorias parceiras é cessão de crédito (Código Civil art. 286), regime jurídico diferente de pagamento de bens/serviços. Forçar gateway re-classifica indevidamente.

### 6. Defesas remanescentes (não retiradas pela ADR)

Esta ADR formaliza o modelo, mas mantém todas as defesas técnicas existentes:

- L01-46 — lock ordering determinístico previne deadlock.
- L05-01 — SQLSTATE distinguíveis em `execute_swap` e `cancel_swap_order`.
- L05-02 — TTL/expiração via cron.
- L06-06 — kill switch `swap.enabled` para freeze do marketplace.
- L11-04 — Dependabot semântico aumenta janela de resposta a CVE em libs financeiras.

## Schema

```sql
ALTER TABLE public.swap_orders
  ADD COLUMN IF NOT EXISTS external_payment_ref text;

COMMENT ON COLUMN public.swap_orders.external_payment_ref IS
  'L02-07/ADR-008: referência opcional ao pagamento bilateral off-platform '
  '(PIX, wire, contrato de cessão). Recomendado mas não obrigatório. '
  'Audit/CFO usam para reconciliação. Aceita ate 200 chars (livre).';

-- Constraint defensiva: tamanho razoável, sem quebra de linha (anti-injection)
ALTER TABLE public.swap_orders
  ADD CONSTRAINT swap_orders_external_payment_ref_chk
    CHECK (
      external_payment_ref IS NULL
      OR (
        length(external_payment_ref) BETWEEN 4 AND 200
        AND external_payment_ref !~ '[\x00-\x1f]'
      )
    );
```

## API contract

```typescript
// POST /api/swap action="accept"
{
  action: "accept",
  order_id: "uuid",
  external_payment_ref?: "PIX-202604171535-XYZ"  // opcional, max 200 chars
}
```

Audit log:

```jsonc
{
  "action": "swap.offer.accepted",
  "target_id": "<order-uuid>",
  "metadata": {
    "external_payment_ref": "PIX-...",  // ou null se omitido
    "amount_usd": 500,
    "fee_amount_usd": 5
  }
}
```

## Consequences

### Positivas

- **Clareza jurídica/contábil** — modelo "cessão de crédito" registrado formalmente.
- **Auditabilidade reforçada** — `external_payment_ref` serve como pivot na reconciliação com extratos bancários reais.
- **Compatibilidade backward** — campo opcional, não quebra clientes existentes.
- **Observability** — métrica de "% accepts sem ref" indica saúde do processo operacional.
- **Defesa contra fraude** — log estruturado WARN quando ausente vira sinal de revisão.

### Negativas

- **Não impede fraude no acto** — admin_master de má-fé pode preencher ref bogus. Mitigação: CFO compara com extratos bancários. Solução longo prazo: integração com PSP para validação automática (out of scope desta ADR).
- **Educação operacional** — onboarding de admin_masters precisa explicar a importância do campo.
- **Dependência de honra** — modelo assume relacionamento prévio entre assessorias (típico em clearing interclub real, mas exige due diligence).

### Métricas de sucesso

- **6 meses**: ≥80% dos accepts com `external_payment_ref` preenchido.
- **12 meses**: 0 disputas não-resolvíveis em <7 dias por falta de evidência.
- **Sempre**: 0 swaps com `external_payment_ref` que NÃO existem no extrato bancário do seller (verificado em sample mensal).

## Referências

- [ADR-007: Modelo de Custódia e Clearing](./007-custody-clearing-model.md) §6.
- [L02-07 finding](../audit/findings/L02-07-execute-swap-buyer-funding-nao-e-lockado-corretamente.md).
- Código Civil Brasileiro Art. 286-298 (Cessão de Crédito).
- Migration: `supabase/migrations/20260417280000_swap_external_payment_ref.sql`.
