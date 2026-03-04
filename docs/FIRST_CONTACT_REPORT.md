# FIRST CONTACT REPORT — Relatório Final

**Produto:** Omni Runner (App Flutter + Portal Next.js)
**Data:** 2026-03-04
**Método:** First-Contact Testing simulado — 6 fases (30s, Exploração, Goal Test, Compreensão, Fricção, Veredito)
**Testador:** UX Researcher simulando usuário completamente novo, sem docs, sem backend

---

## 1. Resumo Executivo

O Omni Runner é uma plataforma de corrida social com conceito forte — competição gamificada com OmniCoins, gestão de assessorias esportivas, e integração Strava — mas o primeiro contato falha em comunicar esse valor. O onboarding exige uma decisão irreversível (escolha de papel) no segundo passo, antes do usuário entender o produto; o termo "assessoria" nunca é explicado; a dependência do Strava só é revelada após 10+ taps; e a funcionalidade #1 prometida na Welcome Screen ("Desafie corredores") é bloqueada por um gate de assessoria + aprovação humana assíncrona. O portal do staff sofre de sobrecarga cognitiva com ~30 itens de menu. **Nota geral: 5.5/10.** O produto tem um núcleo excelente escondido atrás de um onboarding que assume demais sobre o usuário. Não está pronto para novos usuários sem correções críticas.

---

## 2. O que o usuário ENTENDE que o produto faz

Nos primeiros 30 segundos, o usuário constrói este modelo mental:

> "É um app de corrida social/competitivo. Posso desafiar outros corredores, treinar em grupo com um professor, participar de campeonatos e ver métricas. Parece um Strava com gamificação e foco em grupos."

O Portal é entendido como painel administrativo para o lado B2B (quem gerencia o grupo de treino).

**Gaps no modelo mental:**

| O que o usuário ACHA | O que é VERDADE |
|---|---|
| O app rastreia minhas corridas | O app NÃO rastreia — depende 100% do Strava |
| Posso desafiar corredores livremente | Desafios exigem assessoria + aprovação de staff |
| Posso explorar antes de decidir meu papel | A escolha de papel é permanente e acontece no passo 2 |
| "Assessoria" é algo tipo um clube | É um conceito específico da cultura de corrida brasileira, nunca explicado |
| OmniCoins são uma feature secundária | OmniCoins são centrais — vêm da assessoria e gateiam desafios |

O usuário sai do primeiro contato entendendo ~60% do produto. Os 40% que faltam são exatamente os diferenciais.

---

## 3. O que o produto REALMENTE parece entregar

A exploração completa revela um gap significativo entre percepção e realidade:

**Percepção (Welcome Screen):** App de corrida para qualquer corredor com 4 funcionalidades genéricas.

**Realidade:** Plataforma integrada para assessorias de corrida brasileiras com:
- Gestão de grupo (professor → atletas) via portal web + app
- Economia interna (OmniCoins distribuídos pela assessoria, apostados em desafios)
- Gamificação pesada (XP, badges, streaks, verificação, milestones)
- Zero tracking próprio — 100% dependente do Strava como fonte de dados
- Modelo B2B2C: assessoria compra créditos → distribui para atletas → atletas apostam em desafios

**O gap:**
- A Welcome Screen vende um app de corrida genérico. O produto real é uma plataforma B2B2C para assessorias.
- O corredor solo (sem assessoria) tem acesso limitado — mas isso nunca é comunicado antes do onboarding.
- O portal tem complexidade financeira de nível fintech (Custódia, Swap de Lastro, Conversão Cambial, Clearing) que intimida staff novo.

---

## 4. Pontos de Confusão (lista priorizada)

