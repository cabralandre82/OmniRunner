# GAMIFICATION_POLICY.md — Regras de Compliance para App Store / Play Store

> **Sprint:** 12.0.0
> **Status:** ATIVO — Documento obrigatório antes de qualquer código de gamificação
> **Revisão obrigatória:** Antes de cada release que inclua features de gamificação

---

## 1. PRINCÍPIO FUNDAMENTAL

A gamificação do Omni Runner é 100% baseada em **engajamento e diversão**.
Moedas internas (Coins) existem apenas como unidade de progresso no app.
**Nenhum elemento de gamificação possui ou implica valor monetário real.**

---

## 2. DEFINIÇÃO DE COINS

| Aspecto | Regra |
|---------|-------|
| Nome oficial | **OmniCoins** (ou "Coins" na UI) |
| Natureza | Unidade de progresso virtual, interna ao app |
| Conversibilidade | **NÃO convertíveis** — sem resgate, sem troca, sem transferência para dinheiro |
| Compra com dinheiro real | **PROIBIDA** — Coins nunca são vendidos via IAP ou qualquer outro meio |
| Transferência entre usuários | **PROIBIDA** — Coins não saem da conta do usuário |
| Valor monetário | **ZERO** — Coins não possuem, representam ou implicam valor financeiro |
| Expiração | Coins não expiram |
| Uso permitido | Desbloquear customizações visuais (badges, temas, molduras de avatar) |
| Uso proibido | Vantagem competitiva em desafios (pay-to-win) |

---

## 3. COMO COINS SÃO ADQUIRIDOS

OmniCoins existem **somente em duas formas de aquisição**:

| Forma | Descrição |
|-------|-----------|
| **Assessoria** | O professor/coach da assessoria distribui OmniCoins aos seus atletas. É a única fonte de criação de OmniCoins no sistema. |
| **Desafios com inscrição** | Ao vencer um desafio com entry fee > 0, o vencedor recebe as OmniCoins do(s) perdedor(es). Não há criação de coins — é redistribuição do pool. |

### 3.1 O que NÃO dá OmniCoins

| Atividade | Recompensa |
|-----------|-----------|
| Completar sessão de corrida | XP, badges — **nunca OmniCoins** |
| Desafio gratuito (entry fee = 0) | **Nada** (zero coins para todos) |
| Streak semanal/mensal | XP, badges — **nunca OmniCoins** |
| Personal record (PR) | XP, badges — **nunca OmniCoins** |
| Badge desbloqueado | Reconhecimento visual — **nunca OmniCoins** |
| Missão completada | XP — **nunca OmniCoins** |
| Ranking/leaderboard | Posição — **nunca OmniCoins** |

### 3.2 Fluxo de OmniCoins em desafios

1. Cada participante paga o entry fee ao entrar (débito da wallet)
2. As fees formam um pool (entry_fee × número de participantes)
3. O vencedor recebe o pool inteiro
4. Em caso de empate, cada um recebe seu fee de volta (refund)
5. Se ninguém correu, todos recebem refund
6. Desafios gratuitos (fee = 0): zero movimentação de coins

**Regra de ouro:** OmniCoins só entram no sistema via assessoria. Dentro do app, só mudam de mão via desafios com inscrição.

---

## 4. DESAFIOS — REGRAS LOJA-SAFE

### 4.1 Desafios 1v1

| Aspecto | Regra |
|---------|-------|
| Criação | Qualquer usuário pode desafiar outro |
| Aceitação | O desafiado aceita ou recusa (nunca automático) |
| Tipo | Distância, pace, ou tempo em período definido (1h, 3h, 6h, 12h, 24h) |
| Entry fee | OmniCoins (0 = gratuito). Fee pago ao entrar, vai pro pool |
| Resultado (grátis) | **Zero coins** para todos — só vale a competição |
| Resultado (com fee) | Vencedor: pool inteiro (fee × 2). Perdedor: 0 |
| Não completou | Quem não correu no período = **perdeu** (DNF, 0 coins) |
| Ambos não correram | Ambos DNF. Se tinha fee, cada um recebe refund |
| Um correu, outro não | Quem correu ganha automaticamente |
| Empate (grátis) | **Zero coins** |
| Empate (com fee) | Cada um recebe o fee de volta (refund) |
| Validação | Apenas sessões com `isVerified == true` contam |
| **Visibilidade** | Enquanto o desafio está ativo, cada atleta pode ver **apenas** se o oponente completou ou não. **Nenhum detalhe** (pace, distância, tempo) é visível antes de ambos completarem. Após ambos completarem (ou o período expirar), os detalhes são revelados. Isso impede que um atleta espere o outro terminar para ajustar seu esforço. |

### 4.2 Desafios de Grupo

