# Guia B2B — Modelo de Custódia & Clearing

## 1. Visão Geral do Modelo

O portal opera como **infraestrutura B2B de custódia e clearing** para assessorias esportivas. O sistema gerencia coins com lastro fixo **1 coin = US$ 1,00**.

### Fluxo simplificado

```
Clube deposita USD → Lastro liberado → Coins emitidas para atletas
     Atleta queima coins (burn) no clube afiliado
           ↓
     Se interclub → Clearing automático (3% taxa)
     Se intra-club → Lastro liberado de volta
```

### Papéis

| Papel | Descrição |
|-------|-----------|
| **Portal** | Custodiante e operador de clearing. Nunca vende coins ao atleta. |
| **Clube (assessoria)** | Deposita lastro, emite coins para atletas, recebe burns. |
| **Atleta** | Usa coins no app. Nunca vê dinheiro. |
| **App** | Interface coins-only. Zero referência a valores monetários. |

---

## 2. Taxas e Spreads

| Tipo | Taxa | Configurável | Descrição |
|------|------|-------------|-----------|
| **Clearing interclub** | 3,00% | Sim (platform_fee_config) | Cobrada quando coins são queimadas em clube diferente do emissor |
| **Swap de lastro** | 1,00% | Sim | Transferência de lastro disponível entre clubes |
| **Spread cambial (entrada)** | 0,75% | Sim | Aplicado na conversão de moeda local → USD no depósito |
| **Spread cambial (saída)** | 0,75% | Sim | Aplicado na conversão de USD → moeda local na retirada |

---

## 3. Regras de Custódia e Limites

### Conta Segregada por Clube

Cada clube possui uma conta de custódia isolada com:

- **total_deposited_usd** (D): Total depositado em USD
- **total_committed** (R): Reservado para coins em circulação
- **available** (A = D − R): Saldo livre para emissão, swap ou retirada

### Invariantes (nunca violadas)

1. `D = R + A` — Sempre verdadeiro por definição
2. `R_i = M_i` — Reservado deve igualar coins vivas emitidas pelo clube
3. `D ≥ 0`, `R ≥ 0` — Nunca negativos
4. `D ≥ R` — Deposited nunca menor que committed

### Limites

- **Emissão**: Só permitida se `A ≥ coins_solicitadas`
- **Swap**: Só do saldo disponível (A)
- **Retirada**: Só do saldo disponível (A). Não pode afetar reservas.
- **Bloqueio**: Conta pode ser bloqueada por violação de invariantes

---

## 4. Processo Operacional de Burn

### No App (coins-only)

1. Atleta apresenta QR code ou token no clube afiliado
2. Dispositivo do clube envia `BURN_FROM_ATHLETE` via Edge Function
3. Função `execute_burn_atomic` executa em transação atômica:
   - Debita wallet do atleta
   - Cria entradas no `coin_ledger` por emissor (breakdown)
   - Cria `clearing_event` com breakdown
   - Cria `clearing_settlements` para itens interclub
   - Executa settlements automaticamente (auto-settle)

### Breakdown por Emissor

Se o atleta tem coins de 3 clubes e queima 100:
```
Club A (emissor): 50 coins → intra-club (se A = resgatante) → libera lastro
Club B (emissor): 30 coins → interclub → settlement com 3% taxa
Club C (emissor): 20 coins → interclub → settlement com 3% taxa
```

### Idempotência

- Cada burn tem `burn_ref_id` único (UNIQUE constraint)
- Re-processar mesmo burn_ref_id é seguro (rejeitado pelo DB)

---

## 5. Clearing Interclub

### Fórmula

Para cada item onde `emissor ≠ resgatante`:
```
gross_usd = coins × US$ 1,00
fee_usd   = gross × 3%
net_usd   = gross − fee
```

### Efeitos contábeis

| Conta | Campo | Efeito |
|-------|-------|--------|
| Emissor (debtor) | total_committed | −coins |
| Emissor (debtor) | total_deposited_usd | −gross |
| Resgatante (creditor) | total_deposited_usd | +net |
| Portal | platform_revenue | +fee |

### Netting

Burns são agregados por janela temporal (1 min) e par (emissor, resgatante) para reduzir volume de operações. O resultado final é idêntico ao processamento item-a-item.

---

## 6. Swap de Lastro

Clubes podem transferir lastro disponível entre si.

### Fluxo

1. Vendedor cria oferta: `amount_usd` do seu saldo disponível
2. Comprador aceita oferta
3. Execução atômica:
   - `D_seller −= amount`
   - `D_buyer += amount × (1 − 1%)`
   - `platform_revenue += amount × 1%`

### Proteções

- Vendedor precisa ter `available ≥ amount`
- Deadlock prevention: contas travadas em ordem determinística (UUID)
- Não é possível comprar própria oferta

---

## 7. Depósitos e Retiradas

### Depósito

1. Admin do clube inicia depósito via portal
2. Gateway de pagamento (Stripe/MercadoPago) processa
3. Webhook confirma pagamento (idempotente por `payment_reference`)
4. Lastro creditado na conta de custódia

**Se depósito em moeda local**: conversão para USD com spread (0,75%).

### Retirada

1. Admin solicita retirada do saldo disponível
2. Validação: `amount ≤ available` (nunca afeta reservas)
3. Conversão USD → moeda local com spread (0,75%)
4. Payout processado via gateway

---

## 8. SLAs de Liquidação

| Operação | SLA |
|----------|-----|
| Depósito (confirmação webhook) | < 5 segundos após evento do gateway |
| Clearing (auto-settle) | Imediato (síncrono com burn) |
| Clearing (batch/netting) | 1 minuto (via clearing-cron) |
| Swap | Imediato (execução atômica) |
| Retirada | Payout em até 2 dias úteis (depende do gateway) |
| Invariant check | A cada operação + health check contínuo |

---

## 9. Observabilidade

- **Health check** (`/api/health`): verifica DB + invariantes de custódia
- **Invariant endpoint** (`/api/platform/invariants`): relatório detalhado
- **Audit log**: todas operações registradas em `portal_audit_log`
- **Platform revenue**: receitas de clearing, swap e FX rastreadas em `platform_revenue`
- **Métricas**: timing de operações, contadores de erro, gauges de saúde

---

## 10. Segurança

- Webhook signatures verificadas (HMAC-SHA256, timing-safe)
- CSRF protection em rotas mutáveis
- Rate limiting por IP/usuário
- Contas bloqueadas automaticamente em caso de violação de invariantes
- Operações bloqueadas se invariantes falham (pre-operation gate)
