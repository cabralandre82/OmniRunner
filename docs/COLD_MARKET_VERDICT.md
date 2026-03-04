# Cold Market Test — Fase 9: Veredito de Mercado

**Produto:** Omni Runner  
**Data:** 04/03/2026  
**Perspectiva:** Usuário frio, zero contexto prévio  
**Baseado em:** Fases 1-8 do Cold Market Test completo

---

## 1. Eu instalaria?

### SIM — com ressalvas.

**Justificativa:** Se eu encontrasse o Omni Runner na loja (Play Store/App Store), as screenshots e descrição provavelmente seriam atraentes o suficiente para eu baixar — é gratuito, promete desafios, gamificação, e tem visual polido. O custo de experimentar é zero (exceto espaço no celular).

**Porém:** O nome "Omni Runner" não comunica nada de diferenciador. Parece genérico. Eu precisaria de um dos seguintes gatilhos para instalar:
- Um amigo/treinador recomendou (warm market)
- Vi alguém compartilhar o card do Running DNA no Instagram (viralidade visual)
- Vi um anúncio que mostrava o radar chart ou desafios com coins (paid acquisition)

**Cold market puro (busca orgânica "app de corrida")?** A chance de eu instalar é baixa. Strava, Nike Run Club e Garmin Connect dominam esse espaço de busca. O Omni Runner precisaria de ASO (App Store Optimization) excepcional ou um hook visual muito forte na listagem.

---

## 2. Eu continuaria usando?

### Como usuário orgânico (cold market): NÃO.

**Justificativa:** Nos primeiros 5 minutos, eu enfrentaria:
1. Login obrigatório sem preview do app
2. Onboarding com conceito de "assessoria" que não conheço
3. Dashboard completamente vazio
4. Pedido para conectar o Strava (outro app que talvez eu não tenha)
5. Nenhuma funcionalidade utilizável imediatamente

Sem um motivo forte para voltar e sem nenhum valor entregue na primeira sessão, eu provavelmente esqueceria o app. Não desinstalaria imediatamente, mas em 7 dias, quando o celular sugerisse "apps não usados", eu confirmaria a remoção.

**Condição para mudar essa resposta:** Se ao conectar o Strava, meu histórico fosse importado e eu imediatamente visse meu Running DNA, badges retroativos, e um desafio sugerido — aí sim, eu ficaria.

### Como usuário convidado (warm market): SIM, provavelmente.

**Justificativa:** Se meu treinador mandou instalar e está organizando desafios dentro da assessoria, a motivação externa sustenta o uso. O app funciona bem como extensão da experiência de uma assessoria de corrida. O problema de cold start desaparece quando:
- Alguém me diz o código da assessoria
- O treinador distribui OmniCoins
- Há desafios em grupo criados pelo coach
- A liga dá propósito coletivo às corridas

**O app é um produto B2B disfarçado de B2C.** Funciona para o atleta que chega via assessoria; falha para o atleta que chega sozinho.

---

## 3. Eu recomendaria?

### SIM — mas apenas para um público específico.

**Para quem eu recomendaria:**
- Treinadores de corrida que buscam engajar seus alunos com gamificação
- Assessorias de corrida que querem um app white-label sem custo
- Corredores que já usam Strava e fazem parte de um grupo de corrida
- Corredores competitivos que querem apostar com amigos

**Para quem eu NÃO recomendaria:**
- Iniciantes que estão começando a correr (barreira de Strava + verificação)
- Corredores solo sem interesse em grupos (metade das features bloqueadas)
- Quem não tem Strava (o app é inutilizável)
- Quem busca um app GPS tracker simples (o app não grava corridas)

---

## 4. Ratings (0-10)

### Clareza — O usuário entende o que o app faz?
**Nota: 4/10**

A welcome screen diz "Seu app de corrida completo" com bullets genéricos. Isso é insuficiente para comunicar o diferencial. O usuário NÃO entende:
- Que o app depende do Strava (não grava corridas sozinho)
- Que assessoria é o modelo de uso principal
- Que desafios com OmniCoins são o core loop
- Que features avançadas (DNA, Liga, Wrapped) existem

O que o app **É** (plataforma de gamificação de corrida para assessorias) e o que o app **PARECE SER** (mais um app de corrida) são coisas diferentes. A comunicação é genérica demais.

### Valor percebido — O usuário vê por que deveria usar?
**Nota: 3/10**

Nos primeiros 5 minutos, o valor percebido é próximo de zero. Toda tela mostra "faça X para ver algo". O usuário não experiencia nenhum valor — apenas recebe promessas textuais. O TipBanner com "Primeiros passos" é informacional mas não emocional.

