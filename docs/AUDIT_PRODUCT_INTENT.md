# Análise de Intenção do Produto — Omni Runner

**Data:** 2026-03-06
**Método:** Análise reversa baseada exclusivamente na observação do código-fonte, schema do banco, fluxos implementados e features entregues.
**Classificação:** Documento de auditoria profissional

---

## 1. Qual Problema o Produto Resolve

### O Problema Central

Assessorias de corrida no Brasil operam de forma fragmentada: usam planilhas para treinos, WhatsApp para comunicação, transferências bancárias para cobrança, e Strava/Garmin para acompanhar atividades. O coach não tem visão unificada dos atletas, não consegue monetizar além da mensalidade básica, e não tem ferramentas para engajar e reter sua base.

### Problemas Específicos Identificados no Código

| Problema | Evidência no Sistema |
|----------|---------------------|
| **Fragmentação de ferramentas** | Integrações com Strava, TrainingPeaks, wearables BLE — o sistema centraliza dados dispersos |
| **Cobrança manual** | Motor financeiro com Asaas, split automático, manutenção por atleta — automatiza billing |
| **Falta de engajamento** | Gamificação completa (OmniCoins, XP, badges, desafios, ligas, campeonatos) — cria retenção |
| **Sem dados de performance** | Dashboard de analytics, métricas de engajamento, CRM — dá visibilidade ao coach |
| **Isolamento entre assessorias** | Sistema de parcerias e campeonatos inter-assessorias — cria rede |
| **Trapaça em competições** | Pipeline anti-cheat com 6 camadas — protege a integridade |
| **Dependência de conectividade** | Offline-first com Isar + sync — funciona durante corridas sem sinal |

### Hipótese de Produto (derivada do código)

> "Se dermos às assessorias de corrida uma plataforma unificada que combina gestão de atletas, treinos estruturados, gamificação com valor real (OmniCoins), e billing automatizado, elas poderão escalar suas operações, aumentar o engajamento e criar novas fontes de receita — enquanto atletas ganham uma experiência de corrida gamificada e socialmente conectada."

---

## 2. Quem São os Usuários

### Persona 1: Atleta (Usuário do App)

**Perfil:** Corredor amador ou intermediário, membro de uma assessoria de corrida, entre 25-50 anos, smartphone Android/iOS, possivelmente com relógio esportivo.

| Aspecto | Detalhe |
|---------|---------|
| **Motivação primária** | Melhorar performance com orientação profissional |
| **Motivação secundária** | Pertencer a uma comunidade, competir, acumular recompensas |
| **Fluxo principal** | Abrir app → ver treino do dia → correr com GPS → registrar atividade → ganhar XP/OmniCoins |
| **Dores resolvidas** | Treino estruturado via .FIT, tracking com anti-cheat, progresso visível, recompensas tangíveis |
| **Evidências no código** | 99 telas mobile, conexão BLE, Strava sync, social features, gamificação, detecção de parques |

**Jornada típica:**
1. Recebe convite da assessoria → instala app
2. Conecta Strava e/ou wearable
3. Recebe treinos do coach no app
4. Corre com GPS tracking
5. Ganha OmniCoins e XP
6. Participa de desafios e campeonatos
7. Compete em ligas e rankings

### Persona 2: Coach / Admin da Assessoria (Usuário do Portal)

**Perfil:** Profissional de educação física que lidera um grupo de corrida (assessoria), entre 30-55 anos, gerencia de 20 a 500+ atletas.

| Aspecto | Detalhe |
|---------|---------|
| **Motivação primária** | Gerenciar e escalar sua assessoria profissionalmente |
| **Motivação secundária** | Monetizar além da mensalidade, diferenciar-se no mercado |
| **Fluxo principal** | Acessar portal → criar treinos → acompanhar atletas → gerenciar cobranças → analisar métricas |
| **Dores resolvidas** | Billing automático, treinos estruturados, visibilidade de engajamento, competições inter-assessorias |
| **Evidências no código** | 30+ rotas de assessoria, dashboard financeiro, workout builder, CRM, analytics, branding customizável |

**Capacidades no sistema:**
- Criar e gerenciar templates de treino com blocos estruturados
- Configurar billing automático via Asaas com split de pagamento
- Distribuir OmniCoins para atletas como incentivo
- Criar desafios com entry fee (nova fonte de receita)
- Organizar campeonatos e convidar assessorias parceiras
- Monitorar engajamento e retenção via analytics
- Personalizar branding (cores, logo) da assessoria no app

### Persona 3: Administrador da Plataforma (Usuário do Painel Admin)

