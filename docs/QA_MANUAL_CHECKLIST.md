# QA Manual — Checklist de 15 Minutos

> Execute cada item na ordem. Marque ✓ ao completar. Se qualquer item falhar, pare e reporte.

## Pré-requisito

```bash
cd portal && npm run qa:e2e
```

Se o comando acima passar, siga com a verificação manual abaixo.

---

## 1. Custódia (3 min)

- [ ] Abrir página **Custódia** (`/custody`)
- [ ] Verificar 5 KPI cards: Total Depositado, Reservado, Disponível, Coins Vivas, Total Liquidado
- [ ] Conferir badges de invariantes:
  - [ ] "OK: Total = Reservado + Disponível" (verde)
  - [ ] "OK: Reservado = Coins Vivas" (verde)
  - [ ] Se vermelho: clicar no link "Ver Auditoria" e investigar
- [ ] Aba **Extrato**: conferir pelo menos 3 linhas com tipo, valor, saldo após, e referência clicável
- [ ] Aba **Depósitos**: conferir moeda original, spread, gateway, status, provider_ref
- [ ] Aba **Retiradas**: conferir cotação, spread, provider fee, status
- [ ] Clicar em **Exportar CSV** no extrato — arquivo baixa corretamente
- [ ] Clicar no botão **Depositar** — modal/formulário abre

## 2. Clearing (3 min)

- [ ] Abrir página **Clearing** (`/clearing`)
- [ ] Verificar 6 KPIs: A Receber, A Pagar, Recebido, Pago, Taxas Pagas, SLA Médio
- [ ] Filtrar por **"A receber"** → lista mostra apenas settlements onde o clube é creditor
- [ ] Filtrar por **status "settled"** → lista mostra apenas settlements liquidados
- [ ] Buscar por um **Burn ID** conhecido → encontra o settlement correto
- [ ] Clicar em **"Ver detalhes"** de um settlement:
  - [ ] Mostra referência do burn (link clicável para Auditoria)
  - [ ] Mostra movimentação contábil: D emissor, C resgatante, C plataforma
  - [ ] Mostra IDs técnicos: event_id, settlement_id
- [ ] Clicar no link do burn → navega para página de Auditoria com o burn aberto
- [ ] Voltar para Clearing
- [ ] Clicar em **Exportar CSV** → arquivo baixa

## 3. FX (2 min)

- [ ] Abrir página **FX** (`/fx`)
- [ ] Verificar KPIs: Volume Convertido, Receita Spread, Provider Fees, Spread Médio, Pendentes
- [ ] **Simulador entrada**: inserir 1000 BRL, cotação 5.0 → verificar que mostra:
  - Raw USD: 200.00
  - Spread (0.75%): 1.50
  - USD Creditado: 198.50
- [ ] **Simulador saída**: inserir 100 USD, cotação 5.0 → verificar que mostra:
  - Spread (0.75%): 0.75
  - BRL Recebido: 496.25
- [ ] Conferir seção **Política de Câmbio** (texto fixo sobre determinação de cotação)
- [ ] Tabela de operações: conferir pelo menos 1 linha com direção, moeda, cotação, spread, status

## 4. Swap (2 min)

- [ ] Abrir página **Swap** (`/swap`)
- [ ] Verificar 5 KPIs: Disponível, Volume 7d, Volume 30d, Taxas Pagas, Ofertas Abertas
- [ ] Se houver ofertas abertas: verificar que mostra bruto, taxa (1%), líquido, contraparte
- [ ] Formulário de criar oferta: verificar campos (valor, tipo)
- [ ] Tentar criar oferta com valor acima do disponível → deve ser bloqueado
- [ ] Histórico: verificar tabela com tipo (Compra/Venda), contraparte, swap ID, status
- [ ] Clicar em **Exportar CSV** → arquivo baixa

## 5. Auditoria (3 min)

- [ ] Abrir página **Auditoria** (`/audit`)
- [ ] Verificar cards: Burns, Settlements, Interclub, Intra-club
- [ ] Buscar por **Burn ID** → encontra o burn
- [ ] Expandir o burn:
  - [ ] **Linha do Tempo**: mostra timestamps (criado, token, scan, commit)
  - [ ] **Breakdown por issuer**: mostra clube emissor + quantidade de coins
  - [ ] **Settlements encadeados**: mostra ID, devedor, credor, bruto, taxa, líquido, status
  - [ ] **Detalhes Técnicos**: mostra event_id, burn_ref, athlete_id
- [ ] Buscar por **Athlete ID** → filtra burns desse atleta
- [ ] Clicar em **Exportar CSV** → arquivo baixa com dados da busca

## 6. Settings (1 min)

- [ ] Abrir página **Settings** (`/settings`)
- [ ] Seção **Taxas Aplicadas**: tabela com tipo (clearing, swap, fx_spread), taxa %, status
- [ ] Seção **Status de Custódia**: Total, Reservado, Disponível, Bloqueio
- [ ] Conferir que taxa de clearing = 3%, swap = 1%, fx_spread = 0.75%

## 7. Header Global (1 min)

- [ ] Verificar badge de ambiente: **PROD** (azul) ou **SANDBOX** (amarelo)
- [ ] Verificar role do usuário: admin / financeiro / suporte
- [ ] Se conta bloqueada: banner vermelho visível no topo da Custódia

---

## Resultado

| Item | Status |
|------|--------|
| Custódia | ☐ OK / ☐ FALHA |
| Clearing | ☐ OK / ☐ FALHA |
| FX | ☐ OK / ☐ FALHA |
| Swap | ☐ OK / ☐ FALHA |
| Auditoria | ☐ OK / ☐ FALHA |
| Settings | ☐ OK / ☐ FALHA |
| Header | ☐ OK / ☐ FALHA |

**Verificador**: _______________
**Data**: _______________
**Ambiente**: ☐ Produção / ☐ Sandbox
