# Cold Market Test — Fase 6: Relação App ↔ Portal

**Produto:** Omni Runner  
**Data:** 04/03/2026  
**Perspectiva:** Usuário frio, zero contexto prévio

---

## 1. Para que serve o portal (perspectiva de usuário frio)

A tela de login do portal diz **"Portal da Assessoria"** e tem um link dizendo "Atleta? Baixe o app". Isso comunica imediatamente que existem dois mundos:

- **Portal web** = para quem gerencia uma assessoria de corrida
- **App móvel** = para quem corre (o atleta)

O portal parece ser um **painel de gestão completo** para donos e treinadores de assessorias esportivas. Ele oferece gestão de atletas, entrega de treinos, métricas de engajamento, CRM, finanças, campeonatos e liga entre assessorias.

**Clareza inicial: Boa.** A separação é óbvia na tela de login. Porém, a profundidade do portal (clearing, custody, swap, FX, auditoria) surpreende — parece mais uma fintech do que um portal esportivo.

---

## 2. Quem é o usuário do portal vs app?

### Portal (Web)
- **Roles:** `admin_master`, `coach`, `assistant`
- Usuário = dono de assessoria, treinador ou assistente
- Gerencia um `coaching_group` específico (seleciona grupo no login se pertence a vários)
- Tem branding personalizado (logo, cores) — cada assessoria pode ter identidade visual própria
- Acesso baseado em permissões (admin vê financeiro, assistant vê menos)

### App (Flutter)
- **Dois modos na mesma app:**
  - **Atleta** (`AthleteDashboardScreen`): corridas, desafios, wallet, campeonatos, assessoria, parques
  - **Staff** (`StaffDashboardScreen`): gestão de atletas, créditos, campeonatos, confirmações, treinos
- O staff no app tem um botão **"Portal — Abrir no navegador"** que leva ao site web

### Problema de percepção
Um usuário frio que baixa o app e escolhe "professor" no onboarding vai parar no `StaffDashboardScreen` do app. Ele verá cards como "Atletas e Staff", "Créditos", "Performance" — mas o portal web tem **4x mais funcionalidades**. Não fica claro por que ele deveria usar o portal web além do app.

---

## 3. Fluxo de dados: Portal → App

### O que o portal produz que aparece no app:

| Ação no Portal | Resultado no App |
|---|---|
| Gerenciar atletas (aprovar, remover) | Atleta vê/perde sua assessoria |
| Entrega de treinos (Delivery) | Treinos atribuídos ao atleta (via `workout_delivery_items`) |
| Criar campeonatos | Atleta vê campeonatos ativos na `TodayScreen` |
| Distribuir OmniCoins (créditos) | Saldo aparece na `WalletScreen` do atleta |
| Publicar no mural (Announcements) | Atleta vê no feed da assessoria |
| Gerenciar badges | Badges disponíveis no catálogo do atleta |
| Clearing/Compensações | Coins pendentes entre assessorias liberados |
| Liga (enrollment) | Atleta vê ranking da assessoria na `LeagueScreen` |

### O que o app produz que aparece no portal:

| Ação no App | Resultado no Portal |
|---|---|
| Atleta corre (sessão Strava) | Sessions contam no dashboard, engagement, km |
| Atleta entra em desafio | Matchmaking queue visível no portal |
| Atleta pede para entrar na assessoria | Join request aparece para staff |
| Atleta verifica identidade | Status de verificação visível |
| Atleta participa de campeonato | Dados de participação no portal |

### Fluxo financeiro bidirecional:
1. Admin compra créditos no portal (`billing_purchases`)
2. Distribui OmniCoins para atletas
3. Atletas usam coins em desafios
4. Desafios entre assessorias geram `clearing_settlements`
5. Portal mostra contas a pagar/receber entre assessorias

---

## 4. O usuário entende POR QUE o portal existe?

### Para o staff: **Parcialmente**
- O app staff tem um card "Portal — Abrir no navegador", mas **sem explicação do que ele ganha** ao usar o portal vs o app
- Muitas funcionalidades existem **apenas no portal**: CRM, Engagement analytics, Delivery de treinos, Attendance, Communications, Clearing/Finances, Audit, Exports, TrainingPeaks, Matchmaking
- Não existe um "tour" ou comparação mostrando: "Use o app para X, use o portal para Y"

### Para o atleta: **Sim, por exclusão**
- O login do portal diz "Atleta? Baixe o app" — claro que atleta não precisa do portal
- No app, nenhuma tela de atleta referencia o portal

### Lacuna crítica:
O staff que usa **apenas o app** não sabe que está perdendo acesso a 60%+ da plataforma. O portal é onde mora o poder real de gestão, mas a comunicação disso é praticamente inexistente.

---

## 5. O portal complementa ou confunde?

### Complementa quando:
- Staff precisa de análise profunda (engagement score, churn risk, tendências)
- Staff precisa entregar treinos (Delivery via Treinus)
- Staff precisa de CRM (status, tags, notas, alertas)
- Staff precisa de dados financeiros (clearing, custody, FX)
- Staff precisa exportar dados (CSV)
- Staff precisa de keyboard shortcuts e tela grande
- Staff gerencia múltiplos grupos

### Confunde quando:
- Staff abre "Atletas" no app E no portal — qual é a fonte verdadeira?
- Staff vê "Performance" no app e "Engagement" no portal — são coisas diferentes?
- Staff vê "Campeonatos" em ambos — qual usar para criar?
- Staff vê "Créditos" no app e "Custódia/Clearing/Swap/FX" no portal — nível de complexidade muito diferente
- Staff vê "Liga" em ambos — informação idêntica ou diferente?

