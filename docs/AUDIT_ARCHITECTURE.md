# Auditoria de Arquitetura — Omni Runner

**Data:** 2026-03-06
**Escopo:** Análise arquitetural completa da plataforma Omni Runner (App, Portal, Backend)
**Classificação:** Documento de auditoria profissional

---

## 1. Visão Geral do Sistema

O Omni Runner é uma plataforma de fitness/corrida composta por três camadas principais, projetada para atender assessorias de corrida no mercado brasileiro.

```
┌─────────────────────────────────────────────────────────────────┐
│                        USUÁRIOS FINAIS                          │
│         Atletas (App)    Coaches (Portal)    Admins (Portal)    │
└──────────┬──────────────────┬──────────────────┬────────────────┘
           │                  │                  │
           ▼                  ▼                  ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────────┐
│   App Flutter    │ │  Portal Next.js  │ │   Painel Admin       │
│   (Mobile)       │ │  (Web SSR)       │ │   (Web SSR)          │
│   iOS / Android  │ │  Multi-tenant    │ │   Rotas /admin/*     │
└────────┬─────────┘ └────────┬─────────┘ └──────────┬───────────┘
         │                    │                       │
         └────────────┬───────┴───────────────────────┘
                      │
                      ▼
         ┌─────────────────────────┐
         │   Supabase Backend      │
         │   ─ PostgreSQL (RLS)    │
         │   ─ 59 Edge Functions   │
         │   ─ Auth (GoTrue)       │
         │   ─ Realtime            │
         │   ─ Storage             │
         └────────────┬────────────┘
                      │
         ┌────────────┴────────────────────┐
         │       Integrações Externas      │
         │  Strava · Asaas · Stripe ·      │
         │  MercadoPago · TrainingPeaks ·  │
         │  Sentry · Firebase · pg_cron    │
         └─────────────────────────────────┘
```

---

## 2. Stack Tecnológico

| Camada | Tecnologia | Versão / Detalhes |
|--------|-----------|-------------------|
| **App Mobile** | Flutter / Dart | Multi-plataforma (iOS + Android) |
| **Gerenciamento de Estado** | BLoC (flutter_bloc) | 31 BLoCs identificados |
| **Banco Local** | Isar v3 | Offline-first (⚠️ EOL) |
| **Navegação** | Imperativa (Navigator 1.0) | 99 telas registradas |
| **Monitoramento App** | Sentry | Error tracking + session replays |
| **Push Notifications** | Firebase Cloud Messaging | Android + iOS |
| **Portal Web** | Next.js 14 | App Router + Server Components |
| **Estilização Portal** | CSS Custom Properties | Design system próprio, 17 componentes UI |
| **Testes Portal** | Vitest + Playwright | 600 testes unitários, 16 specs E2E |
| **Backend** | Supabase | PostgreSQL + Edge Functions (Deno) |
| **Migrations** | SQL nativo | 131 migrations versionadas |
| **Segurança DB** | Row Level Security (RLS) | Todas as 32+ tabelas protegidas |
| **Jobs Agendados** | pg_cron | 4 jobs (auto-topup, lifecycle, clearing, verification) |
| **CI/CD** | GitHub Actions | 4 workflows (portal, flutter, supabase, release) |
| **Pre-commit** | Lefthook | dart analyze + next lint |

---

## 3. Arquitetura do App (Flutter)

### 3.1 Métricas do Código

| Métrica | Valor |
|---------|-------|
| Arquivos `.dart` | 636 |
| Telas (screens) | 99 |
| BLoCs | 31 |
| Entidades | 67 |
| Interfaces de repositório | 48 |
| Arquivos de teste | 169 |

### 3.2 Clean Architecture

O app segue o padrão Clean Architecture com separação em camadas:

```
┌───────────────────────────────────────────────┐
│                 PRESENTATION                   │
│   99 Screens · 31 BLoCs · Widgets             │
├───────────────────────────────────────────────┤
│                   DOMAIN                       │
│   67 Entities · 48 Repository Interfaces      │
│   Use Cases · Value Objects                    │
├───────────────────────────────────────────────┤
│               DATA / INFRASTRUCTURE            │
│   Repository Implementations · Data Sources   │
│   Isar (local) · Supabase (remote)            │
│   Mappers · DTOs                              │
└───────────────────────────────────────────────┘
```

