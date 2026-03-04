# FASE 5 — Friction Test

**Data:** 2026-03-04
**Testador:** UX Researcher (usuário simulado, completamente novo)
**Método:** Análise de código das telas user-facing em `omni_runner/lib/presentation/screens/` e `portal/src/app/`

---

## Flow 1: ONBOARDING (novo usuário → primeira tela útil)

### Trace real (via `auth_gate.dart`)

```
welcome_screen → login_screen → [loading] → onboarding_role_screen → [loading]
→ join_assessoria_screen → [loading] → onboarding_tour_screen → home_screen
→ (tap "Hoje") → today_screen
```

**Nota:** O `auth_gate.dart` insere telas de loading entre cada transição e adiciona o `onboarding_tour_screen` antes do home. O `home_screen` aterrissa na tab `AthleteDashboardScreen` (tab 0), não na `TodayScreen` (tab 1).

### Contagem de métricas

| Métrica | Caminho rápido (social + skip) | Caminho completo (email + assessoria + tour) |
|---------|-------------------------------|----------------------------------------------|
| **Telas visitadas** | 7 | 7 + 9 slides do tour = 16 "telas" |
| **Taps/cliques** | 10 | 22 |
| **Decisões** | 4 | 6 |
| **Campos a preencher** | 0 | 3 |
| **Momentos de confusão** | 6 | 8 |
| **Momentos de feedback claro** | 3 | 5 |

### Detalhamento dos taps (caminho rápido: social login + skip assessoria + skip tour)

| # | Tela | Ação | Taps |
|---|------|------|------|
| 1 | `welcome_screen.dart` | Tap "COMEÇAR" | 1 |
| 2 | `login_screen.dart` | Tap "Continuar com Google" | 1 |
| 3 | OAuth externo | Autorizar no Google | ~2 |
| 4 | `onboarding_role_screen.dart` | Tap "Sou atleta" | 1 |
| 5 | `onboarding_role_screen.dart` | Tap "Continuar" | 1 |
| 6 | `onboarding_role_screen.dart` | Tap "Sim, sou Atleta" (confirm dialog) | 1 |
| 7 | `join_assessoria_screen.dart` | Tap "Pular — posso entrar depois" | 1 |
| 8 | `onboarding_tour_screen.dart` | Tap "Pular" | 1 |
| 9 | `home_screen.dart` | Tap tab "Hoje" | 1 |
| | | **Total** | **~10** |

### Detalhamento dos taps (caminho completo: email + assessoria + tour completo)

| # | Tela | Ação | Taps |
|---|------|------|------|
| 1 | `welcome_screen.dart` | Tap "COMEÇAR" | 1 |
| 2 | `login_screen.dart` | Tap "Continuar com Email" | 1 |
| 3 | `login_screen.dart` | Preencher email | 1 |
| 4 | `login_screen.dart` | Preencher senha | 1 |
| 5 | `login_screen.dart` | Tap "Entrar" | 1 |
| 6 | `onboarding_role_screen.dart` | Tap "Sou atleta" | 1 |
| 7 | `onboarding_role_screen.dart` | Tap "Continuar" | 1 |
| 8 | `onboarding_role_screen.dart` | Tap "Sim, sou Atleta" (confirm) | 1 |
| 9 | `join_assessoria_screen.dart` | Digitar nome da assessoria | 1 |
| 10 | `join_assessoria_screen.dart` | Tap no resultado | 1 |
| 11 | `join_assessoria_screen.dart` | Tap "Solicitar" (confirm dialog) | 1 |
| 12 | `join_assessoria_screen.dart` | Tap "Entendi" (success dialog) | 1 |
| 13-21 | `onboarding_tour_screen.dart` | 8x "PRÓXIMO" + 1x "COMEÇAR A CORRER" | 9 |
| 22 | `home_screen.dart` | Tap tab "Hoje" | 1 |
| | | **Total** | **~22** |

### Decisões com consequência

