# Cold Market Test — Fase 8: Drop-off (Abandono)

**Produto:** Omni Runner  
**Data:** 04/03/2026  
**Perspectiva:** Usuário frio, zero contexto prévio

---

## 1. Funil de Drop-off — Da instalação à retenção

```
LOJA (100%) ──→ INSTALAR (60%) ──→ ABRIR (55%) ──→ WELCOME (50%) ──→ LOGIN (35%)
    │                │                │                │                │
    │ -40% não       │ -5% abre e     │ -5% não       │ -15% barreira   │
    │ instala        │ fecha           │ entende       │ de login        │
    │                │                 │               │                 │
    ▼                ▼                 ▼               ▼                 ▼
 LOGIN OK (30%) ──→ ROLE SELECT (28%) ──→ ASSESSORIA (25%) ──→ HOME (22%)
    │                    │                    │                    │
    │ -2% erro           │ -3% confusão       │ -3% pula sem      │
    │ ou desiste         │ sobre papel        │ entender           │
    │                    │                    │                    │
    ▼                    ▼                    ▼                    ▼
 ABA HOJE (18%) ──→ VÊ STRAVA CTA (16%) ──→ CONECTA STRAVA (8%) ──→ CORRE (4%)
    │                    │                        │                      │
    │ -4% telas          │ -8% não tem            │ -4% não corre        │
    │ vazias             │ Strava ou              │ nos 3 dias           │
    │                    │ desiste                │ seguintes            │
    │                    │                        │                      │
    ▼                    ▼                        ▼                      ▼
 VOLTA PÓS-CORRIDA (3%) ──→ AHA MOMENT (2.5%) ──→ RETENÇÃO D7 (1.5%)
```

**Taxa estimada de conversão cold market: ~1.5-2% (instalação → retenção D7)**

---

## 2. Pontos de abandono detalhados

### DROP-OFF #1 — Welcome Screen: "Promessa genérica"
**Tela:** `WelcomeScreen`  
**Gatilho:** O usuário vê "Seu app de corrida completo" com 4 bullets genéricos (GPS, desafios, evolução, assessoria). Não há diferenciação clara vs. Strava/Nike Run Club.  
**Emoção:** Indiferença → "Parece mais um app de corrida"  
**Expectativa quebrada:** Esperava algo único que justificasse outra instalação além do Strava  
**Muro:** Nenhum muro técnico, mas falta de gancho emocional  
**Severidade:** 3/5  

**Confusão:** O bullet "Corra com GPS preciso" cria a expectativa de que o app grava corridas diretamente. Na verdade, ele depende do Strava. Essa promessa será quebrada 5 minutos depois.

---

### DROP-OFF #2 — Login Screen: "Preciso criar conta para ver o app?"
**Tela:** `LoginScreen`  
**Gatilho:** Barreira obrigatória de autenticação. 4 opções (Google, Apple/iOS, Instagram, Email). Sem opção de "explorar sem conta".  
**Emoção:** Resistência → "Ainda não sei se quero, mas já pedem meus dados"  
**Expectativa quebrada:** Apps modernos permitem explorar antes de pedir login  
**Muro:** 🔒 **Login obrigatório** — barreira de autenticação antes de ver qualquer valor  
**Severidade:** 4/5  

**Confusão:** 
- Instagram OAuth pode confundir — "Login com Instagram num app de corrida?"
- Texto "Ao continuar, você concorda com nossa Política de Privacidade" sem mostrar Termos de Uso
- Se o servidor estiver fora: "Sem conexão com o servidor" — o app para completamente

---

### DROP-OFF #3 — Role Selection: "O que é assessoria?"
**Tela:** `OnboardingRoleScreen`  
**Gatilho:** Pergunta "Como você quer usar o Omni Runner?" com duas opções: "Sou atleta" e "Represento uma assessoria". Para 95%+ dos usuários cold market, a segunda opção é irrelevante.  
**Emoção:** Confusão leve → "Óbvio que sou atleta, por que perguntar?"  
**Expectativa quebrada:** Onboarding deveria ser sobre o USUÁRIO, não sobre o modelo de negócios do app  
**Muro:** 🔒 **Chamada de rede obrigatória** (`set-user-role` Edge Function) com 3 retries — pode falhar e bloquear  
**Severidade:** 2/5  