### 3.3 Padrão BLoC

- **31 BLoCs** gerenciam o estado da aplicação
- Padrão `Event → BLoC → State` seguido de forma consistente
- Alguns screens acessam repositórios diretamente, contornando o BLoC (violação arquitetural identificada)

### 3.4 Offline-First com Isar v3

```
┌──────────┐     ┌──────────┐     ┌──────────────┐
│  Screen  │────▶│   BLoC   │────▶│  Repository  │
└──────────┘     └──────────┘     └──────┬───────┘
                                         │
                              ┌──────────┴──────────┐
                              │                     │
                         ┌────▼─────┐         ┌────▼─────┐
                         │  Isar    │         │ Supabase │
                         │  (local) │◀─sync──▶│ (remote) │
                         └──────────┘         └──────────┘
```

- Dados são persistidos localmente no Isar v3 para uso offline
- Sincronização bidirecional com Supabase quando online
- **Risco crítico:** Isar v3 atingiu End of Life — sem atualizações de segurança ou compatibilidade futuras

### 3.5 Features Principais do App

| Feature | Descrição |
|---------|-----------|
| **GPS Tracking** | Rastreamento em tempo real com pipeline anti-cheat |
| **Strava** | Integração OAuth para importação/exportação de atividades |
| **Gamificação** | OmniCoins, XP, badges, desafios, campeonatos, ligas |
| **Treinos** | Workout builder para coaches com exportação .FIT |
| **Social** | Amigos, grupos, feed de atividades |
| **Parques** | Detecção automática de parques durante corridas |
| **Wearables** | Conexão BLE com monitores cardíacos |
| **Design System** | Sistema de design com suporte a light/dark mode |

---

## 4. Arquitetura do Portal (Next.js 14)

### 4.1 Métricas do Código

| Métrica | Valor |
|---------|-------|
| Arquivos `.ts/.tsx` | 338 |
| Rotas de assessoria | 30+ |
| Rotas de admin | 11+ |
| Rotas de API | 40+ |
| Testes unitários (Vitest) | 74 arquivos, 600 testes |
| Testes E2E (Playwright) | 16 specs |
| Componentes UI | 17 |
| Loading skeletons | 40 arquivos `loading.tsx` |

### 4.2 App Router e Server Components

```
┌─────────────────────────────────────────────────┐
│                  Next.js 14                      │
│                                                  │
│  ┌─────────────────────────────────────────────┐│
│  │          Server Components                   ││
│  │   Páginas data-heavy · SSR · Streaming       ││
│  │   40 loading.tsx (skeleton states)           ││
│  └─────────────────────────────────────────────┘│
│                                                  │
│  ┌─────────────────────────────────────────────┐│
│  │          Server Actions                      ││
│  │   Mutações de produto · Forms               ││
│  └─────────────────────────────────────────────┘│
│                                                  │
│  ┌─────────────────────────────────────────────┐│
│  │          API Routes (40+)                    ││
│  │   Webhooks · Integrações · CRUD             ││
│  └─────────────────────────────────────────────┘│
│                                                  │
│  ┌─────────────────────────────────────────────┐│
│  │          Middleware                           ││
│  │   Multi-tenancy · Auth · CSRF · Rate Limit  ││
│  └─────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
```

### 4.3 Multi-Tenancy

```
Request → Cookie (assessoria_id)
       → Middleware (re-verificação no DB)
       → RLS no Supabase (isolamento de dados)
```

- Identificação do tenant via cookie
- Re-verificação obrigatória no middleware contra o banco de dados
- Isolamento de dados garantido por RLS no PostgreSQL
- Cada assessoria visualiza apenas seus próprios dados

### 4.4 Camadas de Segurança

| Camada | Implementação |
|--------|---------------|
| **CSP** | Content Security Policy configurada |
| **CSRF** | Proteção contra Cross-Site Request Forgery |
| **Rate Limiting** | Limitação de requisições por IP/sessão |
| **HMAC Webhooks** | Verificação de assinatura em webhooks de pagamento |
| **RLS** | Row Level Security em todas as tabelas |
| **Audit Logging** | Registro de ações administrativas |