**Perfil:** Equipe interna do Omni Runner responsável por operar a plataforma, aprovar assessorias, e monitorar o ecossistema.

| Aspecto | Detalhe |
|---------|---------|
| **Motivação primária** | Manter a plataforma saudável, aprovar assessorias, monitorar financeiro |
| **Fluxo principal** | Aprovar assessorias → monitorar OmniCoins → verificar clearing → acompanhar métricas |
| **Evidências no código** | 11+ rotas admin, audit logging, reconciliação financeira, gestão de assessorias |

**Capacidades no sistema:**
- Aprovar/rejeitar cadastro de assessorias
- Monitorar custódia global de OmniCoins
- Verificar processos de clearing e settlement
- Acessar logs de auditoria
- Gerenciar configurações globais da plataforma

---

## 3. Proposta de Valor Central

### Para Atletas
> **"Corra, ganhe, compita."** — Uma experiência de corrida gamificada onde cada quilômetro rende recompensas reais (OmniCoins = $1 USD), com treinos profissionais do seu coach, tracking GPS confiável, e competições emocionantes.

### Para Assessorias
> **"Escale sua assessoria com tecnologia."** — Plataforma completa que substitui planilhas, WhatsApp e boletos por treinos estruturados, billing automático, gamificação que retém atletas, e campeonatos que atraem novos.

### Para a Plataforma
> **"A infraestrutura das assessorias de corrida."** — Marketplace B2B2C onde assessorias operam profissionalmente, atletas se engajam via gamificação, e a plataforma captura valor via fees de manutenção e processamento financeiro.

---

## 4. Fluxos Principais de Usuário

### 4.1 Fluxo do Atleta

```
Instalação → Cadastro → Vinculação à Assessoria → Conexão Strava/Wearable
     │
     ▼
Recebe Treino → Visualiza Blocos → Exporta .FIT → Corre com GPS
     │
     ▼
Atividade Registrada → Anti-Cheat → XP + OmniCoins → Badge/Nível
     │
     ▼
Participa de Desafio → Entry Fee (OmniCoins) → Compete → Settlement
     │
     ▼
Liga/Campeonato → Ranking → Interação Social → Retenção
```

### 4.2 Fluxo da Assessoria

```
Cadastro → Aprovação pelo Admin → Configuração de Branding
     │
     ▼
Configurar Asaas → Criar Plano → Convidar Atletas → Billing Automático
     │
     ▼
Criar Templates de Treino → Montar Blocos → Atribuir a Atletas
     │
     ▼
Comprar OmniCoins (Custódia) → Distribuir para Atletas → Engajamento
     │
     ▼
Criar Desafios/Campeonatos → Parcerias → Escala → Analytics
```

### 4.3 Fluxo Financeiro

```
Assessoria deposita USD → Custódia (Saldo OmniCoins)
     │
     ├──▶ Distribuição direta para atletas
     │
     └──▶ Desafios com entry fee
              │
              ▼
         Atletas pagam entry → Pool acumula → Corrida acontece
              │
              ▼
         Settlement → Vencedores recebem → Platform fee deduzida
              │
              ▼
         Transferências OmniCoins processadas → Clearing periódico
```

---

## 5. Análise do Modelo de Receita

### 5.1 Fontes de Receita Identificadas

| Fonte | Mecanismo | Evidência |
|-------|----------|-----------|
| **Taxa de manutenção por atleta** | Assessoria paga fee mensal por atleta ativo via Asaas Split | Integração Asaas com split, manutenção por atleta |
| **OmniCoins como moeda da plataforma** | 1 OmniCoin = $1 USD. Assessorias compram, plataforma custodia | Tabelas de custody, clearing, deposits |
| **Platform fee em desafios** | Percentual retido pela plataforma em entry fees de desafios | Settlement com dedução de fees |
| **Processamento de pagamentos** | Margem sobre processamento via gateways (Asaas, Stripe, MercadoPago) | Múltiplas integrações de pagamento |

### 5.2 Análise do Motor Financeiro

```
                    ENTRADA DE CAPITAL
                          │
              ┌───────────┴───────────┐
              │                       │
       Mensalidade              Compra de
       do Atleta                OmniCoins
       (via Asaas)              (Assessoria)
              │                       │
              ▼                       ▼
       ┌──────────┐           ┌──────────────┐
       │ Split:   │           │ Custódia:    │
       │ Assessoria│           │ 1 coin = $1  │
       │ + Platform│           │ Na plataforma│
       │ Fee      │           └──────┬───────┘
       └──────────┘                  │
                              ┌──────┴───────┐
                              │              │
                        Distribuição    Entry Fees
                        gratuita       (Desafios)
                              │              │
                              ▼              ▼
                        Atletas       Pool → Settlement
                        recebem       → Platform Fee
                                      → Vencedores
```

