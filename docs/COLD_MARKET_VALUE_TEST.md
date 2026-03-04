# Cold Market Test — Fase 3: Teste de Valor (3 Minutos)

> Simulação: o usuário completou o onboarding e está na home screen. Tem 3 minutos. O que consegue fazer? O que sente?

---

## Contexto: Estado do usuário ao chegar na Home

Antes de começar o relógio de 3 minutos, o usuário já gastou ~2-3 minutos no onboarding:
- Viu a welcome screen
- Fez login (Google/Apple/Instagram/Email)
- Escolheu "Sou atleta"
- Decidiu sobre assessoria (provavelmente pulou)
- Passou pelo tour (provavelmente pulou)

**Estado ao entrar na Home:** Sem Strava conectado, sem assessoria, sem corridas registradas, sem amigos, 0 OmniCoins.

---

## 1. Que ações o usuário pode tentar em 3 minutos?

### Navegação disponível (Bottom Navigation Bar)

| Aba | Ícone | O que mostra |
|---|---|---|
| **Início** | 🏠 | Dashboard com 7 cards (desafios, assessoria, progresso, verificação, campeonatos, parques, créditos) |
| **Hoje** | 📅 | Streak, desafios ativos, CTA do Strava, recap da corrida, stats |
| **Histórico** | 🕐 | Lista de corridas passadas |
| **Mais** | ☰ | Assessoria, social, perfil, configurações, ajuda |

### Ações possíveis nos primeiros 3 minutos:

#### Minuto 0-1: Exploração do Dashboard (Início)

O usuário vê:
- **"Olá, atleta!"** (nome genérico — não configurou perfil)
- **"O que deseja fazer hoje?"**
- **TipBanner:** "Primeiros passos: 1. Conecte seu Strava... 2. Entre em uma assessoria... 3. Crie ou encontre um desafio... 4. Complete corridas para se tornar Atleta Verificado"
- **7 cards em grid 2x2:**

| Card | O que acontece ao tocar |
|---|---|
| Meus desafios | Abre lista vazia — "Nenhum desafio ainda" |
| Entrar em assessoria | Abre tela de busca de assessoria |
| Meu progresso | Abre hub de progresso (XP, badges, missões) — sem dados |
| Verificação | Mostra status de atleta verificado — incompleto |
| Campeonatos | Bloqueado — requer assessoria |
| Parques | Abre tela de parques — sem dados |
| Meus créditos | Abre wallet — 0 OmniCoins, "Nenhuma movimentação ainda" |

**Resultado:** O usuário toca em vários cards e vê telas vazias ou bloqueadas. Nenhum card produz resultado tangível sem Strava conectado e sem corridas.

#### Minuto 1-2: Exploração da aba "Hoje"

O usuário vê:
- **TipBanner:** "O Omni Runner funciona com o Strava: corra com qualquer relógio... Conecte em Configurações → Integrações."
- **Streak banner:** "Sem sequência ativa — Corra hoje para iniciar uma nova sequência!"
- **CTA grande e destacado:** "Conecte o Strava para começar" — botão laranja "Conectar Strava"
  - Explicação: "O Omni Runner importa suas corridas direto do Strava. Funciona com qualquer relógio..."
- **Sem recap de corrida** (nunca correu)
- **Sem stats** (tudo zerado)

**Resultado:** A tela comunica claramente que o próximo passo é conectar o Strava. Mas o usuário não pode fazer isso em 3 minutos (requer conta Strava, OAuth flow, e idealmente já ter corridas registradas).

#### Minuto 2-3: Exploração do "Mais" e tentativas diversas

Na aba "Mais":

| Seção | Itens |
|---|---|
| Minha Assessoria | Minha Assessoria, Escanear QR, Entregas Pendentes, Meu Treino do Dia |
| Social | Convidar amigos, Meus Amigos, Atividade dos amigos |
| Conta | Meu Perfil, Configurações, Diagnósticos |
| Ajuda | Suporte, Perguntas Frequentes, Sobre |

**Ações tentáveis:**
- **Meu Perfil:** Pode editar nome, foto — funciona ✅
- **Configurações:** Pode mudar tema (dark/light), ver integrações — funciona ✅
- **Perguntas Frequentes:** Pode ler FAQ — funciona ✅
- **Minha Assessoria:** "Você não está em nenhuma assessoria" — bloqueado ❌
- **Convidar amigos:** Pode gerar link de convite — funciona ✅ (mas para quem?)
- **Meus Amigos:** Lista vazia — sem amigos ❌
- **Suporte:** "Você precisa estar em uma assessoria para acessar o suporte" — bloqueado ❌