### 4.5 Features do Portal

| Feature | Descrição |
|---------|-----------|
| **Gestão de Atletas** | Cadastro, monitoramento, métricas de engajamento |
| **Dashboard Financeiro** | Receitas, despesas, split de pagamentos |
| **Billing (Asaas)** | Assinaturas, cobranças automáticas, webhooks |
| **OmniCoins** | Custódia (Saldo OmniCoins), compensações (Transferências OmniCoins), distribuições |
| **Treinos** | Templates de treino, blocos, atribuição a atletas |
| **Campeonatos** | Criação, agendamento, convites entre assessorias |
| **CRM** | Pipeline de leads e gestão de relacionamento |
| **Analytics** | Métricas de engajamento e retenção |
| **Branding** | Customização visual por assessoria |

---

## 5. Arquitetura do Backend (Supabase)

### 5.1 Métricas

| Métrica | Valor |
|---------|-------|
| Migrations SQL | 131 |
| Edge Functions | 59 |
| Módulos utilitários compartilhados | 10 |
| Tabelas | 32+ |
| Jobs pg_cron | 4 |

### 5.2 Estrutura do Banco de Dados

```
┌──────────────────────────────────────────────────────┐
│                    PostgreSQL                         │
│                                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐│
│  │   Identidade │  │   Corrida    │  │  Gamificação ││
│  │   ──────────  │  │   ──────     │  │  ──────────  ││
│  │   profiles    │  │   runs       │  │  omnicoins   ││
│  │   assessorias │  │   run_points │  │  challenges  ││
│  │   memberships │  │   anti_cheat │  │  badges      ││
│  │   partnerships│  │   parks      │  │  xp_events   ││
│  └──────────────┘  └──────────────┘  │  leagues     ││
│                                       └─────────────┘│
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐│
│  │  Financeiro  │  │   Treinos    │  │   Social     ││
│  │  ──────────  │  │   ──────     │  │   ──────     ││
│  │  subscriptions│  │   workouts   │  │  friendships ││
│  │  payments    │  │   blocks     │  │  groups      ││
│  │  clearing    │  │   templates  │  │  activities  ││
│  │  custody     │  │   assignments│  │              ││
│  └──────────────┘  └──────────────┘  └─────────────┘│
│                                                       │
│  ┌───────────────────────────────────────────────────┐│
│  │              RLS em TODAS as tabelas              ││
│  └───────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────┘
```

### 5.3 Edge Functions (59)

As Edge Functions rodam em Deno e cobrem:

- Webhooks de pagamento (Asaas, Stripe, MercadoPago)
- Integrações com Strava e TrainingPeaks
- Pipeline anti-cheat
- Operações financeiras (custódia, clearing, distribuição)
- Notificações push
- Processamento de atividades

### 5.4 Infraestrutura Compartilhada

10 módulos utilitários compartilhados entre Edge Functions:

- Autenticação e autorização
- Validação de entrada
- Logging estruturado
- Helpers de resposta HTTP
- Clientes de integração

### 5.5 Jobs Agendados (pg_cron)

| Job | Frequência | Função |
|-----|-----------|--------|
| **auto-topup** | Periódico | Reposição automática de OmniCoins |
| **lifecycle** | Periódico | Gerenciamento do ciclo de vida de assinaturas |
| **clearing** | Periódico | Compensação e liquidação de transações |
| **verification** | Periódico | Verificação de integridade de dados |

### 5.6 Pipeline Anti-Cheat

```
Atividade GPS recebida
        │
        ▼
┌───────────────────┐
│ Speed Impossibility│──▶ Velocidade fisicamente impossível?
└───────┬───────────┘
        ▼
┌───────────────────┐
│   GPS Jumps       │──▶ Saltos de posição anormais?
└───────┬───────────┘
        ▼
┌───────────────────┐
│   Teleport        │──▶ Teletransporte entre pontos?
└───────┬───────────┘
        ▼
┌───────────────────┐
│ Vehicle Detection │──▶ Padrão de movimento veicular?
└───────┬───────────┘
        ▼
┌───────────────────┐
│ Cadence Analysis  │──▶ Cadência incompatível com corrida?
└───────┬───────────┘
        ▼
┌───────────────────┐
│ HR Plausibility   │──▶ Frequência cardíaca implausível?
└───────┬───────────┘
        ▼
   RESULTADO: Aprovada / Flagged / Rejeitada
```