| Aspecto | Regra |
|---------|-------|
| Tamanho | 2-50 participantes |
| Meta | Definida pelo criador (ex: "50 km coletivos em 7 dias") |
| Lógica | **Cooperativo** — o grupo ganha ou perde como unidade |
| Contribuição | Sessões verificadas somam para o progresso coletivo (distância/tempo: soma; pace: média) |
| Meta atingida (grátis) | **Zero coins** — só vale a conquista coletiva |
| Meta atingida (com fee) | Pool dividido igualmente entre **todos** (correu ou não) |
| Meta não atingida | 0 coins para todos (participaram mas falharam) |
| Ninguém correu (com fee) | Todos DNF, refund do fee |
| Abandono | Sai do grupo sem penalidade; contribuição anterior permanece |

### 4.3 Rankings Locais

| Aspecto | Regra |
|---------|-------|
| Escopo | Semanal/mensal, por distância, pace ou frequência |
| Visibilidade | Pública dentro do app (opt-in) |
| Prêmio | Badge/posição — **nunca** Coins por ranking position |
| Anti-fraude | Apenas sessões verificadas aparecem |
| Reset | Rankings resetam automaticamente no período seguinte |

---

## 5. VOCABULÁRIO — TERMOS OBRIGATÓRIOS E PROIBIDOS

### 5.1 Termos PROIBIDOS (nunca usar em UI, push, marketing, metadata)

| Termo Proibido | Motivo |
|----------------|--------|
| aposta / bet / wager | Implica gambling |
| ganhar dinheiro / earn money | Implica valor monetário |
| sacar / withdraw / cash out | Implica resgate financeiro |
| cashout / redeem for cash | Implica conversibilidade |
| prêmio em dinheiro / cash prize | Implica recompensa monetária |
| loteria / lottery | Implica jogo de azar |
| jackpot | Implica gambling |
| payout | Implica pagamento |
| stake / staking | Implica aposta |
| buy coins / comprar moedas | Coins não são vendidos |
| trade / trocar coins | Coins não são transferíveis |
| invest / investir | Implica retorno financeiro |
| prize pool / bolsa de prêmios | Implica pool financeiro |
| real money / dinheiro real | Implica valor monetário |
| gambling / jogo de azar | Implicação direta |

### 5.2 Termos PERMITIDOS (usar sempre que possível)

| Termo Permitido | Contexto de uso |
|-----------------|-----------------|
| desafio / challenge | Competição entre corredores |
| participação / participation | Ato de completar um desafio |
| pontos / points | Sinônimo casual de Coins na UI |
| moedas / coins | Unidade de progresso |
| recompensa in-app / in-app reward | Resultado de atividade |
| conquista / achievement | Milestone alcançado |
| badge | Emblema visual desbloqueável |
| streak | Sequência de atividade |
| ranking / leaderboard | Classificação por mérito |
| meta / goal | Objetivo de desafio |
| progresso / progress | Avanço na gamificação |
| completar / complete | Finalizar desafio/meta |
| bônus / bonus | Coins extras por mérito esportivo |
| personalização / customization | Uso dos Coins na loja interna |
| loja / shop | Interface para gastar Coins em itens visuais |
| destravar / unlock | Ação de obter item com Coins |

---

## 6. COMPLIANCE: APP STORE (APPLE)

### Apple App Store Review Guidelines relevantes

| Guideline | Regra | Nosso status |
|-----------|-------|:------------:|
| **3.1.1 In-App Purchase** | Moedas virtuais devem ser vendidas via IAP | ✅ N/A — Coins não são vendidos |
| **3.1.2(a) Gambling** | Apps que facilitam gambling requerem licença | ✅ N/A — Sem gambling |
| **5.3.4 Body & Health** | Apps de fitness devem ser precisos | ✅ Anti-cheat valida sessões |
| **4.7 HTML5 Games** | Mini-games devem usar capacidades nativas | ✅ N/A — Sem mini-games |
| **3.2.2(ii) Contests** | Contests com prêmios devem cumprir leis locais | ✅ N/A — Sem prêmios monetários |

### Declaração para App Store Review (se questionado)

> "OmniCoins are a purely cosmetic in-app progress currency earned
> exclusively through verified physical activity (running). They cannot
> be purchased, transferred, converted to real money, or redeemed for
> anything outside the app. They are used solely to unlock visual
> customizations (badges, themes, avatar frames). No real-money prizes
> or gambling mechanics exist in the app."

---

## 7. COMPLIANCE: GOOGLE PLAY STORE

### Google Play Developer Policy relevantes

| Policy | Regra | Nosso status |
|--------|-------|:------------:|
| **Real-Money Gambling** | Apps que facilitam gambling requerem licença | ✅ N/A — Sem gambling |
| **Misleading Claims** | Não prometer recompensas monetárias | ✅ Coins são explicitamente não-monetários |
| **Simulated Gambling** | Simulated gambling requer age-gate | ✅ N/A — Sem mecânicas de azar |
| **Health Claims** | Não fazer claims médicos | ✅ App é fitness tracking, não diagnóstico |
| **In-App Purchases** | Moedas vendidas devem usar Play Billing | ✅ N/A — Coins não são vendidos |

