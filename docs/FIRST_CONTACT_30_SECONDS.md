# First-Contact Test — Primeiros 30 Segundos

**Data:** 2026-03-04
**Testador:** Usuário simulado, completamente novo, nunca viu o produto.

---

## APP — Welcome Screen

### O que eu vejo

Abro o app no celular. Aparece um ícone grande de uma pessoa correndo (Material Icon `directions_run_rounded`, 96px, cor primária) que desliza de cima com fade-in. Abaixo, o nome **"Omni Runner"** em headline bold.

Depois de ~0.5s, quatro bullets aparecem com fade:

| Ícone                  | Texto                          |
|------------------------|--------------------------------|
| `emoji_events_outlined`  | "Desafie corredores"           |
| `groups_outlined`        | "Treine com sua assessoria"    |
| `military_tech_outlined` | "Participe de campeonatos"     |
| `insights_outlined`      | "Evolua com métricas reais"    |

Na parte inferior, um botão grande cheio (FilledButton) com o texto **"COMEÇAR"**.

**Evidência:** `welcome_screen.dart:87-93` — `'Omni Runner'`; linhas 106-123 — bullets; linha 146 — `'COMEÇAR'`

---

## PORTAL — Landing Page

Acesso `portal/` no navegador. O `page.tsx` raiz faz `redirect("/dashboard")`, que — sem autenticação — provavelmente redireciona para `/login`.

Na tela de login vejo:
- Título **"Omni Runner"** (h1, bold, 2xl)
- Subtítulo **"Portal da Assessoria"** (texto secundário, sm)
- Botão **"Entrar com Google"** (com ícone Google colorido)
- Botão **"Entrar com Apple"** (fundo preto, ícone Apple branco)
- Divisor com texto **"ou"**
- Formulário de e-mail/senha com campos "E-mail" (placeholder: `seu@email.com`) e "Senha" (placeholder: `••••••••`)
- Botão **"Entrar com e-mail"** (fundo `bg-brand`)
- Mensagem de erro condicional: "E-mail ou senha inválidos" / "Falha na autenticação"

**Evidência:** `portal/src/app/login/page.tsx:213` — `'Omni Runner'`; linha 214 — `'Portal da Assessoria'`; linha 95 — `'Entrar com Google'`; linha 111 — `'Entrar com Apple'`; linha 176 — `'Entrar com e-mail'`

---

## Respostas como usuário novo

### 1. O que eu acho que este app faz?

**App:** Parece um app de corrida social/competitivo. Os bullets me dizem que posso desafiar outros corredores, treinar com um grupo ("assessoria"), participar de campeonatos e ver métricas. Parece tipo um Strava com elementos de gamificação e foco em grupos de treino.

**Portal:** Parece ser o painel administrativo de quem gerencia um desses grupos de treino ("assessoria"). A palavra "Portal da Assessoria" me diz que o produto tem dois lados: o app para o atleta e o portal para o treinador/gestor.

### 2. Para quem parece ser?

Para **corredores brasileiros** que treinam em grupos (assessorias de corrida). O idioma é português brasileiro, e o conceito de "assessoria esportiva" é muito específico da cultura de corrida no Brasil. Público secundário: os treinadores/gestores dessas assessorias (portal).

### 3. O que o produto quer que eu faça primeiro?

**App:** Tocar "COMEÇAR" — é o único botão na tela, claro e sem ambiguidade.
**Portal:** Fazer login com Google, Apple ou e-mail/senha. Não há opção de cadastro visível no portal (faz sentido, é para staff já existente).

### 4. O que é confuso nos primeiros 30 segundos?

- **"Assessoria"** — Se eu não sou do mundo da corrida brasileira, não faço ideia do que é isso. Nenhuma explicação ou tooltip. Um corredor casual de outro país ficaria perdido.
- **"Desafie corredores"** — Desafiar como? Corrida real? Virtual? Aposta? Não está claro o formato.
- **"Evolua com métricas reais"** — O que são "métricas reais"? Isso gera a pergunta: de onde vêm os dados? Relógio? GPS do celular? Strava? Nada é dito aqui.
- **Portal:** "Portal da Assessoria" — ok, se eu sou staff já sei, mas não há zero contexto para quem cai aqui por engano. Nenhum link "Não é assessoria? Baixe o app".
- **Nenhuma imagem real** — A welcome screen usa apenas ícones Material Design genéricos. Nenhuma foto de corredor, nenhum screenshot do app em uso. Parece "em construção" mais do que "polished product".

### 5. Impressão visual

| Aspecto          | App Welcome                     | Portal Login                      |
|------------------|---------------------------------|-----------------------------------|
| **Modernidade**  | Moderno. Animações de fade/slide são suaves (1400ms). Material 3 com FilledButton, design system com tokens. | Moderno. Tailwind, rounded-xl, shadow-lg, botões com hover states. |
| **Profissionalismo** | Profissional mas genérico. Sem identidade visual forte — poderia ser qualquer app. Falta um logo real (usa ícone Material genérico). | Profissional. Layout limpo, centralizado, bom espaçamento. |
| **Minimalismo**  | Sim, poucos elementos. Poderia ter 1-2 imagens para humanizar. | Sim, bom. Formulário conciso. |
| **Confiança**    | Média. Sem social proof, sem número de usuários, sem ratings. | OK. Tem login social (Google/Apple), o que gera confiança. |
| **Nota geral**   | 7/10 — Limpo e funcional, mas falta personalidade. | 7.5/10 — Simples e eficaz, mas também genérico. |

---

## Resumo Executivo (30 segundos)

| Dimensão                          | Nota |
|-----------------------------------|------|
| Clareza do que o app faz          | 7/10 — Entendo que é corrida + competição, mas "assessoria" é opaco |
| Clareza do público-alvo           | 6/10 — Claramente Brasil, mas "assessoria" exclui corredores casuais |
| Clareza da ação esperada          | 9/10 — "COMEÇAR" no app, formulário de login no portal. Sem ambiguidade. |
| Impressão de profissionalismo     | 7/10 — Moderno mas genérico. Falta identidade visual. |
| Motivação para continuar          | 6/10 — Bullets interessantes, mas falta urgência ou gancho emocional. |
