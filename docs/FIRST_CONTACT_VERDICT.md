# FASE 6 — New User Verdict

**Data:** 2026-03-04
**Testador:** UX Researcher (usuário simulado, completamente novo)
**Tempo simulado:** ~10 minutos com o produto
**Método:** Análise de todas as telas user-facing do app (`omni_runner/lib/presentation/screens/`) e portal (`portal/src/app/`)

---

## Eu continuaria usando?

**Resposta: MAYBE**

### Por que ficaria

1. **O conceito é forte.** Competição social entre corredores com moeda virtual é um hook legítimo. Strava tem segmentos e clubs, mas nenhum sistema de apostas (OmniCoins) ou campeonatos internos de assessoria. Isso é um diferencial real.

2. **O ecossistema assessoria-atleta resolve um problema real.** Professores de corrida no Brasil gerenciam tudo via WhatsApp + planilha. Uma plataforma integrada (portal para staff + app para atleta) com ranking, créditos e gestão de membros é uma proposta de valor clara — para quem entende o que é.

3. **Streaks + XP + badges são vícios funcionais.** O sistema de gamificação (`today_screen.dart` streak banner, milestones, XP) me manteria abrindo o app diariamente, desde que eu já tenha corridas sincronizadas.

4. **A integração Strava é a decisão técnica correta.** Não reinventar o tracking e aproveitar o ecossistema existente (Garmin → Strava → Omni Runner) é inteligente. Reduz fricção técnica e aproveita dados de melhor qualidade.

### O que me faria sair

1. **Não tenho assessoria.** Se eu sou um corredor solo, o app basicamente me mostra cards vazios no dashboard. Os desafios que eu quero criar exigem assessoria ou OmniCoins — e OmniCoins vêm da assessoria. Ciclo fechado que exclui corredores independentes.

2. **A escolha de papel permanente me assusta.** Eu não quero tomar uma decisão irreversível nos primeiros 2 minutos de uso. Isso é o tipo de UX que me faz instalar, olhar, e desinstalar "para pensar" — e nunca voltar.

3. **Não entendi o que são OmniCoins nos primeiros 10 minutos.** O tour diz que "vêm da assessoria" mas eu pulei o tour. Nas telas principais, OmniCoins aparecem em chips e badges mas sem explicação contextual.

4. **Descobrir que preciso do Strava DEPOIS de todo o onboarding é frustrante.** Eu investi 10 taps e 3 decisões para chegar à tela "Hoje" e só aí descubro que preciso de outro app. Se eu não tiver Strava instalado, simplesmente paro.

---

## Eu abandonaria?

**Resposta: SIM, em um ponto específico**

### Ponto exato de abandono

**`onboarding_role_screen.dart` — o diálogo de confirmação de papel.**

Quando o app me mostra:

> "Essa escolha é permanente e não pode ser alterada depois. Se precisar trocar, entre em contato com o suporte."

...com ícone de warning amarelo, texto em vermelho, e ícone de cadeado, meu instinto como novo usuário é: **"Eu não sei o que estou fazendo. Vou pesquisar antes de decidir."** Fecho o app. Pesquiso "Omni Runner" no Google. Se não encontro informação suficiente em 60 segundos, desinstalo.

### Abandono #1 razão

**Ansiedade de decisão irreversível + falta de contexto = paralisia.**

O produto pede comprometimento máximo no momento de conhecimento mínimo. É como um restaurante que pede que você escolha o prato antes de ver o cardápio — e diz que não pode trocar depois.

### Ponto secundário de abandono

**`today_screen.dart` — descoberta do requisito do Strava.**

Se eu passo pelo onboarding (talvez com pressa, sem ler bem), chego à tela "Hoje" e vejo:

> "Conecte o Strava para começar"

Se eu não tenho Strava: **game over.** Preciso instalar outro app, criar conta, conectar um relógio, correr, esperar sincronização, e ENTÃO voltar. Abandono garantido para quem não é do ecossistema.

