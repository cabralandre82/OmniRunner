# First-Contact Test — Exploração Livre (5 minutos)

**Data:** 2026-03-04
**Testador:** Usuário simulado, completamente novo.

---

## APP — Fluxo do Atleta

---

### 1. Welcome Screen

**O que vi:** Tela com ícone de corredor, nome "Omni Runner", quatro bullets descrevendo funcionalidades ("Desafie corredores", "Treine com sua assessoria", "Participe de campeonatos", "Evolua com métricas reais") e um botão "COMEÇAR" na parte inferior. Animações suaves de fade e slide.

**O que esperava:** Uma tela de boas-vindas com explicação clara do que o app faz, talvez com imagens de pessoas correndo ou screenshots do app.

**O que aconteceu:** Entendi o propósito geral (corrida + competição + grupos), mas o termo "assessoria" não foi explicado. O botão "COMEÇAR" é claro — vou tocar nele.

**Veredicto:** 🟢 AÇÃO CLARA

**Evidência:** `welcome_screen.dart:87-93` — `'Omni Runner'`; linhas 106-123 — bullets com ícones; linha 146 — `'COMEÇAR'`

---

### 2. Login Screen

**O que vi:** Ícone de corredor menor (72px), título **"Entrar no Omni Runner"**, subtexto **"Use sua conta para sincronizar treinos, desafios e progresso entre dispositivos."** Quatro opções de login:
- "Continuar com Google" (botão outlined, ícone `g_mobiledata_rounded`)
- "Continuar com Apple" (botão filled preto, só aparece no iOS)
- "Continuar com Instagram" (botão outlined, gradiente rosa/roxo)
- "Continuar com Email" (botão outlined cinza, expande formulário)

O formulário de email tem campos Email e Senha, botões "Entrar"/"Criar conta", link "Não tem conta? Criar agora" e "Esqueci a senha". No rodapé: **"Ao continuar, você concorda com nossa Política de Privacidade"** (link para omnirunner.com.br/privacidade).

Se houver um invite pendente, aparece um banner: **"Você recebeu um convite! Faça login para entrar na assessoria."**

**O que esperava:** Tela de login padrão com Google/Apple e email. Instagram é incomum — inesperado mas faz sentido para público fitness brasileiro.

**O que aconteceu:** Opções claras. Bom ter Instagram como opção (público-alvo usa muito). O subtexto "sincronizar treinos, desafios e progresso entre dispositivos" finalmente explica algo sobre o que o app faz. Porém, preciso criar conta antes de ver QUALQUER conteúdo do app — não há modo "explorar sem conta" visível aqui.

**Veredicto:** 🟢 AÇÃO CLARA

**Evidência:** `login_screen.dart:198` — `'Entrar no Omni Runner'`; linhas 205-209 — subtexto sobre sincronização; linha 319 — `'Continuar com Instagram'`; linha 355 — `'Continuar com Email'`; linhas 467-482 — política de privacidade

---

### 3. Onboarding Role Screen

**O que vi:** Título: **"Como você quer usar o Omni Runner?"**. Subtexto em vermelho (cor de erro): **"Essa escolha é permanente e define toda a sua experiência no app."**

Dois cards com radio button:
1. **"Sou atleta"** — subtexto: "Treinar, competir em desafios e acompanhar minha evolução"
2. **"Represento uma assessoria"** — subtexto: "Gerenciar atletas, organizar eventos e acompanhar o grupo"

Botão "Continuar" (desabilitado até selecionar). Ao tocar "Continuar", aparece um dialog de confirmação com **aviso em vermelho**: "Essa escolha é permanente e não pode ser alterada depois. Se precisar trocar, entre em contato com o suporte."

**O que esperava:** Talvez uma tela perguntando meu nome, foto, nível de experiência — o básico de onboarding. Não esperava uma **decisão irreversível** logo no segundo passo.