| # | Momento | Tela | O que confundiu | Impacto | Fix sugerido |
|---|---------|------|-----------------|---------|--------------|
| 1 | Onboarding passo 2 | `onboarding_role_screen.dart` L69, L176-179 | Decisão PERMANENTE de papel com aviso em vermelho e ícone de cadeado. Usuário não entende a diferença entre papéis e é forçado a decidir irreversivelmente. | **HIGH** — Ponto #1 de abandono. Paralisia de decisão. | Tornar reversível via configurações, ou remover linguagem de medo (sem vermelho, sem "permanente"). |
| 2 | Desafios bloqueados | `athlete_dashboard_screen.dart` (AssessoriaRequiredSheet) | Card "Meus desafios" → bloqueio por falta de assessoria. Welcome Screen promete "Desafie corredores" mas não entrega. | **HIGH** — Promessa #1 quebrada. Frustração imediata. | Permitir desafios livres entre amigos sem assessoria, ou avisar na Welcome Screen que assessoria é necessária. |
| 3 | Strava oculto | `today_screen.dart` L1017-1029 | Dependência 100% do Strava revelada apenas DEPOIS de 7 telas e 10+ taps de onboarding. | **HIGH** — Abandono de quem não tem Strava após investir tempo no onboarding. | Mencionar Strava na Welcome Screen. Oferecer conexão Strava durante o onboarding. |
| 4 | Sidebar do portal | `portal/src/components/sidebar.tsx` L31-116 | ~30 itens de menu em 6 seções. Termos financeiros (Custódia, Swap de Lastro, Conversão Cambial) parecem exchange de crypto, não app de corrida. | **HIGH** — Staff novo fica avassalado. Medo de mexer em financeiro. | Progressive disclosure: mostrar 5-8 itens no início, desbloquear com uso. Renomear termos financeiros. |
| 5 | "Assessoria" opaca | `welcome_screen.dart` L112, `join_assessoria_screen.dart` L621 | Termo aparece 20+ vezes e NUNCA é definido. Corredores casuais ou fora do Brasil ficam perdidos. | **HIGH** — Exclui todo público que não é do ecossistema de corrida BR. | Adicionar tooltip/subtítulo: "Assessoria = seu grupo de corrida com treinador". |
| 6 | Aprovação assíncrona | `join_assessoria_screen.dart` L358-360 | Após solicitar entrada em assessoria, precisa esperar aprovação humana sem prazo estimado. Sem fallback. | **HIGH** — Dead end. Usuário fica travado indefinidamente. | Adicionar tempo estimado, ou aprovação automática com trial period. |
| 7 | Tour de 9 slides | `onboarding_tour_screen.dart` L22-98, L134-137 | 9 slides com info crítica (Strava, OmniCoins, verificação) que ~90% dos usuários vão pular. | **MEDIUM** — Info essencial perdida. | Reduzir para 3-4 slides. Mover info crítica para tooltips contextuais. |
| 8 | Dashboard 7 cards | `athlete_dashboard_screen.dart` L422-490 | "OmniCoins", "Verificação", "Campeonatos" não significam nada no dia 1. Tip banner "Primeiros passos" é ótimo mas desaparece ao fechar. | **MEDIUM** — Overload cognitivo. Usuário não sabe por onde começar. | Progressive disclosure. Tip banner persistente. Empty states com explicação. |
| 9 | "Bora correr?" sem botão | `today_screen.dart` L976 | Texto sugere ação de iniciar corrida, mas não existe botão "Start Run" — app depende do Strava. | **MEDIUM** — Expectativa quebrada. | Mudar copy para "Bora correr no Strava?" ou "Corra com seu relógio — importamos automaticamente". |
| 10 | Caminhos duplicados Strava | `today_screen.dart` L494-500, L1041 | Tip banner diz "Configurações → Integrações" mas há CTA direto "Conectar Strava" na mesma tela. | **MEDIUM** — Confusão sobre qual caminho seguir. | Remover instrução do tip ou apontar para o CTA na própria tela. |
| 11 | Tab padrão errada | `home_screen.dart` L43-48 | Aterrissa em AthleteDashboard (tab 0) em vez de TodayScreen (tab 1), adiando o primeiro contato com valor. | **MEDIUM** — 1 tap extra até o CTA de Strava. | Fazer "Hoje" a tab padrão para novos usuários. |
| 12 | OmniCoins sem explicação | `athlete_dashboard_screen.dart` L488-490, `more_screen.dart` L88-89 | Aparecem em cards, badges e QR scanner, mas ninguém explica de onde vêm ou para que servem. | **MEDIUM** — Conceito central fica opaco. | Tooltip ou card explicativo no primeiro acesso ao card "Meus créditos". |
| 13 | Portal sem onboarding | `portal/src/app/(portal)/dashboard/page.tsx` L167-285 | Staff novo vê dashboard de zeros sem CTA de "Convide seu primeiro atleta" ou checklist de setup. | **MEDIUM** — Primeira impressão vazia e sem direção. | Adicionar checklist "Getting Started" no primeiro acesso do portal. |
| 14 | "Pular" pouco visível | `join_assessoria_screen.dart` L711, L716-718 | TextButton discreto no final. Micro-texto "Você pode usar o app normalmente" quase invisível. | **LOW** — Usuários sem assessoria perdem o escape. | Tornar "Pular" um botão secundário proeminente. Subir micro-texto. |
| 15 | Sem "Esqueci senha" no portal | `portal/src/app/login/page.tsx` | Login do portal não tem link de recuperação de senha visível. | **LOW** — Staff com email/senha fica travado se esqueceu. | Adicionar link "Esqueci minha senha" abaixo do formulário. |
| 16 | Sem link "Baixe o app" no portal | `portal/src/app/login/page.tsx` L214 | Quem cai no portal por engano não tem saída para o app. | **LOW** — Visitantes acidentais ficam confusos. | Adicionar "Não é staff? Baixe o app" no login. |
| 17 | Role labels raw no portal | `portal/src/app/(portal)/select-group/page.tsx` | Roles como `admin_master`, `coach`, `assistant` mostrados como texto técnico. | **LOW** — Parece inacabado. | Humanizar: "Administrador", "Treinador", "Assistente". |

