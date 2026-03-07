# Auditoria de Maturidade do Produto — Omni Runner

**Data:** 06 de março de 2026
**Versão:** 1.0
**Escopo:** Avaliação de maturidade do produto Omni Runner como plataforma de gestão de assessorias de corrida, engajamento de atletas e controle financeiro.

---

## 1. O MVP Resolve o Problema Central?

**Problema central:** Assessorias de corrida brasileiras precisam de uma plataforma unificada para gerenciar atletas, prescrever treinos, acompanhar desempenho via GPS, engajar alunos e controlar o fluxo financeiro — tudo em um único ecossistema.

**Veredicto: Sim, o MVP resolve o problema central de forma abrangente.**

O Omni Runner entrega uma solução end-to-end que cobre os três pilares fundamentais de uma assessoria de corrida:

- **Gestão de atletas e treinos:** O portal B2B oferece CRM de atletas, construtor de treinos com exportação .FIT, analytics de engajamento e gerenciamento multi-tenant. A assessoria tem visibilidade completa sobre seus alunos.
- **Engajamento e retenção:** O sistema de gamificação (XP, badges, desafios, campeonatos, ligas, missões, temporadas) e a economia de OmniCoins criam loops de retenção que vão muito além do que se espera de um MVP.
- **Controle financeiro:** A custódia de OmniCoins (1 coin = US$ 1), clearing entre assessorias, integração com Asaas (auto-split), Stripe e MercadoPago, e operações financeiras idempotentes formam uma camada financeira de nível profissional.

A cobertura funcional é notavelmente ampla: GPS tracking com anti-cheat, integração com Strava, social (amigos, grupos, rankings), arquitetura offline-first, e um portal administrativo completo com KPIs, exportações e audit trail.

---

## 2. Análise de Completude de Features

### 2.1 Features Presentes e Funcionais

| Categoria | Features | Status |
|---|---|---|
| **Tracking** | GPS tracking, anti-cheat (velocidade, teleporte, veículo, cadência, FC) | Completo |
| **Integrações** | Strava OAuth, importação de atividades, sync via webhook | Completo |
| **Gamificação** | OmniCoins, XP, badges, desafios, campeonatos, ligas, missões, temporadas | Completo |
| **Coaching** | Construtor de treinos, exportação .FIT, gestão de atletas, CRM, analytics | Completo |
| **Financeiro** | Custódia OmniCoin, clearing, Asaas com auto-split, Stripe, MercadoPago, taxas | Completo |
| **Social** | Amigos, grupos, metas de grupo, rankings, detecção de parques | Completo |
| **Portal** | Admin multi-tenant, controle financeiro, KPIs, exportações, audit trail | Completo |
| **Admin** | Aprovação de assessorias, gestão de taxas, produtos, tickets de suporte | Completo |
| **Parcerias** | Parcerias entre assessorias para campeonatos conjuntos | Completo |
| **Infraestrutura** | Offline-first, dark mode, design tokens, i18n ready | Completo |
| **Qualidade** | 263 arquivos de teste, 4 workflows CI, monitoramento Sentry | Completo |
| **Segurança** | CSP, CSRF, rate limiting, HMAC, audit logging, RLS com testes de penetração | Completo |

### 2.2 Features Parcialmente Implementadas

| Feature | Estado | Observação |
|---|---|---|
| Dark mode | Funcional, porém hardcoded | Sem toggle para o usuário escolher tema |
| Internacionalização | Estrutura preparada (i18n ready) | Sem evidência de múltiplos idiomas ativos |
| Cobertura de widget tests | 6 de 99 telas testadas | Gap significativo na camada de apresentação |
| Publicação em stores | Manual | Sem pipeline automatizado de publicação |

### 2.3 Features Ausentes

| Feature | Impacto | Prioridade |
|---|---|---|
| Toggle de tema (dark/light) | Baixo | Média |
| Roteamento declarativo (Flutter) | Médio (manutenção) | Alta |
| Rate limiter distribuído (Redis) | Alto (escalabilidade) | Alta |
| Testes de carga/stress no CI | Médio (confiabilidade) | Média |
| Testes de regressão visual | Baixo | Baixa |
| Pipeline de publicação automatizada | Médio (operacional) | Média |

---

## 3. Features que Bloqueariam Uso Real

Avaliando criticamente o que impediria uma assessoria real de operar com o Omni Runner em produção:

### 3.1 Bloqueadores Críticos

1. **Isar v3 EOL:** A dependência de um banco de dados local em fim de vida representa risco de incompatibilidade com futuras versões do Flutter/Dart. Em produção, uma falha no Isar significaria perda de dados offline e degradação severa da experiência do usuário. **Mitigação necessária:** Plano de migração para alternativa mantida (Isar v4, Drift, ObjectBox).

