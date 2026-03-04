# Cold Market Test — Fase 7: AHA Moment

**Produto:** Omni Runner  
**Data:** 04/03/2026  
**Perspectiva:** Usuário frio, zero contexto prévio

---

## 1. Mapa completo de potenciais AHA Moments (ordenados por acessibilidade)

### AHA #1 — "Minha corrida apareceu aqui!"
**Tela:** `TodayScreen` → `_RunRecapCard`  
**O que acontece:** O atleta conecta o Strava, faz uma corrida, e ao abrir o app vê um recap completo: distância, pace, duração, elevação, frequência cardíaca, cadência. O app "sabe" o que ele fez.  
**Passos:** Instalar → Onboarding → Conectar Strava → Correr → Abrir o app  
**Pré-requisitos:** Conta Strava ativa, fazer pelo menos 1 corrida  
**Tempo estimado:** 1-3 dias (depende de quando o usuário corre)  
**Visibilidade desde o início:** Média. A `TodayScreen` mostra um CTA "Bora Correr" e pede conexão Strava, mas o valor real só aparece após a primeira corrida.  
**Impacto emocional:** ⭐⭐⭐ (médio) — Satisfaz, mas não surpreende. Muitos apps fazem isso.

---

### AHA #2 — "Estou numa sequência!"
**Tela:** `TodayScreen` → `_StreakBanner`  
**O que acontece:** Após a segunda corrida em dias consecutivos (ou semana consecutiva), aparece o streak counter. O atleta percebe que o app rastreia consistência.  
**Passos:** Instalar → Conectar Strava → Correr 2+ vezes em janela de streak  
**Pré-requisitos:** 2+ corridas em período consecutivo  
**Tempo estimado:** 3-7 dias  
**Visibilidade desde o início:** Baixa. O streak banner só aparece quando `currentStreak > 0`. Antes disso, o atleta não sabe que o sistema de streaks existe.  
**Impacto emocional:** ⭐⭐⭐ (médio) — Gamificação simples mas eficaz. Cria urgência de não quebrar a sequência.

---

### AHA #3 — "Ganhei uma medalha!"
**Tela:** `BadgesScreen`  
**O que acontece:** O atleta desbloqueia seu primeiro badge (provavelmente "Primeira corrida verificada" ou "5km total"). Vê recompensas de XP e OmniCoins.  
**Passos:** Instalar → Onboarding → Conectar Strava → Correr → Dashboard → "Meu progresso" → Badges  
**Pré-requisitos:** 1+ corrida verificada  
**Tempo estimado:** 1-3 dias  
**Visibilidade desde o início:** Muito baixa. Badges estão a 3 toques de profundidade: Dashboard → Meu progresso → Badges. Não há notificação visível de badge desbloqueado na tela principal.  
**Impacto emocional:** ⭐⭐⭐⭐ (alto) — Badges com tiers (Bronze, Silver, Gold, Diamond) e badges secretos criam sensação de descoberta. "O que mais posso desbloquear?"

---

### AHA #4 — "Check-in automático no parque!"
**Tela:** `TodayScreen` → `_ParkCheckinCard`  
**O que acontece:** O atleta corre em um parque mapeado. O app detecta automaticamente e sugere check-in. Ele descobre que existe uma comunidade local com ranking.  
**Passos:** Instalar → Conectar Strava → Correr em um parque cadastrado → Abrir app  
**Pré-requisitos:** Correr fisicamente em um parque mapeado no sistema  
**Tempo estimado:** 1-7 dias (depende de localização e hábito)  
**Visibilidade desde o início:** Nula. O card só aparece se `lastRun.parkId != null`. Não há menção de parques antes disso.  
**Impacto emocional:** ⭐⭐⭐⭐ (alto) — "O app sabe ONDE eu corri e me conecta com outros corredores dali". Surpreendente e contextualmente relevante.

---