---

## Eu preciso de um tutorial?

**Resposta: NÃO consigo descobrir sozinho os conceitos-chave**

O app é tecnicamente navegável (botões claros, hierarquia visual ok), mas os **conceitos** são opacos:

1. Não sei o que é "assessoria" sem contexto cultural
2. Não sei como funcionam OmniCoins (de onde vêm, como gasto)
3. Não sei que preciso do Strava até muito tarde

### O que um tutorial de 30 segundos precisaria explicar

1. **"O Omni Runner sincroniza com seu Strava."** — Primeira frase. Antes de tudo. Se não tem Strava, o usuário precisa saber que é pré-requisito.

2. **"Assessoria = seu grupo de corrida com treinador. Sem assessoria, você pode usar o app sozinho, mas desafios com OmniCoins ficam limitados."** — Elimina toda a confusão sobre assessoria e sobre o que muda com/sem ela.

3. **"OmniCoins são moedas virtuais que sua assessoria distribui. Você aposta em desafios — o vencedor leva tudo."** — Uma frase que explica o ciclo completo: de onde vêm, como usam, por que importam.

---

## Scores (0-10)

| Dimensão | Score | Justificativa |
|----------|-------|---------------|
| **Clareza** | 5/10 | O app comunica que é sobre corrida + competição, mas os conceitos centrais (assessoria, OmniCoins, dependência do Strava) ficam opacos até muito dentro do produto. A Welcome Screen promete 4 coisas genéricas em vez de 1 proposta clara. |
| **Facilidade de começar** | 4/10 | O onboarding exige 10-22 taps, passa por 7 telas + um tour de 9 slides, e inclui uma decisão permanente. Para chegar ao valor (ver dados de corrida), preciso terminar o onboarding + conectar Strava + ter corrido no Strava. São pelo menos 3 dependências externas. |
| **Entendimento do propósito** | 6/10 | Eu *intuio* que é para assessorias de corrida, mas o app não DITA isso claramente. O welcome diz "Desafie corredores" + "Treine com sua assessoria" + "Participe de campeonatos" + "Evolua com métricas" — são 4 propostas para 4 públicos. Falta a frase: "O app da sua assessoria de corrida." |
| **Confiança no produto** | 7/10 | Design moderno (Material 3 + tokens), animações suaves, login social (Google/Apple), textos em português nativo e consistente. O portal usa Tailwind com design system sólido. Parece profissional. Perde pontos pela falta de identidade visual (logo genérico Material Icon, nenhuma foto, nenhum social proof). |

---

## The 1-Minute Pitch Test

### O que eu diria a um amigo

> "O Omni Runner é um app para corredores que treinam em assessorias — aqueles grupos de corrida com professor, sabe? Ele conecta com o Strava e importa suas corridas automaticamente. A sacada é que ele tem desafios entre corredores: você aposta umas moedas virtuais chamadas OmniCoins, e quem corre mais ou mais rápido leva o pool. Tem ranking do grupo, sequência de dias correndo, badges, XP — tipo uma gamificação do treino. E o professor tem um portal web onde controla tudo: vê quem tá treinando, distribui créditos, organiza campeonatos internos."

### O que eu NÃO conseguiria explicar

1. **O que acontece se eu NÃO tenho assessoria.** O app permite pular a assessoria, mas o que eu posso fazer sem ela? Desafios? Rankings? OmniCoins? Não ficou claro.

2. **De onde vêm os OmniCoins.** O tour diz "da assessoria", mas como? O professor compra? Ganha de graça? Quanto custa? É um modelo freemium ou pago?

3. **O que é "Atleta Verificado" na prática.** O tour menciona que preciso de 7 corridas válidas. "Válidas" como? Distância mínima? GPS verificado? Anti-cheat? O critério é opaco.

4. **O que diferencia isso do Strava.** Se eu já uso Strava, por que preciso de outro app? A resposta existe (OmniCoins, assessoria, campeonatos), mas o app não a articula em nenhum momento.