**O que aconteceu:** PÂNICO. Acabei de criar minha conta e a SEGUNDA tela me pede uma decisão PERMANENTE? Isso é extremamente agressivo. A maioria dos usuários não sabe a diferença entre os papéis ainda. O aviso em vermelho com "permanente" e "não pode ser alterada" é assustador. Muitos vão desistir aqui ou se sentir pressionados.

**Veredicto:** 🔴 CONFUSÃO

**Evidência:** `onboarding_role_screen.dart:167-168` — `'Como você quer usar\no Omni Runner?'`; linhas 176-180 — subtexto em `theme.colorScheme.error`; linhas 188-190 — `'Sou atleta'`; linhas 195-199 — `'Represento uma assessoria'`; linhas 69-70 — `'Essa escolha é permanente e não pode ser alterada depois.'`

---

### 4. Join Assessoria Screen (após escolher "Atleta")

**O que vi:** Título: **"Encontre sua assessoria"**. Subtexto: **"Busque pelo nome, escaneie um QR ou use um código."**

Elementos na tela:
- Campo de busca com placeholder **"Buscar assessoria..."** e ícone de QR scanner no canto
- Botão de texto: **"Tenho um código"** (abre dialog para colar UUID)
- Área central com ícone groups e texto **"Digite o nome da assessoria para buscar"**
- Seção de convites pendentes (se existirem) com botão **"Aceitar"**
- Na parte inferior: **"Pular — posso entrar depois"** (TextButton)
- Micro-texto: **"Você pode usar o app normalmente. Assessoria desbloqueia ranking de grupo e desafios em equipe."**

Ao solicitar entrada em uma assessoria, aparece dialog: **"Solicitar entrada?"** com texto explicando que a assessoria precisa aprovar.

**O que esperava:** Algo me guiando para o primeiro uso — talvez "faça sua primeira corrida" ou "conecte seu Strava". Não esperava ser OBRIGADO a encontrar um grupo antes de usar o app.

**O que aconteceu:** Pelo menos posso pular ("Pular — posso entrar depois"), mas a tela inteira é dedicada a um conceito que eu, como novo usuário, talvez nem conheça ainda. O placeholder diz "Buscar assessoria..." — mas e se eu não tenho assessoria? O botão de pular é um TextButton discreto no final — deveria ser mais proeminente. O micro-texto no final é CRUCIAL ("Você pode usar o app normalmente") mas quase invisível.

**Veredicto:** 🟡 AMBIGUIDADE

**Evidência:** `join_assessoria_screen.dart:621-622` — `'Encontre sua\nassessoria'`; linha 630 — `'Busque pelo nome, escaneie um QR ou use um código.'`; linha 644 — `'Buscar assessoria...'`; linha 711 — `'Pular — posso entrar depois'`; linhas 716-718 — micro-texto sobre uso normal

---

### 5. Home Screen (após onboarding)

**O que vi:** Barra de navegação inferior com 4 tabs (para atleta):
- **Início** (ícone home)
- **Hoje** (ícone today)
- **Histórico** (ícone history)
- **Mais** (ícone menu)

Se estiver em modo mock, banner amarelo no topo: **"Modo demonstração — dados não serão salvos"**

Para staff, apenas 2 tabs: Início e Mais.

**O que esperava:** Uma home screen com conteúdo interessante logo de cara. Tabs fazem sentido.

**O que aconteceu:** A navegação é clara e padrão. Quatro tabs é gerenciável. Os nomes em português são bons. "Mais" é o padrão de "hambúrguer" expandido.

**Veredicto:** 🟢 AÇÃO CLARA

**Evidência:** `home_screen.dart:62-82` — 4 NavigationDestination: `'Início'`, `'Hoje'`, `'Histórico'`, `'Mais'`; linhas 110-120 — staff: `'Início'` e `'Mais'`

---

### 6. Athlete Dashboard Screen (tab "Início")

**O que vi:** AppBar com título **"Omni Runner"**. Abaixo, saudação: **"Olá, [nome]!"** (ou "Olá, atleta!" se sem nome). Pergunta: **"O que deseja fazer hoje?"**