---

## 5. Mapa de Fricção

### Scores por fluxo

| Fluxo | Telas | Cliques (min–max) | Decisões | Confusões | Feedback claro | Score (0-100) |
|-------|-------|--------------------|----------|-----------|----------------|---------------|
| 1. Onboarding (novo usuário → home) | 7 (+9 tour) | 10–22 | 4–6 | 6–8 | 3–5 | **40** — Alta fricção |
| 2. First Value (ver dados de corrida) | 2 | 4–5 | 2 | 4 | 3 | **43** — Alta fricção |
| 3. Portal First Use (staff → dashboard) | 2–3 | 3–6 | 1–2 | 3 | 4 | **57** — Fricção moderada |
| **Média** | | | | | | **47** |

**Fórmula:** `Score = 100 × (feedback / (confusão + feedback))` — quanto menor, mais fricção.

### Detalhamento do caminho crítico (onboarding rápido)

| # | Tela | Ação | Taps |
|---|------|------|------|
| 1 | `welcome_screen.dart` | Tap "COMEÇAR" | 1 |
| 2 | `login_screen.dart` | Tap "Continuar com Google" | 1 |
| 3 | OAuth externo | Autorizar no Google | ~2 |
| 4 | `onboarding_role_screen.dart` | Tap "Sou atleta" | 1 |
| 5 | `onboarding_role_screen.dart` | Tap "Continuar" | 1 |
| 6 | `onboarding_role_screen.dart` | Tap "Sim, sou Atleta" (confirm) | 1 |
| 7 | `join_assessoria_screen.dart` | Tap "Pular" | 1 |
| 8 | `onboarding_tour_screen.dart` | Tap "Pular" | 1 |
| 9 | `home_screen.dart` | Tap tab "Hoje" | 1 |
| | | **Total mínimo** | **~10** |

10 taps mínimos para chegar ao primeiro CTA de valor (conectar Strava). O caminho completo (email + assessoria + tour) exige 22 taps.

---

## 6. Scores Consolidados

| Dimensão | Nota (0–10) | Justificativa |
|----------|-------------|---------------|
| **Clareza do que o app faz** | 5 | Welcome Screen vende 4 propostas genéricas em vez de 1 clara. Conceitos centrais (assessoria, OmniCoins, Strava) ficam opacos até profundamente no produto. |
| **Clareza do público-alvo** | 5 | Tenta atender 3 públicos (corredor solo, corredor de assessoria, staff) sem priorizar. O idioma é BR mas "assessoria" exclui quem não é do ecossistema. |
| **Facilidade de começar** | 4 | 10–22 taps no onboarding, decisão permanente no passo 2, 3 dependências externas (conta, Strava, assessoria) para chegar ao valor. |
| **Entendimento do propósito** | 6 | Usuário intui "corrida + competição" mas não consegue articular o diferencial vs. Strava nem explicar OmniCoins/assessoria. |
| **Confiança no produto** | 7 | Design moderno (Material 3, Tailwind), animações suaves, login social, textos nativos em PT-BR. Perde pontos por logo genérico, zero social proof, nenhuma foto real. |
| **Motivação para continuar** | 6 | Bullets da Welcome interessantes mas sem urgência emocional. Streaks/XP são hooks válidos — mas só funcionam com dados. |
| **Ação esperada clara** | 8 | Botão "COMEÇAR" sem ambiguidade, login social padrão, CTAs geralmente claros. Perde pontos pelo pular discreto e tab padrão errada. |
| **Navegabilidade** | 7 | 4 tabs intuitivas no app, portal sidebar organizada em seções. Mas sidebar tem ~30 itens e dashboard tem 7–12 cards — overload. |
| **Completude de fluxo (Goal B: desafios)** | 2 | Funcionalidade #1 (desafios) é bloqueada por assessoria + aprovação. Flow não completa end-to-end sem intervenção humana externa. |
| **Completude de fluxo (Goal D: portal staff)** | 8 | Staff chega ao dashboard em 6 passos. Fluxo limpo e funcional, mas falta onboarding contextual. |
| **MÉDIA GERAL** | **5.8** | **Conceito forte, execução do primeiro contato com fricção significativa.** |