---

## 2. Que resultados são obtidos?

### Resultados concretos em 3 minutos:

| Ação | Resultado |
|---|---|
| Ver o dashboard | Todos os cards levam a telas vazias ou bloqueadas |
| Tentar criar desafio | Tela de desafios vazia; precisa de Strava para que corridas contem |
| Ver streak | "Sem sequência ativa" — precisa correr |
| Ver OmniCoins | 0 coins, sem movimentação |
| Ver progresso | Nível 1, 0 XP, 0 corridas |
| Editar perfil | Consegue editar nome e foto ✅ |
| Mudar tema | Consegue trocar dark/light ✅ |
| Ver FAQ | Consegue ler informações ✅ |
| Conectar Strava | Pode iniciar o processo (requer conta Strava) |

### Resultado líquido: **ZERO VALOR FUNCIONAL**

O usuário não consegue:
- ❌ Gravar uma corrida (o app depende do Strava, não grava diretamente)
- ❌ Ver dados de performance (não tem corridas)
- ❌ Participar de um desafio (não tem Strava, não é verificado)
- ❌ Interagir com outros corredores (não tem amigos, não tem assessoria)
- ❌ Ganhar OmniCoins (precisa correr, completar desafios, ou receber da assessoria)
- ❌ Acessar suporte (precisa de assessoria)

---

## 3. Pontos de confusão

### Confusão 1: "O app não grava corrida?"
O Omni Runner **não é um GPS tracker autônomo** — ele importa corridas do Strava. Isso não fica claro na welcome screen (que diz "Corra com GPS preciso"). O usuário pode esperar abrir o app e apertar "Iniciar Corrida", mas essa funcionalidade depende do Strava. A aba "Hoje" tem um CTA "Bora correr?" que na verdade diz "corra com seu relógio e sua atividade será importada automaticamente" — ou seja, corra FORA do app.

**Severidade: 🔴 Crítica** — O bullet "Corra com GPS preciso" na welcome screen cria expectativa que o app não atende diretamente.

### Confusão 2: "O que é assessoria?"
Apesar de estar no onboarding, o conceito de assessoria continua confuso na home. O card "Entrar em assessoria" aparece no dashboard, mas o usuário solo não entende por que deveria. Campeonatos ficam bloqueados sem assessoria, suporte fica bloqueado sem assessoria — parece que o app é inútil sem uma.

**Severidade: 🟡 Alta**

### Confusão 3: "Para que servem OmniCoins?"
O card "Meus créditos" leva a uma tela com 0 coins e a mensagem "Peça ao professor da sua assessoria para distribuir OmniCoins." Para quem não tem assessoria, isso é um beco sem saída. O ContextualTipBanner explica que coins vêm de desafios e treinos, mas ambos requerem Strava e corridas.

**Severidade: 🟡 Média**

### Confusão 4: "Atleta Verificado? Verificado de quê?"
O card "Verificação" no dashboard não é autoexplicativo. O tour menciona "Complete 7 corridas válidas para se tornar Verificado", mas o usuário que pulou o tour não sabe disso.

**Severidade: 🟡 Média**

### Confusão 5: Navegação redundante
"Minha Assessoria" aparece em 3 lugares: card no dashboard, item no menu "Mais", e implicitamente na tela de "Hoje" (feed da assessoria). Três caminhos para o mesmo destino vazio.

**Severidade: 🟢 Baixa**

---

## 4. O app entrega valor em 3 minutos?

### **NÃO.**

**Justificativa detalhada:**

O Omni Runner é um app do tipo "cold start problem" extremo. Todas as funcionalidades centrais requerem pelo menos um pré-requisito:

| Funcionalidade | Pré-requisito |
|---|---|
| Ver dados de corrida | Strava conectado + ter corrido |
| Participar de desafios | Strava + Atleta Verificado (7 corridas) |
| Streak | Ter corrido hoje |
| OmniCoins | Assessoria ou completar desafios |
| Campeonatos | Assessoria |
| Ranking de parque | Ter corrido em um parque |
| Feed de amigos | Ter amigos adicionados |
| Suporte | Assessoria |

