---
id: L09-01
audit_ref: "9.1"
lens: 9
title: "Modelo de \"Coin = US$ 1\" pode ser classificado como arranjo de pagamento (BCB Circ. 3.885/2018)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "compliance", "bcb", "adr", "reliability"]
files:
  - docs/compliance/BCB_CLASSIFICATION.md
  - tools/audit/check-bcb-classification.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-bcb-classification.ts
linked_issues: []
linked_prs: []
owner: legal-finance-platform
runbook: docs/compliance/BCB_CLASSIFICATION.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  ADR formal `docs/compliance/BCB_CLASSIFICATION.md` define a
  posição regulatória do produto. Três opções foram analisadas;
  **Option B — Parceria com IP autorizada (Asaas)** foi escolhida.

  Posture operacional:
  - Fluxo fiduciário (BRL) roda dentro da Asaas (IP autorizada BCB).
  - Omni Runner atua como **Payment Initiation Service** (PIS) + orquestrador.
  - `custody_accounts` / `clearing_settlements` são espelho contábil,
    não fonte monetária — reconciliação diária contra saldo Asaas.
  - OmniCoin é ticket esportivo não-monetário, emitido apenas em
    desafios (reforçado pela L22-02).
  - Asaas assume deveres de PLD/FT, COAF reporting, KYC/KYB,
    limites por CPF/CNPJ.
  - Omni Runner nunca emite BRL fora da Asaas; três caminhos
    enumerados de withdrawal: (1) challenge prize, (2) custody
    reversal, (3) subscription refund.

  CI guard `audit:bcb-classification` enforça (~35 invariantes):
  - seções §1–§6 canônicas presentes;
  - 7 referências legais obrigatórias (Lei 7.492/86, BCB Circ.
    3.885/2018, Res. BCB 80/2021, Lei 9.613/98, LC 105/2001,
    Circ. BCB 3.978/2020, CMN/BCB Circ. 3.682/2013);
  - as 3 opções apresentadas com decisão explícita;
  - cross-refs L22-02, L09-06, L09-07;
  - review triggers canônicos (Asaas perde autorização, volume
    > R$ 250 mi, regra BCB nova, expansão multi-país).

  Opções não escolhidas (registradas para auditoria futura):
  - **Option A** ("crédito de marketing" não-resgatável) —
    rejeitada: desnatura o produto (desafios com prêmio em BRL
    precisam de resgate).
  - **Option C** (Omni Runner vira IP autorizada BCB) — adiada:
    capital mínimo R$ 2 mi + 18–24 meses de processo, reavaliar
    em Wave 5+ se volume anual > R$ 250 mi.

  Coin policy: ADR reforça L22-02 — OmniCoin permanece challenge-only
  e jamais é tratada como unidade monetária.
---
# [L09-01] Modelo de "Coin = US$ 1" pode ser classificado como arranjo de pagamento (BCB Circ. 3.885/2018)
> **Lente:** 9 — CRO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Legal / Finance / Platform (conjunto)
**Personas impactadas:** Assessoria (legal/finance owner), atleta (transparência de resgate)

## Achado
Produto emite tokens (OmniCoin) com paridade contábil, mantém `custody_accounts`, `clearing_settlements` e `swap_orders` com conversão BRL/USD — combinação que aciona critério BCB para **arranjo de pagamento** (Circ. 3.885/2018) e potencialmente **Instituição de Pagamento** (Res. BCB 80/2021) acima de R$ 500 mi/ano ou 1 M transações/ano.

## Risco / Impacto
Operação não-autorizada = intervenção BCB + sanção penal (Lei 7.492/86, Art. 16 — reclusão 1–4 anos).

## Correção aplicada

### 1. ADR formal (`docs/compliance/BCB_CLASSIFICATION.md`)
Documento que:
- cita 7 fontes legais (Lei 7.492/86, BCB Circular 3.885/2018, BCB Resolução 80/2021, Lei 9.613/98, Lei Complementar 105/2001, Circular BCB 3.978/2020, CMN/BCB Circular 3.682/2013);
- apresenta 3 opções (A: marketing-credit; B: Asaas partnership; C: BCB IP authorisation) com decisão explícita;
- define invariantes operacionais (BRL só dentro da Asaas, OmniCoin challenge-only, custody como espelho, withdrawal paths enumerados, SoD com PLD/FT/COAF na IP);
- lista triggers de revisão (Asaas perde autorização, volume > R$ 250 mi, regra BCB nova, expansão multi-país);
- review log datado.

### 2. Posture escolhida — Option B (Asaas partnership)
- Todo fluxo fiduciário passa pela Asaas (IP autorizada).
- Omni Runner = Payment Initiation Service + orquestrador de gamificação.
- `custody_accounts` é espelho contábil, reconciliado contra Asaas.
- Asaas assume PLD/FT, COAF reporting, limites CPF/CNPJ, KYC/KYB.

### 3. CI guard (`tools/audit/check-bcb-classification.ts`)
- ~35 asserts verificando seções, referências legais, opções e decisões, cross-refs com L22-02 (`audit:omnicoin-narrative`), L09-06 (`audit:asaas-key-encryption`), L09-07 (`audit:refund-sla`), review triggers canônicos.
- Comando: `npm run audit:bcb-classification`.

### 4. Reforço cross-cutting
- L22-02 continua sendo SSR para "OmniCoin emitida apenas em desafios".
- L09-06 garante Asaas API key encriptada at-rest.
- L09-07 garante SLA de refund/chargeback.
- L10-06 SoD impede platform_admin único de movimentar BRL.

## Teste de regressão
- `npm run audit:bcb-classification` — ~35 asserts.
- Revisão anual obrigatória por Legal/Finance/Platform.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.1).
- `2026-04-21` — Fixed via ADR `docs/compliance/BCB_CLASSIFICATION.md` + CI guard `audit:bcb-classification`. Posture = Option B (parceria Asaas).
