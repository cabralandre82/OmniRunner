# COLD MARKET TEST — FASE 4: ONBOARDING REAL

**App:** Omni Runner  
**Data:** 04/03/2026  
**Perspectiva:** Usuário com ZERO contexto, primeira vez abrindo o app  

---

## 1. Fluxo Completo de Onboarding (Tela por Tela)

### Tela 1 — Welcome Screen
- **O que vê:** Ícone de corredor, título "Seu app de corrida completo", subtítulo "Treinos, desafios, métricas e assessoria — tudo em um app"
- **Bullets animados:**
  - Corra com GPS preciso
  - Desafie outros corredores
  - Acompanhe sua evolução
  - Treine com assessoria ou sozinho
- **CTA:** Botão "COMEÇAR"
- **Campos:** 0
- **Decisões:** 1 (tocar "COMEÇAR")
- **Permissões:** 0

### Tela 2 — Login Screen
- **O que vê:** Ícone de corredor, "Entrar no Omni Runner", subtítulo explicando sincronização
- **Opções de autenticação:**
  - Continuar com Google
  - Continuar com Apple (somente iOS)
  - Continuar com Instagram
  - Continuar com Email (expande formulário com email + senha)
- **Link:** Política de Privacidade
- **Campos:** 0 (social login) ou 2 (email + senha)
- **Decisões:** 1 (escolher método de login)
- **Permissões:** 0

### Tela 3 — Onboarding Role Screen
- **O que vê:** "Como você quer usar o Omni Runner?"
- **Subtítulo:** "Você pode ajustar isso depois em Configurações."
- **Opções (cards com rádio):**
  - "Sou atleta" — Treinar, competir em desafios e acompanhar minha evolução
  - "Represento uma assessoria" — Gerenciar atletas, organizar eventos e acompanhar o grupo
- **Dialog de confirmação:** Descreve a experiência escolhida + aviso de que pode mudar em Configurações
- **Campos:** 0
- **Decisões:** 1 (escolher papel) + 1 (confirmar no dialog)
- **Permissões:** 0

### Tela 4 — Join Assessoria Screen (apenas atletas)
- **O que vê:** "Encontre sua assessoria"
- **Explicação:** "Assessoria é seu grupo de corrida com treinador"
- **4 formas de entrar:**
  1. Buscar por nome (campo de texto com debounce)
  2. Escanear QR code (abre câmera)
  3. Inserir código manualmente (dialog)
  4. **Pular** — "Pular — posso entrar depois"
- **Texto de suporte:** "Você pode usar o app normalmente. Assessoria desbloqueia ranking de grupo e desafios em equipe."
- **Convites pendentes:** Mostra se existirem (botão "Aceitar")
- **Campos:** 0-1 (busca opcional)
- **Decisões:** 1 (buscar assessoria ou pular)
- **Permissões:** 0-1 (câmera, somente se escanear QR)

### Tela 5 — Onboarding Tour Screen (9 slides, skipável)
- **O que vê:** Tour com 9 slides swipáveis:
  1. Conecte seu Strava
  2. Desafie outros corredores
  3. Treine com sua assessoria
  4. Mantenha sua sequência (streak)
  5. Acompanhe sua evolução
  6. Encontre amigos
  7. Desafie seus amigos (3 tipos de desafio)
  8. OmniCoins
  9. Atleta Verificado
- **Botão "Pular"** no topo direito
- **Botão "PRÓXIMO"** embaixo (último slide: "COMEÇAR A CORRER")
- **Campos:** 0
- **Decisões:** 0 (pode pular a qualquer momento)
- **Permissões:** 0

### Tela 6 — Home Screen (destino final)
- **Tab padrão:** "Hoje" (index 1)
- **Tabs:** Início, Hoje, Histórico, Mais
- **TipBanner de primeiro uso:** "Primeiros passos: 1. Conecte seu Strava... 2. Entre em assessoria... 3. Crie um desafio... 4. Complete corridas para verificação"

---

## 2. Campos Solicitados por Etapa

| Etapa | Campos obrigatórios | Campos opcionais |
|-------|---------------------|------------------|
| Welcome | 0 | 0 |
| Login (social) | 0 | 0 |
| Login (email) | 2 (email, senha) | 0 |
| Role Selection | 0 | 0 |
| Join Assessoria | 0 | 1 (busca) |
| Tour | 0 | 0 |
| **TOTAL (social)** | **0** | **1** |
| **TOTAL (email)** | **2** | **1** |

---

## 3. Decisões Obrigatórias

| # | Decisão | Peso Cognitivo |
|---|---------|----------------|
| 1 | Tocar "COMEÇAR" | Baixo |
| 2 | Escolher método de login | Médio |
| 3 | Escolher papel (atleta vs assessoria) | Médio |
| 4 | Confirmar papel no dialog | Baixo |
| 5 | Buscar assessoria ou pular | Médio |
| 6 | Avançar ou pular o tour | Baixo |
| **TOTAL** | **6 decisões** | |

---

## 4. Análise de Fricção

### Necessário vs Desnecessário

