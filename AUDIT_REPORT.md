# RELATÓRIO DE AUDITORIA COMPLETA — OMNI RUNNER

> Data: 2026-02-24
> Perspectivas: Senior Product Designer + Senior QA Engineer + Senior Product Logic Expert
> Escopo: Todos os fluxos do app (atleta + assessoria), caminhos felizes e de erro

---

## 1. ONBOARDING (Welcome → Login → Role → Assessoria/Staff)

### 1.1 Caminho Feliz
`WelcomeScreen → LoginScreen → OnboardingRoleScreen → JoinAssessoriaScreen (atleta) OU StaffSetupScreen (staff) → HomeScreen`

### 1.2 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| O-1 | ALTA | **Não há opção de login por email/senha.** Apenas Google, Apple (iOS only), Instagram. Se o usuário Android não tem Google e não usa Instagram, não consegue entrar. | Exclusão de usuários Android sem Google. | Adicionar login por email/senha como fallback universal. |
| O-2 | MÉDIA | **Seleção de role é irreversível.** "Escolha com atenção" — mas não há como trocar depois. Se o atleta errou e escolheu "Assessoria", fica preso. | Frustração, necessidade de suporte manual. | Permitir troca de role em Settings, ou pelo menos um "Você tem certeza?" com explicação clara das consequências. |
| O-3 | MÉDIA | **JoinAssessoriaScreen tem 4 caminhos de entrada** (busca, QR, código, skip) — excelente. Mas "Continuar sem assessoria" pode confundir: o atleta pode pensar que perde funcionalidades. | Abandono por medo. | Texto mais claro: "Você pode entrar em uma assessoria depois, nas configurações." |
| O-4 | BAIXA | **WelcomeScreen não tem splash/animação.** O ícone estático e os bullets são funcionais, mas não criam wow factor para um app de corrida. | Primeira impressão fraca. | Animação Lottie de um corredor, ou breve vídeo de 3 segundos. |
| O-5 | BAIXA | **Login com Instagram** — usa ícone genérico `camera_alt_outlined` em vez do logo oficial do Instagram. | Parece não-oficial, pode causar desconfiança. | Usar SVG/asset do logo do Instagram (respeitando guidelines da Meta). |
| O-6 | CRÍTICO | **AuthGate mock mode** — se Supabase falha ao iniciar, o app vai direto para Home sem login. O usuário não vê nenhuma funcionalidade real (tudo depende de server). Em mock mode, o app é um shell vazio. | Usuário pensa que o app está quebrado. | Mostrar tela de erro de conexão com retry, em vez de enviar para Home vazia. |

---

## 2. HOME & NAVEGAÇÃO

### 2.1 Estrutura

**Atleta:** 4 tabs (Início, Correr, Histórico, Mais)
**Staff:** 2 tabs (Início, Mais)

### 2.2 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| N-1 | ALTA | **Staff não tem acesso a Desafios.** O staff tem apenas "Início" e "Mais", sem tab de desafios ou matchmaking. Se um professor quiser criar desafios para motivar alunos, não consegue (pelo app). | Funcionalidade limitada para staff. | Avaliar se staff deveria ter acesso a Desafios (criando para o grupo) ou se isso é intencional. |
| N-2 | MÉDIA | **Dashboard do atleta tem 6 cards** mas nenhum acesso direto à verificação do atleta. O usuário só descobre que precisa ser verificado quando tenta criar desafio com stake > 0. | Falta de proatividade; jornada reativa. | Adicionar card "Status de Verificação" no dashboard, ou badge no perfil mostrando status. |
| N-3 | MÉDIA | **Tab "Mais" do atleta mistura conteúdo de Staff e Atleta.** O item "Operações QR (Staff)" aparece no menu do ATLETA, mas falha com "Acesso restrito a staff" quando o atleta toca. | Confusão, erro previsível. | Esconder "Operações QR (Staff)" se o `userRole == 'ATLETA'`. Ele já está dentro de `if (!_isStaff)`. |
| N-4 | BAIXA | **"Minha Assessoria" aparece no dashboard E no menu "Mais".** Duplicação de acesso desnecessária. | Confusão sobre onde gerenciar. | Manter em um lugar só, ou diferenciar: dashboard = visão resumida, Mais = gestão completa. |
| N-5 | BAIXA | **Histórico só mostra 20-30 sessões.** Para atletas ativos (1 corrida/dia), isso cobre apenas 1 mês. | Perda de contexto histórico. | Paginação infinita ou filtro por período. |

---

## 3. FLUXO DE CORRIDA (Tracking → Summary → Sync)

### 3.1 Caminho Feliz
`Tab "Correr" → Mapa carrega → Iniciar corrida → Correndo (GPS tracking + métricas) → Finalizar → RunSummaryScreen → Auto-sync`