### AHA #5 — "Estou contribuindo para minha assessoria!"
**Tela:** `LeagueScreen` → `_MyContributionCard`  
**O que acontece:** O atleta descobre que seus quilômetros contam para o ranking da assessoria. Ele não corre sozinho — corre pela equipe.  
**Passos:** Instalar → Onboarding → Entrar em assessoria → Correr → Dashboard → Liga  
**Pré-requisitos:** Pertencer a uma assessoria inscrita na liga  
**Tempo estimado:** 1-7 dias  
**Visibilidade desde o início:** Baixa. A Liga está no dashboard como card, mas sem urgência. O card de contribuição pessoal aparece somente dentro da tela de liga.  
**Impacto emocional:** ⭐⭐⭐⭐ (alto) — Transforma corrida individual em coletiva. Pertencimento e propósito.

---

### AHA #6 — "Aposto que corro mais que você"
**Tela:** `ChallengeDetailsScreen` + `ChallengeResultScreen`  
**O que acontece:** O atleta cria ou aceita um desafio 1v1 ou em grupo. Ao final, vê resultado com coins ganhos/perdidos e pode desafiar novamente.  
**Passos:** Instalar → Onboarding → Conectar Strava → Dashboard → "Meus desafios" → Criar/aceitar desafio → Completar período → Ver resultado  
**Pré-requisitos:** Ter OmniCoins para entry fee, outra pessoa para desafiar  
**Tempo estimado:** 3-14 dias (depende da duração do desafio)  
**Visibilidade desde o início:** Média. "Meus desafios" é um card no dashboard. Mas criar desafio requer coins e um oponente — duas barreiras.  
**Impacto emocional:** ⭐⭐⭐⭐⭐ (muito alto) — Competição direta com prêmio. Adrenalina, bragging rights, revanches. **Este é o core loop emocional do produto.**

---

### AHA #7 — "Minha evolução é real"
**Tela:** `AthleteEvolutionScreen`  
**O que acontece:** O atleta vê gráficos de tendência (pace, distância, volume, frequência) mostrando melhora ao longo do tempo. Baseline comparativo.  
**Passos:** Instalar → Conectar Strava → Correr regularmente → Dashboard → "Meu progresso" → Evolução  
**Pré-requisitos:** Histórico suficiente para calcular baseline (~4+ semanas de dados)  
**Tempo estimado:** 30+ dias  
**Visibilidade desde o início:** Nula. Sem dados, a tela não tem valor. Não aparece em nenhuma comunicação inicial.  
**Impacto emocional:** ⭐⭐⭐⭐ (alto) — Ver que "seu pace médio melhorou 8% em 4 semanas" é validação poderosa.

---

### AHA #8 — "Correndo contra meu fantasma"
**Tela:** `GhostComparisonCard` (widget)  
**O que acontece:** O atleta compete contra uma corrida anterior sua (ou de outro corredor). Vê em tempo real se está à frente ou atrás, com delta de metros e pace.  
**Passos:** Instalar → Conectar Strava → Correr mesma rota 2+ vezes → Ativar ghost comparison  
**Pré-requisitos:** 2+ corridas na mesma rota, feature ativada  
**Tempo estimado:** 7-14 dias  
**Visibilidade desde o início:** Nula. Não aparece em nenhuma tela inicial. É um widget dentro de outra tela.  
**Impacto emocional:** ⭐⭐⭐⭐⭐ (muito alto) — "Estou correndo contra mim mesmo" é extremamente motivador. Shadow racing é premium.

---