Banner de primeiros passos (tip dismissível):
> "Primeiros passos:
> 1. Conecte seu Strava e faça sua primeira corrida
> 2. Entre em uma assessoria (peça o código ao professor)
> 3. Crie ou encontre um desafio para competir
> 4. Complete corridas para se tornar Atleta Verificado"

Se há solicitação pendente de assessoria, card amarelo: **"Solicitação pendente — Aguardando aprovação da assessoria..."**

Se já está em assessoria, card de acesso rápido: **"Feed da [nome assessoria]"**

Grid de 7 cards (2 colunas):
1. **"Meus desafios"** — "Competir e acompanhar"
2. **"Minha assessoria"** ou **"Entrar em assessoria"** — nome da assessoria ou "Toque para se juntar" (+ badge "Toque para encontrar" se vazio)
3. **"Meu progresso"** — "XP, badges e missões" (badge "Conecte Strava" se Strava desconectado)
4. **"Verificação"** — "Status de atleta verificado"
5. **"Campeonatos"** — "Competir entre assessorias"
6. **"Parques"** — "Rankings e comunidade"
7. **"Meus créditos"** — "Seus OmniCoins"

**O que esperava:** Um resumo do meu dia (tipo Strava home), talvez minha última corrida, um CTA para correr. Não esperava 7 cards com funcionalidades avançadas logo na home.

**O que aconteceu:** O tip banner de "Primeiros passos" é EXCELENTE — finalmente alguém me disse o que fazer! Mas ele é dismissível e uma vez fechado, nunca mais volta. O grid de 7 cards é denso para um primeiro uso. Cards como "Verificação", "OmniCoins", "Campeonatos" não significam nada para mim no dia 1. O card "Meu progresso" com badge "Conecte Strava" é útil — me empurra para a ação certa. Porém o card "Entrar em assessoria" reforça a dependência de assessoria — parece que metade do app está travada sem uma.

**Veredicto:** 🟡 AMBIGUIDADE

**Evidência:** `athlete_dashboard_screen.dart:304` — `'Olá, $_displayName!'` ou `'Olá, atleta!'`; linhas 320-324 — tip "Primeiros passos"; linhas 422-424 — `'Meus desafios'` / `'Competir e acompanhar'`; linhas 434-436 — `'Minha assessoria'` / `'Entrar em assessoria'`; linhas 450-453 — `'Meu progresso'` / `'XP, badges e missões'`; linhas 460-462 — `'Verificação'`; linhas 468-470 — `'Campeonatos'`; linhas 476-478 — `'Parques'` / `'Rankings e comunidade'`; linhas 488-490 — `'Meus créditos'` / `'Seus OmniCoins'`

---

### 7. Today Screen (tab "Hoje")

**O que vi:** AppBar com título localizado (provavelmente "Hoje").

Tip banner (dismissível): **"O Omni Runner funciona com o Strava: corra com qualquer relógio (Garmin, Coros, Apple Watch) e suas corridas serão importadas automaticamente. Conecte em Configurações → Integrações."**