**Confusão:**
- O diálogo de confirmação diz "Essa será sua experiência principal no app. Se precisar ajustar, acesse Configurações ou fale com o suporte" — parece uma decisão irreversível e assusta o usuário
- O texto "Represento uma assessoria" é jargão — usuários frios não sabem o que é assessoria

---

### DROP-OFF #4 — Join Assessoria: "Buscar o quê?"
**Tela:** `JoinAssessoriaScreen`  
**Gatilho:** Tela pedindo para buscar/escanear QR/inserir código de uma assessoria. Para um usuário frio, isso é completamente sem contexto.  
**Emoção:** Frustração → "Não tenho código, não conheço nenhuma assessoria, por que estou aqui?"  
**Expectativa quebrada:** O app deveria me guiar, não me pedir informações que não tenho  
**Muro:** Nenhum muro técnico (tem botão "Pular"), mas carga cognitiva alta  
**Severidade:** 3/5  

**Confusão:**
- O texto explica "Assessoria é seu grupo de corrida com treinador" — mas e se eu não tenho treinador?
- "Pular — posso entrar depois" é o CTA correto mas está posicionado como secundário (outlined, no fundo)
- O texto "Assessoria desbloqueia ranking de grupo e desafios em equipe" implica que funcionalidades ficam bloqueadas sem assessoria
- Busca vazia com ícone de grupo e "Digite o nome da assessoria para buscar" não ajuda quem não sabe o que buscar

---

### DROP-OFF #5 — Home/Dashboard: "O Deserto de Valor"
**Tela:** `AthleteDashboardScreen`  
**Gatilho:** O usuário finalmente chega ao dashboard e encontra 7 cards em grid, todos levando a telas vazias ou bloqueadas.  
**Emoção:** Decepção profunda → "Instalei, criei conta, e tudo está vazio?"  
**Expectativa quebrada:** Esperava VER valor imediato; recebe apenas promessas de valor futuro  
**Muro:** 🔒 **Muro de dados** — toda funcionalidade requer Strava + corridas  
**Severidade:** 5/5 🔴 CRÍTICO  

**Confusão:**
- TipBanner com "Primeiros passos" lista 4 tarefas: todas requerem ação FORA do app
- Card "Campeonatos" está bloqueado com `AssessoriaRequiredSheet` — o app pune quem pulou assessoria
- Card "Meu progresso" com badge "Conecte Strava" mas sem explicar POR QUÊ
- "Meus créditos" mostra 0 OmniCoins sem contexto de como ganhar
- "Verificação" é incompreensível sem contexto ("Status de atleta verificado")
- Card de solicitação pendente (quando se solicita assessoria) mostra "Aguardando aprovação" — dependência externa sem prazo definido

---

### DROP-OFF #6 — Today Screen: "Conecte o Strava para começar"
**Tela:** `TodayScreen`  
**Gatilho:** Grande CTA laranja "Conecte o Strava para começar" domina a tela. Streak mostra "Sem sequência ativa".  
**Emoção:** Resignação → "Preciso de OUTRO app para esse funcionar?"  
**Expectativa quebrada:** "Corra com GPS preciso" (welcome screen) vs. "Conecte o Strava" (realidade)  
**Muro:** 🔒 **Dependência do Strava** — sem Strava, a tela principal é um CTA gigante  
**Severidade:** 5/5 🔴 CRÍTICO  

**Confusão:**
- O texto diz "Funciona com qualquer relógio: Garmin, Coros, Apple Watch, Polar, Suunto, ou até correndo só com o celular" — então o app não grava direto? Preciso de um relógio?
- "Suas últimas corridas são importadas automaticamente para calibrar seu nível" — backfill do histórico, mas isso não fica claro na UX pós-conexão

---

### DROP-OFF #7 — Challenges List: "Nenhum desafio, e preciso de Strava"
**Tela:** `ChallengesListScreen`  
**Gatilho:** Tela vazia com "Nenhum desafio ainda" e banner de Strava. Botões "Encontrar Oponente" e "Criar e convidar" que requerem Strava e coins.  
**Emoção:** Desilusão → "A feature principal é vazia e bloqueada"  
**Expectativa quebrada:** A welcome screen prometeu "Desafie outros corredores", mas não há ninguém para desafiar  
**Muro:** 🔒 **Strava obrigatório + Coins + outro usuário**  
**Severidade:** 4/5  

---