**Veredicto: Complementa na teoria, confunde na prática.** A falta de um "mapa" claro de responsabilidades entre app e portal gera duplicação percebida e incerteza sobre onde agir.

---

## 6. Análise de sobreposição (features em ambos)

| Feature | App (Staff) | Portal | Diferença |
|---|---|---|---|
| **Listar atletas** | ✅ `CoachingGroupDetailsScreen` | ✅ `/athletes` | Portal tem mais dados (sessions, km, verificação, export CSV) |
| **Performance/Métricas** | ✅ `StaffPerformanceScreen` | ✅ `/engagement` + `/dashboard` | Portal muito mais detalhado (DAU/WAU/MAU, score, churn risk) |
| **Campeonatos** | ✅ `StaffChampionshipTemplatesScreen` | ✅ `/championships` | App cria templates; portal lista campeonatos |
| **Liga** | ✅ `LeagueScreen` | ✅ `/league` | Ambos mostram ranking; app tem contribuição pessoal |
| **Créditos/Wallet** | ✅ `StaffCreditsScreen` | ✅ `/custody` + `/clearing` + `/financial` | Portal exponencialmente mais complexo |
| **Join requests** | ✅ `StaffJoinRequestsScreen` | ✅ `/verification` | Portal tem verificação; app tem solicitações de entrada |
| **Badges** | Via tela de atleta | ✅ `/badges` (settings) | Portal gerencia catálogo; app mostra ao atleta |

### Features APENAS no portal:
- CRM de atletas (status, tags, notas, alertas)
- Entrega de treinos (Delivery via Treinus)
- Presença (Attendance + Analytics)
- Comunicação / Mural
- Matchmaking (fila, somente leitura)
- Clearing / Compensações inter-club
- Custódia / Swap / FX / Distribuições / Auditoria
- Análise de treinos (Workout Analytics)
- TrainingPeaks integration
- Alertas de risco (Risk)
- Exports CSV
- Branding personalizado

### Features APENAS no app:
- Staff: QR Hub (escanear QR para distribuir coins)
- Staff: Confirmações entre assessorias (clearing cases)
- Staff: Suporte direto
- Atleta: Todo o fluxo de corrida, desafios, wallet, parques, DNA, wrapped, streaks

---

## 7. Links faltantes (onde se espera conexão que não existe)

### 7.1 Portal → App
- **Não há deep links do portal para o app.** Se o treinador vê um atleta com risco de churn no portal, não pode enviar uma notificação direta ao atleta pelo portal.
- **Não há preview de como o atleta vê as coisas.** O portal mostra dados brutos, mas não simula a experiência do atleta.
- **Entrega de treinos não tem feedback no app.** O portal mostra `published/confirmed`, mas não existe `workout_delivery_screen.dart` no app — ou seja, o atleta aparentemente não vê a entrega.

### 7.2 App → Portal
- **Staff no app não sabe seu "score" de gestão.** O portal calcula `engagement_score` e `churn_risk`, mas isso não aparece no app staff.
- **Não há notificações push para staff sobre eventos do portal.** Ex: clearing pendente, atleta inativo 30d, créditos baixos.
- **App staff não mostra "o que fazer primeiro".** O portal tem `WelcomeBanner` com onboarding, mas o app staff tem apenas um `TipBanner` genérico.

### 7.3 Dados desconectados
- **Matchmaking** existe no portal (somente leitura) mas não há tela correspondente no app staff
- **Attendance (presença)** existe no portal mas não há registro correspondente no app
- **CRM** existe no portal mas staff no app não tem acesso a notas/tags/status de atletas
- **Communications** existe no portal sem contraparte visível no app
- **Workout delivery** existe no portal (`workout_delivery_batches`/`items`) sem tela no app atleta

---

## 8. Ratings

| Dimensão | Nota (0-10) | Justificativa |
|---|---|---|
| **Clareza da relação** | 4/10 | O login do portal é claro ("Portal da Assessoria"), mas dentro do app não há explicação do que o portal oferece a mais. Staff pode usar o app por meses sem saber que o portal existe. |
| **Complementaridade** | 7/10 | Quando o staff descobre o portal, ele é genuinamente complementar — oferece análises, CRM, financeiro e entrega de treinos que o app não tem. A divisão faz sentido arquitetonicamente. |
| **Nível de confusão** | 6/10 | Sobreposição em 6+ features sem indicação clara de "use X aqui, Y lá". A complexidade financeira do portal (custody, swap, FX, clearing) é desproporcional ao tom leve do app. Um staff frio ficaria confuso sobre por que um app de corrida tem operações de câmbio. |

### Resumo executivo

O portal é um produto poderoso e bem construído, mas **invisível para quem usa apenas o app**. O único link entre app staff e portal é um botão genérico "Abrir no navegador" sem contexto. O portal deveria ser apresentado como a "versão profissional" do painel de gestão, com comunicação clara no app sobre quando e por que usá-lo.

A arquitetura faz sentido (app = mobile-first para corrida; portal = desktop-first para gestão), mas a **ponte entre os dois é quase inexistente**. Um treinador que só usa o celular perde acesso a CRM, delivery de treinos, engagement analytics e todo o módulo financeiro — sem saber que está perdendo.
