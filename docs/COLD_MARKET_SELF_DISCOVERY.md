# COLD MARKET TEST — FASE 5: SELF-DISCOVERY (USO SEM TUTORIAL)

**App:** Omni Runner  
**Data:** 04/03/2026  
**Perspectiva:** Usuário que acabou de completar o onboarding, navegando SEM ajuda  

---

## 1. Mapa de Navegação

### Bottom Navigation (Atleta) — 4 tabs

```
┌─────────┬───────────┬────────────┬────────┐
│ Início  │   Hoje    │ Histórico  │  Mais  │
│ (idx 0) │ (idx 1)*  │  (idx 2)   │(idx 3) │
└────┬────┴─────┬─────┴──────┬─────┴───┬────┘
     │          │            │         │
     ▼          ▼            ▼         ▼
 Dashboard   TodayScreen  History   MoreScreen
```
*Tab padrão ao entrar no app

### Tab "Início" (AthleteDashboardScreen) — Grid de 7 cards

| Card | Destino | Descrição |
|------|---------|-----------|
| Meus desafios | ChallengesListScreen | Desafios 1v1, grupo e equipe |
| Minha assessoria / Entrar em assessoria | MyAssessoriaScreen / JoinAssessoriaScreen | Grupo de corrida |
| Meu progresso | ProgressHubScreen | Hub com todas as features de gamificação |
| Verificação | AthleteVerificationScreen | Status de atleta verificado |
| Campeonatos | AthleteChampionshipsScreen | Competições entre assessorias |
| Parques | MyParksScreen | Rankings e comunidade por parque |
| Meus créditos | WalletScreen | OmniCoins e histórico |

### Tab "Hoje" (TodayScreen) — Feed vertical

| Seção | Conteúdo |
|-------|----------|
| TipBanner (primeira vez) | Explica integração com Strava e relógios |
| Streak Banner | Dias consecutivos correndo, progresso ao próximo marco |
| Desafios Ativos | Cards dos desafios em andamento (se houver) |
| Campeonatos Ativos | Campeonatos em andamento (se houver) |
| Bora Correr / Conecte Strava | CTA para correr ou conectar Strava |
| Run Recap | Métricas da última corrida (distância, pace, duração, FC) |
| Park Check-in | Parque detectado na última corrida |
| Quick Stats | Nível, XP, corridas na semana, km total, corridas total |

### Tab "Histórico" (HistoryScreen) — Lista de corridas

| Conteúdo | Descrição |
|----------|-----------|
| Lista paginada | Últimas 30 corridas (Supabase + local), pull-to-refresh |
| Empty state | "Nenhuma corrida registrada" |
| Detalhes ao tocar | RunDetailsScreen com mapa, métricas e integridade |

### Tab "Mais" (MoreScreen) — Seções

| Seção | Itens |
|-------|-------|
| **Minha Assessoria** | Minha Assessoria, Escanear QR, Entregas Pendentes, Meu Treino do Dia |
| **Social** | Convidar amigos, Meus Amigos, Atividade dos amigos |
| **Conta** | Meu Perfil, Configurações, Diagnósticos |
| **Ajuda** | Suporte, Perguntas Frequentes, Sobre |
| **Logout** | Botão "Sair" com confirmação |

### ProgressHubScreen — Sub-navegação (lista de tiles)

| Seção | Itens |
|-------|-------|
| **Progresso** | Nível e XP, Minha Evolução, Meu DNA de Corredor, Minha Retrospectiva |
| **Competição** | Desafios, Campeonatos, Liga de Assessorias, Rankings |
| **Conquistas** | Badges, Missões, Sequências |
| **OmniCoins** | OmniCoins |
| **Comunidade** | Feed da Assessoria |

---

## 2. Cada Área é Auto-Explicativa?

### Tab "Hoje" — SIM
- **Por quê:** O feed é visual e cronológico. O streak banner é imediatamente compreensível (dias correndo, próximo marco). O CTA "Bora correr?" ou "Conecte Strava" diz exatamente o que fazer. O Run Recap mostra métricas claras (distância, pace, duração). Sem estado vazio confuso.
- **Ressalva:** Se o Strava não estiver conectado, o card explicativo é extenso mas claro — "funciona com qualquer relógio (Garmin, Coros, Apple Watch)".