### 3.2 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| T-1 | ALTA | **Se o mapa não carrega em 6 segundos**, o app mostra `_mapTimedOut = true` mas continua. O usuário pode iniciar corrida sem mapa. Funcional, mas confuso. | Corrida sem feedback visual. | Mostrar texto explicativo: "O mapa não carregou. Sua corrida será rastreada normalmente." |
| T-2 | MÉDIA | **Permissão de GPS.** Se o usuário nega permissão de localização, o TrackingBloc recebe `AppStarted` mas o fluxo falha silenciosamente. | Usuário não entende por que não funciona. | Checar permissões ANTES de mostrar o mapa. Se negada, tela explicativa com botão para Settings do OS. |
| T-3 | MÉDIA | **Recovery screen** — se o app crashou durante uma corrida, o `RecoveryScreen` aparece no restart, oferecendo "Retomar" ou "Descartar". Mas "Retomar" apenas finaliza a sessão (não re-inicia o tracking). | O nome "Retomar" engana — deveria ser "Salvar". | Renomear: "Salvar corrida" e "Descartar corrida". |
| T-4 | MÉDIA | **RunSummaryScreen mostra `isVerified` e `integrityFlags`** — mas esses valores vêm do client-side (pré-check). O servidor pode alterar depois no verify-session. O usuário pode ver "Verificada" e depois na lista ver "Invalidada". | Inconsistência na informação. | Mostrar "Verificação pendente" até o server confirmar, ou atualizar após sync. |
| T-5 | BAIXA | **Fallback de posição inicial = Brasília** (-15.79, -47.89). Se o GPS demora, o mapa mostra o centro do Brasil. | Confusão visual momentânea. | Manter, mas adicionar indicador "Obtendo localização..." sobre o mapa. |

---

## 4. DESAFIOS (Criar → Convidar → Join → Track → Settle)

### 4.1 Caminho Feliz — Criação Manual
`Dashboard → Desafios → "+" → ChallengeCreateScreen → preenche → Criar → ChallengeInviteScreen → compartilha link`

### 4.2 Caminho Feliz — Receber convite
`Deep link → ChallengeJoinScreen → carrega detalhes → "Aceitar Desafio"`

### 4.3 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| C-1 | CRÍTICO | **Após criar desafio, a ÚNICA opção é compartilhar link.** O matchmaking foi adicionado na lista, mas o fluxo de criação manual ainda obriga o compartilhamento. Se o usuário cria desafio e fecha o ChallengeInviteScreen sem compartilhar, o desafio fica "pending" para sempre (expira). | Desafio criado mas nunca jogado. | Oferecer opção "Publicar para matchmaking" no ChallengeInviteScreen, ou alertar "Você não compartilhou. Desafio será cancelado em X horas se ninguém entrar." |
| C-2 | ALTA | **Fluxo de criação e matchmaking são separados** — o usuário precisa decidir ANTES se quer convidar manualmente ou fazer matchmaking. Mas ambos os fluxos pedem as mesmas informações (métrica, meta, duração, stake). | Duplicação de UX. | Unificar: um formulário só, com opção "Enviar link" ou "Encontrar oponente automaticamente" no final. |
| C-3 | ALTA | **Atleta sem assessoria não deve acessar desafios.** Regra de produto: assessoria é pré-requisito para criar, participar ou buscar desafios. | Atletas sem vínculo competindo sem supervisão. | ✅ **CORRIGIDO** — Gate em 3 Edge Functions (`challenge-create`, `challenge-join`, `matchmake`) retorna `NO_ASSESSORIA`. Flutter bloqueia navegação para Desafios e Campeonatos com `AssessoriaRequiredSheet` + CTA "Entrar em assessoria". |
| C-4 | MÉDIA | **Deep link de convite** (`https://omnirunner.app/challenge/{id}`) — se o app não está instalado, o link não resolve. Não há web fallback. | Perda de conversão. | ✅ **CORRIGIDO** — Portal Next.js deployado em `omnirunner.app` (Vercel). Landing pages `/challenge/[id]` e `/invite/[code]` com auto-redirect para deep link, botões de download (Play Store / App Store), e Open Graph metadata. Android App Links via `/.well-known/assetlinks.json` (SHA256 do APK). iOS Universal Links via `/.well-known/apple-app-site-association` (substituir `TEAM_ID` quando Apple Developer Account estiver disponível). |
| C-5 | MÉDIA | **Group challenges: "50 - accepted" slots disponíveis** — hardcoded. Não há opção de limitar o número de participantes em grupo. | Grupo com 50 pessoas perde competitividade. | Adicionar campo "máximo de participantes" (default 50, editável). |
| C-6 | MÉDIA | **Não há notificação push quando um oponente aceita** — o criador do desafio só descobre voltando à lista de desafios. | Desafio ativo sem o criador saber. | ✅ **CORRIGIDO** — Regra `challenge_accepted` adicionada ao `notify-rules`. `challenge-join` dispara push fire-and-forget ao criador e demais participantes: "Fulano aceitou 'Nome do Desafio'. Prepare-se!". Dedup 12h. FCM secrets configurados. |
| C-7 | BAIXA | **Anti-cheat policy "strict" está visível no código** (HR correlation) mas não é selecionável na UI. | Feature fantasma. | Remover do código até implementar, ou adicionar toggle na UI. |

