# Auditoria de Fluxos Core — Omni Runner

**Data:** 2026-03-06
**Método:** Análise detalhada dos 8 fluxos principais do produto, baseada na estrutura do código, schema do banco, Edge Functions, rotas do portal e telas do app.
**Classificação:** Documento de auditoria profissional

---

## Escala de Avaliação

Cada fluxo é avaliado em três dimensões:

| Dimensão | Escala |
|----------|--------|
| **Completude** | 🔴 Incompleto · 🟡 Parcial · 🟢 Completo |
| **Tratamento de Erros** | 🔴 Fraco · 🟡 Adequado · 🟢 Robusto |
| **Qualidade UX** | 🔴 Problemático · 🟡 Funcional · 🟢 Polido |

---

## Fluxo 1: Onboarding do Atleta

**Caminho:** Instalar app → Criar conta → Conectar Strava → Primeira corrida → Ganhar OmniCoins

### Etapas Detalhadas

| # | Etapa | Plataforma | Componentes Envolvidos |
|---|-------|-----------|----------------------|
| 1.1 | Instalar app (App Store / Google Play) | Mobile | — |
| 1.2 | Abrir app → Splash screen | App | Design system, light/dark mode |
| 1.3 | Criar conta (email ou social login) | App | Supabase Auth (GoTrue) |
| 1.4 | Tutorial inicial (banners) | App | Tutorial banners implementados |
| 1.5 | Aceitar convite da assessoria ou buscar | App | Membership entity, assessoria lookup |
| 1.6 | Conectar conta Strava (OAuth) | App | Strava OAuth flow, Edge Function |
| 1.7 | Conceder permissões (GPS, BLE, Push) | App | Permissões do SO |
| 1.8 | Parear wearable BLE (opcional) | App | BLE HR monitor connection |
| 1.9 | Primeira corrida com GPS tracking | App | GPS tracking, Isar (offline), anti-cheat |
| 1.10 | Atividade processada e validada | Backend | Anti-cheat pipeline (6 camadas) |
| 1.11 | Receber XP + OmniCoins | Backend/App | Gamification engine, OmniCoins custody |
| 1.12 | Visualizar badges/nível alcançado | App | Badge system, progression |

### Avaliação

| Dimensão | Nota | Justificativa |
|----------|------|---------------|
| **Completude** | 🟢 Completo | Fluxo cobre desde instalação até recompensa — todos os passos implementados |
| **Tratamento de Erros** | 🟡 Adequado | Sentry captura erros; offline-first absorve falhas de rede; anti-cheat pode rejeitar corridas legítimas sem mensagem clara |
| **Qualidade UX** | 🟡 Funcional | Tutorial banners ajudam, mas múltiplas permissões + conceitos novos (OmniCoins, XP) podem sobrecarregar |

### Problemas Identificados

| # | Problema | Severidade | Detalhe |
|---|---------|-----------|---------|
| 1 | Múltiplas permissões simultâneas | Média | GPS + BLE + Push de uma vez — risco de negação |
| 2 | Anti-cheat falso positivo | Alta | Rejeição de corrida legítima sem apelação clara |
| 3 | OAuth Strava pode falhar | Média | Erro de rede durante OAuth perde contexto do fluxo |
| 4 | Conceitos não explicados | Média | OmniCoins e XP surgem sem contexto suficiente |

---

## Fluxo 2: Criação de Assessoria

**Caminho:** Criar grupo → Ser aprovado → Convidar atletas → Configurar billing

### Etapas Detalhadas