| # | Tela | Decisão | Reversível? | Peso |
|---|------|---------|-------------|------|
| 1 | `login_screen.dart` | Método de login (Google/Apple/Instagram/Email) | Sim (pode deslogar) | Baixo |
| 2 | `onboarding_role_screen.dart` | Atleta vs. Assessoria | **NÃO — permanente** | **CRÍTICO** |
| 3 | `onboarding_role_screen.dart` | Confirmar papel no dialog | Sim (pode voltar) | Médio |
| 4 | `join_assessoria_screen.dart` | Qual assessoria entrar (ou pular) | Parcial (pode trocar depois) | Alto |
| 5 | `onboarding_tour_screen.dart` | Pular ou assistir o tour | Sim (mas não tem como rever) | Baixo |

### Momentos de confusão

| # | Tela | Evidência no código | O que confunde |
|---|------|---------------------|----------------|
| 1 | `onboarding_role_screen.dart` L176-179 | `'Essa escolha é permanente e define toda a sua experiência no app.'` | Ansiedade: o usuário não entende a diferença entre os papéis e é forçado a decidir permanentemente. Texto em vermelho (`theme.colorScheme.error`) amplifica o medo. |
| 2 | `onboarding_role_screen.dart` L69 | `'Essa escolha é permanente e não pode ser alterada depois.'` | Mesmo texto repetido no diálogo de confirmação. Background em `DesignTokens.error` com ícone de cadeado. Sensação de "armadilha". |
| 3 | `join_assessoria_screen.dart` L621 | `'Encontre sua\nassessoria'` | "Assessoria" é jargão. Usuários fora da corrida brasileira não entendem. Sem explicação contextual. |
| 4 | `join_assessoria_screen.dart` L711 | `'Pular — posso entrar depois'` | Onde "depois"? Não diz como encontrar a opção novamente. |
| 5 | `home_screen.dart` L62-66 | Tabs: Início, Hoje, Histórico, Mais | O usuário aterrissa em "Início" (AthleteDashboard). A tela mais útil ("Hoje") é outra tab. Sem indicação de por onde começar. |
| 6 | `today_screen.dart` L976 | `'Bora correr?'` | Parece que deveria ter um botão "Iniciar Corrida". Mas o app não rastreia — depende do Strava. O CTA real é "Conectar Strava", que aparece condicionalmente. |

### Momentos de feedback claro

| # | Tela | Evidência | Tipo |
|---|------|-----------|------|
| 1 | `login_screen.dart` L245-249 | `CircularProgressIndicator` durante login | Loading state |
| 2 | `join_assessoria_screen.dart` L358-360 | `Icons.check_circle_outline` + `'Solicitação enviada!'` | Success dialog |
| 3 | `join_assessoria_screen.dart` L706-709 | `CircularProgressIndicator` no botão durante ação | Loading state |
| 4 | `onboarding_role_screen.dart` L43-94 | Dialog de confirmação com detalhes do papel | Confirmation |

### Análise de fricção

**Telas confusas:**
1. `onboarding_role_screen.dart` — O aviso permanente em vermelho causa paralisia. O usuário ainda não usou o app e já precisa fazer uma escolha irreversível.
2. `join_assessoria_screen.dart` — Múltiplos métodos de entrada (buscar, QR, código, pular) sem hierarchy visual clara. O usuário não sabe qual é o "caminho feliz".
3. `home_screen.dart` — Aterrissar em AthleteDashboard sem nenhum onboarding contextual ou seta apontando para "Hoje".

**Textos que não ajudam:**
1. `'Treine com sua assessoria'` (welcome) — assume que o usuário já tem uma
2. `'Evolua com métricas reais'` (welcome) — o que são "métricas reais" vs. irreais?
3. `'Buscar assessoria...'` (join) — não explica o que é assessoria
4. `'Tenho um código'` (join) — código de quê? Como o obtenho?

**Ações ambíguas:**
1. Botão "Continuar" no role screen — "continuar para onde?" (na verdade abre um diálogo de confirmação)
2. "Pular — posso entrar depois" — onde é "depois"?