| Etapa | Necessário? | Justificativa |
|-------|-------------|---------------|
| Welcome Screen | SIM | Comunica proposta de valor. Rápida (1 toque). Sem formulários. |
| Login | SIM | Obrigatório para sincronização e funcionalidades online. Social login reduz fricção. |
| Role Selection | SIM | O app tem experiências fundamentalmente diferentes para atleta e staff. A escolha molda toda a UX. |
| Dialog de confirmação | PARCIALMENTE | Evita erros, mas adiciona 1 toque extra. Mensagem é útil (avisa que pode mudar depois). |
| Join Assessoria | SIM, mas com ressalva | É importante para o valor do app, MAS o "Pular" bem posicionado permite adiamento. O timing é questionável — um usuário novo não sabe o que é "assessoria". |
| Tour (9 slides) | PARCIALMENTE | O conteúdo é relevante, mas 9 slides é LONGO. O botão "Pular" mitiga, mas quem lê tudo pode sentir fadiga. 5-6 slides seria ideal. |

### Pontos de Fricção Identificados

1. **Tour com 9 slides:** Excessivo para primeiro contato. O usuário ainda não sabe o que é OmniCoin, Verificação ou DNA do Corredor. Esses conceitos só fazem sentido após uso.
2. **"Assessoria" no onboarding:** Termo específico do universo de corrida brasileiro. Usuário casual pode não saber o que é. A explicação "grupo de corrida com treinador" ajuda, mas o timing é prematuro.
3. **Confirmação de papel com dialog:** Duplo toque para algo que o próprio app diz ser ajustável depois. Fricção baixa, mas questionável.

### Pontos Positivos

1. **Zero campos obrigatórios com social login.** Onboarding sem digitação.
2. **"Pular" sempre visível.** Assessoria e tour são opcionais.
3. **Explicações contextuais.** Cada tela explica o que está pedindo e por quê.
4. **Animações suaves.** Welcome Screen com fade-in sequencial transmite qualidade.
5. **Deep link preservado.** Se o usuário veio via convite, o código sobrevive o fluxo de login.
6. **TipBanner no dashboard.** Após o onboarding, o app ainda guia os primeiros passos.

---

## 5. O onboarding é necessário?

**SIM.** O app tem dois perfis fundamentalmente diferentes (atleta vs staff da assessoria) e o login é obrigatório para funcionalidades core (desafios, sincronização, assessoria). Sem onboarding estruturado, o app não sabe o que mostrar ao usuário.

**Porém:** O tour de 9 slides poderia ser substituído por tips contextuais in-app (que o app já usa via `TipBanner`). O onboarding estrutural (login + role + assessoria) é indispensável. O tour é dispensável.

---

## 6. O onboarding é longo demais?

**PARCIALMENTE.** O caminho mínimo (social login + role + pular assessoria + pular tour) leva o usuário ao app em **4 telas e ~30 segundos**. Isso é excelente.

O caminho máximo (email login + role + buscar assessoria + ler 9 slides do tour) pode levar **3-5 minutos**. Isso é demais para um primeiro contato.

**Diagnóstico:** O onboarding tem um piso excelente e um teto alto demais. O teto é controlado pelo usuário (pode pular tudo), mas a existência de 9 slides no tour sugere ambição excessiva de ensinar tudo antes do primeiro uso.

---

## 7. O onboarding comunica valor?

**SIM, mas com distribuição desigual.**

- **Welcome Screen:** Excelente. 4 bullets claros, frase de posicionamento direta.
- **Login Screen:** Não comunica valor — é funcional, como esperado.
- **Role Selection:** Comunica diferença entre perfis. Subtextos nas opções são claros.
- **Join Assessoria:** Comunica valor de forma moderada. Explica que assessoria "desbloqueia ranking de grupo e desafios em equipe" — bom.
- **Tour:** Comunica MUITO valor, talvez demais de uma vez. O usuário não tem contexto para absorver 9 conceitos simultâneos (Strava, desafios, assessoria, streak, evolução, amigos, tipos de desafio, OmniCoins, verificação).

**Problema central:** O valor é comunicado verbalmente (texto), não demonstrado. O usuário lê sobre features em vez de experimentá-las. O TipBanner pós-onboarding com os 4 primeiros passos é, ironicamente, mais eficaz que o tour inteiro.

---

## 8. Ratings

| Critério | Nota (0-10) | Justificativa |
|----------|-------------|---------------|
| **Duração** | 7/10 | Caminho mínimo é curto e rápido. Tour opcional inflaciona o máximo, mas é skipável. |
| **Clareza** | 8/10 | Cada tela explica o que pede. Linguagem simples, em português. Nenhum campo confuso. |
| **Necessidade** | 8/10 | Login e role são indispensáveis. Assessoria é quase necessária. Tour é excessivo. |
| **Comunicação de Valor** | 6/10 | Welcome é boa, tour é informativo mas sobrecarrega. Falta demonstração prática (show, don't tell). |

---

## Resumo Executivo

O onboarding do Omni Runner é **estruturalmente sólido**: pede apenas o essencial (login + papel), permite pular o que não é urgente (assessoria, tour), e não requer preenchimento de perfil. A experiência mínima é rápida e sem fricção.

**Oportunidade de melhoria principal:** Reduzir o tour de 9 para 4-5 slides focados nas ações imediatas (Strava, desafios, assessoria), e confiar mais nos TipBanners contextuais que já existem no app para ensinar features avançadas (OmniCoins, verificação, DNA) quando o usuário encontrá-las organicamente.

**Veredicto final:** Onboarding BOM, com potencial para ser EXCELENTE se o tour for encurtado.