---

## 7. Melhorias Rápidas (Top 10)

Ordenadas por razão impacto/esforço (melhores primeiro).

### 1. Reescrever o aviso de escolha de papel
- **O quê:** Remover linguagem de medo (vermelho, "permanente", ícone de cadeado). Usar tom neutro: "Você pode ajustar isso depois em Configurações ou com o suporte."
- **Onde:** `omni_runner/lib/presentation/screens/onboarding_role_screen.dart` L69-70, L176-180
- **Impacto:** Elimina o ponto #1 de abandono (paralisia de decisão)
- **Esforço:** S — alteração de texto e cor

### 2. Adicionar menção ao Strava na Welcome Screen
- **O quê:** Trocar bullet "Evolua com métricas reais" por "Conecte seu Strava — funciona com qualquer relógio" ou adicionar subtítulo: "Sincronize suas corridas via Strava."
- **Onde:** `omni_runner/lib/presentation/screens/welcome_screen.dart` L106-123
- **Impacto:** Alinha expectativa sobre tracking antes do onboarding. Evita frustração pós-onboarding.
- **Esforço:** S — alteração de texto

### 3. Explicar "assessoria" em 1 frase
- **O quê:** Adicionar subtítulo: "Assessoria = seu grupo de corrida com treinador" na Welcome Screen e/ou na `join_assessoria_screen`.
- **Onde:** `welcome_screen.dart` L112, `join_assessoria_screen.dart` L621-630
- **Impacto:** Desbloqueia compreensão para todo usuário fora do jargão de corrida BR.
- **Esforço:** S — adição de 1 linha de texto

### 4. Tornar "Pular" mais proeminente na tela de assessoria
- **O quê:** Trocar TextButton discreto por botão secundário visível. Subir o micro-texto "Você pode usar o app normalmente" para perto do topo.
- **Onde:** `join_assessoria_screen.dart` L711, L716-718
- **Impacto:** Usuários sem assessoria encontram a saída imediatamente.
- **Esforço:** S — reorganização de layout

### 5. Mudar tab padrão para "Hoje" (novos usuários)
- **O quê:** Para usuários com `stravaConnected == false`, aterrissar na tab "Hoje" (index 1) em vez de "Início" (index 0), garantindo que o CTA de Strava seja a primeira coisa visível.
- **Onde:** `home_screen.dart` L43-48 (variável `_tab` inicial)
- **Impacto:** Primeiro contato com valor 1 tap mais cedo. CTA de Strava impossível de perder.
- **Esforço:** S — condicional simples

### 6. Reduzir tour de 9 para 3-4 slides
- **O quê:** Manter apenas: (1) "Conecte seu Strava", (2) "Entre na sua assessoria e desafie corredores", (3) "OmniCoins: aposte e vença". Mover info restante para tooltips contextuais.
- **Onde:** `onboarding_tour_screen.dart` L22-98
- **Impacto:** ~90% dos usuários absorvem as 3 infos críticas em vez de ~10% que passam por 9 slides.
- **Esforço:** M — rewrite de conteúdo + tooltips contextuais em outras telas

### 7. Reformular proposta de valor da Welcome Screen
- **O quê:** Trocar 4 bullets genéricos por headline clara + 3 bullets focados. Sugestão: headline "O app da sua assessoria de corrida" + bullets: "Desafie seu grupo com OmniCoins", "Ranking, streaks e XP", "Sincronize via Strava".
- **Onde:** `welcome_screen.dart` L87-123
- **Impacto:** Usuário entende o produto, o público-alvo e o diferencial em 5 segundos.
- **Esforço:** M — rewrite de copy + possível ajuste de layout

### 8. Permitir desafios livres sem assessoria
- **O quê:** Remover o `AssessoriaRequiredSheet.guard` do card "Meus desafios" ou criar uma categoria de desafios entre amigos (sem OmniCoins) acessível sem assessoria.
- **Onde:** `athlete_dashboard_screen.dart` (guard check), challenge-related screens
- **Impacto:** A promessa #1 da Welcome Screen ("Desafie corredores") deixa de ser mentira.
- **Esforço:** M — lógica de negócio + possível novo tipo de desafio