---

## 6. Fluxo de Dados Principal

### 6.1 Corrida do Atleta (App → Backend)

```
┌──────────┐    GPS/BLE     ┌──────────┐   Sync    ┌──────────────┐
│  Atleta  │───────────────▶│   App    │─────────▶│   Supabase   │
│  (corre) │                │  Flutter │          │  PostgreSQL  │
└──────────┘                └────┬─────┘          └──────┬───────┘
                                 │                       │
                            Isar (local)          Anti-Cheat Pipeline
                                 │                       │
                                 │                 Edge Functions
                                 │                       │
                                 └──── Offline? ────────▶│
                                       Sync depois       │
                                                   ┌─────▼──────┐
                                                   │  Strava     │
                                                   │  (export)   │
                                                   └─────────────┘
```

### 6.2 Gestão de Assessoria (Portal → Backend)

```
┌──────────┐   Browser    ┌──────────────┐   API/RLS   ┌──────────────┐
│  Coach   │─────────────▶│   Portal     │────────────▶│   Supabase   │
│          │              │   Next.js    │             │              │
└──────────┘              └──────┬───────┘             └──────┬───────┘
                                 │                            │
                          Server Components            Edge Functions
                          Server Actions                     │
                                 │                     ┌─────▼──────┐
                                 │                     │   Asaas    │
                                 │                     │  (billing) │
                                 │                     └────────────┘
                                 │
                          ┌──────▼───────┐
                          │  Middleware   │
                          │  (tenant     │
                          │   isolation) │
                          └──────────────┘
```

### 6.3 Fluxo Financeiro (OmniCoins)

```
┌──────────┐  Depósito   ┌──────────┐  Custódia  ┌──────────────┐
│ Assessoria│───(USD)────▶│  Asaas   │──────────▶│  Saldo       │
│          │             │  Webhook │           │  OmniCoins   │
└──────────┘             └──────────┘           └──────┬───────┘
                                                       │
                                          ┌────────────┴────────────┐
                                          │                         │
                                   ┌──────▼──────┐          ┌──────▼──────┐
                                   │ Distribuição │          │  Desafios   │
                                   │ p/ atletas   │          │  (entry fee)│
                                   └──────┬──────┘          └──────┬──────┘
                                          │                        │
                                          ▼                        ▼
                                   Atleta recebe           Clearing e
                                   OmniCoins               Settlement
                                                                │
                                                                ▼
                                                    Transferência OmniCoins
                                                    para vencedores
```

---

## 7. Mapa de Integrações Externas

| Integração | Tipo | Finalidade |
|-----------|------|-----------|
| **Strava** | OAuth + API | Importação/exportação de atividades, sync de corridas |
| **Asaas** | API + Webhooks | Billing de assinaturas, split de pagamentos, manutenção |
| **Stripe** | API + Webhooks | Processamento de pagamentos (mercado internacional) |
| **MercadoPago** | API + Webhooks | Processamento de pagamentos (mercado brasileiro) |
| **TrainingPeaks** | API | Exportação de treinos para plataforma de treinamento |
| **Firebase** | SDK | Push notifications (FCM) |
| **Sentry** | SDK | Error tracking, session replays, monitoramento |
| **Supabase Auth** | GoTrue | Autenticação (email, social) |
| **Supabase Realtime** | WebSocket | Atualizações em tempo real |
| **Supabase Storage** | S3-compatible | Armazenamento de arquivos (fotos, .FIT) |

---

## 8. Resumo do Schema do Banco de Dados

### 8.1 Grupos de Tabelas (32+ tabelas)

