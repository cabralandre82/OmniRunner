# BCB classification — Omni Runner OmniCoin posture

> **Finding:** [`L09-01`](../audit/findings/L09-01-modelo-de-coin-us-1-pode-ser-classificado.md)
> **Legal references:**
> - Lei 7.492/1986, Art. 16 — "operação não autorizada de instituição financeira" (1–4 anos de reclusão).
> - BCB Circular 3.885/2018 — arranjos de pagamento.
> - BCB Resolução 80/2021 — autorização e funcionamento de Instituições de Pagamento (IP).
> - Lei 9.613/1998 + Circular BCB 3.978/2020 — PLD/FT (COAF).
> - Lei Complementar 105/2001 — sigilo bancário.
> - CMN/BCB Circular 3.682/2013 — payment-arrangement accountability.
> - LGPD Lei 13.709/2018 — adjacente via dados financeiros.
>
> **CI guard:** `npm run audit:bcb-classification`
> **Owner:** Legal / Finance / Platform (joint).
> **Review cadence:** annual, or on change of payment processor, product
> scope, or regulatory update (whichever first).

---

## 1. Executive summary

Omni Runner emits **OmniCoins** — tokens com paridade contábil (1 OmniCoin ≡ 1 unidade de valor estipulada pela assessoria emissora) — usados **exclusivamente dentro de desafios esportivos** (ver L22-02). O produto, porém, mantém:

1. `custody_accounts` — armazenamento de valor em nome de assessoria e atletas.
2. `clearing_settlements` — liquidação interna entre assessorias quando atletas trocam de clube.
3. `swap_orders` / `fx_rate` — possibilidade de conversão para reais e/ou USD no momento do withdrawal.

Essa combinação (custódia de recursos de terceiros + liquidação entre terceiros + conversão para moeda fiduciária) aciona os critérios do BCB para **arranjo de pagamento** (Circular 3.885/2018) e, a partir de R$ 500 mi/ano de volume OU 1 M de transações, **Instituição de Pagamento** (Resolução BCB 80/2021).

**Risco de não-conformidade:** intervenção BCB + sanção penal Art. 16 Lei 7.492/86 (reclusão 1–4 anos).

**Posture escolhida:** **Option B — Partnership with authorized IP (Asaas)**.
Omni Runner atua como Payment Initiation Service (PIS) / orquestrador; a custódia fiduciária, a liquidação em moeda fiduciária e o relacionamento com COAF são responsabilidades contratuais da IP parceira (Asaas). OmniCoins permanecem como *ticket esportivo* não-monetário dentro de desafios.

---

## 2. Analysis of options

### Option A — Restringir OmniCoin a crédito de marketing não-resgatável

- **Descrição:** eliminar `swap_orders`, `withdrawals` em moeda fiduciária e qualquer RPC que permita sacar OmniCoins como reais/dólares. OmniCoin vira *vale-benefício* (Lei 12.850/2011 c/c art. 5º do Decreto 10.854/2021), sem natureza monetária.
- **Impacto de produto:** elimina resgate por atleta. Atletas só podem usar OmniCoins dentro de desafios. Coach / assessoria continuam podendo distribuir, mas sem saída monetária.
- **Risco regulatório:** **baixo** — sai do perímetro BCB.
- **Risco de produto:** **alto** — desafios com prêmio de R$ milhares precisam de solução paralela (transferência PIX direta entre partes), fora da plataforma.
- **Viabilidade técnica:** exige reversão dos módulos `swap_engine`, `withdraw_challenge_refund`, parte do `custody`. ≈ 3 meses.
- **Decisão:** **REJEITADA** — desnatura o produto. Premiação esportiva com OmniCoins precisa ser convertível para o atleta capitalizar o prêmio.

### Option B — Parceria com IP autorizada (Asaas) · **ESCOLHIDA**

- **Descrição:** todo fluxo fiduciário (custódia em BRL, liquidação entre contas, saque) roda dentro da Asaas (IP autorizada BCB — registro no banco central brasileiro). Omni Runner atua como:
  - **Payment Initiation Service (PIS)** — inicia cobranças (plano mensal, entrada de desafio) que são processadas pela Asaas.
  - **Orquestrador de lógica de negócio** — regras de matchmaking, vencimento de desafio, redistribuição de prêmios, todas expressas em reais via API Asaas.
  - **Token ledger não-monetário** — `coin_ledger` registra eventos esportivos em OmniCoins, mas o **efeito fiduciário** (movimentação em BRL) sempre passa pela Asaas.
- **Contrato obrigatório com parceira:**
  - Asaas mantém conta escrow com autorização BCB.
  - Asaas assume deveres de PLD/FT (COAF reporting, registros de operações suspeitas).
  - Asaas é responsável por limites por CPF/CNPJ, KYC/KYB.
  - Omni Runner tem DPA/LGPD com Asaas para troca de dados pessoais.