### DROP-OFF #8 — Wallet: "0 OmniCoins, peça ao professor"
**Tela:** `WalletScreen`  
**Gatilho:** Mostra 0 total, 0 disponível, 0 pendente. Mensagem: "Peça ao professor da sua assessoria para distribuir OmniCoins."  
**Emoção:** Abandono → "Economia do app é inacessível sem assessoria"  
**Expectativa quebrada:** Moeda gamificada que deveria empoderar o jogador, mas é controlada por terceiros  
**Muro:** 🔒 **Assessoria + corridas para ganhar coins**  
**Severidade:** 3/5  

**Confusão:**
- FAB "Escanear QR" na wallet screen — para que serve? O usuário não tem contexto
- "Coins pendentes são prêmios de desafios entre assessorias diferentes" — extremamente nichado

---

### DROP-OFF #9 — Running DNA: "Continue correndo! (10 corridas necessárias)"
**Tela:** `RunningDnaScreen`  
**Gatilho:** Tela de loading que resulta em "Continue correndo! Precisamos de pelo menos 10 corridas verificadas nos últimos 6 meses para gerar seu DNA."  
**Emoção:** Frustração → "A feature mais legal do app e preciso de 10 corridas?"  
**Expectativa quebrada:** O radar chart deveria ser o showcase do app, não uma tela bloqueada  
**Muro:** 🔒 **10 corridas verificadas em 6 meses** — semanas a meses de uso  
**Severidade:** 4/5  

---

### DROP-OFF #10 — League Screen: "Nenhuma temporada ativa"
**Tela:** `LeagueScreen`  
**Gatilho:** Se não há temporada ativa: "A próxima temporada da liga será anunciada em breve." Se há, mas o usuário não tem assessoria, não aparece contribuição pessoal.  
**Emoção:** Desconexão → "Feature que depende de timing e assessoria"  
**Expectativa quebrada:** Liga deveria ser inspiracional, mostra vazio  
**Muro:** 🔒 **Assessoria + temporada ativa**  
**Severidade:** 3/5  

---

### DROP-OFF #11 — Athlete Evolution: "Sem dados de evolução"
**Tela:** `AthleteEvolutionScreen`  
**Gatilho:** "Sem dados de evolução — Continue correndo para gerar análises de evolução do seu desempenho."  
**Emoção:** Tédio → "Mais uma tela vazia"  
**Expectativa quebrada:** "Acompanhe sua evolução" (welcome screen) não funciona sem semanas de dados  
**Muro:** 🔒 **4+ semanas de dados de corrida para baseline**  
**Severidade:** 3/5  

---

### DROP-OFF #12 — Settings: "Ponto sem retorno"
**Tela:** `SettingsScreen`  
**Gatilho:** A integração Strava ainda desconectada é o único item de ação real. Resto é configuração estética.  
**Emoção:** Neutro → funcional mas não gera engajamento  
**Expectativa quebrada:** Nenhuma  
**Muro:** Nenhum  
**Severidade:** 1/5  

---

### DROP-OFF #13 — Profile: "Logout e Delete Account em destaque"
**Tela:** `ProfileScreen`  
**Gatilho:** O perfil mostra edição de nome/foto e logo abaixo: "Sair da conta" (vermelho) e "Excluir conta" (vermelho). Para um usuário frustrado, esses CTAs são a saída mais visível.  
**Emoção:** Negativa → "O app já me oferece saída antes de mostrar valor"  
**Expectativa quebrada:** Perfil deveria celebrar conquistas, não oferecer ejeção  
**Muro:** Nenhum — facilita o abandono  
**Severidade:** 2/5  

---

## 3. Top 5 Pontos de Drop-off (por probabilidade)

| Rank | Ponto | Tela | Taxa est. de abandono | Razão |
|---|---|---|---|---|
| 🥇 1 | **Deserto de Valor** | `AthleteDashboardScreen` + `TodayScreen` | 40-60% dos que chegam | Dashboard inteiro vazio. Sem nada para fazer. O usuário percebe que precisa sair e correr para VER qualquer coisa. O momento mais crítico: o app não entrega o mínimo após forçar login + onboarding. |
| 🥈 2 | **Barreira do Strava** | `TodayScreen` (CTA Strava) | 50-70% que veem o CTA | Metade dos usuários não tem Strava ou não quer conectar outro serviço. O app se torna literalmente inutilizável. Sem alternativa de gravação nativa. |
| 🥉 3 | **Login obrigatório** | `LoginScreen` | 20-30% da welcome | Login antes de ver qualquer valor é a prática mais destrutiva de retenção. O usuário perde 15-30% aqui sem sequer entender o que ganha em troca. |
| 4 | **Não corre em 3 dias** | Pós-onboarding | 60-80% que conectam | Mesmo quem conecta Strava: se não corre nos próximos 3 dias, o app não tem nada para mostrar. Sem notificação de "boas-vindas com dados", sem valor passivo. O app esquece do usuário. |
| 5 | **Assessoria bloqueando features** | `AthleteDashboardScreen` | 30-40% dos solo | Campeonatos bloqueados, suporte bloqueado, coins dependem de assessoria. O usuário solo se sente cidadão de segunda classe. |