---

## 5. MATCHMAKING

### 5.1 Caminho Feliz
`Desafios → "Encontrar Oponente" → configura → "Buscar Oponente" → match encontrado → "Ver Desafio"`

### 5.2 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| M-1 | ALTA | **Matchmaking é somente 1v1.** Não há matchmaking para grupo. O botão "Encontrar Oponente" sugere apenas duelos. | Limita a feature para quem quer grupo. | Adicionar matchmaking para grupo no futuro (e-board). Para MVP, documentar a limitação. |
| M-2 | ALTA | **Quando o match é encontrado, AMBOS participantes são setados como "accepted" automaticamente.** Mas o oponente não consente — ele entrou na fila dizendo "quero um desafio" e o sistema criou. Isso pode surpreender se ele fechou o app. | Falta de opt-in do segundo participante. | O segundo participante deveria receber push notification + ter opção de aceitar/recusar (window de 5 min). Ou deixar explícito na UX da fila: "Ao entrar na fila, você aceita automaticamente o próximo match." |
| M-3 | MÉDIA | **Polling a cada 5s** — se o usuário fica na fila por 20 min, são 240 requests. Rate limit é 20/60s, logo atinge o limite rapidamente. | Erro de rate limit durante busca legítima. | Aumentar intervalo de polling para 15-30s, ou usar Supabase Realtime (subscribe to queue entry changes). |
| M-4 | MÉDIA | **Matchmaking não mostra posição na fila** ("Você é o 3º na fila"). O usuário não sabe se há outras pessoas esperando. | Ansiedade sem contexto. | Adicionar count de waiting entries com mesma config (sem expor user IDs). |
| M-5 | MÉDIA | **Após match, o pop retorna challengeId** mas a `ChallengesListScreen` apenas faz reload da lista. O usuário deveria ser levado DIRETAMENTE ao `ChallengeDetailsScreen`. | Extra tap desnecessário. | Navegar para ChallengeDetailsScreen com o challengeId retornado. |
| M-6 | BAIXA | **Skill bracket é mostrado mas não explicado.** O chip "Nível: Intermediário" aparece na busca, mas o atleta não sabe como isso é calculado. | Frustração se o match demora por causa de bracket. | Adicionar tooltip ou tela "Como funciona": "Seu nível é baseado no pace médio das suas últimas 10 corridas." |

---

## 6. VERIFICAÇÃO DO ATLETA

### 6.1 Caminho Feliz
`Tenta stake > 0 → modal de gate → "Ver minha verificação" → AthleteVerificationScreen → vê checklist → corre 7 corridas → reavaliar → VERIFIED`

### 6.2 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| V-1 | ALTA | **A tela de verificação não é acessível proativamente.** Não há link no dashboard, perfil ou menu. Só aparece quando o gate bloqueia. | O atleta não sabe que verificação existe até tentar stake. | Adicionar card "Status de Verificação" no dashboard E no ProgressHub. |
| V-2 | MÉDIA | **O checklist mostra "identity_ok" e "permissions_ok"** — mas não há implementação real (sempre true no server). Itens sempre verdes confundem: "Se já está verde, por que não sou verified?" | Confusão sobre o que realmente falta. | Remover itens não implementados do checklist, ou marcá-los como "futuro" com ícone diferente. |
| V-3 | MÉDIA | **"Reavaliar agora" pode ser pressionado repetidamente** — rate limit protege o server, mas o usuário não entende por que dá erro. | UX confusa em erro de rate limit. | Desabilitar botão por 30s após pressionar, com countdown visual. |
| V-4 | BAIXA | **Estados CALIBRATING e MONITORED não têm CTA claro.** O checklist mostra o progresso, mas não diz "Continue correndo, faltam X corridas". | Falta de orientação. | Adicionar frase motivacional dinâmica: "Mais 3 corridas e você estará verificado!" |

---

## 7. WALLET (OmniCoins)

### 7.1 Caminho Feliz
`Dashboard → "Meus créditos" → WalletScreen → vê saldo + histórico`