2. **Rate limiter in-memory:** Em cenário de múltiplas instâncias (escala horizontal), o rate limiter atual não compartilha estado entre instâncias, permitindo bypass de limites. Para operações financeiras, isso é um risco de segurança. **Mitigação necessária:** Migração para Redis ou solução distribuída.

3. **Cobertura de testes de UI (6/99 telas):** Com apenas 6% das telas cobertas por widget tests, regressões visuais e funcionais podem passar despercebidas em releases. Para um app que lida com dinheiro real (OmniCoins), isso é preocupante. **Mitigação necessária:** Aumentar cobertura para pelo menos 40-50% das telas críticas.

### 3.2 Riscos Significativos (Não Bloqueadores Imediatos)

4. **Lógica de anti-cheat duplicada:** Código não-DRY aumenta risco de inconsistências em validações de atividades. Uma falha em uma instância que não é replicada na outra pode causar validações incorretas.

5. **BLoC bypass em algumas telas:** Screens acessando dados fora do padrão arquitetural aumentam acoplamento e dificultam testes e manutenção.

6. **99 telas sem roteamento declarativo:** A navegação imperativa em 99 telas cria complexidade significativa de manutenção e dificulta deep linking, analytics de navegação e testes de fluxo.

---

## 4. Features que Excedem Expectativas de MVP

O Omni Runner apresenta diversas funcionalidades que vão significativamente além do que se espera de um MVP:

### 4.1 Sistema de Gamificação Completo
A implementação de OmniCoins (moeda com paridade ao dólar), XP, badges, desafios, campeonatos, ligas, missões e temporadas representa um engine de gamificação de nível de produto maduro. MVPs tipicamente implementam 1-2 mecânicas de engajamento; o Omni Runner implementa 8+.

### 4.2 Anti-Cheat Multi-Camada
Validação de velocidade, detecção de teleporte, detecção de veículo, validação de cadência e frequência cardíaca. Esse nível de sofisticação é comparável a plataformas estabelecidas como o Strava, que levou anos para desenvolver sistemas anti-cheat equivalentes.

### 4.3 Engine Financeiro com Custódia
Operações financeiras idempotentes, clearing entre assessorias, integração com 3 gateways de pagamento (Asaas, Stripe, MercadoPago), auto-split de receita e taxas de plataforma. Isso é infraestrutura de fintech, não de MVP.

### 4.4 Segurança de Nível Enterprise
CSP, CSRF, rate limiting, HMAC, audit logging, RLS com testes de penetração. A postura de segurança excede significativamente o padrão de startups em estágio inicial.

### 4.5 Portal B2B Multi-Tenant
30+ páginas, 40+ rotas de API, 600 testes. Um portal administrativo completo com controle financeiro, KPIs, exportações e audit trail é tipicamente um produto separado, não uma feature de MVP.

### 4.6 Arquitetura Offline-First
Para um app de corrida, a capacidade de funcionar sem conexão é essencial, mas a implementação de offline-first com sincronização é um desafio arquitetural significativo que muitos produtos maduros ainda não resolvem bem.

### 4.7 Parcerias entre Assessorias
A capacidade de assessorias parceiras realizarem campeonatos conjuntos é uma feature de marketplace que pressupõe visão de produto madura.

---

## 5. Avaliação de Prontidão para Usuários Reais

### 5.1 Prontidão para Assessorias (B2B)

| Critério | Status | Nota |
|---|---|---|
| Gestão de alunos | Pronto | CRM funcional com analytics |
| Prescrição de treinos | Pronto | Construtor com exportação .FIT |
| Controle financeiro | Pronto | Multi-gateway com clearing |
| Dashboard de KPIs | Pronto | Portal com exportações |
| Audit trail | Pronto | Registro de operações |
| Onboarding de assessoria | Parcial | Fluxo de aprovação existe, mas sem evidência de tutorial guiado |
| Suporte ao cliente | Parcial | Sistema de tickets existe |

**Veredicto B2B:** O portal está pronto para uso real por assessorias com suporte técnico próximo. Recomenda-se onboarding assistido nos primeiros clientes.

### 5.2 Prontidão para Atletas (B2C via assessoria)

| Critério | Status | Nota |
|---|---|---|
| Tracking de corrida | Pronto | GPS com anti-cheat |
| Visualização de treinos | Pronto | 99 telas no app |
| Gamificação | Pronto | Engine completo |
| Social | Pronto | Amigos, grupos, rankings |
| Offline | Pronto | Offline-first |
| Strava sync | Pronto | OAuth + webhook |
| Experiência visual | Parcial | Dark mode hardcoded, sem toggle |
| Estabilidade | Parcial | 6% de telas com widget tests |

**Veredicto B2C:** O app está funcionalmente pronto, mas a baixa cobertura de testes de UI e a dependência do Isar v3 EOL representam riscos de estabilidade em uso real prolongado.

---

## 6. Prontidão Técnica

### 6.1 Estabilidade