### Classificação de conteúdo (IARC)

| Questão | Resposta |
|---------|----------|
| O app contém gambling? | NÃO |
| O app permite compras in-app? | NÃO (para Coins; IAP futuro seria para premium features, não Coins) |
| O app tem interação social? | SIM (desafios, rankings) |
| O app coleta dados pessoais? | SIM (GPS, HR — já declarado na privacy policy) |

---

## 8. ANTI-FRAUDE NA GAMIFICAÇÃO

### 8.1 Regras de validação com o core

| Validação | Descrição | Módulo |
|-----------|-----------|--------|
| `isVerified` obrigatório | Sessão deve passar anti-cheat para gerar Coins | `IntegrityDetectSpeed` + `IntegrityDetectTeleport` + `VehicleSlidingDetector` |
| Velocidade plausível | Pace entre 2:00/km e 15:00/km | `IntegrityDetectSpeed` |
| Sem teleporte | Distância entre pontos consecutivos consistente | `IntegrityDetectTeleport` |
| Steps correlacionados | Cadência de passos compatível com velocidade | `VehicleSlidingDetector` |
| Duração mínima | Sessão ≥ 1 minuto | Domain rule |
| Distância mínima | Sessão ≥ 100 metros para Coins | Domain rule |
| Rate limiting | Máximo 10 sessões/dia geram Coins | Domain rule |
| Deduplicação | Mesma sessão nunca gera Coins duas vezes | `sessionId` como chave |

### 8.2 O que acontece com sessões não-verificadas

- Sessões flagged pelo anti-cheat (`isVerified == false`) aparecem no histórico
- **Não geram Coins**
- **Não contam para desafios**
- **Não aparecem em rankings**
- Usuário vê indicador visual de que a sessão não foi validada

### 8.3 Auditoria

| Aspecto | Implementação |
|---------|---------------|
| Log de Coins | Toda transação (ganho) registrada com `sessionId`, `source`, `amount`, `timestamp` |
| Imutabilidade | Logs de Coins são append-only (nunca editados) |
| Reconciliação | Saldo = soma de todos os logs de ganho − soma de todos os gastos |
| Admin tooling | Query Supabase para verificar anomalias (futuro) |
| Alertas | Threshold: >500 Coins/dia → flag para revisão (futuro) |

---

## 9. O QUE NÃO IMPLEMENTAR (FORA DO ESCOPO)

| Feature excluída | Motivo |
|------------------|--------|
| Compra de Coins via IAP | Criaria valor monetário; violaria princípio fundamental |
| Transferência de Coins entre usuários | Criaria economia paralela; risco de marketplace |
| Resgate de Coins por prêmios físicos | Criaria valor monetário; compliance com leis de promoção |
| NFTs ou blockchain | Completamente fora do escopo e filosofia do app |
| Anúncios para ganhar Coins | Cria incentivo não-atlético; degrada UX |
| Loot boxes / gacha | Mecânica de gambling; rejeitada por Apple e Google |
| Pay-to-win | Coins comprados dando vantagem em desafios; viola fairness |
| Apostas entre usuários | Gambling; requer licença; violaria policies das lojas |

---

## 10. PARK LEADERBOARDS — COMPLIANCE (Sprint 25.0.0)

A feature "Parks" introduz leaderboards locais por parque. Compliance com esta policy:

| Aspecto | Status |
|---------|--------|
| Park tiers são reconhecimento, não moeda | ✅ Tiers (Rei/Elite/Destaque/Pelotão/Frequentador) são labels visuais |
| Leaderboard não gera Coins diretamente | ✅ Rankings são informativos; XP de parque é futuro e segue caps existentes |
| Vocabulário: "Rei do Parque", "Elite", "Destaque" | ✅ Termos de conquista esportiva, sem conotação monetária |
| Anti-exploit: atividades devem vir do Strava | ✅ GPS validado pelo Strava, não pelo app |
| Matchmaking por parque é fairness-first | ✅ Prioriza adversários do mesmo parque para justiça geográfica |
| Shadow Racing não envolve apostas | ✅ Corrida fantasma é referência de pace, sem stake |
| Park community não é marketplace | ✅ "Quem corre aqui" é discovery social, sem transações |

---

## 11. REVISÃO E ATUALIZAÇÃO

| Trigger de revisão | Ação |
|--------------------|------|
| Nova feature de gamificação | Verificar contra este documento antes de implementar |
| Atualização das policies da Apple/Google | Revisar seções 6 e 7 |
| Feedback de App Review rejection | Ajustar vocabulário/mecânicas e documentar em DECISIONS.md |
| Adição de IAP (premium features futuras) | Garantir que IAP é para features, NUNCA para Coins |

---

*Documento criado no Sprint 12.0.0 — Atualizado em 26/02/2026 (Sprint 25.0.0 — Parks Compliance)*