### 7.2 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| W-1 | ALTA | **O atleta NÃO tem como obter OmniCoins por conta própria.** O empty state diz "Peça ao professor da sua assessoria para distribuir OmniCoins." Se o atleta não tem assessoria, dead end. | Feature monetária inacessível para atletas independentes. | Definir formas de ganhar coins: completar corridas, missões, badges. Se já existe, conectar o fluxo. |
| W-2 | MÉDIA | **Pending coins (cross-assessoria prizes) não têm CTA.** O saldo mostra "pendente" mas não explica O QUE o atleta precisa fazer para liberar. | Confusão sobre dinheiro "preso". | Explicar: "Coins pendentes são liberados após confirmação do professor/staff da assessoria adversária." |
| W-3 | BAIXA | **Histórico do wallet não tem filtro por tipo** (earned, spent, pending). | Difícil encontrar transação específica. | Adicionar chips de filtro. |

---

## 8. PERFIL & CONFIGURAÇÕES

### 8.1 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| P-1 | ALTA | **Não há opção de logout visível.** O `ProfileScreen` tem "Sair da conta" (via AuthRepository.signOut), mas se o usuário não navega até Mais → Perfil, não encontra. | Não consegue trocar de conta. | Adicionar "Sair" claramente em Settings/Mais, não escondido dentro de Perfil. |
| P-2 | MÉDIA | **Não há foto de perfil.** O campo display_name é editável, mas sem avatar/foto. | App social sem identidade visual. | Adicionar upload de avatar (armazenar no Supabase Storage). |
| P-3 | MÉDIA | **Não há opção de deletar conta** (exigência LGPD/GDPR). | Compliance legal em risco. | Adicionar "Excluir minha conta" com confirmação, que chama um RPC de exclusão. |
| P-4 | BAIXA | **Configurações só tem "Áudio durante a corrida".** Muito limitado. | Falta de controle do usuário. | Adicionar: notificações, unidades (km/mi), tema (dark/light), privacidade. |

---

## 9. STAFF / ASSESSORIA

### 9.1 Caminho Feliz — Staff
`Login → Onboarding → "Represento assessoria" → Criar assessoria OU Entrar como professor → StaffDashboard → Atletas, Confirmações, Performance, Campeonatos, Créditos, Admin`

### 9.2 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| S-1 | ALTA | **Staff não pode correr no app.** Home do staff tem apenas dashboard de gestão, sem tabs "Correr" e "Histórico". Se o professor é corredor, precisa de outra conta. | Exclusão do professor como atleta. | Ou permitir dual-role (staff que também corre), ou adicionar tab de corrida no shell do staff. |
| S-2 | ALTA | **"Solicitações de entrada" (join requests)** — não há push notification para o staff quando um atleta solicita entrada. O staff precisa checar manualmente. | Atleta espera indefinidamente. | ✅ **CORRIGIDO** — Regra `join_request_received` no `notify-rules`. Flutter dispara fire-and-forget após `fn_request_join`. Push enviado para admin_master + professor: "Fulano quer entrar em 'Nome'. Aprove no app." Dedup 12h. |
| S-3 | MÉDIA | **Invite code/QR** — o staff pode gerar QR e código de convite, mas não há indicação de quantos usaram o código, ou se ele tem validade. | Falta de rastreabilidade. | Mostrar count de usos, data de criação, opção de expirar/revogar. |
| S-4 | MÉDIA | **Créditos (StaffCreditsScreen)** — o staff vê saldo de coins para distribuir, mas o fluxo de AQUISIÇÃO de coins pelo staff não está claro no app. | Dúvida sobre como obter coins para o grupo. | Explicar: portal web → comprar pacotes → coins creditados na assessoria. |
| S-5 | BAIXA | **Performance screen** mostra métricas do grupo, mas sem comparação temporal (esta semana vs anterior). | Dados sem contexto de evolução. | Adicionar gráficos de tendência. |

---

## 10. ASSESSORIA (Perspectiva do Atleta)

### 10.1 Problemas Encontrados

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| A-1 | ALTA | **Trocar de assessoria** é possível mas não há feedback sobre o impacto. O atleta perde acesso ao grupo anterior? Perde histórico? Coins? | Medo de trocar. | Explicar na UI: "Seus treinos e coins permanecem. Você será removido do grupo X e adicionado ao grupo Y." |
| A-2 | MÉDIA | **Feed da assessoria** existe (AssessoriaFeedScreen) mas é acessado apenas via ProgressHub → Feed. Devia ser mais visível. | Feature escondida. | Adicionar no dashboard do atleta ou como card. |
| A-3 | MÉDIA | **Atleta sem assessoria** — vários cards mostram "empty state" mas não há jornada guiada para encontrar uma assessoria depois do onboarding. | Dead ends múltiplos. | Botão "Encontrar assessoria" que reabre o fluxo de busca/QR/código. |

---

## 11. CAMPEONATOS

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| CH-1 | MÉDIA | **Campeonatos são criados pelo staff** mas o atleta só vê se está inscrito. Não há "browse" de campeonatos do grupo. | Baixa discoverability. | Mostrar campeonatos ativos do grupo no dashboard. |

---

## 12. PROBLEMAS TRANSVERSAIS (Cross-flow)