### Tab "Início" (Dashboard) — SIM, parcialmente
- **Por quê:** Grid de cards com ícones, títulos e subtítulos descritivos. "Meus desafios — Competir e acompanhar", "Meu progresso — XP, badges e missões". Intuitivo para explorar.
- **Ressalva:** Card "Verificação" sem contexto. Um usuário novo não sabe o que é "Status de atleta verificado" ou por que deveria se verificar. O card "Parques — Rankings e comunidade" também pode confundir quem nunca ouviu falar da feature.
- **Ponto positivo:** TipBanner de boas-vindas com 4 primeiros passos. Card de assessoria mostra "Toque para encontrar" quando vazio.

### Tab "Histórico" — SIM
- **Por quê:** Lista simples de corridas com data, distância, pace. Empty state com mensagem clara. Puxar para atualizar. Zero confusão.

### Tab "Mais" — SIM
- **Por quê:** Seções organizadas por categoria (Assessoria, Social, Conta, Ajuda). Cada item tem título + subtítulo descritivo. Estrutura de menu familiar. "Meu Perfil — Ver e editar seu perfil" é auto-explicativo.

### WalletScreen (Créditos/OmniCoins) — PARCIALMENTE
- **Por quê:** O card de saldo é claro (Total, Disponível, Pendente, Ganhos, Gastos). O histórico de movimentações é compreensível. O ContextualTipBanner explica na primeira visita: "OmniCoins são moedas virtuais que você ganha ao completar desafios e treinos."
- **Ressalva:** O FAB "Escanear QR" sem contexto. O que acontece ao escanear um QR? De onde vem esse QR? Empty state ajuda: "Peça ao professor da sua assessoria para distribuir OmniCoins."

### ChallengesListScreen (Desafios) — SIM
- **Por quê:** Empty state claro: "Nenhum desafio ainda — Crie um desafio e convide corredores para competir com você!" com dois CTAs ("Encontrar Oponente" e "Criar e convidar"). TipBanners explicam matchmaking e criação.
- **Ponto positivo:** Se Strava não conectado, banner explica que precisa conectar para participar.

### ProgressHubScreen — SIM
- **Por quê:** Lista organizada em seções (Progresso, Competição, Conquistas, OmniCoins, Comunidade). Cada item tem ícone + título + subtítulo descritivo. Funciona como sumário do app.

### Running DNA — PARCIALMENTE
- **Por quê:** Se tem dados, é visualmente impressionante (radar chart 6 eixos + insights + previsões de PR). Se não tem dados, mostra: "Continue correndo! Precisamos de pelo menos 10 corridas verificadas nos últimos 6 meses."
- **Ressalva:** Termos como "Versatilidade" e "Competitividade" no radar não são imediatamente claros. O que significa ter 45 de "Evolução"?

### Wrapped (Retrospectiva) — SIM
- **Por quê:** Stories-style com slides swipáveis. Números em destaque, gráficos de pace, desafios, badges, curiosidades. Formato familiar (Spotify Wrapped). Compartilhamento integrado.
- **Ressalva:** Se dados insuficientes, mostra estado claro: "Precisamos de pelo menos 3 corridas verificadas nesse período."

### League (Liga de Assessorias) — SIM
- **Por quê:** Ranking com medalhas (top 3), score, nome, cidade. Card "Como funciona" explica a fórmula. Filtros (Global/Meu Estado). Contribution card personalizado.
- **Ressalva:** Sem assessoria, o usuário vê ranking mas sem contexto pessoal.

### Profile (Perfil) — SIM
- **Por quê:** Avatar editável, nome, email, redes sociais. Campo de texto simples. Salvar, sair, excluir conta. Formulário direto.

### Settings (Configurações) — SIM
- **Por quê:** Seções claras: Integrações (Strava), Aparência (tema), Unidades, Privacidade, Ajuda. Toggle para imperial vs métrico. Texto explicativo em cada seção.

### FAQ — SIM
- **Por quê:** 5 perguntas comuns em formato expandível. Respostas curtas e diretas. Sem fricção.

### Support (Suporte) — PARCIALMENTE
- **Por quê:** Requer assessoria para acessar. Se o usuário não está em assessoria, recebe: "Você precisa estar em uma assessoria para acessar o suporte." Isso é um dead-end para usuários sem assessoria.