---

## 4. Timeline de Drop-off

### Minuto 0-1: Welcome + Login (20-30% abandonam)
- **O que acontece:** Usuário vê a welcome screen, lê os bullets, toca "COMEÇAR"
- **Risco:** Promessa genérica não diferencia o app. Login obrigatório sem preview
- **Quem sai:** Curiosos casuales que não veem razão para criar conta
- **Emoção:** "Hmm, preciso criar conta já?"

### Minuto 1-3: Onboarding Role + Assessoria (5-10% abandonam)
- **O que acontece:** Escolhe "Sou atleta", diálogo de confirmação, tela de assessoria
- **Risco:** Conceito de assessoria é jargão. Tela de busca inútil para quem é cold
- **Quem sai:** Quem se sente perdido com terminologia ("assessoria?", "grupo de corrida?")
- **Emoção:** "Não entendo essa parte, vou pular"

### Minuto 3-5: Dashboard vazio (30-50% abandonam) 🔴 MOMENTO MAIS LETAL
- **O que acontece:** Chega ao dashboard. Toca em cards. Tudo vazio. Vai para "Hoje". CTA do Strava gigante.
- **Risco:** O gap entre expectativa (app de corrida funcional) e realidade (container vazio) é devastador
- **Quem sai:** Qualquer um sem motivação externa forte (treinador mandou, amigo convidou)
- **Emoção:** "Gastei 5 minutos pra nada. Não vou correr SÓ pra testar um app."

### Minuto 5-10: Tentativa de exploração (10-20% restantes abandonam)
- **O que acontece:** Os persistentes tentam explorar mais: wallet (0 coins), perfil, configurações
- **Risco:** Cada tela reforça a mensagem "você não tem nada aqui"
- **Quem sai:** Quem tentou dar uma chance e não encontrou um único motivo para ficar
- **Emoção:** "Vou voltar... algum dia... (nunca volta)"

### Dia 1: Pós-instalação (50-70% nunca abrem D2)
- **O que acontece:** O app não envia nenhuma notificação de boas-vindas relevante
- **Risco:** Sem reengajamento proativo, o app é esquecido
- **Quem sai:** Quem não correu nesse dia e não tem lembrete
- **Emoção:** App vira ícone invisível na tela

### Semana 1: Retenção crítica (80-90% já saíram)
- **O que acontece:** Quem conectou Strava e correu 1-2x vê o Run Recap e streak
- **Risco:** Se a corrida não é particularmente reveladora no app, o usuário volta ao Strava
- **Quem sobra:** Apenas quem tem assessoria ativa OU quem já criou/recebeu um desafio
- **Emoção:** "O Strava já me mostra isso. Por que usar dois apps?"

---

## 5. Retention Killers — Features que ativamente empurram o usuário para fora

### RK1. Dependência absoluta do Strava
O Omni Runner não é um app de corrida — é um **add-on do Strava**. Se você não tem Strava, o app é inútil. Isso elimina todo o mercado de corredores casuais que gravam corridas no celular, Apple Watch nativo, ou Google Fit. A welcome screen promete "Corra com GPS preciso", criando expectativa de gravação nativa que não existe.

### RK2. Telas vazias como estado padrão
Toda tela principal (dashboard, desafios, wallet, liga, evolução, DNA) abre em estado vazio com mensagem "faça X para ver algo". Isso não é cold start mitigation — é cold start punição. O app diz "você ainda não fez nada" em vez de "olha o que você pode fazer".

### RK3. Assessoria como gatekeeper
Campeonatos: bloqueado sem assessoria. OmniCoins: "Peça ao professor". Suporte: "Precisa estar em assessoria". Feed: inexistente sem assessoria. O modelo B2B (coach-to-athlete) vazou para a experiência do consumidor final. O atleta solo é tratado como incompleto.