**O único valor entregue em 3 minutos é informacional:** o usuário entende O QUE o app faz (via dashboard + tips + tour), mas não EXPERIMENTA nenhuma funcionalidade. É como abrir o Netflix sem nenhum filme no catálogo e ser informado de que "filmes aparecerão quando você conectar o serviço de streaming".

**O que DEVERIA acontecer em 3 minutos:**
- O app poderia mostrar dados demo/sample de como seria o dashboard com corridas
- Poderia ter um modo "primeira corrida" com GPS nativo (sem Strava)
- Poderia permitir entrar em um desafio público/aberto como espectador
- Poderia mostrar rankings de parques mesmo sem ter corrido neles
- Poderia gamificar o próprio onboarding (XP por completar perfil, conectar Strava, etc.)

---

## 5. Estado emocional do usuário após 3 minutos

### Perfil emocional por persona:

#### Corredor com assessoria + Strava:
- **Minuto 0-1:** "Legal, parece organizado" (curiosidade)
- **Minuto 1-2:** "Ah, preciso conectar Strava, ok" (leve fricção)
- **Minuto 2-3:** "Vou conectar e voltar depois" (intenção de retorno: **ALTA**)
- **Estado final:** Levemente positivo. Vai voltar se o professor/amigo incentivou.

#### Corredor solo sem Strava:
- **Minuto 0-1:** "Hm, parece ser para quem já corre bastante" (hesitação)
- **Minuto 1-2:** "Preciso de Strava? Preciso de assessoria? Preciso correr 7 vezes?" (frustração crescente)
- **Minuto 2-3:** "Esse app não serve pra mim" (abandono)
- **Estado final:** 😞 **Frustrado/decepcionado**. Provável desinstalação.

#### Corredor casual que viu anúncio:
- **Minuto 0-1:** "Que bonito, vamos ver..." (curiosidade)
- **Minuto 1-2:** "Tudo vazio, nada funciona..." (confusão)
- **Minuto 2-3:** "Desafios com OmniCoins? Mas tenho 0 e preciso de 7 corridas? Chato." (desmotivação)
- **Estado final:** 😐 **Indiferente**. O app não mostrou nada que justifique manter instalado.

### Emoção dominante: **FRUSTRAÇÃO POR PROMESSA NÃO CUMPRIDA**

A welcome screen promete "Seu app de corrida completo" e "Corra com GPS preciso", mas nos primeiros 3 minutos o usuário descobre que:
1. O app não grava corridas diretamente
2. Tudo requer Strava
3. Muitas funcionalidades requerem assessoria
4. Desafios requerem 7 corridas verificadas
5. OmniCoins requerem assessoria ou corridas

A distância entre a promessa (welcome screen) e a realidade (dashboard vazio) é grande demais.

---

## Scorecard Final

| Dimensão | Nota | Justificativa |
|---|---|---|
| Time-to-value | 1/10 | Valor funcional zero em 3 minutos |
| Clareza das ações | 6/10 | O TipBanner de primeiros passos ajuda, mas as ações requerem pré-requisitos externos |
| Engajamento imediato | 2/10 | Sem loop de engajamento — tudo é "faça X fora do app e volte" |
| Resolução do cold start | 1/10 | Nenhuma estratégia para mostrar valor com dados vazios |
| Motivação para voltar | 4/10 | Depende inteiramente de motivação externa (treinador, amigo) |
| Satisfação emocional | 3/10 | Mais frustração que satisfação |
| **Nota geral** | **2.8/10** | O app falha em entregar valor nos primeiros 3 minutos |

---

## Diagnóstico Central

O Omni Runner tem um **problema clássico de marketplace/plataforma**: o produto só tem valor quando o usuário já tem dados (corridas), conexões (Strava, assessoria, amigos) e histórico (7 corridas verificadas). Mas para chegar lá, o usuário precisa investir dias ou semanas.

**O gap é fatal para aquisição orgânica.** O app funciona bem para quem chega via convite de assessoria (o treinador configura, incentiva, e o atleta já tem Strava). Mas para aquisição cold market (loja, anúncio, busca orgânica), os primeiros 3 minutos são um deserto de valor.

**Analogia:** É como baixar um app de delivery que exige que você cadastre seu próprio restaurante antes de poder pedir comida.