| # | Severidade | Problema | Impacto | Sugestão |
|---|---|---|---|---|
| X-1 | CRÍTICO | **Sem onboarding contextual.** O app não tem tutorial, coach marks, ou tooltips na primeira vez. Um "dummy" abre o app e vê 6 cards sem saber o que fazer primeiro. | Perda massiva de novos usuários. | Adicionar onboarding tour: "1) Sua primeira corrida → 2) Entre numa assessoria → 3) Crie um desafio". Ou um checklist de "primeiros passos" no dashboard. |
| X-2 | CRÍTICO | **Não há tratamento de "sem internet" consistente.** Cada tela trata erros de rede de forma diferente (some mostra SnackBar, some vai para empty state, AuthGate vai para mock mode). | UX inconsistente; estados quebrados. | Criar um widget global `NoConnectionBanner` que aparece no topo quando a rede cai, com retry automático. |
| X-3 | ALTA | **LoginRequiredSheet** aparece para features que requerem conta — mas o usuário já fez login na maioria dos casos (exceto mock mode). Se está em mock mode (Supabase falhou), TUDO mostra "Faça login". | Confusão total em mock mode. | Se está em mock mode, mostrar tela dedicada de "Sem conexão" em vez de deixar navegar e bloquear em cada feature. |
| X-4 | ALTA | **Sem pull-to-refresh em várias telas.** Dashboard, Challenges List, Wallet — dependem de carregamento inicial. Se deu erro, o usuário precisa voltar e re-entrar. | Frustração. | Adicionar RefreshIndicator em todas as telas que carregam dados do server. |
| X-5 | MÉDIA | **Versão do app é hardcoded "v1.0.0"** no About dialog. | Informação incorreta após updates. | Usar `package_info_plus` para pegar versão dinâmica. |
| X-6 | MÉDIA | **Não há dark mode.** O tema é apenas `deepPurple` light. | Uso noturno é comum para corredores matutinos. | Adicionar toggle de tema (dark/light/system). |
| X-7 | BAIXA | **Sem i18n.** Todo o app é em português brasileiro. | Limita expansão. | Aceitar por agora (target market é BR), mas estruturar para i18n futuro. |

---

## 13. BUGS POTENCIAIS ENCONTRADOS

| # | Local | Bug | Risco |
|---|---|---|---|
| B-1 | `more_screen.dart` L76-84 | **"Operações QR (Staff)" visível para atletas** — o guard de `!_isStaff` esconde seções de "Assessoria", mas "Operações QR (Staff)" está DENTRO do bloco `if (!_isStaff)`, ou seja, aparece para atletas. | CONFIRMADO — código inconsistente. |
| B-2 | `matchmaking_screen.dart` | **Rate limit vs polling.** Rate limit do matchmake é 20/60s. Polling é 5s = 12 req/min. Com a chamada inicial, em 2 min o atleta ultrapassa o rate limit. | Race condition em uso normal. |
| B-3 | `challenge_create_screen.dart` L614 | **`typeStr` não inclui `team_vs_team`.** O SegmentedButton tem apenas `oneVsOne` e `group`. Se `team_vs_team` fosse selecionável, o `typeStr` seria errado. | Baixo risco (não selecionável atualmente). |
| B-4 | `history_screen.dart` L47-50 | **Merge remoto + local** faz SELECT de 30 sessions do server a cada vez que a tab fica visível. Se o atleta navega entre tabs frequentemente, muitas queries desnecessárias. | Performance degradada. |
| B-5 | `challenges_list_screen.dart` | **`_openMatchmaking` é função top-level** que usa `context.read<ChallengesBloc>()` — mas o matchmaking retorna um `challengeId`. Deveria navegar direto para detalhes do desafio, não recarregar a lista. | UX subótima — extra tap. |

---

## 14. FLUXOS FALTANTES (Features Gaps)

| # | Gap | Por que importa |
|---|---|---|
| F-1 | **Notificações push** — existem no código (`PushNotificationService`) mas não há evidência de triggers nos fluxos críticos: desafio aceito, match encontrado, campeonato começou, join request recebido. | Usuário não volta ao app sem push. |
| F-2 | **Compartilhamento social** — após corrida, não há "Compartilhar no Instagram/WhatsApp" com card visual bonito. | Perda de viralidade orgânica. | ✅ **CORRIGIDO** — `RunShareCard` gera imagem PNG com gradiente, distância hero, pace, duração, FC, nome e badge "Corrida verificada". Botão de compartilhar no `RunSummaryScreen` abre share sheet nativo. |
| F-3 | **Métricas de melhoria pessoal** — o app rastreia corridas mas não mostra evolução (gráfico de pace ao longo do tempo, PR, records). | Falta de motivação para continuar. | ✅ **CORRIGIDO** — `PersonalEvolutionScreen` com 3 gráficos (pace, volume, frequência semanal) via `fl_chart` + cards de PR (melhor pace, maior distância). Integrado no ProgressHub. |
| F-4 | **Friends / Social graph** — tem `InviteFriendsScreen` e `FriendsScreen`, mas não há feed de atividades dos amigos. | Feature social superficial. | ✅ **CORRIGIDO** — `FriendsActivityFeedScreen` com cards de corrida dos amigos (avatar, nome, distância, pace, duração, tempo relativo). RPC `fn_friends_activity_feed` (SECURITY DEFINER) cruza friendships + sessions + profiles. Paginação 30 por vez. Integrado no menu Mais. |
| F-5 | **Recuperação de sessão após crash** — RecoveryScreen existe e é boa. Mas o texto dos botões confunde ("Retomar" deveria ser "Salvar"). | Detalhe de copy. |