### AHA #9 — "Esse é meu DNA de corredor"
**Tela:** `RunningDnaScreen`  
**O que acontece:** Radar chart de 6 eixos (Velocidade, Resistência, Consistência, Evolução, Versatilidade, Competitividade) + insights textuais + previsão de PR com nível de confiança.  
**Passos:** Instalar → Conectar Strava → Correr 10+ vezes verificadas em 6 meses → Dashboard → DNA  
**Pré-requisitos:** **Mínimo 10 corridas verificadas nos últimos 6 meses**  
**Tempo estimado:** 60-180 dias  
**Visibilidade desde o início:** Nula. Requer volume significativo de dados. Sem preview ou teaser.  
**Impacto emocional:** ⭐⭐⭐⭐⭐ (muito alto) — **O AHA mais poderoso do produto.** Unicamente pessoal, visualmente impactante, compartilhável. "Não sabia que meu perfil era assim."

---

### AHA #10 — "Meu ano em corrida"
**Tela:** `WrappedScreen`  
**O que acontece:** Retrospectiva estilo "Spotify Wrapped" com 6 slides: números totais, evolução de pace, desafios, badges, curiosidades, compartilhamento.  
**Passos:** Instalar → Correr regularmente → Período wrapped disponível  
**Pré-requisitos:** **Mínimo 3 corridas verificadas no período**  
**Tempo estimado:** Depende do calendário (anual ou por período)  
**Visibilidade desde o início:** Nula. Disponível apenas em janelas específicas.  
**Impacto emocional:** ⭐⭐⭐⭐⭐ (muito alto) — Nostalgia + orgulho + viralidade (compartilhamento de card). Mas inacessível para usuário frio — requer meses de uso.

---

## 2. Resumo estruturado por AHA

| # | AHA Moment | Passos | Pré-requisitos | Tempo | Visibilidade |
|---|---|---|---|---|---|
| 1 | Run Recap | 4 | Strava + 1 corrida | 1-3 dias | Média |
| 2 | Streak | 4 | 2+ corridas consecutivas | 3-7 dias | Baixa |
| 3 | Primeiro Badge | 5 | 1 corrida verificada | 1-3 dias | Muito baixa |
| 4 | Park Check-in | 4 | Correr em parque mapeado | 1-7 dias | Nula |
| 5 | Liga (Contribuição) | 5 | Assessoria + Liga inscrita | 1-7 dias | Baixa |
| 6 | Desafio Completo | 6+ | Coins + oponente + tempo | 3-14 dias | Média |
| 7 | Evolução | 5 | 4+ semanas de dados | 30+ dias | Nula |
| 8 | Ghost Racing | 5 | 2+ corridas mesma rota | 7-14 dias | Nula |
| 9 | Running DNA | 5 | 10 corridas em 6 meses | 60-180 dias | Nula |
| 10 | Wrapped | 4 | 3+ corridas no período | Meses | Nula |

---

## 3. PRIMEIRO AHA possível (menor esforço)

### 🏆 AHA #1 — Run Recap na TodayScreen

**Por quê:** É o AHA mais próximo do zero porque:
- É a tela que o atleta vê ao abrir o app (`TodayScreen`)
- Precisa apenas de 1 corrida sincronizada do Strava
- Mostra dados automaticamente sem ação adicional
- Envolve métricas pessoais (distância, pace, FC, cadência)

**Mas tem um problema:** Antes da primeira corrida, a `TodayScreen` mostra apenas um CTA "Bora Correr" com ícone de corredor. Não há preview do que o atleta ganhará ao completar uma corrida. O "AHA" está atrás de uma **parede de esforço físico** — o atleta precisa literalmente sair de casa e correr.

**Tempo realista até o AHA:** Se o atleta já corre regularmente com Strava, pode ser **horas**. Se não, pode ser **dias** ou **nunca** (se ele desistir antes).

---

## 4. AHA MAIS FORTE (maior impacto emocional)

### 🏆 AHA #9 — Running DNA

**Por quê:** É o único AHA que:
- Revela algo que o atleta **não sabia sobre si mesmo**
- Usa visualização impactante (radar chart de 6 eixos)
- Inclui insights em linguagem natural ("Você é um corredor de resistência com alta consistência")
- Oferece previsões de PR com nível de confiança
- É **compartilhável** (gera card visual para redes sociais)
- Não existe em nenhum concorrente mainstream