---

## 3. Dead-Ends Encontrados

| # | Localização | Descrição | Severidade |
|---|-------------|-----------|------------|
| 1 | **Suporte sem assessoria** | "Você precisa estar em uma assessoria para acessar o suporte." Usuário sem assessoria não tem canal de suporte. | ALTA |
| 2 | **Campeonatos sem assessoria** | `AssessoriaRequiredSheet.guard` bloqueia acesso. Sem caminho alternativo. | MÉDIA |
| 3 | **Treino do Dia sem assessoria** | "Você não está em nenhuma assessoria." — sem alternativa, sem link para entrar em assessoria. | MÉDIA |
| 4 | **Entregas Pendentes sem contexto** | Usuário sem assessoria ou sem treinos enviados ao relógio não sabe o que esta tela faz. | BAIXA |
| 5 | **Running DNA com < 10 corridas** | Mostra "Continue correndo!" mas não indica progresso (quantas das 10 já fez). | BAIXA |
| 6 | **Wrapped com < 3 corridas** | Idem — sem indicação de progresso ao limiar. | BAIXA |

---

## 4. Pontos de Confusão

| # | Ponto | Descrição |
|---|-------|-----------|
| 1 | **"Verificação"** | Card no dashboard sem explicação prévia. O que é "Atleta Verificado"? Por que devo me verificar? Onde está o benefício? O tour menciona (slide 9), mas quem pulou o tour está perdido. |
| 2 | **"OmniCoins" sem moedas** | Empty state diz "Peça ao professor da sua assessoria para distribuir OmniCoins" — mas se o usuário não está em assessoria, como consegue OmniCoins? Corridas e desafios também dão moedas, mas isso não fica claro aqui. |
| 3 | **QR Scanner no Wallet** | FAB "Escanear QR" na WalletScreen. Escanear o quê? De quem? Para quê? Sem tooltip ou explicação. |
| 4 | **"Entregas Pendentes"** | Título vago. Entrega de quê? Para quem? Subtítulo ajuda ("Confirmar treinos enviados ao relógio") mas é jargão técnico. |
| 5 | **Assessoria vs Amigos** | Dois conceitos sociais distintos (assessoria = grupo com coach, amigos = rede pessoal). A diferença não é óbvia para um novo usuário. |
| 6 | **"Parques"** | Feature nova e inesperada. O card "Rankings e comunidade" não explica que funciona por GPS/detecção automática. |
| 7 | **Pending Request Banner** | Dashboard mostra "Solicitação pendente — aguardando aprovação da assessoria" mas não explica o que o usuário pode fazer enquanto espera. O texto "Você será notificado quando a assessoria aprovar" ajuda parcialmente. |

---

## 5. O produto é auto-explicativo?

**SIM, com ressalvas.** O Omni Runner é surpreendentemente navegável sem tutorial para as features CORE (correr, ver métricas, histórico, streak). A navegação por tabs é familiar, os cards do dashboard têm títulos descritivos, e os empty states geralmente orientam o próximo passo.

**Onde falha:** Features avançadas (Verificação, OmniCoins, DNA, Liga) dependem de contexto que o usuário não tem. O app assume familiaridade com o ecossistema de assessorias de corrida brasileiras. Um corredor casual que baixou o app por curiosidade pode se sentir perdido no vocabulário (assessoria, staff, OmniCoins, verificação, desafio 1v1 com pool).

**Veredicto:** Para o público-alvo (corredor brasileiro em assessoria), é auto-explicativo. Para público geral (corredor casual), precisa de mais onboarding contextual nas features avançadas.

---

## 6. O usuário sabe o que fazer?

**SIM, nos primeiros 5 minutos.** O TipBanner do dashboard lista 4 passos claros:
1. Conecte seu Strava e faça sua primeira corrida
2. Entre em uma assessoria (peça o código ao professor)
3. Crie ou encontre um desafio para competir
4. Complete corridas para se tornar Atleta Verificado

**Depois dos primeiros 5 minutos:** Depende. Se o Strava está conectado e corridas importadas, o app fica rico em dados e a navegação faz sentido. Se o Strava NÃO está conectado, a tela "Hoje" mostra um CTA enorme para conectar — fica claro, mas a experiência é vazia.