| # | Etapa | Plataforma | Componentes Envolvidos |
|---|-------|-----------|----------------------|
| 2.1 | Acessar portal e criar conta | Portal | Supabase Auth, registro |
| 2.2 | Preencher dados da assessoria | Portal | Formulário de cadastro, Server Action |
| 2.3 | Submeter para aprovação | Portal | Status: pendente |
| 2.4 | Admin da plataforma revisa e aprova | Portal (admin) | Rotas /admin/*, audit logging |
| 2.5 | Notificação de aprovação enviada | Backend | Push notification / email |
| 2.6 | Configurar branding (cores, logo) | Portal | Branding customization feature |
| 2.7 | Configurar integração Asaas | Portal | Asaas API, chaves de API |
| 2.8 | Criar primeiro plano de assinatura | Portal | Subscription management |
| 2.9 | Gerar link/código de convite | Portal | Invite system |
| 2.10 | Atletas se vinculam à assessoria | App | Membership creation |
| 2.11 | Billing automático ativado | Backend | Asaas webhooks, split payments |

### Avaliação

| Dimensão | Nota | Justificativa |
|----------|------|---------------|
| **Completude** | 🟢 Completo | Fluxo inteiro implementado — do cadastro ao billing |
| **Tratamento de Erros** | 🟡 Adequado | Validação de formulários e audit logging presentes; falhas de integração Asaas podem gerar estados inconsistentes |
| **Qualidade UX** | 🟡 Funcional | Aprovação manual introduz latência; setup Asaas é técnico; branding é diferencial positivo |

### Problemas Identificados

| # | Problema | Severidade | Detalhe |
|---|---------|-----------|---------|
| 1 | Aprovação manual sem SLA | Média | Coach não sabe quando será aprovado — risco de abandono |
| 2 | Configuração Asaas complexa | Alta | Setup de gateway de pagamento sem wizard guiado |
| 3 | Sem onboarding progressivo | Média | Coach precisa configurar tudo antes de operar |
| 4 | Latência até valor | Alta | Dias entre cadastro e primeira cobrança real |

---

## Fluxo 3: Criação e Entrega de Treinos

**Caminho:** Criar template → Adicionar blocos → Atribuir a atletas → Exportação .FIT

### Etapas Detalhadas

| # | Etapa | Plataforma | Componentes Envolvidos |
|---|-------|-----------|----------------------|
| 3.1 | Acessar seção de treinos no portal | Portal | Workout templates route |
| 3.2 | Criar template de treino | Portal | Template builder, Server Action |
| 3.3 | Adicionar blocos ao treino | Portal | Block editor (aquecimento, principal, volta à calma) |
| 3.4 | Configurar parâmetros (distância, pace, zona FC) | Portal | Form fields, validação |
| 3.5 | Atribuir treino a atletas individuais ou grupos | Portal | Assignment system, bulk operations |
| 3.6 | Atleta recebe notificação de novo treino | Backend/App | Push notification (FCM), realtime |
| 3.7 | Atleta visualiza treino no app | App | Workout detail screen |
| 3.8 | Atleta exporta para .FIT | App | .FIT file generation |
| 3.9 | Atleta carrega .FIT no relógio esportivo | App/Externo | File transfer, Bluetooth/USB |
| 3.10 | Atleta executa treino com GPS tracking | App | GPS tracking, zones monitoring |
| 3.11 | Coach acompanha execução no portal | Portal | Analytics, completion rates |

### Avaliação

| Dimensão | Nota | Justificativa |
|----------|------|---------------|
| **Completude** | 🟢 Completo | Template → blocos → atribuição → .FIT → execução — fluxo completo |
| **Tratamento de Erros** | 🟢 Robusto | Validação de parâmetros no builder; .FIT é formato padronizado; offline-first para execução |
| **Qualidade UX** | 🟢 Polido | Workflow do coach bem estruturado; atleta tem experiência fluida do treino até execução |

### Problemas Identificados

| # | Problema | Severidade | Detalhe |
|---|---------|-----------|---------|
| 1 | Exportação .FIT pode falhar em dispositivos antigos | Baixa | Formato .FIT é complexo — edge cases possíveis |
| 2 | Sem preview visual do treino para o coach | Baixa | Coach não vê como o atleta visualizará o treino no app |
| 3 | TrainingPeaks integration frozen | Média | Integração com TrainingPeaks documentada como pausada/congelada |

---

## Fluxo 4: Billing de Assinatura

**Caminho:** Configurar Asaas → Criar plano → Atribuir com auto-billing → Webhook de pagamento

### Etapas Detalhadas

| # | Etapa | Plataforma | Componentes Envolvidos |
|---|-------|-----------|----------------------|
| 4.1 | Coach configura conta Asaas no portal | Portal | Asaas API integration, credentials |
| 4.2 | Criar plano de assinatura (valor, período) | Portal | Subscription plan management |
| 4.3 | Atribuir plano a atletas | Portal | Assignment com vinculação Asaas |
| 4.4 | Asaas gera cobrança automática | Externo | Asaas billing engine |
| 4.5 | Atleta recebe boleto/PIX/cartão | Externo | Asaas payment methods |
| 4.6 | Atleta realiza pagamento | Externo | Gateway de pagamento |
| 4.7 | Webhook de confirmação recebido | Backend | Edge Function + HMAC verification |
| 4.8 | Status da assinatura atualizado | Backend | Subscription table, RLS |
| 4.9 | Split executado (assessoria + platform fee) | Backend | Asaas Split, maintenance fee |
| 4.10 | Dashboard financeiro atualizado | Portal | Financial dashboard, Server Components |
| 4.11 | Job de lifecycle gerencia vencimentos | Backend | pg_cron lifecycle job |

### Avaliação

| Dimensão | Nota | Justificativa |
|----------|------|---------------|
| **Completude** | 🟢 Completo | Ciclo completo de billing implementado — da configuração ao split |
| **Tratamento de Erros** | 🟢 Robusto | HMAC em webhooks, rate limiting, audit logging, RLS, job de lifecycle |
| **Qualidade UX** | 🟡 Funcional | Setup inicial complexo para o coach; após configurado, automático e transparente |

### Problemas Identificados

| # | Problema | Severidade | Detalhe |
|---|---------|-----------|---------|
| 1 | Setup Asaas sem wizard | Alta | Coach precisa entender conceitos de gateway |
| 2 | Falha de webhook | Média | Se webhook falhar, assinatura pode ficar em estado inconsistente (mitigado por job de verificação) |
| 3 | Múltiplos gateways | Média | Asaas + Stripe + MercadoPago multiplica cenários de falha |
| 4 | Reconciliação | Baixa | Dependência de job de clearing para garantir consistência |

---

## Fluxo 5: Desafio (Challenge)

**Caminho:** Criar desafio → Atletas participam → Correm → Settlement → Transferência OmniCoins

### Etapas Detalhadas

| # | Etapa | Plataforma | Componentes Envolvidos |
|---|-------|-----------|----------------------|
| 5.1 | Coach cria desafio no portal | Portal | Challenge creation, parameters |
| 5.2 | Define regras (distância, pace, duração, entry fee) | Portal | Challenge config, OmniCoins entry fee |
| 5.3 | Publica desafio para atletas da assessoria | Portal/Backend | Challenge publication, notifications |
| 5.4 | Atletas visualizam desafio no app | App | Challenge listing, detail screen |
| 5.5 | Atleta paga entry fee (OmniCoins) | App/Backend | OmniCoins debit, custody check |
| 5.6 | Pool de prêmios acumula | Backend | Challenge pool accumulation |
| 5.7 | Atletas correm durante período do desafio | App | GPS tracking, anti-cheat validation |
| 5.8 | Atividades validadas pelo anti-cheat | Backend | 6-layer anti-cheat pipeline |
| 5.9 | Ranking calculado ao fim do desafio | Backend | Ranking engine, criteria evaluation |
| 5.10 | Settlement executado | Backend | Clearing engine, platform fee deduction |
| 5.11 | Vencedores recebem OmniCoins | Backend | OmniCoins credit, transfer records |
| 5.12 | Transferências OmniCoins registradas | Backend/Portal | Formerly "Compensações", now "Transferências OmniCoins" |
| 5.13 | Resultados visíveis para todos | App/Portal | Leaderboard, results screen |

### Avaliação

| Dimensão | Nota | Justificativa |
|----------|------|---------------|
| **Completude** | 🟢 Completo | Ciclo completo: criação → participação → competição → settlement → distribuição |
| **Tratamento de Erros** | 🟢 Robusto | Anti-cheat protege integridade; clearing job garante consistência financeira; custody verification |
| **Qualidade UX** | 🟢 Polido | Fluxo engajante com gamificação real; labels recentemente humanizados |

### Problemas Identificados

| # | Problema | Severidade | Detalhe |
|---|---------|-----------|---------|
| 1 | Anti-cheat falso positivo em desafio | Crítica | Rejeição incorreta quando há dinheiro envolvido é grave |
| 2 | Entry fee sem reembolso claro | Média | Se desafio for cancelado, política de reembolso precisa ser explícita |
| 3 | Settlement timing | Baixa | Clearing periódico pode gerar atraso entre fim do desafio e recebimento |
| 4 | Disputas | Média | Sem sistema visível de contestação de resultados |

---

## Fluxo 6: Campeonato (Championship)

**Caminho:** Criar template → Agendar → Convidar assessorias parceiras → Gerenciar

### Etapas Detalhadas

| # | Etapa | Plataforma | Componentes Envolvidos |
|---|-------|-----------|----------------------|
| 6.1 | Coach cria template de campeonato | Portal | Championship template builder |
| 6.2 | Define etapas, datas, regras | Portal | Championship config, multi-stage |
| 6.3 | Agenda campeonato (data início/fim) | Portal | Scheduling system |
| 6.4 | Convida assessorias parceiras | Portal | Partnership system, invite flow |
| 6.5 | Assessorias parceiras aceitam convite | Portal | Partnership acceptance, notification |
| 6.6 | Atletas de múltiplas assessorias participam | App | Cross-assessoria enrollment |
| 6.7 | Etapas executadas (corridas com GPS) | App | GPS tracking, anti-cheat |
| 6.8 | Rankings atualizados por etapa | Backend | Multi-stage ranking engine |
| 6.9 | Classificação geral computada | Backend | Aggregate scoring |
| 6.10 | Resultados publicados | App/Portal | Championship results, leaderboards |

### Avaliação

| Dimensão | Nota | Justificativa |
|----------|------|---------------|
| **Completude** | 🟢 Completo | Template → agendamento → parcerias → execução multi-etapa → resultados |
| **Tratamento de Erros** | 🟡 Adequado | Anti-cheat presente; parcerias com fluxo de aceite; cancelamento de etapas a verificar |
| **Qualidade UX** | 🟡 Funcional | Funcionalidade poderosa mas complexa; convite entre assessorias é diferencial |

### Problemas Identificados

| # | Problema | Severidade | Detalhe |
|---|---------|-----------|---------|
| 1 | Complexidade de configuração | Média | Multi-stage + multi-assessoria gera muitas opções para o coach |
| 2 | Coordenação entre assessorias | Média | Conflitos de agenda e regras entre organizadores |
| 3 | Distinção campeonato vs desafio vs liga | Alta | Três sistemas de competição — usuário pode confundir |
| 4 | Escala de participantes | Baixa | Campeonato inter-assessorias pode gerar grandes volumes |

---

## Fluxo 7: OmniCoin

**Caminho:** Depositar USD → Custódia → Distribuir para atletas → Usar em desafios → Clearing

### Etapas Detalhadas

| # | Etapa | Plataforma | Componentes Envolvidos |
|---|-------|-----------|----------------------|
| 7.1 | Assessoria decide comprar OmniCoins | Portal | Saldo OmniCoins page |
| 7.2 | Realiza depósito em USD | Portal/Externo | Gateway de pagamento (Asaas/Stripe/MercadoPago) |
| 7.3 | Webhook confirma pagamento | Backend | HMAC verification, Edge Function |
| 7.4 | OmniCoins creditados na custódia | Backend | Custody table, 1:1 parity |
| 7.5 | Coach distribui OmniCoins para atletas | Portal | Distribution engine, bulk or individual |
| 7.6 | Atletas recebem OmniCoins no app | App/Backend | Balance update, notification |
| 7.7 | Atleta usa OmniCoins como entry fee | App | Challenge enrollment, debit |
| 7.8 | OmniCoins acumulam no pool do desafio | Backend | Challenge pool |
| 7.9 | Settlement distribui para vencedores | Backend | Clearing engine |
| 7.10 | Platform fee deduzida | Backend | Fee calculation, platform revenue |
| 7.11 | Clearing periódico reconcilia saldos | Backend | pg_cron clearing job |
| 7.12 | Auto-topup reabastece se configurado | Backend | pg_cron auto-topup job |
| 7.13 | Verificação de integridade executada | Backend | pg_cron verification job |

### Avaliação

| Dimensão | Nota | Justificativa |
|----------|------|---------------|
| **Completude** | 🟢 Completo | Ciclo monetário completo: entrada → custódia → circulação → settlement → clearing |
| **Tratamento de Erros** | 🟢 Robusto | HMAC em webhooks; 3 jobs pg_cron dedicados (clearing, verification, auto-topup); audit logging; RLS |
| **Qualidade UX** | 🟡 Funcional | Labels melhorados (Saldo OmniCoins); fluxo financeiro é inerentemente complexo |

### Problemas Identificados

| # | Problema | Severidade | Detalhe |
|---|---------|-----------|---------|
| 1 | Custódia regulatória | Crítica | Manter 1:1 USD pode exigir licença financeira dependendo da jurisdição |
| 2 | Reconciliação tardia | Média | Clearing periódico pode gerar discrepância temporária |
| 3 | Saldo insuficiente | Baixa | Coach tenta distribuir mais que possui — tratamento de erro necessário |
| 4 | Auditabilidade | Baixa | Trilha de auditoria precisa ser imutável para compliance |
| 5 | Multi-gateway de entrada | Média | Depósito via 3 gateways diferentes aumenta complexidade de reconciliação |

---

## Fluxo 8: Parceria (Partnership)

**Caminho:** Buscar assessoria → Enviar convite → Aceitar → Convidar para campeonato

### Etapas Detalhadas

| # | Etapa | Plataforma | Componentes Envolvidos |
|---|-------|-----------|----------------------|
| 8.1 | Coach busca assessorias no portal | Portal | Assessoria search/discovery |
| 8.2 | Visualiza perfil da assessoria | Portal | Assessoria profile page |
| 8.3 | Envia convite de parceria | Portal | Partnership invite, Server Action |
| 8.4 | Assessoria convidada recebe notificação | Backend/Portal | Notification system |
| 8.5 | Coach da assessoria convidada revisa convite | Portal | Partnership inbox |
| 8.6 | Aceita ou rejeita parceria | Portal | Partnership acceptance flow |
| 8.7 | Parceria ativada bilateralmente | Backend | Partnership record, RLS policies |
| 8.8 | Assessorias parceiras visíveis na criação de campeonato | Portal | Championship invite filter |
| 8.9 | Coach convida parceira para campeonato | Portal | Championship invite flow |
| 8.10 | Atletas de ambas assessorias participam | App | Cross-assessoria championship |

### Avaliação

| Dimensão | Nota | Justificativa |
|----------|------|---------------|
| **Completude** | 🟢 Completo | Discovery → convite → aceite → integração com campeonatos — fluxo end-to-end |
| **Tratamento de Erros** | 🟡 Adequado | Fluxo de aceite/rejeição presente; RLS isola dados entre assessorias |
| **Qualidade UX** | 🟡 Funcional | Fluxo de convite é intuitivo; valor da parceria depende de campeonatos |

### Problemas Identificados

| # | Problema | Severidade | Detalhe |
|---|---------|-----------|---------|
| 1 | Valor da parceria pouco claro | Média | Coach pode não entender por que criar parcerias sem contexto |
| 2 | Sem histórico de interações | Baixa | Depois de aceitar, sem registro de campeonatos compartilhados |
| 3 | Dissolução de parceria | Baixa | Fluxo de encerramento e impacto em campeonatos ativos |
| 4 | Descoberta limitada | Média | Busca de assessorias depende de critérios de filtro adequados |

---

## Resumo Executivo

### Matriz de Avaliação

| # | Fluxo | Completude | Tratamento de Erros | Qualidade UX |
|---|-------|-----------|---------------------|-------------|
| 1 | **Onboarding Atleta** | 🟢 Completo | 🟡 Adequado | 🟡 Funcional |
| 2 | **Criação Assessoria** | 🟢 Completo | 🟡 Adequado | 🟡 Funcional |
| 3 | **Treinos** | 🟢 Completo | 🟢 Robusto | 🟢 Polido |
| 4 | **Billing** | 🟢 Completo | 🟢 Robusto | 🟡 Funcional |
| 5 | **Desafio** | 🟢 Completo | 🟢 Robusto | 🟢 Polido |
| 6 | **Campeonato** | 🟢 Completo | 🟡 Adequado | 🟡 Funcional |
| 7 | **OmniCoin** | 🟢 Completo | 🟢 Robusto | 🟡 Funcional |
| 8 | **Parceria** | 🟢 Completo | 🟡 Adequado | 🟡 Funcional |

### Análise Geral

**Completude: Excelente**
Todos os 8 fluxos core estão implementados de ponta a ponta. Não há fluxo interrompido ou parcialmente construído. Isso indica maturidade significativa do produto.

**Tratamento de Erros: Bom**
4 dos 8 fluxos têm tratamento robusto (treinos, billing, desafios, OmniCoins). Os demais têm tratamento adequado. Destaque para:
- HMAC em webhooks de pagamento
- Anti-cheat com 6 camadas de validação
- 3 jobs pg_cron dedicados à integridade financeira
- Audit logging para rastreabilidade
- Sentry com session replays para diagnóstico

**Qualidade UX: Funcional com pontos de polimento**
2 fluxos são polidos (treinos, desafios), 6 são funcionais. Os principais pontos de melhoria:
- Setup financeiro precisa de wizard guiado
- Aprovação de assessoria precisa de SLA e status tracker
- Três sistemas de competição (desafios, campeonatos, ligas) precisam de diferenciação mais clara
- Permissões do app devem ser contextuais

### Top 10 Problemas Prioritários (Cross-Flow)

| # | Problema | Fluxos Afetados | Severidade | Recomendação |
|---|---------|----------------|-----------|--------------|
| 1 | **Anti-cheat falso positivo** | 1, 5, 6 | 🔴 Crítica | Implementar apelação e revisão humana |
| 2 | **Custódia regulatória** | 7 | 🔴 Crítica | Consulta jurídica sobre licença financeira |
| 3 | **Setup Asaas sem wizard** | 2, 4 | 🔴 Alta | Criar wizard passo a passo com validação |
| 4 | **Aprovação sem SLA** | 2 | 🟡 Alta | Definir SLA, status tracker, notificação |
| 5 | **Confusão desafio/campeonato/liga** | 5, 6 | 🟡 Alta | Taxonomia clara com descrição de cada tipo |
| 6 | **Múltiplas permissões no onboarding** | 1 | 🟡 Média | Solicitar contextualmente |
| 7 | **Reembolso de entry fee** | 5 | 🟡 Média | Política explícita de cancelamento |
| 8 | **Disputas de resultados** | 5, 6 | 🟡 Média | Sistema de contestação formal |
| 9 | **Reconciliação multi-gateway** | 4, 7 | 🟡 Média | Dashboard unificado de reconciliação |
| 10 | **Valor da parceria pouco claro** | 8 | 🟡 Média | Storytelling e benefícios visíveis |

---

## Apêndice: Cobertura de Testes por Fluxo

| Fluxo | Testes Identificados | Cobertura |
|-------|---------------------|-----------|
| Onboarding Atleta | Flutter tests (169 arquivos), Sentry monitoring | Média-Alta |
| Criação Assessoria | Portal Vitest (74 arquivos), Playwright E2E (16 specs) | Média-Alta |
| Treinos | Flutter tests, Portal tests | Média |
| Billing | Portal tests, RLS penetration tests, webhook tests | Alta |
| Desafio | Flutter tests, anti-cheat tests, clearing tests | Alta |
| Campeonato | Flutter tests, Portal tests | Média |
| OmniCoin | QA reconciliation suites, clearing tests, RLS tests | Alta |
| Parceria | Portal tests, RLS tests | Média |

**Total:** 263 arquivos de teste distribuídos entre Flutter (169), Vitest (74), Playwright (16) e SQL (5). CI/CD com 4 workflows e pre-commit hooks (lefthook) garantem execução automatizada.

---

*Documento gerado como parte da auditoria profissional do produto Omni Runner.*
