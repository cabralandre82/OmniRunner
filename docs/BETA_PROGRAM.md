# Programa Beta — Omni Runner

## Visão Geral

O Programa Beta do Omni Runner é uma iniciativa estruturada para validar novas funcionalidades com assessorias parceiras antes do lançamento público. O programa é dividido em três fases progressivas, cada uma com objetivos e critérios claros.

---

## Fases do Programa

### Fase 1 — Alpha (Interno)

- **Participantes:** Equipe interna + 1-2 assessorias fundadoras
- **Duração:** 2-4 semanas
- **Objetivo:** Validar fluxos críticos (login, treinos, pagamentos)
- **Critérios de saída:**
  - Zero crashes bloqueantes em 7 dias consecutivos
  - Fluxos de onboarding, treino e pagamento 100% funcionais
  - Feedback qualitativo positivo da equipe interna

### Fase 2 — Closed Beta

- **Participantes:** 5-10 assessorias selecionadas
- **Duração:** 4-6 semanas
- **Objetivo:** Validar experiência real com atletas, engajamento e retenção
- **Critérios de saída:**
  - NPS >= 7 entre coaches
  - Retenção D7 >= 60% entre atletas
  - Todos os bugs P0/P1 resolvidos

### Fase 3 — Open Beta

- **Participantes:** Qualquer assessoria interessada (inscrição aberta)
- **Duração:** 4-8 semanas
- **Objetivo:** Escala, performance sob carga real, preparação para GA
- **Critérios de saída:**
  - NPS >= 8
  - WAU estável ou crescente por 3 semanas
  - Infraestrutura validada para 50+ assessorias simultâneas

---

## Critérios de Seleção — Assessorias Piloto

Para participar do Closed Beta, a assessoria deve atender a pelo menos 3 dos critérios abaixo:

1. **Porte misto:** Ter entre 20-100 atletas ativos
2. **Engajamento:** Coach responde mensagens no WhatsApp em até 24h
3. **Diversidade de uso:** Utilizar pelo menos 3 módulos (treinos, financeiro, engajamento)
4. **Disponibilidade:** Comprometer-se com feedback semanal por 4 semanas
5. **Perfil técnico:** Ter ao menos 1 pessoa com smartphone Android atualizado (Android 10+)
6. **Motivação:** Interesse genuíno em contribuir com o produto

---

## Agenda de Feedback Semanal

| Dia | Atividade |
|-----|-----------|
| **Segunda** | Envio do changelog semanal no grupo WhatsApp |
| **Quarta** | Check-in assíncrono: "Algum problema ou sugestão essa semana?" |
| **Sexta** | Formulário de feedback semanal (Google Forms) |
| **Quinzenal** | Call de 30min com assessorias para demo + coleta de feedback |

---

## Canal de Comunicação — WhatsApp

O WhatsApp é o canal principal de comunicação com as assessorias beta.

### Diretrizes do Grupo

- **Nome do grupo:** `Omni Runner Beta — [Fase]`
- **Administradores:** Equipe de produto Omni Runner
- **Regras:**
  1. Reportar bugs com screenshot + descrição do que estava fazendo
  2. Sugestões são bem-vindas, mas priorizadas pela equipe
  3. Sem spam ou conteúdo não relacionado ao beta
  4. Respostas da equipe em até 24h (dias úteis)
  5. Informações compartilhadas no grupo são confidenciais

### Estrutura de Mensagens

- **Changelog:** Postado toda segunda com lista de mudanças
- **Bugs conhecidos:** Fixado no topo do grupo
- **Pesquisa NPS:** Enviada quinzenalmente via link

---

## Formulário de Feedback

**Link do formulário:** `https://forms.gle/PLACEHOLDER_BETA_FEEDBACK`

### Campos do formulário:

1. Nome da assessoria
2. Nome do coach respondendo
3. Nota geral da semana (1-10)
4. O que funcionou bem?
5. O que causou frustração?
6. Bugs encontrados (descreva com detalhes)
7. Funcionalidade que mais sentiu falta
8. Recomendaria o Omni Runner para outra assessoria hoje? (0-10, NPS)
9. Comentários adicionais

---

## Métricas Acompanhadas

| Métrica | Descrição | Meta (Closed Beta) |
|---------|-----------|-------------------|
| **DAU** | Usuários ativos diários (atletas) | Crescimento semanal |
| **WAU** | Usuários ativos semanais | >= 70% dos cadastrados |
| **Retenção D1** | % que volta no dia seguinte | >= 50% |
| **Retenção D7** | % que volta após 7 dias | >= 60% |
| **Retenção D30** | % que volta após 30 dias | >= 40% |
| **NPS** | Net Promoter Score (coaches) | >= 7 |
| **NPS Atletas** | Net Promoter Score (atletas) | >= 6 |
| **Crash-free rate** | % de sessões sem crash | >= 99.5% |
| **Bugs P0/P1** | Bugs críticos abertos | 0 |
| **Tempo de resposta** | Tempo médio de resposta a bugs | < 48h |

---

## Processo de Escalação de Bugs

### Classificação de Severidade

| Nível | Descrição | SLA |
|-------|-----------|-----|
| **P0 — Crítico** | App não abre, perda de dados, pagamento incorreto | Fix em 24h |
| **P1 — Alto** | Funcionalidade core quebrada, mas há workaround | Fix em 48h |
| **P2 — Médio** | Bug visual ou funcionalidade secundária afetada | Fix no próximo sprint |
| **P3 — Baixo** | Melhoria de UX, ajuste cosmético | Backlog |

### Fluxo de Escalação

1. **Assessoria reporta** no grupo WhatsApp ou formulário
2. **Equipe classifica** severidade (P0-P3) em até 4h
3. **Confirmação** enviada no grupo com prazo estimado
4. **Fix deployado** → mensagem no grupo com confirmação
5. **Assessoria valida** que o problema foi resolvido

---

## Compromisso de Transparência no Roadmap

- Roadmap público compartilhado mensalmente no grupo beta
- Funcionalidades priorizadas com base no feedback beta são sinalizadas
- Assessorias beta têm acesso antecipado a features antes do GA
- Changelog detalhado a cada release

---

## Benefícios para Assessorias Beta

- Acesso antecipado a todas as funcionalidades
- Canal direto com a equipe de produto
- Prioridade no suporte técnico
- Desconto especial no plano pós-lançamento (a definir)
- Badge "Early Adopter" permanente no perfil da assessoria
- Influência direta no roadmap do produto