Se Strava NÃO conectado — card laranja proeminente:
- Ícone de relógio no fundo Strava (#FC4C02)
- **"Conecte o Strava para começar"**
- Texto explicativo: "O Omni Runner importa suas corridas direto do Strava. Funciona com qualquer relógio: Garmin, Coros, Apple Watch, Polar, Suunto, ou até correndo só com o celular."
- Botão **"Conectar Strava"** (laranja Strava)

Se Strava conectado e correu hoje — card verde:
- **"Boa! Você já correu hoje!"**
- "Sua corrida foi registrada. Veja o recap abaixo!"

Se Strava conectado mas não correu — card gradiente:
- **"Bora correr?"**
- "Corra com seu relógio e sua atividade será importada automaticamente."

Também mostra: streak banner (🔥 "X dias seguidos!"), desafios ativos, campeonatos, recap da última corrida (distância, pace, duração, FC média), comparação com corrida anterior ("X% mais rápido"), card de check-in de parque, quick stats (nível, XP, corridas da semana, km total).

**O que esperava:** Um resumo do meu dia de treino. Talvez uma agenda ou treino do dia.

**O que aconteceu:** Para usuário novo sem Strava = tela quase vazia com um CTA laranja enorme pedindo para conectar Strava. Isso é BOM — me diz exatamente o que fazer. A explicação de que funciona com "qualquer relógio" é crucial e bem posicionada. Mas se eu não tenho Strava nem relógio, fico preso — não há alternativa visível (correr só com GPS do celular, por exemplo). O streak banner, desafios, recap de corrida — tudo depende de ter dados. No dia 1, esta tela será basicamente: "Conecte Strava" + "Sem sequência ativa".

**Veredicto:** 🟢 AÇÃO CLARA (para quem tem Strava) / 🟡 AMBIGUIDADE (para quem não tem)

**Evidência:** `today_screen.dart:497-500` — tip sobre Strava; linhas 1017-1020` — `'Conecte o Strava para começar'`; linhas 1024-1029 — texto explicativo sobre relógios; linha 1043 — `'Conectar Strava'`; linhas 974-976 — `'Bora correr?'` / `'Boa! Você já correu hoje!'`; linhas 812-813 — streak `'X dias seguidos!'`

---

### 8. More Screen (tab "Mais")

**O que vi:** AppBar com título localizado (provavelmente "Mais"). ListView com seções em cards:

**Seção "Minha Assessoria"** (atleta):
- "Minha Assessoria" — "Ver grupo, feed e trocar de assessoria"
- "Escanear QR" — "Ler QR da assessoria para receber ou devolver OmniCoins"
- "Entregas Pendentes" — "Confirmar treinos enviados ao relógio"
- "Meu Treino do Dia" — "Ver o treino agendado para hoje"

**Seção "Social"** (atleta):
- "Convidar amigos" — "Compartilhe o app com outros corredores"
- "Meus Amigos" — "Sua rede de corredores"
- "Atividade dos amigos" — "Corridas recentes dos seus amigos"

**Seção "Conta"**:
- "Meu Perfil" — "Ver e editar seu perfil"
- "Configurações" — "Strava, tema e unidades"
- "Diagnóstico" — "Informações técnicas e depuração"

**Seção "Ajuda"**:
- "Suporte" — "Tickets de suporte da assessoria"
- "Perguntas Frequentes" — "Dúvidas comuns sobre o app"
- "Sobre" — "Omni Runner" (abre AboutDialog com versão e "© 2026 Omni Runner")

Se modo offline/anônimo, card amarelo: **"Modo Offline — Crie uma conta para desbloquear desafios, campeonatos e assessorias."** com botão "Criar conta / Entrar".

Se logado, botão **"Sair"** em vermelho com confirmação.

**O que esperava:** Uma lista de configurações e opções extras. Padrão "Mais" de apps.

**O que aconteceu:** Organização por seções em cards é boa. PORÉM, muitos termos são opacos para dia 1: "OmniCoins", "Entregas Pendentes", "Escanear QR" — QR de quê? Para quê? "Meu Treino do Dia" pressupõe que a assessoria já enviou treino. Para um usuário novo solo, 4 dos 4 itens de "Minha Assessoria" serão inúteis. A seção Social é boa mas vazia no dia 1 (sem amigos). Ponto positivo: "Perguntas Frequentes" existe — mas depende do conteúdo.

**Veredicto:** 🟡 AMBIGUIDADE

**Evidência:** `more_screen.dart:72` — `'Minha Assessoria'`; linhas 88-89 — `'Escanear QR'` / `'Ler QR da assessoria para receber ou devolver OmniCoins'`; linhas 97-98 — `'Entregas Pendentes'`; linhas 108-109 — `'Meu Treino do Dia'`; linhas 141 — `'Convidar amigos'`; linhas 152 — `'Meus Amigos'`; linhas 278-279 — `'Criar conta / Entrar'`; linha 300 — logout com `context.l10n.logout`

---

## PORTAL — Fluxo do Staff

---

### 9. Portal Login

**O que vi:** Página centralizada com card branco sobre fundo secundário. Título "Omni Runner", subtítulo "Portal da Assessoria". Login social (Google, Apple) + email/senha. Mensagens de erro em português.

**O que esperava:** Login de painel admin. Isso.

**O que aconteceu:** Limpo e funcional. Nada de mais. Sem opção de cadastro — correto para portal B2B. Sem link "Esqueci minha senha" visível (falta). Sem branding da assessoria — é genérico.

**Veredicto:** 🟢 AÇÃO CLARA

**Evidência:** `portal/src/app/login/page.tsx:213` — `'Omni Runner'`; linha 214 — `'Portal da Assessoria'`; linha 95 — `'Entrar com Google'`; linha 111 — `'Entrar com Apple'`; linha 176 — `'Entrar com e-mail'`

---

### 10. Portal Dashboard

**O que vi:** Título **"Dashboard"**, subtexto **"Visão geral da assessoria"**. Welcome banner no topo.

Se créditos baixos (<50), alerta vermelho: **"Créditos baixos: X restantes — Recarregue para continuar distribuindo OmniCoins aos atletas."** Com botão "Recarregar Agora" (só para admin_master).

Grid de stats (2 linhas × 4 colunas):
- **"Créditos Disponíveis"** (vermelho se baixo)
- **"Atletas"** (contagem)
- **"Verificados"** (contagem + % do total)
- **"Ativos (7d)"** (WAU + % do total)
- **"Corridas (7d)"** (com trend %)
- **"Km (7d)"** (com trend %)
- **"Desafios (30d)"**
- **"Compras"** (só admin_master, créditos adquiridos)

Gráfico de barras com breakdown diário de sessões (últimos 7 dias: Dom-Sáb).

Seção "Acesso Rápido" (só admin_master): links para "Comprar Créditos", "Ver Atletas", "Engajamento", "Verificação", "Configurações".

Rodapé: LastUpdated timestamp.

**O que esperava:** Overview do grupo com métricas de treino. Talvez lista de atletas recentes.

**O que aconteceu:** Bom dashboard KPI. As métricas são relevantes: atletas, ativos, corridas, distância, trends. Porém, para um staff NOVO abrindo pela primeira vez com 0 atletas, isso vai ser uma tela de zeros — e não há nenhum CTA de "Convide seu primeiro atleta" ou onboarding do portal. O conceito de "Créditos/OmniCoins" aparece logo no primeiro stat block sem explicação — o que são? Por que preciso comprar? O alerta de créditos baixos é agressivo sem contexto.

**Veredicto:** 🟡 AMBIGUIDADE

**Evidência:** `portal/src/app/(portal)/dashboard/page.tsx:167` — `'Dashboard'`; linha 168 — `'Visão geral da assessoria'`; linhas 188-189 — `'Créditos baixos: X restantes'`; linhas 205-232 — stat blocks; linhas 264-285 — "Acesso Rápido"

---

### 11. Portal Sidebar (Navegação)

**O que vi:** Sidebar fixa (desktop 56px width, 224px na verdade — `w-56`) com header mostrando logo da assessoria (ou inicial da letra) + nome. Abaixo, menu colapsável por seções:

**Visão Geral:**
- Dashboard

**Atletas:**
- Atletas
- Verificação
- CRM Atletas
- Alertas/Risco (admin/coach only)

**Engajamento:**
- Engajamento
- Presença
- Análise Presença
- Mural
- Comunicação (admin/coach only)

**Treinos:**
- Treinos
- Análise Treinos
- Entrega Treinos
- Execuções
- Campeonatos
- Matchmaking
- Liga
- TrainingPeaks (se habilitado)

**Financeiro:**
- Custódia (admin only)
- Compensações
- Swap de Lastro (admin only)
- Conversão Cambial (admin only)
- Financeiro
- Distribuições
- Auditoria

**Configurações:**
- Configurações
- Exports
- Badges

Para platform_admin: link extra "Admin Plataforma" no rodapé.

No footer da sidebar: role do usuário em texto muted.

**O que esperava:** 5-8 itens de menu. Algo gerenciável.

**O que aconteceu:** SOBRECARGA MASSIVA. São ~30 itens de menu distribuídos em 6 seções. Para um staff novo, isso é avassalador. Termos como "Custódia", "Swap de Lastro", "Conversão Cambial", "Clearing/Compensações", "Matchmaking" são financeiros/técnicos — parecem pertencer a uma exchange de crypto, não a um app de assessoria de corrida. "Liga", "Campeonatos", "Matchmaking", "Execuções" — qual a diferença? Não há tooltips. O menu financeiro com 7 itens sugere que há uma complexidade enorme de operações financeiras que eu, como coach novo, não entendo e tenho medo de mexer.

**Veredicto:** 🔴 CONFUSÃO

**Evidência:** `portal/src/components/sidebar.tsx:31` — `'Dashboard'`; linhas 43-47 — grupo Atletas com 4 itens; linhas 58-63 — grupo Engajamento com 5 itens; linhas 75-83 — grupo Treinos com 8 itens; linhas 94-101 — grupo Financeiro com 7 itens; linhas 113-116 — grupo Configurações com 3 itens

---

## Resumo de Veredictos

| # | Tela | Veredicto | Principal Problema |
|---|------|-----------|--------------------|
| 1 | Welcome Screen | 🟢 AÇÃO CLARA | Falta identidade visual, mas funcional |
| 2 | Login Screen | 🟢 AÇÃO CLARA | Instagram é boa surpresa; falta "explorar sem conta" |
| 3 | Onboarding Role | 🔴 CONFUSÃO | Decisão PERMANENTE no 2º passo; aviso assustador |
| 4 | Join Assessoria | 🟡 AMBIGUIDADE | Obriga a buscar assessoria; "Pular" pouco visível |
| 5 | Home (tabs) | 🟢 AÇÃO CLARA | Navegação padrão e intuitiva |
| 6 | Athlete Dashboard | 🟡 AMBIGUIDADE | 7 cards no dia 1 é overload; tip banner é bom mas dismissível |
| 7 | Today Screen | 🟢/🟡 | Ótimo CTA de Strava; vazio sem dados; sem alternativa a Strava |
| 8 | More Screen | 🟡 AMBIGUIDADE | Termos opacos (OmniCoins, QR, Entregas); dependência de assessoria |
| 9 | Portal Login | 🟢 AÇÃO CLARA | Falta "Esqueci senha" e link "baixe o app" |
| 10 | Portal Dashboard | 🟡 AMBIGUIDADE | Sem onboarding portal; "Créditos" sem explicação |
| 11 | Portal Sidebar | 🔴 CONFUSÃO | ~30 itens de menu; termos financeiros intimidam |

---

## Top 5 Problemas Críticos de Primeiro Contato

1. **Decisão irreversível no onboarding** — Escolher role permanente no 2º passo é hostil. Recomendação: tornar reversível ou adiar até ser necessário.

2. **Sidebar do portal com ~30 itens** — Overload cognitivo. Um coach novo não sabe o que é "Custódia" ou "Swap de Lastro". Recomendação: progressive disclosure — mostrar só 5-8 itens no início, desbloquear com uso.

3. **"Assessoria" nunca é explicada** — Termo aparece 20+ vezes nas telas e NUNCA é definido. Um corredor casual, um estrangeiro, ou alguém fora do ecossistema de assessorias brasileiras ficará perdido. Recomendação: tooltip ou onboarding card explicando "assessoria = grupo de treino com professor".

4. **Dependência de Strava sem alternativa visível** — A tela "Hoje" e o dashboard são inúteis sem Strava. Não há menção de tracking pelo GPS do celular. Se o produto funciona SÓ com Strava, isso deveria ser dito na Welcome Screen. Se funciona sem, deveria ter alternativa visível.

5. **Dashboard do atleta com 7 cards no dia 1** — "OmniCoins", "Verificação", "Campeonatos" não significam nada para quem acabou de instalar. O tip banner "Primeiros passos" é ótimo mas desaparece ao ser fechado. Recomendação: empty states com explicação em cada card; progressive disclosure.