**Feedback insuficiente:**
1. Após login social, apenas troca de tela. Nenhum "Bem-vindo, [nome]!" ou confirmação visual.
2. Após pular assessoria, nenhuma confirmação. A tela simplesmente avança.
3. O tour pode ser pulado sem nenhuma consequência visível — o usuário nunca saberá o que perdeu.

**Decisões irreversíveis:**
1. **Escolha de papel** — `onboarding_role_screen.dart` L69: `'Essa escolha é permanente e não pode ser alterada depois. Se precisar trocar, entre em contato com o suporte.'` — Esta é a decisão mais pesada de todo o onboarding, feita no momento de MENOR conhecimento do produto.

---

## Flow 2: FIRST VALUE (ver dados de corrida)

### Trace

```
today_screen.dart → tap "Conectar Strava" → OAuth externo → retorno ao app
```

### Contagem de métricas

| Métrica | Valor |
|---------|-------|
| **Telas visitadas** | 2 (TodayScreen + OAuth externo) |
| **Taps/cliques** | 4-5 |
| **Decisões** | 2 |
| **Campos a preencher** | 0 (se já logado no Strava) a 2 (se precisa login no Strava) |
| **Momentos de confusão** | 4 |
| **Momentos de feedback claro** | 3 |

### Detalhamento dos taps

| # | Onde | Ação | Taps |
|---|------|------|------|
| 1 | `home_screen.dart` | Tap tab "Hoje" (se não estiver lá) | 1 |
| 2 | `today_screen.dart` | Scroll até a card Strava (se necessário) | 0-1 |
| 3 | `today_screen.dart` | Tap "Conectar Strava" (L1041) | 1 |
| 4 | OAuth externo | Autorizar acesso no Strava | 2-3 |
| | | **Total** | **~4-5** |

### Decisões

| # | Decisão | Peso |
|---|---------|------|
| 1 | Confiar ao app o acesso ao Strava (dados de atividade) | Alto — envolve dados pessoais |
| 2 | Autorizar escopos de leitura no Strava OAuth | Alto — permissões de dados |

### Momentos de confusão

| # | Tela | Evidência | O que confunde |
|---|------|-----------|----------------|
| 1 | `today_screen.dart` L494-500 | TipBanner: `'Conecte em Configurações → Integrações.'` | Contradição: há um CTA direto "Conectar Strava" logo abaixo na mesma tela, mas o tip diz para ir em Configurações. Dois caminhos para a mesma ação. |
| 2 | `today_screen.dart` L1024-1029 | `'O Omni Runner importa suas corridas direto do Strava.'` | Primeira vez que o usuário descobre que o app NÃO rastreia corridas. Essa informação deveria ter aparecido no Welcome ou no Onboarding. |
| 3 | `today_screen.dart` L352-388 | `_connectStrava()` — chama `controller.startConnect()` | Após conectar, chama `_load()` para carregar dados. Se o usuário não tem corridas no Strava, verá o card "Bora correr?" sem nenhum dado — e sem explicação de quanto tempo leva para dados aparecerem. |
| 4 | N/A | Sem conta Strava | Se o usuário não usa Strava, não há nenhum guidance alternativo. Nenhum link "Não tenho Strava" ou explicação de como criar uma conta. |

### Momentos de feedback claro

| # | Tela | Evidência | Tipo |
|---|------|-----------|------|
| 1 | `today_screen.dart` L361-363 | `SnackBar('Strava conectado como ${connected.athleteName}!')` | Success feedback — excelente, confirma nome do atleta |
| 2 | `today_screen.dart` L537-542 | `_BoraCorrerCard` muda para "Boa! Você já correu hoje!" quando `ranToday` | Estado visual claro pós-corrida |
| 3 | `today_screen.dart` L547-554 | `_RunRecapCard` mostra distância, pace, duração | Valor imediato quando há dados |

### Análise de fricção

**Telas confusas:**
1. `today_screen.dart` — O tip banner (L494-500) e o CTA da card Strava (L1041) coexistem, oferecendo dois caminhos diferentes para a mesma ação.