### RK4. Login obrigatório sem preview
O app pede login (com dados pessoais) antes de mostrar qualquer funcionalidade. Nenhum modo de exploração. Nenhum demo. O commitment ask é alto para o valor demonstrado (zero).

### RK5. 7 corridas para verificação + 10 para DNA
Os milestones estão MUITO distantes do primeiro uso. Para um corredor casual que corre 2x/semana: 3.5 semanas para verificação, 5 semanas para DNA. Essas features deveriam ser a cenoura, mas estão atrás de uma maratona de paciência.

### RK6. Economia fechada (OmniCoins)
A wallet começa com 0 coins. Para ganhar coins, precisa de corridas verificadas ou assessoria distribuindo. Para gastar coins, precisa de desafios (que requerem oponente + Strava). É uma economia circular sem entrada para novos usuários.

### RK7. Sem conteúdo passivo
O app não tem feed de corridas de outros, não tem dicas de treino, não tem artigos, não tem notícias de corrida, não tem nada para consumir passivamente. Se você não gerou dados ativos, não há NADA para ver.

---

## 6. Retention Hooks — Features que PODERIAM puxar o usuário de volta

### RH1. Streak System (potencial alto, ativação tardia)
O sistema de streaks com milestones (7, 14, 30, 60, 100 dias) e XP progressivo é um excelente loop de retenção. **Problema:** só ativa após a segunda corrida consecutiva. O usuário precisa CHEGAR ao streak para ser retido por ele.

### RH2. Running DNA (potencial altíssimo, ativação muito tardia)
O radar chart de 6 eixos é genuinamente único no mercado. Compartilhável, visualmente impactante, auto-revelatório. **Problema:** 10 corridas em 6 meses. O hook mais forte do produto é praticamente inacessível para novos usuários.

### RH3. Desafios com Coins (potencial alto, múltiplas barreiras)
Competição 1v1 com apostas de OmniCoins é emocionante e cria revanches naturais. **Problema:** requer Strava, coins, oponente, e tempo. 4 barreiras simultâneas.

### RH4. Check-in automático em parques (potencial médio, geográfico)
Descobrir que o app sabe onde você corre e conecta com outros corredores locais. **Problema:** só funciona em parques mapeados no seed, e só após uma corrida naquele parque.

### RH5. Liga de Assessorias (potencial alto, dependência)
Senso de pertencimento e competição coletiva. "Meus quilômetros ajudam meu grupo." **Problema:** requer assessoria inscrita na liga + temporada ativa.

### RH6. Notificação de streak em risco
O sistema detecta se o streak está em risco e notifica às 18h. **Problema:** só funciona para quem já tem streak ≥ 3 dias. Não alcança novos usuários.

### RH7. Comparação com corrida anterior
O `_ComparisonRow` mostra delta de pace e distância vs. corrida anterior. Feedback de progresso tangível. **Problema:** requer 2+ corridas.

### Diagnóstico dos hooks:
**Todos os hooks de retenção estão atrás de barreiras de ativação.** O app tem hooks fortes, mas nenhum é ativável na primeira sessão. A jornada é: sobreviver ao deserto → chegar ao oásis. A maioria morre no deserto.

---

## 7. Recomendações para reduzir cada ponto de drop-off

### R1. Para o "Deserto de Valor" (DROP-OFF #5, severidade 5/5)
**Ação:** Importar histórico do Strava no momento da conexão (últimas 20-50 corridas)  
**Impacto:** Transforma o dashboard de "tudo vazio" para "olha o que você já fez" — badges retroativos, streak passado, Run Recap, DNA parcial, parques detectados  
**Esforço:** Médio (backfill já existe parcialmente)  
**Redução estimada de drop-off:** -50% neste ponto

### R2. Para a "Barreira do Strava" (DROP-OFF #6, severidade 5/5)
**Ação:** Implementar gravação GPS nativa mínima (sem relógio, apenas celular)  
**Impacto:** Remove a dependência absoluta do Strava. O atleta pode "experimentar" uma corrida direto no app  
**Esforço:** Alto  
**Alternativa:** Aceitar uploads manuais de GPX/TCX ou integrar Health Connect/Apple Health diretamente  
**Redução estimada de drop-off:** -30% neste ponto

