# Termos Operacionais e Financeiros

## 1. Objetivo

Esta plataforma permite que atletas disputem desafios usando Coins e que clubes operem a economia de Coins com seguranca, incluindo compensacao automatica entre clubes quando Coins de diferentes emissores forem queimadas.

## 2. Definicoes

- **Coin**: Unidade digital utilizada exclusivamente para desafios no app.
- **Emissor (Issuer)**: Clube que colocou Coins em circulacao.
- **Queima (Burn)**: Operacao no app em que Coins sao removidas de circulacao no clube afiliado do atleta.
- **Portal B2B**: Ambiente exclusivo para clubes, onde sao exibidos saldos, custodia, taxas, compensacoes e swaps.
- **Lastro**: Valor em USD mantido em custodia como garantia operacional do sistema.
- **Clearing**: Processo de compensacao automatica entre clubes quando Coins interclub sao queimadas.
- **Swap**: Transferencia de lastro disponivel entre clubes dentro do portal.

## 3. Regra de Lastro (fixa)

- Cada Coin colocada em circulacao exige lastro fixo de US$ 1 por Coin.
- O lastro e mantido em USD.
- O app nao exibe valores monetarios; todo financeiro fica no portal e no contrato.

## 4. Deposito e Capacidade de Emissao

- O clube deposita USD no portal.
- O deposito libera capacidade operacional para colocar Coins em circulacao.
- O portal nao vende Coins ao clube; ele opera custodia e controle de lastro.
- Cada deposito e confirmado via webhook do provedor de pagamento (Stripe/MercadoPago) com verificacao de assinatura.

## 5. Operacao de Queima no Clube (procedimento)

1. O atleta solicita a queima de X Coins no clube afiliado.
2. A queima e feita no app (modo atleta gera token; modo clube escaneia e confirma).
3. Apos a queima, o clube realiza o pagamento ao atleta fora do app.
4. A plataforma registra a queima e inicia os processos B2B de compensacao quando aplicavel.

Importante: A plataforma nao controla nem executa pagamentos ao atleta.

## 6. Compensacao Interclub (Clearing)

Quando o clube queima Coins que foram emitidas por outros clubes:

- A plataforma calcula automaticamente a compensacao.
- A plataforma transfere lastro do clube emissor para o clube que realizou a queima.
- Taxa de clearing: 3% sobre o volume compensado.

Formula:
- Bruto (USD) = coins x US$ 1,00
- Taxa = bruto x 3%
- Liquido = bruto - taxa

Efeitos contabeis:
- Emissor: reservado -= coins, depositado -= bruto
- Resgatante: depositado += liquido
- Plataforma: receita += taxa

## 7. Swap de Lastro (Liquidez B2B)

Clubes podem negociar lastro entre si no portal para ajuste de liquidez:

- Swap ocorre apenas com saldo disponivel (nao impacta reservas).
- Taxa de swap: 1% sobre o volume transferido.
- Comprador recebe (1 - 1%) do montante.
- Plataforma retem 1%.

## 8. Conversao Cambial (entrada e saida)

- Depositos e retiradas podem envolver conversao de moeda local para USD.
- A plataforma aplica um spread cambial de 0,75% a 1% na entrada e/ou saida.
- A taxa efetiva e a cotacao de referencia sao apresentadas no portal no momento da operacao.
- Taxas de spread e taxas do provedor de pagamento sao registradas separadamente.

## 9. Regras de Risco e Limites

- Se um clube ficar com saldo insuficiente para cobrir reservas exigidas:
  - Novas emissoes/colocacoes em circulacao sao bloqueadas ate recomposicao de lastro.
- O portal mantem trilha de auditoria de burns, compensacoes e swaps.
- Invariantes de custodia sao verificadas automaticamente:
  - Total Depositado >= Reservado
  - Reservado = Coins em circulacao do emissor
- Operacoes sao bloqueadas automaticamente se invariantes falharem.

## 10. Transparencia e Relatorios

O clube tera acesso no portal a:

- Saldo total em custodia (USD)
- Saldo reservado e disponivel
- Historico de burns associados ao clube
- Compensacoes interclub (a pagar / a receber)
- Taxas cobradas (clearing, swap, FX)
- Operacoes de conversao cambial com cotacao de referencia
- Extratos e conciliacoes
- Trilha de auditoria (burn -> settlement, por burn_id)

## 11. Observacoes Importantes

1. A plataforma nao controla nem executa pagamentos ao atleta.
2. A plataforma nao exibe dinheiro no app e nao realiza operacoes monetarias no app.
3. Todas as operacoes monetarias e taxas sao B2B no portal e contratualmente acordadas.
4. A plataforma nao promete rendimento aos clubes sobre lastro depositado.
5. Retiradas de lastro sao permitidas apenas do saldo disponivel, nunca afetando reservas.

## 12. Taxas Resumo

| Tipo | Taxa | Configuravel |
|------|------|-------------|
| Clearing interclub | 3,00% | Sim |
| Swap de lastro | 1,00% | Sim |
| Spread cambial (entrada) | 0,75% - 1,00% | Sim |
| Spread cambial (saida) | 0,75% - 1,00% | Sim |

---
Versao: 2026-02-28