**O problema devastador:** Requer **10 corridas verificadas em 6 meses**. Um corredor recreativo que corre 2x/semana levará ~5 semanas. Um iniciante pode levar 3-6 meses. A maioria dos usuários frios **nunca chegará a esse AHA**.

**O segundo mais forte:** AHA #6 (Desafio Completo) pela competição direta e coins. Mas também requer coins, oponente e dias de espera.

---

## 5. Gap Analysis: Instalação → Primeiro AHA

```
INSTALAR ──→ ONBOARDING ──→ CONECTAR STRAVA ──→ SAIR E CORRER ──→ VOLTAR AO APP ──→ AHA
   │              │                │                    │                 │
   0 min        2-5 min         +5 min            +30 min a DIAS       +1 min
                                                  (PAREDE FÍSICA)
```

### Tempos estimados:
- **Instalação → Onboarding completo:** 2-5 minutos
- **Onboarding → Conexão Strava:** +1-5 minutos (se já tem Strava)
- **Conexão Strava → Primeira corrida:** **VARIÁVEL: horas a dias**
- **Corrida → Run Recap visível:** <5 minutos (sync automático)
- **TOTAL até primeiro AHA:** **Horas a dias** (mínimo ~40 minutos se correr imediatamente)

### Gap crítico identificado:
Entre "conectar Strava" e "primeira corrida importada" existe um **vácuo total de valor**. O app não oferece nada de interessante durante esse período:

- Sem dados históricos importados do Strava (histórico de corridas)
- Sem preview de features futuras
- Sem mini-AHA simulado
- Sem conteúdo educativo
- Sem interação social
- Dashboard com cards que levam a telas vazias

O atleta baixa o app, faz onboarding, e encontra... **nada**. Precisa sair, correr, e voltar para ver qualquer valor.

---

## 6. Existe AHA para um usuário frio?

### Resposta: Não existe AHA imediato para o usuário frio.

**Razões:**

1. **Todos os AHAs requerem dados de corrida.** Sem correr, nenhuma feature mostra valor. O app é um container vazio esperando ser preenchido.

2. **Não há importação de histórico.** Se o atleta já tem 200 corridas no Strava, o app não importa esse histórico para gerar valor imediato (badges retroativos, DNA parcial, evolução).

3. **O onboarding não demonstra o produto.** As telas de onboarding (WelcomeScreen, OnboardingRoleScreen, JoinAssessoriaScreen) são funcionais — criam conta e vinculam assessoria — mas não mostram o que o produto faz. Não há demo, screenshots de features, ou "veja o que você vai desbloquear".

4. **Não há "AHA de descoberta".** O dashboard mostra cards genéricos (Meus desafios, Meu progresso, etc.) sem preview do conteúdo. Um atleta frio vê labels mas não entende o valor por trás deles.

5. **O AHA social está bloqueado.** Desafios, liga e parques dependem de outros usuários ou assessoria — barreiras externas ao controle do app.

### O resultado prático:
Um usuário frio que instala o Omni Runner e **não corre nos próximos 3 dias** provavelmente desinstala. O app não oferece razão para voltar.

---

## 7. Recomendações para trazer o AHA mais perto da instalação

### R1. Importar histórico do Strava na conexão
Ao conectar Strava, importar as últimas 20-50 corridas. Isso permitiria:
- Gerar badges retroativos → AHA imediato de "já desbloqueei 5 badges!"
- Calcular evolução → AHA de "meu pace melhorou 12% nos últimos 3 meses"
- Running DNA parcial → AHA de perfil de corredor (se ≥10 corridas)
- Popular o `RunRecapCard` → mostrar a última corrida imediatamente
- Identificar parques → mostrar "Você corre no Ibirapuera! Sabia que tem 47 corredores lá?"
**Impacto: Reduz gap de DIAS para MINUTOS.**