O valor real do produto é alto (Running DNA, Desafios com coins, Ghost Racing, Streaks), mas está completamente invisível para o usuário frio. É como um restaurante incrível sem vitrine — quem entra ama, mas quase ninguém entra.

### Facilidade de começar — O usuário consegue começar sem fricção?
**Nota: 3/10**

O onboarding tem 6 passos obrigatórios (Welcome → Login → Role → Confirmação → Assessoria → Home), cada um com carga cognitiva. Depois do onboarding, há mais passos necessários (conectar Strava, fazer uma corrida, esperar sync). O time-to-value é de horas a dias, não minutos.

Para comparação:
- **Strava:** Instalar → Login → Gravar corrida → Ver resultado = 10 minutos
- **Nike Run Club:** Instalar → Guided Run → Correr → Resultado = 15 minutos
- **Omni Runner:** Instalar → Login → Onboarding → Conectar Strava → Correr fora → Voltar = horas

### Confiança — O app parece confiável e polido?
**Nota: 7/10**

Este é o ponto forte. O app tem:
- Design system consistente (`DesignTokens`)
- Animações suaves (stagger, fade-in, shimmer loading)
- Tratamento de erros completo (sem crashes, mensagens claras)
- Dark mode funcional
- Acessibilidade (Semantics labels)
- Texto em português natural, sem erros
- UX defensiva (confirmações antes de ações destrutivas)
- Privacy policy linkada

O app PARECE profissional e bem feito. Não passa sensação de "app indie incompleto". Se o conteúdo fosse preenchido, a confiança seria 9/10.

### Retenção provável — O usuário volta amanhã?
**Nota: 2/10 (cold market) | 6/10 (warm market)**

**Cold market:** Sem notificação de reengajamento, sem conteúdo para consumir passivamente, sem razão para voltar. O app não cria urgência nem curiosidade após a primeira sessão vazia.

**Warm market:** Se o treinador está ativo, há feed da assessoria, desafios em andamento, e pressão social. O sistema de streaks cria urgência a partir da segunda corrida consecutiva.

---

## 5. Análise de Posicionamento de Mercado

### Em que mercado o Omni Runner compete?

O Omni Runner compete em 3 mercados sobrepostos:

1. **Apps de corrida para consumidores** (Strava, Nike Run Club, Garmin Connect, adidas Running)
2. **Plataformas de gamificação fitness** (Challenges, leaderboards, virtual coins)
3. **Ferramentas B2B para treinadores** (gestão de grupos, acompanhamento de atletas)

O problema: o app tenta ser os três ao mesmo tempo, sem ser referência em nenhum para o mercado cold.

### Quem são os concorrentes?

| Concorrente | Público | Diferencial | Strava necessário? |
|---|---|---|---|
| **Strava** | Mainstream | GPS + Social + Segments + Clubs | Ele É o Strava |
| **Nike Run Club** | Iniciantes | Guided Runs + Coaching grátis | Não |
| **Garmin Connect** | Hardware | Profundidade de dados + relógio | Não (usa Garmin) |
| **adidas Running** | Casual | Planos de treino + GPS | Não |
| **Peloton** | Premium | Aulas guiadas + community | Não |
| **Runna** | Treino | Planos de treino personalizados | Não |
| **Omni Runner** | Assessorias | Desafios + Coins + DNA + Liga | **SIM (obrigatório)** |

### Qual é o diferenciador único?

O Omni Runner tem 4 diferenciais genuínos que nenhum concorrente mainstream oferece:

1. **Running DNA** — Perfil radar de 6 eixos com insights + previsão de PR. Nenhum concorrente faz isso gratuitamente.
2. **Desafios com OmniCoins** — Apostas virtuais em corridas 1v1 ou grupo. Gamificação com skin in the game.
3. **Liga de Assessorias** — Ranking coletivo de grupos de corrida. Transforma corrida individual em esporte coletivo.
4. **Anti-cheat com verificação** — GPS + frequência cardíaca para garantir competições justas.

### O diferenciador é visível nos primeiros 5 minutos?

**NÃO.** Nenhum dos 4 diferenciais é demonstrado, mostrado em preview, ou sequer mencionado nos primeiros 5 minutos. O Running DNA precisa de 10 corridas. Desafios precisam de coins e oponente. Liga precisa de assessoria. Verificação precisa de 7 corridas.

A welcome screen menciona apenas conceitos genéricos ("desafios", "evolução"). As features que tornam o Omni Runner ÚNICO estão escondidas atrás de semanas de uso.

**Isso é o equivalente a uma Ferrari estacionada numa garagem trancada. O carro é incrível, mas ninguém sabe que ele está lá.**

---

## 6. Análise de Modelo de Crescimento