---

## 15. PRIORIZAÇÃO RECOMENDADA

### P0 — Fazer IMEDIATAMENTE (bloqueiam uso real)
1. **X-1** Onboarding contextual (primeiro uso sem guia = perda de 80% dos usuários)
2. **O-6** Mock mode silencioso → substituir por tela de erro com retry
3. **X-2** Tratamento de "sem internet" consistente
4. **P-3** Opção de deletar conta (LGPD)
5. **B-2** Rate limit vs polling no matchmaking (corrigir intervalo para 15-30s)

### P1 — Fazer no próximo Sprint
6. **O-1** Login por email/senha como fallback
7. **N-3** Esconder "Operações QR" do menu do atleta (B-1)
8. **V-1** Verificação acessível proativamente (dashboard card)
9. **M-2** Consentimento do segundo participante no matchmaking
10. **C-1** CTA "Publicar para matchmaking" no invite screen

### P2 — Fazer quando possível
11. **O-2** Permitir troca de role
12. **S-1** Staff que também corre (dual-role)
13. **W-1** Formas de ganhar coins sem assessoria
14. **C-2** Unificar formulário de criação + matchmaking
15. **X-6** Dark mode

### P3 — Nice to have
16. **P-2** Foto de perfil
17. **M-4** Posição na fila
18. **F-2** Compartilhamento social pós-corrida
19. **O-4** Animação na WelcomeScreen
20. **X-5** Versão dinâmica

---

## 16. RESUMO EXECUTIVO

O app tem uma **base sólida**: arquitetura limpa (BLoC, Clean Architecture), backend robusto (Supabase RLS, Edge Functions, triggers), e features avançadas (matchmaking, verificação de atleta, campeonatos, ghost runs, anti-cheat).

Os **pontos fortes** são:
- Monetization gate impenetrável (4 camadas)
- Offline-first com sync inteligente
- Gamification completa (XP, badges, missões, streaks, leaderboards, coins)
- Matchmaking queue-based (design superior)

Os **pontos fracos** são:
- **Onboarding zero**: novo usuário é largado no app sem orientação
- **Conectividade frágil**: mock mode silencioso, tratamento de erro inconsistente
- **Features escondidas**: verificação, feed, campeonatos difíceis de encontrar
- **Gaps de notificação**: sem push nos momentos críticos
- **Staff limitado**: não pode correr, sem push para join requests

O app está **funcional para early adopters** que já entendem o conceito, mas **não está pronto para "dummies"** — falta a camada de orientação e hand-holding que transforma um produto técnico em um produto acessível.

---

## 17. CORREÇÕES APLICADAS (2026-02-24)