| Aspecto | Avaliação |
|---|---|
| Arquitetura | Clean Architecture (app) + App Router (portal) — padrões sólidos e bem estabelecidos |
| Tratamento de erros | Multi-camada com sealed failures + Sentry — excelente |
| Monitoramento | Sentry integrado em toda a stack — produção-ready |
| CI/CD | 4 workflows CI — pipeline de qualidade funcional |
| Testes | 263 arquivos de teste incluindo testes de penetração RLS — acima da média |
| Banco de dados | 131 migrações, 32+ tabelas com RLS — esquema maduro |
| Edge Functions | 59 funções serverless — backend robusto |

### 6.2 Riscos Técnicos para Produção

| Risco | Severidade | Probabilidade |
|---|---|---|
| Isar v3 EOL causa incompatibilidade | Alta | Média (6-12 meses) |
| Rate limiter bypass em multi-instância | Alta | Alta (ao escalar) |
| Regressão visual não detectada | Média | Alta (sem testes visuais) |
| Widget crash não coberto por testes | Média | Média |
| Anti-cheat inconsistente por duplicação | Média | Baixa |

### 6.3 Veredicto Técnico

A base técnica é sólida e profissional. O produto pode ir para produção com usuários reais, desde que:
1. Exista plano de migração do Isar v3 com timeline definido.
2. O rate limiter seja migrado para Redis antes de escalar horizontalmente.
3. A cobertura de widget tests aumente gradualmente, priorizando fluxos financeiros e de tracking.

---

## 7. Viabilidade do Modelo de Negócio

### 7.1 Economia de OmniCoins

| Aspecto | Avaliação |
|---|---|
| Paridade (1 OmniCoin = US$ 1) | Modelo claro e fácil de entender |
| Custódia | Implementada com idempotência — sólida |
| Clearing entre assessorias | Permite ecossistema de parcerias |
| Risco regulatório | Moeda virtual com paridade fixa pode atrair escrutínio regulatório dependendo do volume. Necessário parecer jurídico. |

### 7.2 Billing e Split

| Aspecto | Avaliação |
|---|---|
| Multi-gateway (Asaas, Stripe, MercadoPago) | Cobertura ampla do mercado brasileiro e internacional |
| Auto-split via Asaas | Automatiza distribuição de receita |
| Taxas de plataforma | Modelo de receita claro e escalável |
| Operações idempotentes | Previne cobranças duplicadas — essencial |

### 7.3 Viabilidade

O modelo de negócio é **viável e bem estruturado**:
- **Receita recorrente** via taxas de manutenção das assessorias.
- **Receita transacional** via percentual sobre OmniCoins e transações.
- **Network effects** via parcerias entre assessorias e campeonatos conjuntos.
- **Lock-in positivo** via gamificação (XP, badges, histórico) e economia de OmniCoins.

**Risco principal:** A complexidade do engine financeiro exige auditoria contábil/jurídica antes de operar com volumes significativos. Operações com moeda virtual e split de receita têm implicações fiscais e regulatórias no Brasil.

---

## 8. Veredicto Geral de Maturidade

### Classificação: MVP Avançado / Produto Pré-Lançamento

O Omni Runner **não é um MVP típico**. Em termos de funcionalidades, arquitetura e profundidade técnica, ele está significativamente acima do que se espera de um primeiro produto viável. A classificação mais precisa seria **MVP Avançado** ou **Produto Pré-Lançamento**.

### Pontos que sustentam essa classificação:

**A favor de "produto maduro":**
- ~1.000 arquivos de código-fonte (636 app + 338 portal)
- 263 arquivos de teste com CI/CD
- Engine financeiro com custódia e multi-gateway
- Anti-cheat multi-camada
- Segurança de nível enterprise
- Portal B2B completo com 600 testes
- 131 migrações de banco — esquema estável
- Monitoramento Sentry completo
- 212 arquivos de documentação

**A favor de "ainda é MVP":**
- Sem usuários em produção mencionados
- Dependência EOL (Isar v3)
- 6% de cobertura de widget tests
- Rate limiter não distribuído
- Dívida técnica identificada (anti-cheat duplicado, BLoC bypass)
- Sem publicação automatizada em stores
- Dark mode sem toggle de usuário

### Escala de Maturidade

```
[Protótipo] → [MVP] → [MVP Avançado ★] → [Beta] → [GA] → [Produto Maduro]
                              ↑
                        Omni Runner
```

O produto está pronto para **beta fechado com assessorias selecionadas**, com acompanhamento técnico próximo. Para lançamento aberto (GA), é necessário resolver os bloqueadores críticos (Isar v3, rate limiter, cobertura de testes) e obter parecer jurídico sobre a economia de OmniCoins.

---

*Documento gerado como parte da auditoria completa do Omni Runner.*
*Próximos documentos: AUDIT_MARKET_POSITION.md, AUDIT_SCORES.md, AUDIT_FINAL_REPORT.md*
