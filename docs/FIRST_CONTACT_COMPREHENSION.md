# FASE 4 — Comprehension Test

**Tester:** UX Researcher (first-time user, no docs, no backend code)
**Date:** 2026-03-04
**Method:** Evaluated all user-facing screens in `omni_runner/lib/presentation/screens/`

---

## Q1: Eu entendi o que este produto faz?

**Resposta: PARCIALMENTE SIM**

### O que entendi

O Omni Runner é um app de corrida focado em **competição social**: desafios 1v1/grupo/time entre corredores, dentro de "assessorias" (grupos de treino com professor). Ele importa dados do Strava, gamifica a experiência com XP/badges/streaks, e adiciona uma moeda virtual (OmniCoins) para apostas em desafios.

### Onde o entendimento falhou

**O app NÃO rastreia corridas.** Isso é a maior surpresa. Em nenhum momento na Welcome Screen ou no Onboarding Tour fica claro que o app depende 100% do Strava. O usuário descobre isso somente na tela "Hoje", quando vê o prompt "Conecte o Strava para começar" — vários passos após o onboarding completo.

- **Tela:** `today_screen.dart`, linhas 1017-1021
- **Texto visível:** `'Conecte o Strava para começar'` e `'O Omni Runner importa suas corridas direto do Strava.'`
- **Expectativa do usuário:** Ao ver "Bora correr?" (linha 976), o usuário espera um botão "Iniciar Corrida". Não existe esse botão em nenhuma tela.
- **Correção:** Na Welcome Screen, adicionar um subtítulo como *"Conecte seu Strava ou relógio — nós fazemos o resto"* para alinhar a expectativa antes mesmo do login.

O Onboarding Tour *menciona* Strava no slide 1 (`onboarding_tour_screen.dart`, linhas 26-29: `'Suas corridas são importadas automaticamente do Strava'`), mas como o tour tem 9 slides e o botão "Pular" está bem visível, é provável que o usuário pule o tour inteiro e nunca veja essa informação.

---

## Q2: Eu entendi para quem ele é?

**Resposta: NÃO**

### O que me confundiu

O app tenta atender **três públicos distintos** sem deixar claro qual é o principal:

1. **Corredor solo** — quer rastrear corridas e ver progresso pessoal
2. **Corredor de assessoria** — treina com professor, quer ranking do grupo
3. **Staff de assessoria** — quer gerenciar atletas, criar campeonatos

A tela de escolha de papel (`onboarding_role_screen.dart`) apresenta isso como uma bifurcação binária e permanente:

- **Tela:** `onboarding_role_screen.dart`, linhas 187-203
- **Texto visível:** `'Sou atleta'` vs. `'Represento uma assessoria'`
- **Problema:** O subtítulo do atleta diz `'Treinar, competir em desafios e acompanhar minha evolução'` — parece que posso usar o app sozinho. Mas na prática, desafios requerem assessoria.

O texto de aviso é ameaçador:
- **Tela:** `onboarding_role_screen.dart`, linhas 176-179
- **Texto visível:** `'Essa escolha é permanente e define toda a sua experiência no app.'`
- **Texto no diálogo:** `'Essa escolha é permanente e não pode ser alterada depois.'` (linha 69)
- **Expectativa:** Eu esperava poder explorar livremente e depois decidir. A permanência me dá medo de errar.
- **Correção:** Remover a permanência ou reduzir a linguagem de medo. A maioria dos apps permite trocar de perfil. Se é realmente irreversível por razões técnicas, explicar *por quê*.

O welcome screen (linhas 107-123) mistura mensagens:
- `'Desafie corredores'` → sugere competição casual entre amigos
- `'Treine com sua assessoria'` → sugere que preciso de um professor
- `'Participe de campeonatos'` → sugere competição formal entre equipes
- `'Evolua com métricas reais'` → sugere ferramenta de análise pessoal

São 4 propostas de valor para 4 públicos diferentes, apresentadas como se fossem uma coisa só.

**Correção:** Na Welcome Screen, escolher UMA proposta de valor primária. Sugestão: *"O app de corrida da sua assessoria"* — posiciona claro que é para corredores em grupos de treino. O corredor solo é atendido como caso secundário.

---

## Q3: Eu entendi qual problema ele resolve?

**Resposta: NÃO**

### O que me confundiu

Eu não consigo articular qual problema o Omni Runner resolve que o Strava, Nike Run Club, ou uma planilha já não resolvam.

**Tracking de corrida?** O app não rastreia — depende do Strava.

**Competição?** Strava tem segmentos, clubs, e challenges nativos. O diferencial aqui seria OmniCoins e o sistema de assessorias, mas isso só fica claro muito profundamente no app.