**Textos que não ajudam:**
1. `'Conecte o Strava para começar'` — "começar o quê?" não diz o benefício imediato
2. `'Funciona com qualquer relógio: Garmin, Coros, Apple Watch, Polar, Suunto, ou até correndo só com o celular.'` — lista longa demais, perde atenção

**Ações ambíguas:**
1. O botão "Conectar Strava" na TodayScreen vs. a instrução "Configurações → Integrações" no tip — qual é o correto?

**Feedback insuficiente:**
1. Nenhum indicador de progresso durante o backfill de corridas históricas. O usuário conecta e pode não ver dados imediatamente.
2. Se não há corridas no Strava, nenhuma mensagem explica isso.

**Decisões irreversíveis:**
Nenhuma — Strava pode ser desconectado em Configurações.

---

## Flow 3: PORTAL FIRST USE (staff abre o portal)

### Trace

```
login/page.tsx → [auth check] → select-group/page.tsx → dashboard/page.tsx
```

### Contagem de métricas

| Métrica | Valor |
|---------|-------|
| **Telas visitadas** | 2-3 (login + select-group só se >1 grupo + dashboard) |
| **Taps/cliques** | 3-6 |
| **Decisões** | 1-2 |
| **Campos a preencher** | 0-2 |
| **Momentos de confusão** | 3 |
| **Momentos de feedback claro** | 4 |

### Detalhamento dos taps (caminho rápido: social login + 1 grupo)

| # | Tela | Ação | Taps |
|---|------|------|------|
| 1 | `login/page.tsx` | Tap "Entrar com Google" | 1 |
| 2 | OAuth externo | Autorizar | ~2 |
| 3 | `select-group/page.tsx` | Auto-redirect (1 grupo) | 0 |
| 4 | `dashboard/page.tsx` | Visualizar | 0 |
| | | **Total** | **~3** |

### Decisões

| # | Decisão | Peso |
|---|---------|------|
| 1 | Método de login: Google, Apple, ou email | Baixo |
| 2 | Selecionar grupo (só se múltiplos) | Baixo — visual claro |

### Momentos de confusão

| # | Tela | Evidência | O que confunde |
|---|------|-----------|----------------|
| 1 | `login/page.tsx` L214 | `'Portal da Assessoria'` | Apenas um subtítulo genérico. Não explica o que o portal faz ou quem deveria estar aqui. Nenhum link "Não é staff? Baixe o app". |
| 2 | `select-group/page.tsx` L22-33 | `redirect("/no-access")` | Se o usuário não tem nenhum grupo staff, é redirecionado para `/no-access` sem explicação de como ser adicionado como staff. |
| 3 | `dashboard/page.tsx` L204-257 | 8+ cards de estatísticas | Muita informação de uma vez. Sem hierarquia visual de "o que fazer primeiro". Nenhum "getting started" ou checklist para novo staff. |

### Momentos de feedback claro

| # | Tela | Evidência | Tipo |
|---|------|-----------|------|
| 1 | `login/page.tsx` L176 | `'Entrando...'` no botão durante submit | Loading state |
| 2 | `login/page.tsx` L166-168 | `'E-mail ou senha inválidos'` em `bg-error-soft` | Error state claro |
| 3 | `select-group/page.tsx` L34-36 | Auto-redirect se 1 grupo | Seamless — o melhor padrão possível |
| 4 | `dashboard/page.tsx` L170-202 | Warning de créditos baixos com CTA "Recarregar Agora" | Proactive feedback excelente |

### Análise de fricção

**Telas confusas:**
1. `dashboard/page.tsx` — Visão geral densa. Sem "próximos passos" para novo staff.

**Textos que não ajudam:**
1. `'Portal da Assessoria'` — genérico demais
2. Role labels no select-group (`'admin_master'`, `'coach'`, `'assistant'`) — mostrados como texto raw, sem humanização

**Ações ambíguas:**
1. Dashboard tem "Acesso Rápido" com links mas sem priorização — Comprar Créditos, Ver Atletas, Engajamento, Verificação, Configurações. Qual primeiro?