### Pode crescer organicamente (cold installs)?

**NÃO na implementação atual.** Razões:
- ASO fraco (nome genérico, proposta genérica)
- Time-to-value de horas/dias mata retenção D1
- Sem loop de viralidade no onboarding
- Diferenciais invisíveis na primeira sessão
- Sem conteúdo para SEO/discovery

**Condição para mudar:** Importar histórico do Strava + preview de DNA na instalação + permitir gravação nativa. Isso transformaria a primeira sessão de "deserto" para "revelação".

### Pode crescer via referral?

**SIM, com limitações.** O app tem:
- Botão "Convidar amigos" com link de convite
- Deep links para assessoria (QR code, código)
- Cards compartilháveis (Running DNA, Run Recap, Wrapped)

**Mas:** O referral só funciona se o amigo convidado:
1. Tem Strava
2. Corre regularmente
3. Aceita criar conta num app novo
4. Está disposto a esperar dias para ver valor

O card do Running DNA compartilhado no Instagram/TikTok é o melhor vetor de viralidade — visualmente impactante e gera curiosidade ("quero ver o meu!"). Mas gera frustração quando o novo usuário descobre que precisa de 10 corridas para ver o dele.

### Pode crescer via B2B (assessorias)?

**SIM — este é o modelo natural.** Razões:
- O Portal Next.js existe exclusivamente para coaches
- O onboarding tem fluxo específico para "ASSESSORIA_STAFF"
- O sistema de convites (QR, código, deep link) é robusto
- Liga de Assessorias cria competição entre grupos
- Campeonatos são exclusivos para assessorias
- OmniCoins distribuídos pelo coach criando economia interna

**O B2B resolve o cold start automaticamente:** o coach configura o grupo, distribui coins, cria desafios, e quando o atleta entra via convite, já tem assessoria, coins, e desafios esperando. O app faz sentido imediato.

### Qual modelo de crescimento funciona melhor?

**B2B (assessoria-led growth) é o único modelo viável no estado atual.**

Funil ideal:
```
COACH descobre o Portal → COACH cria assessoria → COACH convida atletas →
ATLETAS entram com código → COACH cria desafios → ATLETAS correm →
ATLETAS convidam amigos → AMIGOS entram na assessoria → CRESCIMENTO ORGÂNICO
```

O crescimento é coach → atleta → atleta. Não é loja → atleta. O produto é um **SaaS para treinadores** que se manifesta como **app para atletas**.

---

## 7. Veredito Final

O Omni Runner é um **produto excelente preso dentro de uma experiência de primeiro uso terrível**. As features de diferenciação — Running DNA, Desafios com OmniCoins, Liga de Assessorias, Ghost Racing, Wrapped — são genuinamente inovadoras e representam uma visão de produto sofisticada que vai além de qualquer app de corrida mainstream. A qualidade técnica é alta: o código é limpo, o design system é consistente, o tratamento de erros é maduro, e a arquitetura (Flutter + Supabase + Edge Functions) é moderna e escalável.

Porém, para o mercado frio, o app é **um container vazio que exige fé**. O usuário precisa acreditar que "depois de conectar Strava, correr 10 vezes, entrar numa assessoria, e esperar semanas, o app será incrível". Nenhum produto consumer sobrevive pedindo essa quantidade de fé no cold market. A taxa de conversão estimada de instalação → retenção D7 é de 1-2% para cold installs, o que é insustentável para growth orgânico.

**O diagnóstico central é claro: o Omni Runner é um produto B2B que está tentando ser descoberto como B2C.** O modelo de distribuição deveria ser coach-first, não consumer-first. O Portal já existe. O sistema de convites já funciona. A oportunidade real é conquistar assessorias de corrida que levam o app aos atletas — não convencer atletas individuais a adotar mais um app.

**O app está pronto para escalar via assessorias. Não está pronto para cold market.**

---

## 8. Top 10 Mudanças para Melhorar Conversão Cold Market

*(Ordenadas por impacto estimado)*

### 1. 🔴 Importar histórico completo do Strava na conexão
**Impacto: Transformacional**  
Ao conectar Strava, importar as últimas 30-50 corridas. Gerar instantaneamente: Run Recap da última corrida, badges retroativos, streak histórico, DNA parcial (se ≥3 corridas), evolução de pace, parques detectados. O dashboard passa de "vazio" para "cheio de dados pessoais" em 60 segundos.

**Resultado:** O primeiro AHA muda de "horas-dias" para "5 minutos".