5. **Se o app é gratuito ou pago.** Nenhuma menção a preço em nenhuma tela do onboarding. O portal tem "Comprar Créditos" no dashboard, mas para o atleta, o modelo econômico é invisível.

---

## Top 5 "If Only..." Moments

### 1. Se ao menos o app me dissesse "Você precisa do Strava" ANTES do onboarding

Na Welcome Screen, entre os bullets, um que dissesse:
> "Conecte seu Strava — corrida com qualquer relógio ou celular"

Isso alinha a expectativa antes de investir 10+ taps no onboarding. O usuário sem Strava pode decidir imediatamente se quer instalar, em vez de descobrir no final.

**Impacto:** Eliminaria o principal ponto de frustração e abandono pós-onboarding.

### 2. Se ao menos a escolha de papel NÃO fosse permanente (ou parecesse menos assustadora)

Duas opções:
- **Melhor:** Permitir troca de papel via suporte ou configurações
- **Mínimo:** Reescrever o aviso para ser menos ameaçador: em vez de ícone de cadeado + texto vermelho, usar "Você pode trocar depois entrando em contato com o suporte" em tom neutro

**Impacto:** Eliminaria a paralisia de decisão no onboarding — o ponto #1 de abandono.

### 3. Se ao menos houvesse uma explicação de "assessoria" em 1 frase na Welcome Screen

Um subtítulo sob "Treine com sua assessoria":
> "Assessoria = seu grupo de corrida com treinador"

Ou na `join_assessoria_screen.dart`, acima do campo de busca:
> "Assessoria é o grupo de treino da sua corrida. Busque pelo nome ou peça o código ao seu treinador."

**Impacto:** Desbloquearia o entendimento para todo usuário que não vem do jargão da corrida brasileira.

### 4. Se ao menos a tela "Hoje" fosse a tab padrão (ou o Strava CTA estivesse no Dashboard)

Trocar `_tab = 0` (AthleteDashboard) por `_tab = 1` (TodayScreen) como tab padrão — pelo menos para novos usuários. Ou mostrar o card "Conecte Strava" no AthleteDashboard.

**Impacto:** O primeiro contato com valor aconteceria 1 tap mais cedo, e o CTA de Strava seria impossível de perder.

### 5. Se ao menos o tour tivesse 3 slides em vez de 9

Três slides essenciais:
1. "Conecte seu Strava" — requisito técnico
2. "Entre na sua assessoria e desafie corredores" — proposta de valor
3. "OmniCoins: aposte em desafios, vencedor leva tudo" — hook de gamificação

Com 3 slides, ninguém pula. Com 9, quase todos pulam.

**Impacto:** As 3 informações críticas (Strava, assessoria, OmniCoins) seriam absorvidas por 90%+ dos usuários em vez dos ~10% que hoje passam por todos os 9 slides.

---

## Resumo Final — Veredito do Novo Usuário

| Pergunta | Resposta |
|----------|----------|
| Continuaria usando? | **MAYBE** — Sim se tenho assessoria e Strava. Não se sou corredor solo ou casual. |
| Onde abandonaria? | **Diálogo de confirmação de papel** (decisão permanente no minuto 2) |
| Razão #1 de abandono | **Medo de errar em decisão irreversível + falta de contexto** |
| Preciso de tutorial? | **Sim** — 30 segundos sobre Strava, assessoria e OmniCoins |
| Nota geral | **5.5/10** — Conceito excelente, execução do primeiro contato com fricção significativa |

### O produto tem um núcleo forte escondido atrás de um onboarding que assume demais.

O Omni Runner assume que o usuário:
1. Já sabe o que é assessoria
2. Já tem Strava instalado
3. Já tem certeza de que é atleta (e não staff)
4. Está disposto a fazer uma escolha permanente antes de explorar

Nenhuma dessas premissas é verdade para um novo usuário. O produto seria dramaticamente melhor se deixasse o usuário **experimentar antes de se comprometer**.