| Grupo | Tabelas Estimadas | Descrição |
|-------|-------------------|-----------|
| **Identidade e Acesso** | 4-5 | Profiles, assessorias, memberships, roles, partnerships |
| **Atividades** | 4-5 | Runs, run_points, GPS data, anti-cheat results |
| **Gamificação** | 5-6 | OmniCoins, challenges, badges, XP, leagues, championships |
| **Financeiro** | 4-5 | Subscriptions, payments, custody, clearing, fees |
| **Treinos** | 3-4 | Workout templates, blocks, assignments |
| **Social** | 3-4 | Friendships, groups, activities, notifications |
| **Infraestrutura** | 3-4 | Audit logs, feature flags, parques, branding |

### 8.2 Proteção RLS

- **100% das tabelas** possuem políticas RLS ativas
- Isolamento por assessoria (multi-tenancy)
- Isolamento por usuário (dados pessoais)
- Testes de penetração RLS documentados
- Políticas auditadas com suítes de testes específicas

---

## 9. Pontos Fortes

| # | Ponto Forte | Impacto |
|---|-------------|---------|
| 1 | **Clean Architecture consistente** no app (636 arquivos, 67 entidades, 48 interfaces) | Alta manutenibilidade e testabilidade |
| 2 | **RLS em 100% das tabelas** com testes de penetração | Segurança de dados robusta |
| 3 | **Cobertura de testes abrangente** (263 arquivos de teste, 600 testes portal) | Confiabilidade em deploys |
| 4 | **Pipeline anti-cheat multi-camada** (6 verificações) | Integridade dos dados de corrida |
| 5 | **Multi-tenancy com re-verificação** no middleware | Isolamento de dados confiável |
| 6 | **Offline-first** com sincronização bidirecional | UX resiliente sem conectividade |
| 7 | **40 loading.tsx** com skeletons | Percepção de performance superior |
| 8 | **CI/CD com 4 workflows** + pre-commit hooks | Qualidade de código automatizada |
| 9 | **Segurança em camadas** (CSP, CSRF, rate limiting, HMAC, RLS, audit) | Defesa em profundidade |
| 10 | **Design system próprio** com light/dark mode | Consistência visual |

---

## 10. Pontos Fracos e Riscos

| # | Risco | Severidade | Descrição |
|---|-------|-----------|-----------|
| 1 | **Isar v3 EOL** | 🔴 Crítico | Banco local sem suporte. Sem patches de segurança ou compatibilidade com futuras versões do Flutter. Migração inevitável. |
| 2 | **Navegação imperativa (99 telas)** | 🟡 Médio | Navigator 1.0 com 99 telas gera complexidade crescente. Deep links e state restoration difíceis de manter. Recomendada migração para GoRouter ou auto_route. |
| 3 | **Screens que bypasam BLoC** | 🟡 Médio | Violação da arquitetura limpa. Cria acoplamento direto entre UI e dados, dificultando testes e manutenção. |
| 4 | **131 migrations SQL** | 🟡 Médio | Volume alto de migrations pode tornar o setup de desenvolvimento lento e propenso a conflitos. Considerar squash periódico. |
| 5 | **59 Edge Functions sem versionamento explícito** | 🟡 Médio | Quantidade significativa de funções distribuídas. Risco de duplicação de lógica e dificuldade de rastreamento. Mitigado parcialmente pelos 10 módulos compartilhados. |
| 6 | **Dependência de múltiplos gateways de pagamento** | 🟢 Baixo | Asaas + Stripe + MercadoPago aumentam superfície de manutenção, mas proporcionam flexibilidade de mercado. |
| 7 | **Acoplamento com Supabase** | 🟢 Baixo | Forte dependência de features específicas do Supabase (RLS, Edge Functions, Auth). Migração futura seria custosa. Risco aceitável dado o valor entregue. |

---

## 11. Recomendações Prioritárias

1. **Migrar Isar v3** para alternativa suportada (Drift, ObjectBox ou Hive) — prioridade máxima
2. **Adotar navegação declarativa** (GoRouter) para as 99 telas — melhora manutenibilidade e deep linking
3. **Corrigir violações de BLoC** — garantir que todas as screens acessem dados via BLoC
4. **Considerar squash de migrations** — consolidar as 131 migrations periodicamente
5. **Documentar contratos das Edge Functions** — criar catálogo de APIs para as 59 funções

---

*Documento gerado como parte da auditoria profissional do produto Omni Runner.*