- **Impacto de produto:** nenhum visível ao usuário final. OmniCoins continuam sendo a gamificação; o saldo em BRL que lastreia prêmios de desafio vive na Asaas.
- **Risco regulatório:** **baixo-médio** — continua necessário:
  1. Não permitir saque direto sem passar pelo endpoint Asaas.
  2. `custody_accounts` deve ser um *espelho contábil* do saldo na Asaas, não a fonte fiduciária.
  3. Reconciliação diária entre `wallets.balance_coins` (gamificação) × saldo Asaas (monetário).
- **Viabilidade técnica:** parcialmente já implementada — módulo Asaas está integrado (ver `supabase/migrations/20260421530000_l09_06_asaas_key_at_rest.sql` para chave criptografada).
- **Decisão:** **ESCOLHIDA**.

### Option C — Obter autorização BCB como IP

- **Descrição:** Omni Runner se torna IP autorizada.
- **Requisitos:**
  - Capital social mínimo R$ 2 milhões (Res. BCB 80/2021, Art. 20).
  - Diretor estatutário com qualificação.
  - Estrutura de compliance, PLD/FT, auditoria interna.
  - Processo de autorização BCB 18–24 meses.
- **Decisão:** **REJEITADA no horizonte de Wave 1–2** — escala atual não justifica custo.
  Reconsiderada em Wave 5+ se volume ultrapassar R$ 250 mi/ano (50% do trigger regulatório).

---

## 3. Operational invariants (Option B enforcement)

A posture escolhida exige disciplina técnica. Este documento é o contrato:

### 3.1 Jamais emita BRL fora da Asaas

- Nenhum código pode criar crédito/débito em BRL diretamente. Todo fluxo BRL passa por um `edge-function` que chama a API da Asaas.
- `wallets.balance_coins` é **unidade de gamificação esportiva** (OmniCoin), nunca reais.
- Saques para atleta são originados por RPC que enfileira um **webhook outbound** à Asaas (`fn_withdraw_challenge_prize_asaas`) que, confirmado, atualiza o espelho contábil via callback.

### 3.2 OmniCoin ≠ moeda

- Por política L22-02, OmniCoin é emitida/burned **apenas dentro de desafios**. Nenhum outro evento (referral, sponsorship, onboarding, streak-sem-challenge) gera OmniCoin. O CI guard `audit:ledger-reason` enforça isso.
- Narrativa user-facing nunca apresenta OmniCoin como moeda — ver L22-02 (`audit:omnicoin-narrative`).

### 3.3 Custody como espelho, não fonte

- `custody_accounts` e `clearing_settlements` são registros *de apoio* à reconciliação. A fonte autoritativa é o saldo Asaas.
- RPC `fn_reconcile_custody_vs_asaas()` (a ser criado no pacote L09-09) roda em cron diário e alerta divergências.

### 3.4 Withdrawal paths enumerados

- Três e apenas três caminhos de withdrawal em BRL existem:
  1. **Challenge prize withdrawal** — `challenge_withdrawal` + webhook Asaas.
  2. **Custody deposit reversal** — a pedido da assessoria (L09-07 cooling-off).
  3. **Refund de subscription** — CDC Art. 49 + L23-09.
- Todo novo caminho precisa de audit-finding explícito + atualização deste documento + CI guard.

### 3.5 Segregação de responsabilidades

- **Asaas:** custódia fiduciária, compliance PLD/FT, COAF reporting, KYC/KYB.
- **Omni Runner:** experiência do atleta/coach, regras de gamificação, orquestração via PIS.
- Nenhum `platform_admin` da Omni Runner pode transferir BRL entre contas via painel — essa ação é sempre delegada à Asaas.

---

## 4. Enforcement — CI guard `audit:bcb-classification`

O guard `tools/audit/check-bcb-classification.ts` verifica:

1. Este documento existe e cobre as seções §1–§5 canônicas.
2. Todas as referências legais mandatórias estão presentes (BCB 3.885/2018, Res. 80/2021, Lei 7.492/86, Lei 9.613/98).
3. Posture escolhida é explícita (*Option B — Partnership with authorized IP*).
4. Linking com OmniCoin challenge-only policy (L22-02).
5. Linking com Asaas at-rest encryption (L09-06).
6. Linking com refund/chargeback policy (L09-07).
7. O finding L09-01 referencia este documento.

---

## 5. Review triggers

Reavaliar esta posture em qualquer um dos seguintes eventos:

- Asaas perde ou suspende autorização BCB.
- Volume anual transacionado passa R$ 250 mi (50% do trigger regulatório) → avaliar migração para Option C.
- BCB publica norma que amplia o perímetro de "arranjo de pagamento" de forma a capturar o ledger OmniCoin mesmo como gamificação.
- Mudança de país (expansão para ES/MX/AR) — cada país tem regulador próprio (SBS, CNBV, BCRA) e esta análise se torna um template.
- Produto introduz feature que cria caminho novo de BRL (novo método de saque, assinatura white-label, marketplace).

---

## 6. Review log

| Data         | Responsável                | Alteração                                                                            |
|--------------|----------------------------|--------------------------------------------------------------------------------------|
| 2026-04-21   | Legal + Finance + Platform | Documento inicial. Posture = Option B (Asaas). Linking com L22-02, L09-06, L09-07.   |