| # | ID | Severidade | Correção | Arquivo(s) |
|---|---|---|---|---|
| 1 | B-1/N-3 | **BUG CONFIRMADO** | QR Operations removido do menu do atleta e movido para bloco staff-only. Antes estava invertido (visível só para atletas). | `more_screen.dart` |
| 2 | B-2/M-3 | **BUG CRÍTICO** | Polling de matchmaking alterado de 5s → 20s para não exceder rate limit (20 req/60s). | `matchmaking_screen.dart` |
| 3 | O-6 | **CRÍTICO** | Mock mode não vai mais direto para Home. Redireciona para WelcomeScreen e mostra erro ao tentar login sem conexão. | `auth_gate.dart`, `login_screen.dart`, `main.dart` |
| 4 | B-5/M-5 | **ALTO** | Após match no matchmaking, navega automaticamente para ChallengeDetailsScreen em vez de só recarregar lista. | `challenges_list_screen.dart` |
| 5 | V-1/N-2 | **ALTO** | Card "Verificação" adicionado ao dashboard principal, substituindo "Convidar amigos" (que já está em Mais). | `athlete_dashboard_screen.dart` |
| 6 | V-3 | **MÉDIO** | Botão "Reavaliar agora" tem cooldown de 30s após pressionar, impedindo spam. | `athlete_verification_screen.dart` |
| 7 | W-2 | **MÉDIO** | Coins pendentes agora mostram explicação detalhada: o que são, por que existem e quando serão liberados. | `wallet_screen.dart` |
| 8 | C-1 | **ALTO** | Diálogo de confirmação ao fechar ChallengeInviteScreen sem compartilhar o link. Intercepta botão voltar via PopScope. | `challenge_invite_screen.dart` |
| 9 | O-3 | **MÉDIO** | "Continuar sem assessoria" renomeado para "Pular — posso entrar depois" com texto explicando o que se perde/ganha. | `join_assessoria_screen.dart` |
| 10 | T-4 | **MÉDIO** | RunSummary agora mostra nota "Verificação final pelo servidor ao sincronizar" para esclarecer que isVerified é provisório. | `run_summary_screen.dart` |
| 11 | P-1 | **ALTO** | Botão "Sair da conta" adicionado ao menu Mais (mais visível), com diálogo de confirmação. | `more_screen.dart` |
| 12 | P-3 | **CRÍTICO (LGPD)** | Opção "Excluir minha conta" adicionada no ProfileScreen com diálogo duplo de confirmação e chamada a edge function. | `profile_screen.dart` |
| 13 | X-4 | **MÉDIO** | Pull-to-refresh adicionado em ChallengesListScreen e WalletScreen. | `challenges_list_screen.dart`, `wallet_screen.dart` |
| 14 | X-1 | **CRÍTICO** | Onboarding contextual: TipBanner no dashboard reescrito com 4 passos claros (correr, assessoria, desafio, verificação). | `athlete_dashboard_screen.dart` |

| 15 | W-3 | **CRÍTICO** | BLE HR e Export eram inacessíveis. Tela "Wearables e Saúde" transformada de informativa para funcional com botão "Conectar sensor". Botão "Exportar" adicionado no detalhe de cada corrida. | `more_screen.dart`, `run_details_screen.dart` |
| 16 | W-5 | **ALTO** | Settings não tinha seção de wearables. Adicionado: toggle alertas FC por zona, editor de FC máxima com validação, visualização das 5 zonas de FC com faixas de BPM calculadas em tempo real. | `settings_screen.dart`, `more_screen.dart` |
| 17 | W-4 | **MÉDIO** | FIT encoder implementado — formato binário completo com file_id, events, records (GPS+HR+speed+altitude+distance), lap, session, activity. CRC-16 correto. ExportScreen habilitado para FIT. 15 testes unitários. | `fit_encoder.dart`, `export_screen.dart`, `export_service_impl.dart` |
| 18 | X-2 | **CRÍTICO** | NoConnectionBanner global: widget que detecta conectividade via `connectivity_plus` e mostra banner laranja "Sem conexão" no topo. Integrado no HomeScreen para ambos shells (atleta + staff). | `no_connection_banner.dart`, `home_screen.dart` |
| 19 | O-1 | **ALTO** | Login por email/senha adicionado como fallback universal. Formulário expansível com validação, toggle login/cadastro, campos email e senha, fluxo "Esqueci a senha" com resetPasswordForEmail do Supabase. Backend já suportava (signIn/signUp existiam no AuthRepository). | `login_screen.dart`, `auth_repository.dart`, `i_auth_datasource.dart`, `remote_auth_datasource.dart`, `mock_auth_datasource.dart` |
| 20 | X-5 | **MÉDIO** | Versão do app agora é dinâmica via `package_info_plus`. About dialog mostra versão real + build number. | `more_screen.dart` |
| 21 | X-6 | **MÉDIO** | Dark mode implementado: ThemeNotifier com persistência (SharedPreferences), 3 opções (Sistema/Claro/Escuro) no SettingsScreen, darkTheme configurado no MaterialApp. | `theme_notifier.dart`, `main.dart`, `settings_screen.dart` |
| 22 | V-4 | **BAIXO** | CTA motivacional dinâmico: mensagens de status agora incluem contagem de corridas faltantes para CALIBRATING e trust score atual para MONITORED. | `athlete_verification_screen.dart` |
| 23 | W-3 | **BAIXO** | Filtro por tipo no histórico do wallet: chips "Todos", "Ganhos", "Gastos" para filtrar transações. | `wallet_screen.dart` |
| 24 | M-6 | **BAIXO** | Skill bracket com explicação: tooltip "Seu nível é calculado pelo pace médio das suas últimas 10 corridas" ao tocar no chip de nível. | `matchmaking_screen.dart` |
| 25 | B-3 | **BAIXO** | typeStr corrigido: switch exaustivo que mapeia ChallengeType para strings snake_case corretas (`one_vs_one`, `group`, `team_vs_team`). | `challenge_create_screen.dart` |
| 26 | T-2 | **MÉDIO** | Permissão GPS permanentemente negada agora mostra botão "Abrir Configurações" que leva às settings do SO (via `Geolocator.openAppSettings()`). | `tracking_bottom_panel.dart` |