### R2. Preview interativo durante onboarding
Antes de pedir conta/Strava, mostrar 3 slides interativos:
- "Veja como é seu DNA de corredor" (radar chart com dados demo)
- "Desafie amigos com OmniCoins" (animação de desafio)
- "Sua assessoria na liga nacional" (ranking animado)
**Impacto: Cria antecipação e entendimento do valor.**

### R3. AHA imediato sem corrida
Criar um "mini-AHA" que não depende de dados de corrida:
- Quiz de perfil de corredor ("Qual seu tipo de corredor?") → resultado básico
- Explorar parques próximos com ranking → "Tem 23 corredores perto de você"
- Catálogo de badges com preview → "Veja o que você pode desbloquear"
- Explorar desafios disponíveis → "Aposto que corro 30km essa semana"
**Impacto: Dá razão para explorar o app antes de correr.**

### R4. Notificação inteligente pós-corrida
Se o atleta conectou Strava mas não abriu o app após correr:
- Push: "Você correu 5.2km! Veja seu recap e confira se desbloqueou um badge 🏅"
**Impacto: Puxa o atleta de volta ao app no momento certo.**

### R5. Streak retroativo
Ao importar histórico, reconhecer streaks passados:
- "Você teve uma sequência de 4 semanas em outubro! Vamos superar?"
**Impacto: Ativa gatilho de consistência sem esforço novo.**

### R6. Demo mode / dados de exemplo
Para atletas sem Strava ou que não querem conectar imediatamente:
- Mostrar o app com dados fictícios de um corredor exemplo
- "Assim vai ficar seu dashboard quando você conectar o Strava"
**Impacto: Remove a barreira de "preciso correr para ver algo".**

### R7. Reduzir requisitos do Running DNA
Atualmente exige 10 corridas verificadas em 6 meses. Considerar:
- DNA "preview" com 3 corridas (com disclaimer de baixa confiança)
- DNA completo com 10 corridas
**Impacto: O AHA mais forte fica acessível 3x mais rápido.**

---

## 8. Ratings

| Dimensão | Nota (0-10) | Justificativa |
|---|---|---|
| **Tempo até AHA** | 3/10 | O primeiro AHA real (Run Recap) requer uma corrida física, que pode levar horas a dias. Não há AHA "zero esforço" na instalação. O gap entre instalar e sentir valor é letal para retenção D1. |
| **Impacto emocional** | 8/10 | Quando os AHAs acontecem, são poderosos. Running DNA, Ghost Racing, Wrapped e Desafios criam experiências emocionais genuínas que não existem em concorrentes. O problema não é a qualidade dos AHAs — é a demora para chegar neles. |
| **Acessibilidade** | 2/10 | Os AHAs mais impactantes (DNA, Wrapped, Ghost) exigem semanas a meses de uso. Estão escondidos atrás de múltiplas camadas de navegação. Sem preview, sem teaser, sem breadcrumbs. O atleta frio não sabe que essas features existem até tropeçar nelas. |

### Resumo executivo

O Omni Runner tem **AHAs extremamente fortes** — Running DNA, Ghost Racing e Wrapped são features de classe mundial que criam diferenciação real. O problema é que estão **trancados atrás de semanas ou meses de uso ativo**.

O app sofre do **"paradoxo do container vazio"**: é um produto incrível com dados, mas inútil sem dados. Um usuário frio vê um app vazio e não tem razão para voltar.

A recomendação mais urgente é **importar histórico do Strava na conexão**. Isso transformaria o primeiro acesso de "tela vazia, vá correr" para "olha o que você já conquistou, veja seu DNA, aqui está seu perfil" — um AHA imediato e pessoal.

**A distância entre o produto que existe e o produto que o usuário frio percebe é enorme.** O valor está lá, mas invisível.