**Feedback insuficiente:**
1. Nenhuma mensagem de boas-vindas personalizada ao entrar no portal pela primeira vez
2. `/no-access` — precisaria ver essa tela, mas provavelmente é uma dead-end sem guidance

**Decisões irreversíveis:**
Nenhuma no portal.

---

## Tabela Resumo

| Flow | Telas | Cliques (min-max) | Decisões | Campos | Confusão | Feedback |
|------|-------|-------------------|----------|--------|----------|----------|
| 1. Onboarding | 7 (+9 tour) | 10-22 | 4-6 | 0-3 | 6-8 | 3-5 |
| 2. First Value | 2 | 4-5 | 2 | 0-2 | 4 | 3 |
| 3. Portal | 2-3 | 3-6 | 1-2 | 0-2 | 3 | 4 |

---

## Friction Score (0-100, lower = more friction)

Fórmula: `Score = 100 × (feedback_moments / (confusion_moments + feedback_moments))`

| Flow | Confusão | Feedback | Score | Interpretação |
|------|----------|----------|-------|---------------|
| 1. Onboarding | 6 | 4 | **40** | Alta fricção. Decisão permanente prematura + jargão não explicado + tour longo. |
| 2. First Value | 4 | 3 | **43** | Alta fricção. Descoberta tardia da dependência do Strava + caminhos duplicados. |
| 3. Portal | 3 | 4 | **57** | Fricção moderada. Login eficiente, mas dashboard sem onboarding contextual. |
| **Média** | | | **47** | **O produto tem fricção significativa, especialmente no onboarding do app.** |

---

## Top 5 Pontos de Fricção Críticos

### 1. Escolha de papel permanente sem contexto (CRÍTICO)
- **Tela:** `onboarding_role_screen.dart` L69, L176-179
- **Problema:** Decisão irreversível feita quando o usuário sabe MENOS sobre o produto
- **Impacto:** Paralisia de decisão, medo de errar, possível abandono
- **Recomendação:** Tornar reversível, ou postergar a decisão até o usuário ter usado o app

### 2. Dependência do Strava revelada tarde demais (ALTO)
- **Tela:** `today_screen.dart` L1017-1029
- **Problema:** Usuário completa todo o onboarding (7 telas, 10+ taps) e só então descobre que precisa do Strava
- **Impacto:** Frustração, sensação de tempo perdido, abandono se não tem Strava
- **Recomendação:** Mencionar Strava na Welcome Screen e oferecer conexão durante o onboarding

### 3. Onboarding Tour de 9 slides com "Pular" prominente (ALTO)
- **Tela:** `onboarding_tour_screen.dart` L22-98, L134-137
- **Problema:** Informações críticas (Strava, OmniCoins, verificação) enterradas em 9 slides que quase todo usuário vai pular
- **Impacto:** Usuários perdem informação essencial, têm que descobrir por conta própria
- **Recomendação:** Reduzir para 3-4 slides. Mover informação crítica para tooltips contextuais nas telas relevantes.

### 4. Jargão "assessoria" sem explicação (MÉDIO)
- **Tela:** `welcome_screen.dart` L112, `join_assessoria_screen.dart` L621
- **Problema:** Termo central do app nunca é explicado. Assume que 100% dos usuários são do mundo da corrida brasileira.
- **Impacto:** Corredores casuais ou de fora do Brasil ficam perdidos
- **Recomendação:** Adicionar subtítulo: "Assessoria = seu grupo de corrida com treinador"

### 5. Landing page pós-onboarding não é a tela mais útil (MÉDIO)
- **Tela:** `home_screen.dart` L43-48 — tab 0 é AthleteDashboard, não TodayScreen
- **Problema:** O usuário aterrissa em um dashboard com cards abstratos em vez da tela "Hoje" onde veria o CTA do Strava e seus dados de corrida
- **Impacto:** Primeiro contato com valor é adiado por mais 1 tap + necessidade de descobrir a tab "Hoje"
- **Recomendação:** Considerar fazer "Hoje" a tab padrão para novos usuários, ou mostrar CTA Strava no Dashboard