**Gestão de assessoria?** Isso é um problema real — professores de corrida no Brasil gerenciam grupos via WhatsApp + planilhas. Mas a Welcome Screen não fala com esse público.

O problema real que o app parece resolver é: **"assessorias de corrida não têm uma plataforma integrada para gerenciar atletas, criar competições internas, e engajar o grupo com gamificação."**

Mas a tela que DEVERIA comunicar isso (`welcome_screen.dart`) não menciona "assessoria" como conceito central. A palavra "assessoria" aparece apenas no bullet 2 (`'Treine com sua assessoria'`, linha 112), embutida entre outros bullets genéricos.

- **Tela:** `welcome_screen.dart`, linhas 104-124
- **Texto visível:** Os 4 bullets (Desafie corredores / Treine com sua assessoria / Participe de campeonatos / Evolua com métricas reais)
- **Expectativa:** Se o problema é "assessorias não têm plataforma", eu esperaria ver: *"O app oficial da sua assessoria de corrida"* como headline, com bullets sobre funcionalidades específicas (ranking do grupo, treinos do professor, desafios entre alunos).
- **Alternativas mentais do usuário:** "Posso fazer tudo isso no Strava. Por que preciso de outro app?"
- **Correção:** Reformular a proposta de valor da Welcome Screen para posicionar a assessoria como centro. Exemplo: *"Seu grupo de corrida, agora com superpoderes."*

---

## Q4: Eu conseguiria explicar este app para outra pessoa?

**Resposta: PARCIALMENTE**

### O que eu diria (tentativa de elevator pitch)

> "O Omni Runner é um app para assessorias de corrida. Ele conecta com o Strava, pega seus dados de corrida e usa pra criar desafios com outros corredores, ranking no grupo, e um sistema de moedas virtuais."

### O que está faltando para eu conseguir dizer com confiança

1. **Não sei se o app funciona sem assessoria.** O onboarding deixa pular a assessoria, mas depois bloqueia funcionalidades. A mensagem é contraditória.

2. **Não sei o que são OmniCoins na prática.** O onboarding tour diz `'Suas OmniCoins vêm da sua assessoria de corrida'` (`onboarding_tour_screen.dart`, linhas 86-87), mas não explica como a assessoria distribui, nem o que o corredor faz com elas além de apostar em desafios.

3. **Não sei o que "Atleta Verificado" muda.** O tour menciona `'Complete 7 corridas válidas para se tornar Verificado'` (linhas 93-96) mas um novo usuário não sabe o que "válidas" significa, nem por que precisaria ser verificado antes de simplesmente correr.

4. **Não consigo explicar o diferencial vs. Strava.** Se alguém me perguntar "por que não uso o Strava direto?", eu não teria resposta clara baseada apenas no que as telas me mostraram.

### O que corrigiria isso

A Welcome Screen precisa de uma **single clear sentence** que posicione o app. Sugestão:

> **"O app da sua assessoria de corrida. Desafios entre alunos, ranking do grupo, e gamificação — tudo sincronizado com seu Strava."**

Isso comunica:
- Para quem é (alunos de assessoria)
- O que faz (desafios, ranking, gamificação)
- Como funciona (sincroniza com Strava — não substitui)
- O que o diferencia (assessoria-first)

---

## Resumo de Issues

| # | Tela | Problema | Impacto | Correção |
|---|------|----------|---------|----------|
| 1 | `welcome_screen.dart` L104-124 | 4 bullets genéricos, nenhuma proposta clara | Usuário não entende o que o app faz | Reformular com headline + 3 bullets focados em assessoria |
| 2 | `welcome_screen.dart` L104-124 | Nenhuma menção a Strava como requisito | Usuário espera rastrear corridas no app | Adicionar "Conecte seu Strava" na Welcome Screen |
| 3 | `onboarding_role_screen.dart` L69-70 | Escolha permanente e irreversível de papel | Ansiedade e medo de errar | Permitir troca ou reduzir linguagem de medo |
| 4 | `onboarding_role_screen.dart` L190 | "Sou atleta" sugere uso solo, mas app requer assessoria | Expectativa quebrada ao acessar desafios | Reformular subtitle para mencionar assessoria |
| 5 | `today_screen.dart` L976 | "Bora correr?" sem botão de iniciar corrida | Expectativa de botão "Start Run" | Mudar copy para "Bora correr no Strava?" ou similar |
| 6 | `athlete_dashboard_screen.dart` L214 | Desafios bloqueados sem assessoria | Contradiz proposta de valor #1 da Welcome Screen | Permitir desafios livres entre amigos (sem assessoria) |
| 7 | `onboarding_tour_screen.dart` L22-98 | 9 slides — informação demais, fácil de pular | Informação crítica (Strava, OmniCoins) é perdida | Reduzir para 3-4 slides. Mover info crítica para telas contextuais |