### AUDIT-FIX BATCH 4 — Correções Finais (20 itens)

| # | ID | Severidade | Correção | Arquivos |
|---|----|-----------|----------|----------|
| 27 | A-1 | **ALTA** | Trocar assessoria: diálogo expandido com lista visual do que se mantém (treinos, desafios, verificação) e o que se perde (grupo, coins pendentes). | `my_assessoria_screen.dart` |
| 28 | M-2 | **ALTA** | Matchmaking: estado `pendingConfirm` adicionado. Match encontrado mostra card de revisão com todas os detalhes (oponente, métrica, meta, tempo, stake) e botões Aceitar/Recusar. | `matchmaking_screen.dart` |
| 29 | C-2 | **ALTA** | Fluxo unificado: banner "Sem oponente? Use o matchmaking" adicionado ao topo do formulário de criação de desafio. | `challenge_create_screen.dart` |
| 30 | O-2 | **MÉDIA** | Role irreversível: diálogo de confirmação explícito com aviso em vermelho "Esta escolha é permanente". Subtítulo do onboarding também reforçado. | `onboarding_role_screen.dart` |
| 31 | P-2 | **MÉDIA** | Avatar: CircleAvatar com iniciais + botão câmera para upload via `image_picker`. Upload para Supabase Storage `avatars/`. | `profile_screen.dart` |
| 32 | B-4 | **MÉDIA** | History: stale-guard de 30s evita re-queries ao trocar tabs rapidamente. | `history_screen.dart` |
| 33 | C-5 | **MÉDIA** | Group challenge: seletor de 3 a 100 participantes (default 10) com botões +/-. Valor enviado ao backend via `max_participants`. | `challenge_create_screen.dart`, `challenge_rules_entity.dart`, `challenges_bloc.dart` |
| 34 | A-3 | **MÉDIA** | Atleta sem assessoria: card do dashboard muda para "Entrar em assessoria" com ícone `group_add`, navegando para `JoinAssessoriaScreen`. | `athlete_dashboard_screen.dart` |
| 35 | A-2 | **MÉDIA** | Feed da assessoria: card proeminente no dashboard quando o atleta tem assessoria, com acesso direto ao feed. | `athlete_dashboard_screen.dart` |
| 36 | M-4 | **MÉDIA** | Posição na fila: backend calcula posição (entradas waiting com mesmo metric/bracket), Flutter exibe "Posição na fila: N". | `matchmake/index.ts`, `matchmaking_screen.dart` |
| 37 | S-3 | **MÉDIA** | Invite code: tela de convite mostra contagem de entradas via código e status ativo/desativado. | `invite_qr_screen.dart` |
| 38 | CH-1 | **MÉDIA** | Campeonatos: filter chips (Todos, Abertos, Ativos, Inscritos) para navegação filtrada. | `athlete_championships_screen.dart` |
| 39 | O-4 | **BAIXA** | WelcomeScreen: animação sequencial (logo slide+fade → bullets fade → CTA fade) em 1.4s. | `welcome_screen.dart` |
| 40 | O-5 | **BAIXA** | Instagram: ícone com gradiente de cores do Instagram (amarelo → rosa → roxo) via ShaderMask. | `login_screen.dart` |
| 41 | T-5 | **BAIXA** | GPS fallback: banner amarelo "Obtendo sua localização..." aparece quando usando posição fallback (Brasília). | `tracking_screen.dart` |
| 42 | N-4 | **BAIXA** | Duplicação removida: "Assessorias" e "Minha Assessoria" unificados em um único tile no menu Mais. | `more_screen.dart` |
| 43 | N-5 | **BAIXA** | Paginação: histórico agora carrega 30 por vez com botão "Carregar mais". Query Supabase usa `range()`. | `history_screen.dart` |
| 44 | C-7 | **BAIXA** | Anti-cheat strict: removida menção a "Avançada (FC obrigatória)" que não está implementada. Sempre mostra "Padrão". | `challenge_details_screen.dart` |
| 45 | S-5 | **BAIXA** | Performance temporal: KPI de corridas semanais agora compara com semana anterior ("±N% vs sem. anterior"). | `staff_performance_screen.dart` |
| 46 | P-4 | **BAIXA** | Settings expandidos: seção Unidades (km/mi toggle), seção Privacidade (visibilidade ranking, share feed). Auth Debug só em debug mode. | `settings_screen.dart`, `coach_settings_entity.dart`, `coach_settings_repo.dart` |

### Items já corretos (sem alteração necessária)
- **T-3**: RecoveryScreen já diz "Salvar e continuar" com ícone correto.
- **T-1**: Map timeout já exibe mensagem "Mapa indisponível offline" com explicação.
- **V-2**: Checklist no app mostra apenas itens implementados (corridas, integridade, consistência, trust score).