### R3. Para o "Login obrigatório" (DROP-OFF #2, severidade 4/5)
**Ação:** Modo exploração sem login. Permitir ver o app com dados demo antes de criar conta  
**Impacto:** Reduz resistência inicial drasticamente  
**Esforço:** Médio  
**Redução estimada de drop-off:** -40% neste ponto

### R4. Para "Assessoria bloqueando features" (DROP-OFF #4+, severidade 3/5)
**Ação:** Remover bloqueios para atletas solo. Campeonatos podem ter divisão solo. Suporte acessível para todos. OmniCoins ganháveis por corridas independente de assessoria  
**Impacto:** O atleta solo se sente cidadão de primeira classe  
**Esforço:** Médio  
**Redução estimada de drop-off:** -25% no segmento solo

### R5. Para "Não corre em 3 dias" (DROP-OFF timeline dia 1)
**Ação:** Sequência de 5 notificações pós-instalação:  
- D0: "Bem-vindo! Conecte o Strava para desbloquear seu progresso"  
- D1: "Sua primeira corrida desbloqueia 50 OmniCoins + badge 'Primeira Corrida'"  
- D2: "X corredores perto de você correram hoje. Bora?"  
- D3: "Complete 3 corridas para ver seu perfil de corredor começar a se formar"  
- D7: "Desafie um amigo — crie seu primeiro 1v1!"  
**Impacto:** Reengajamento proativo nos dias críticos  
**Esforço:** Baixo  
**Redução estimada de drop-off:** -20% no D1-D7

### R6. Para telas vazias gerais
**Ação:** Substituir TODAS as telas vazias por previews visuais do que aparecerá com dados. Em vez de "Nenhum desafio ainda", mostrar um card mockup de desafio com overlay "Crie seu primeiro desafio". Em vez de "0 OmniCoins", mostrar a economia com exemplo visual.  
**Impacto:** O usuário entende o valor antes de experimentá-lo  
**Esforço:** Baixo-médio  
**Redução estimada de drop-off:** -15% geral

### R7. Para o gap Welcome → Login
**Ação:** Adicionar 3 slides de demo interativo ANTES do login:  
1. Running DNA demo (radar chart animado)  
2. Desafio demo (animação de competição)  
3. Liga/Parques demo (mapa com corredores)  
Botão: "Quero isso → Criar conta"  
**Impacto:** O usuário sabe EXATAMENTE o que ganha ao criar conta  
**Esforço:** Médio  
**Redução estimada de drop-off:** -30% no login

### R8. Para Running DNA inacessível
**Ação:** DNA Preview com 3 corridas (com disclaimer de confiança baixa). DNA completo com 10.  
**Impacto:** O AHA mais forte fica 3x mais acessível  
**Esforço:** Baixo  
**Redução estimada de drop-off:** Melhora retenção D30+ em ~15%

### R9. Para a confusão de assessoria no onboarding
**Ação:** Mover a tela de assessoria para DEPOIS da home. Permitir que o usuário descubra assessoria organicamente (via dashboard, desafios, liga). No onboarding, apenas: login → role → home.  
**Impacto:** Remove fricção e confusão do fluxo inicial  
**Esforço:** Baixo  
**Redução estimada de drop-off:** -10% no onboarding

### R10. Para a wallet vazia
**Ação:** Dar 100 OmniCoins de boas-vindas. Suficiente para 1 desafio de entry fee baixo. Cria primeiro loop de engajamento.  
**Impacto:** O usuário tem "algo" na wallet e um motivo para criar um desafio  
**Esforço:** Muito baixo  
**Redução estimada de drop-off:** -10% na wallet, +engagement em desafios

---

## Resumo Executivo

O Omni Runner perde aproximadamente **95-98% dos usuários cold market** entre a instalação e a retenção D7. O funil tem 3 pontos de destruição massiva:

1. **O deserto de valor pós-onboarding** (dashboard vazio, telas vazias, nada para fazer)
2. **A dependência absoluta do Strava** (sem Strava = app inútil)
3. **O gap temporal até o primeiro AHA** (horas a dias, não minutos)

O app foi desenhado para o **warm market** (atleta convidado por treinador, com Strava, com assessoria) e funciona bem para esse público. Mas para **cold market** (usuário orgânico da loja), a experiência é um deserto que pune a curiosidade.

A boa notícia: os hooks de retenção (streak, DNA, desafios, parques) são genuinamente fortes. O problema não é o produto — é o **tempo para chegar até ele**.