### 2. 🔴 Running DNA Preview com 3 corridas
**Impacto: Alto**  
Gerar um DNA "beta" com confiança baixa a partir de 3 corridas. Mostrar radar chart com disclaimer "Perfil preliminar — complete 10 corridas para DNA completo". O AHA mais poderoso fica acessível 3x mais rápido. Inclui call-to-action para compartilhar mesmo no estado beta.

**Resultado:** O diferenciador mais forte vira acessível na primeira semana.

### 3. 🔴 Modo exploração sem login obrigatório
**Impacto: Alto**  
Permitir que o usuário navegue o app com dados demo antes de criar conta. Mostrar: dashboard populado com dados fictícios, DNA de exemplo, desafio simulado, liga com ranking real. Botão "Criar conta para ver MEUS dados" em cada tela.

**Resultado:** O usuário entende o valor ANTES de investir tempo no login.

### 4. 🟡 Onboarding visual com demonstração do DNA e Desafios
**Impacto: Alto**  
Adicionar 3 slides antes do login mostrando features únicas com animação: radar chart do DNA girando, desafio 1v1 com coins, liga com ranking. Texto: "Descubra seu perfil de corredor", "Aposte corridas com amigos", "Represente seu grupo".

**Resultado:** O usuário sabe exatamente o que ganha ao criar conta.

### 5. 🟡 Gravação GPS nativa (sem Strava)
**Impacto: Alto**  
Implementar gravação básica de corrida via GPS do celular. Não precisa competir com Strava em precisão — apenas permitir que o usuário "teste" o app sem outro serviço. Corridas nativas contam para badges, streaks e DNA como corridas "não verificadas".

**Resultado:** Remove a dependência absoluta do Strava, abrindo mercado para corredores casuais.

### 6. 🟡 100 OmniCoins de boas-vindas
**Impacto: Médio**  
Dar 100 coins grátis ao completar o onboarding. Suficiente para entrar em 1 desafio de entrada baixa. Cria primeiro ciclo da economia de jogo e motivo para explorar desafios.

**Resultado:** A wallet não começa vazia. O usuário tem "dinheiro para jogar".

### 7. 🟡 Substituir TODAS as telas vazias por previews
**Impacto: Médio**  
Em vez de "Nenhum desafio ainda", mostrar mockup visual de como um desafio aparece, com overlay "Crie seu primeiro". Em vez de "Sem sequência ativa", mostrar como o streak banner fica com 7 dias (visual aspiracional). Cada tela vazia deveria mostrar o DESTINO, não o VAZIO.

**Resultado:** O usuário vê o que está por vir em vez de sentir que não tem nada.

### 8. 🟢 Sequência de 5 notificações push pós-instalação
**Impacto: Médio**  
D0: "Conecte Strava para desbloquear seu perfil", D1: "Sua primeira corrida vale 50 coins!", D2: "X corredores perto de você estão correndo", D3: "Complete 3 corridas para ver seu DNA começar", D7: "Desafie um amigo — primeiro desafio é grátis!".

**Resultado:** Reengajamento proativo nos 7 dias críticos.

### 9. 🟢 Remover assessoria do onboarding obrigatório
**Impacto: Médio-baixo**  
Mover JoinAssessoriaScreen para depois da home. Colocar como card no dashboard com CTA contextual. No onboarding: Welcome → Login → Role → Home (3 passos, não 5).

**Resultado:** Onboarding 40% mais curto. Menos fricção e confusão.

### 10. 🟢 Desbloquear features solo (campeonatos, suporte)
**Impacto: Médio-baixo**  
Campeonatos solo (ranking individual sem assessoria). Suporte acessível para todos (não só quem tem assessoria). OmniCoins ganháveis por corridas verificadas (não só por assessoria).

**Resultado:** O atleta solo não se sente cidadão de segunda classe.

---

## Tabela Resumo de Ratings

| Dimensão | Nota | Resumo |
|---|---|---|
| **Clareza** | 4/10 | O app não comunica seu diferencial. Parece genérico. |
| **Valor percebido** | 3/10 | Zero valor nos primeiros 5 min. Tudo são promessas. |
| **Facilidade de começar** | 3/10 | 6 passos de onboarding + Strava + correr = horas. |
| **Confiança** | 7/10 | Visual polido, erros tratados, dark mode, texto natural. |
| **Retenção provável** | 2/10 (cold) / 6/10 (warm) | Sem hook de retenção na primeira sessão. |
| **Média cold market** | **3.8/10** | — |
| **Média warm market** | **5.8/10** | — |

---

## Conclusão em uma frase

> O Omni Runner é um produto A+ com uma experiência de primeiro uso D-: features de classe mundial presas atrás de semanas de uso, em um app que depende de outro app (Strava), e que só faz sentido quando alguém de fora (coach) configura o ecossistema para o atleta entrar.