### 5.3 Paridade OmniCoin-Dólar

A decisão de fixar 1 OmniCoin = $1 USD é significativa:

- **Simplifica contabilidade** — sem volatilidade, sem conversão complexa
- **Cria obrigação de custódia** — a plataforma mantém reserva 1:1
- **Habilita clearing** — liquidação periódica entre assessorias
- **Gera float** — capital em custódia gera rendimento para a plataforma enquanto não é utilizado
- **Exige compliance** — a operação de custódia pode ter implicações regulatórias

---

## 6. Posicionamento do Produto

### 6.1 Quadrante Competitivo (deduzido das features)

```
                    MAIS FUNCIONALIDADES
                          │
                          │
    Apps de Corrida       │       ★ OMNI RUNNER
    Genéricos             │       (Gestão + Gamificação
    (Strava, Nike Run)    │        + Financeiro)
                          │
    ──────────────────────┼──────────────────────
    CONSUMIDOR            │              B2B2C
                          │
    Apps de Treino        │       Plataformas de
    (TrainingPeaks)       │       Coaching
                          │       (sem gamificação)
                          │
                    MENOS FUNCIONALIDADES
```

### 6.2 Diferenciadores Únicos

1. **Gamificação com valor real:** OmniCoins lastreados em dólares — diferente de pontos virtuais sem valor
2. **Anti-cheat robusto:** 6 camadas de verificação — essencial para competições com dinheiro real
3. **Multi-tenancy nativo:** Cada assessoria opera independentemente com branding próprio
4. **Parcerias inter-assessorias:** Campeonatos e competições entre grupos diferentes
5. **Offline-first:** Funciona durante corridas sem sinal — crítico para uso real

### 6.3 Mercado-Alvo

O produto é claramente direcionado ao **mercado brasileiro de assessorias de corrida**:

- Interface e documentação em português
- Integração com Asaas (gateway brasileiro)
- Integração com MercadoPago (brasileiro)
- Modelo de assessoria (conceito culturalmente brasileiro)
- Detecção de parques (funcionalidade localizada)

### 6.4 Maturidade do Produto

Com base na análise do código, o produto demonstra **maturidade de produto em estágio avançado**:

| Indicador | Avaliação |
|-----------|-----------|
| **131 migrations** | Evolução contínua e significativa do schema |
| **263 arquivos de teste** | Investimento sério em qualidade |
| **Pipeline anti-cheat** | Feature sofisticada de produto maduro |
| **Motor financeiro completo** | Custódia, clearing, split — complexidade de fintech |
| **4 workflows de CI/CD** | Infraestrutura de equipe profissional |
| **Audit logging** | Consciência de compliance e rastreabilidade |
| **Rollback runbook** | Preparação para operação em produção |
| **Session replays (Sentry)** | Monitoramento proativo de UX em produção |

---

## 7. Riscos de Produto Identificados

| Risco | Severidade | Análise |
|-------|-----------|---------|
| **Complexidade crescente** | Alta | 99 telas, 59 Edge Functions, 131 migrations — o produto pode estar acumulando complexidade mais rápido que a capacidade de manter |
| **Custódia financeira** | Alta | Manter custódia 1:1 de OmniCoins exige compliance regulatório e reserva de capital |
| **Dependência de Isar v3** | Alta | Banco local em EOL ameaça a fundação offline-first |
| **Múltiplos gateways** | Média | Asaas + Stripe + MercadoPago multiplica a superfície de manutenção financeira |
| **Concentração no Brasil** | Média | Modelo fortemente acoplado ao conceito brasileiro de assessoria. Internacionalização exigiria redesign de produto |

---

## 8. Conclusão

O Omni Runner é uma plataforma ambiciosa e substancialmente desenvolvida que resolve um problema real e específico do mercado brasileiro de corrida. A combinação de gestão de assessoria, gamificação com valor monetário real, e billing automatizado cria um produto com alto potencial de lock-in tanto para assessorias quanto para atletas.

O motor financeiro (OmniCoins com lastro em dólar, clearing, custódia) eleva o produto além de um simples app de corrida para o território de fintech — o que traz tanto oportunidades de monetização quanto responsabilidades regulatórias.

A principal ameaça ao produto não é externa (competição), mas interna: a complexidade acumulada (99 telas, 131 migrations, 59 Edge Functions) precisa ser gerenciada proativamente para evitar que a velocidade de desenvolvimento degrade.

---

*Documento gerado como parte da auditoria profissional do produto Omni Runner.*
