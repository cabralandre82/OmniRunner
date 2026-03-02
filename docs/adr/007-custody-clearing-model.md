# ADR-007: Modelo de Custódia e Clearing Interclub

**Status:** Accepted  
**Date:** 2026-02-28

## Context

O app opera como ledger global de OmniCoins com desafios entre atletas de diferentes assessorias. Quando um atleta ganha coins de adversários de outras assessorias e depois queima essas coins no seu clube afiliado, o clube resgatante precisa ser compensado pelos clubes emissores. Sem um mecanismo automatizado, isso gera caos operacional na escala internacional.

## Decision

### 1. O portal se torna câmara de compensação B2B (Clearing House)
- O portal **não vende mais coins** diretamente
- O portal opera como **infraestrutura de custódia** e **compensação entre assessorias**
- Funcionalidades de billing/checkout ficam em dead code com feature flag

### 2. Lastro obrigatório: 1 Coin = US$ 1.00
- Cada coin tem lastro fixo global de **US$ 1.00**
- Assessoria deposita USD via gateway (Stripe/MercadoPago)
- Depósito gera direito de emitir coins equivalentes
- Coins em circulação nunca excedem lastro depositado

### 3. Custódia segregada por assessoria
- Saldos segregados contabilmente por assessoria
- Cada assessoria tem: total_deposited, total_committed, total_available, total_settled

### 4. Rastreabilidade total (issuer)
- Toda coin carrega `issuer_group_id` (assessoria emissora)
- No burn, o backend executa um "burn plan" determinístico (prioriza coins do mesmo emissor)
- O breakdown por emissor alimenta o motor de clearing

### 5. Clearing automático
- Cada burn gera um evento com breakdown por emissor
- Burns intra-clube: `R -= b`, `A += b` (lastro liberado fica como disponível)
- Burns interclub: `R -= b`, `D -= b`, `D_creditor += (1-α)·b` (lastro transferido)
- Taxa de clearing configurável (default: 3%)
- `settle_clearing` reduz `total_committed` e `total_deposited_usd` do emissor atomicamente

### 6. Swap de lastro B2B
- Assessorias com lastro excedente (A > 0) podem vendê-lo a outras
- Direção: `D_seller -= amount`, `D_buyer += (amount - fee)`. Pagamento off-platform.
- Validação: `A_seller >= amount` (swap só do disponível, nunca do reservado)
- Taxa de swap configurável (default: 1%)

### 7. Gestão de risco e invariantes
- Saldo insuficiente → bloqueia novas emissões
- Settlements pendentes até recomposição de saldo
- `check_custody_invariants()` verifica automaticamente: `D >= 0`, `R >= 0`, `D >= R`
- `custody_release_committed()` garante que burns reduzem R atomicamente
- Serialização por emissor via `FOR UPDATE` locks no Postgres

## Database Schema

### Novas tabelas
- `custody_accounts` — saldo segregado por assessoria (D, R, settled)
- `custody_deposits` — histórico de depósitos de lastro
- `clearing_events` — registro de burns com breakdown por emissor
- `clearing_settlements` — compensações interclub
- `swap_orders` — ordens de swap de lastro B2B
- `platform_fee_config` — taxas configuráveis

### SQL Functions
- `confirm_custody_deposit(deposit_id)` — confirma depósito, incrementa D
- `custody_commit_coins(group_id, count)` — emissão: R += m, A -= m
- `custody_release_committed(group_id, count)` — burn: R -= b (libera lastro)
- `settle_clearing(settlement_id)` — interclub: R -= b, D -= gross, D_creditor += net
- `check_custody_invariants()` — retorna violações (vazio = sistema saudável)

### Alterações
- `coin_ledger` — nova coluna `issuer_group_id` (nullable, backward-compatible)

### Invariantes (contábeis)

Para cada clube emissor `i`:
- `D_i = R_i + A_i` (depósito = reservado + disponível)
- `R_i = M_i` (reservado = coins em circulação)
- `M_i <= D_i` (nunca emitir sem lastro)
- Lastro **não pode ser sacado livremente** — só sai via burn ou swap
- Global: `Σ R_i = Σ M_i` e `Σ D_i = custódia real`

## Consequences

### Positivas
- Escalável internacionalmente (compensação automática)
- Zero risco de inadimplência (lastro prévio obrigatório)
- App permanece coins-only (zero menção a dinheiro)
- Receita recorrente via taxas de clearing e swap

### Negativas
- Complexidade operacional maior no portal
- Assessorias precisam depositar lastro antes de emitir (barreira de entrada)
- Necessidade de compliance financeiro em jurisdições específicas