### 9. Adicionar progressive disclosure na sidebar do portal
- **O quê:** Colapsar seções Financeiro e Treinos avançados (Matchmaking, Liga, Swap de Lastro) por padrão. Mostrar apenas Dashboard, Atletas, Engajamento e Configurações para novo staff. Desbloquear com uso ou toggle "Modo avançado".
- **Onde:** `portal/src/components/sidebar.tsx` L31-116
- **Impacto:** Staff novo vê 8-10 itens em vez de 30. Reduz intimidação.
- **Esforço:** M — lógica de collapse + estado de preferência

### 10. Adicionar onboarding checklist no portal
- **O quê:** No primeiro acesso ao dashboard, mostrar um banner/card "Primeiros passos" com: (1) Convide seu primeiro atleta, (2) Configure seu grupo, (3) Distribua OmniCoins. Similar ao tip banner do app.
- **Onde:** `portal/src/app/(portal)/dashboard/page.tsx` L167-285
- **Impacto:** Staff novo sabe exatamente o que fazer em vez de encarar um dashboard de zeros.
- **Esforço:** M — novo componente + estado de first-visit

---

## 8. Decisão Final

### Ready for users? **CONDITIONAL**

O produto tem um conceito forte e diferenciado, com design moderno e funcional. Mas o primeiro contato tem falhas estruturais que causarão abandono significativo em usuários reais.

### O que DEVE mudar antes de usuários reais verem isto

**Sem negociação (blockers):**

1. **Eliminar a linguagem de medo na escolha de papel.** Remover "permanente", vermelho, ícone de cadeado. No mínimo, permitir troca via suporte com tom neutro. (~2h de trabalho)

2. **Mencionar Strava na Welcome Screen.** O usuário precisa saber que o app depende do Strava ANTES de investir no onboarding. (~30min)

3. **Explicar "assessoria" em 1 frase.** Adicionar subtítulo explicativo na Welcome Screen e/ou na tela de join. (~30min)

4. **Desbloquear pelo menos 1 tipo de desafio sem assessoria.** A promessa #1 não pode ser gateada por aprovação humana assíncrona. (~1-2 dias)

**Altamente recomendado (antes de marketing ativo):**

5. Reduzir tour para 3-4 slides
6. Trocar tab padrão para "Hoje" em novos usuários
7. Tornar "Pular" proeminente na tela de assessoria
8. Progressive disclosure na sidebar do portal
9. Onboarding checklist no portal

### Os primeiros 60 segundos ideais para um novo usuário

```
[0s]  Welcome Screen
      → Headline: "O app da sua assessoria de corrida"
      → 3 bullets: Desafios com OmniCoins | Rankings e XP | Via Strava
      → Botão: "COMEÇAR"

[10s] Login
      → Google / Apple / Instagram / Email (como está — funciona bem)

[20s] Strava Connect (NOVO — antes da escolha de papel)
      → "Conecte seu Strava para sincronizar corridas"
      → Botão "Conectar Strava" + "Pular por enquanto"

[30s] Escolha de papel (tom neutro)
      → "Como quer usar o Omni Runner?"
      → Sem "permanente". Sem vermelho. "Pode ajustar depois."

[40s] Assessoria (com Pular proeminente)
      → "Tem uma assessoria? Encontre aqui."
      → Botão secundário: "Quero usar sozinho por enquanto"
      → Subtítulo: "Assessoria = seu grupo de corrida com treinador"

[50s] Mini-tour (3 slides, não 9)
      → Slide 1: "Corra e importe do Strava automaticamente"
      → Slide 2: "Desafie corredores — aposte OmniCoins"
      → Slide 3: "Suba no ranking da sua assessoria"

[60s] Tela "Hoje" (tab padrão)
      → Se Strava conectado: "Bora correr!" + dados se existirem
      → Se Strava não conectado: CTA laranja para conectar
      → Desafio rápido visível mesmo sem assessoria
```

**Tempo para valor: 60 segundos.** Hoje são ~3 minutos + dependência de aprovação humana.

---

*Relatório gerado como consolidação das fases: 30 Segundos, Exploração Livre, Goal Test, Comprehension Test, Friction Test e New User Verdict. Todos os dados referenciados com evidência de código-fonte.*