**Problema:** A sequência de valor não é guiada. O app diz "faça estas 4 coisas" mas não conduz o usuário por elas em ordem. Não há checklist interativo, progress bar de setup, ou nudges sequenciais. Tudo depende da leitura (e memória) do TipBanner.

---

## 7. Features que Precisam Explicação vs Features Intuitivas

### Intuitivas (funcionam sem explicação)

| Feature | Por quê |
|---------|---------|
| Streak (sequência) | Formato "🔥 X dias seguidos" é universalmente compreendido |
| Histórico de corridas | Lista cronológica com métricas, padrão de app fitness |
| Perfil | Avatar + nome + email, padrão de todo app |
| Configurações (tema, unidades) | Toggles e rádios familiares |
| FAQ | Formato expansível de perguntas, universalmente compreendido |
| Compartilhar corrida | Botão "Compartilhar" com card visual |
| Diário de corrida | Bottom sheet com campo de texto e emojis de humor |

### Precisam de Explicação

| Feature | O que falta |
|---------|-------------|
| **Verificação de Atleta** | O que é, por que importa, como se verifica, quais os benefícios |
| **OmniCoins** | De onde vêm, para que servem, como ganhar sem assessoria |
| **Desafios com pool** | O que é entry fee, como funciona o pool, risco de perder moedas |
| **DNA de Corredor** | O que cada eixo do radar significa, como melhorar cada um |
| **Liga de Assessorias** | Como a pontuação é calculada, como contribuir para o ranking |
| **Campeonatos** | Diferença entre campeonato e desafio, quem organiza, como participar |
| **Matchmaking** | Como funciona o pareamento, o que "nível compatível" significa |
| **Parques** | Como a detecção funciona, o que é "Rei do Parque", como ativar |
| **Entregas Pendentes** | O que são, quando aparecem, como usar |
| **QR Scanner** | Para quê serve, em que contexto usar |

---

## 8. Ratings

| Critério | Nota (0-10) | Justificativa |
|----------|-------------|---------------|
| **Auto-explicativo** | 6/10 | Core features (correr, streak, histórico) são claras. Features avançadas (Verificação, OmniCoins, DNA, Liga) precisam de contexto que não existe in-app. |
| **Clareza de navegação** | 8/10 | 4 tabs claros, dashboard com grid de cards, MoreScreen bem organizado por seções. ProgressHub funciona como sumário. Nenhuma rota confusa. |
| **Descobribilidade de features** | 7/10 | Dashboard expõe 7 features principais. ProgressHub lista 13 sub-features. Tab "Mais" organiza tudo. Porém: algumas features estão aninhadas 2-3 níveis (Mais → Assessoria → Treino do Dia) e podem ser ignoradas. |

---

## Resumo Executivo

O Omni Runner é um app **surpreendentemente bem organizado** para a quantidade de features que oferece. A navegação por tabs é limpa, o dashboard funciona como ponto de partida visual, e a maioria das telas tem empty states úteis que orientam o próximo passo.

**Pontos fortes:**
- Tab "Hoje" é o melhor ponto de entrada — mostra streak, desafios ativos, última corrida, e stats. Tudo contextual e atualizado.
- TipBanners contextuais (primeira visita) em múltiplas telas reduzem a necessidade de tutorial formal.
- Empty states acionáveis ("Crie um desafio e convide corredores", "Peça o código ao professor").
- Comparação automática com corrida anterior no Run Recap.
- Strava como fonte de dados remove a necessidade de GPS in-app para a maioria dos usuários.

**Pontos fracos:**
- Dead-end de suporte para usuários sem assessoria (ALTA prioridade).
- Features avançadas (Verificação, DNA, Liga) assumem conhecimento prévio.
- Ausência de checklist interativo de primeiros passos (depende de um TipBanner de texto).
- QR Scanner e Entregas são expostos sem contexto suficiente.
- Vocabulário do ecossistema (assessoria, staff, pool, OmniCoins) não é universalmente compreendido.

**Veredicto final:** O app é **navegável e descobrível** para seu público-alvo (corredor brasileiro em assessoria). Para expansão de mercado (corredor casual/internacional), precisaria de mais onboarding contextual e glossário integrado.
