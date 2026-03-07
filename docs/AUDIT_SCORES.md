# Auditoria de Pontuação por Dimensão — Omni Runner

**Data:** 06 de março de 2026
**Versão:** 1.0
**Escopo:** Avaliação quantitativa do Omni Runner em 6 dimensões de qualidade, com justificativa detalhada para cada nota.

---

## Metodologia

Cada dimensão é avaliada na escala de 0 a 100, onde:

| Faixa | Classificação | Significado |
|---|---|---|
| 0-20 | Crítico | Não funcional ou severamente deficiente |
| 21-40 | Insuficiente | Funciona parcialmente, muitas lacunas |
| 41-60 | Adequado | Funcional com ressalvas significativas |
| 61-75 | Bom | Sólido, com pontos de melhoria identificados |
| 76-85 | Muito Bom | Acima da média, poucas lacunas |
| 86-95 | Excelente | Referência de qualidade, melhorias marginais |
| 96-100 | Excepcional | Raro, padrão de excelência da indústria |

---

## Resumo de Pontuações

| # | Dimensão | Pontuação | Classificação |
|---|---|:---:|---|
| 1 | Engenharia | **78** | Muito Bom |
| 2 | UX | **62** | Bom |
| 3 | Robustez | **80** | Muito Bom |
| 4 | Escalabilidade | **68** | Bom |
| 5 | Clareza do Produto | **58** | Adequado |
| 6 | Maturidade do MVP | **76** | Muito Bom |

---

## 1. Engenharia — 78/100 (Muito Bom)

**Definição:** Qualidade da arquitetura, padrões de código, cobertura de testes, pipeline de CI/CD e práticas de desenvolvimento.

### Justificativa

- **Arquitetura bem definida e consistente:** O app Flutter segue Clean Architecture com separação clara de camadas (domain, data, presentation). O portal Next.js utiliza App Router, padrão moderno recomendado. O backend Supabase com 32+ tabelas RLS e 59 Edge Functions demonstra arquitetura serverless bem estruturada. Essa consistência em 3 camadas tecnológicas distintas é notável. **(+15)**

- **Cobertura de testes substancial, porém desbalanceada:** 263 arquivos de teste (169 no app, 600 testes no portal) representam investimento significativo em qualidade. Os testes de penetração RLS no backend são especialmente relevantes para um produto com dados financeiros. Contudo, apenas 6 de 99 telas (~6%) possuem widget tests, criando um gap severo na camada de apresentação. Testes de integração e E2E não são mencionados. **(-10)**

- **CI/CD funcional com 4 workflows:** Pipeline automatizado garante que regressões sejam detectadas antes do merge. A existência de 4 workflows distintos indica cobertura de múltiplos cenários (lint, test, build, deploy provavelmente). Falta publicação automatizada em stores e testes de carga no CI. **(-5)**

- **Padrões arquiteturais aplicados com algumas violações:** Clean Architecture é respeitada na maioria do codebase, mas existem instâncias de BLoC bypass (screens acessando dados fora do padrão) e duplicação de lógica de anti-cheat. A ausência de roteamento declarativo em 99 telas é uma dívida técnica arquitetural significativa. **(-7)**

- **Qualidade documental excepcional:** 212 arquivos de documentação para um MVP é muito acima da média da indústria. Isso demonstra disciplina e facilita onboarding de novos desenvolvedores, manutenção e auditoria. **(+5)**

**Fatores de penalização:**
- Dependência Isar v3 EOL (-5)
- Anti-cheat duplicado/não-DRY (-3)
- BLoC bypass em telas (-2)
- Sem roteamento declarativo (-5)
- Widget test gap 6/99 (-5)

**Fatores de bonificação:**
- 131 migrações = schema maduro (+3)
- Testes de penetração RLS (+5)
- 212 docs (+5)
- Sealed failures pattern (+3)
- Sentry integrado (+2)

---

## 2. UX — 62/100 (Bom)

**Definição:** Clareza da interface, navegação, consistência visual, feedback ao usuário e experiência de onboarding.

### Justificativa

- **Design token system implementado:** A existência de um sistema de design tokens indica preocupação com consistência visual e possibilidade de tematização. Isso é uma prática de nível profissional que muitos produtos maduros não possuem. **(+10)**

- **99 telas indicam cobertura funcional ampla:** A quantidade de telas sugere que os fluxos do usuário são bem decompostos, com telas dedicadas para cada funcionalidade. Porém, sem roteamento declarativo, a navegação entre essas 99 telas pode ser confusa para o desenvolvimento e potencialmente para o usuário se não houver hierarquia clara. **(+5/-5)**

- **Dark mode hardcoded é uma falha de UX:** O usuário não tem controle sobre o tema visual do app. Forçar dark mode pode prejudicar usabilidade em condições de alta luminosidade (corrida ao ar livre com sol). Para um app de corrida, isso é particularmente problemático. Dark mode deveria ser opção, não imposição. **(-8)**

- **Internacionalização preparada mas não ativa:** A estrutura i18n está ready, mas sem evidência de múltiplos idiomas ativos. Para o mercado brasileiro, português é suficiente inicialmente, mas strings hardcoded podem dificultar futuras expansões. **(-3)**

- **Sem evidência de onboarding guiado ou tutoriais in-app:** Com a complexidade funcional do produto (gamificação, OmniCoins, desafios, ligas, parcerias), um onboarding guiado é essencial. Não há menção de fluxo de primeiro uso, tooltips contextuais ou tutoriais. Para assessorias adotando a plataforma, a curva de aprendizado pode ser íngreme. **(-12)**

**Observações:**
- Sem acesso direto ao app rodando, a avaliação de UX é limitada aos indicadores estruturais (design tokens, temas, i18n, quantidade de telas).
- A avaliação seria mais precisa com screenshots, gravações de fluxo ou acesso ao app.

**Fatores de penalização:**
- Dark mode sem toggle (-8)
- Sem onboarding/tutoriais evidentes (-12)
- 99 telas sem roteamento declarativo (risco de UX) (-5)
- i18n não ativo (-3)

**Fatores de bonificação:**
- Design tokens (+10)
- Offline-first (UX resiliente) (+5)
- 99 telas (cobertura funcional) (+5)

---

## 3. Robustez — 80/100 (Muito Bom)

**Definição:** Tratamento de erros, resiliência offline, idempotência de operações, segurança financeira e controle de permissões.

### Justificativa

- **Tratamento de erros multi-camada com sealed failures é excelente:** O padrão de sealed failures garante que erros são tipados e tratados exaustivamente pelo compilador. Combinado com Sentry para monitoramento em produção, isso cria um pipeline completo de detecção, classificação e resposta a erros. Poucos MVPs implementam esse nível de rigor. **(+15)**

- **Arquitetura offline-first é crítica e bem implementada:** Para um app de corrida, perder dados de atividade por falta de conexão é inaceitável. A arquitetura offline-first garante que treinos são registrados localmente e sincronizados quando possível. Isso demonstra entendimento profundo do domínio. **(+10)**

- **Operações financeiras idempotentes previnem erros críticos:** Em um sistema que lida com dinheiro real (OmniCoins = US$ 1), a idempotência previne cobranças duplicadas, transferências repetidas e inconsistências de saldo. Isso é requisito de nível fintech e está implementado. **(+12)**

- **Segurança abrangente com múltiplas camadas:** CSP, CSRF, rate limiting, HMAC, audit logging e RLS com testes de penetração formam uma postura de segurança robusta. Para um produto que lida com dados financeiros e pessoais, isso é essencial e está bem executado. **(+10)**

- **Rate limiter in-memory é ponto fraco significativo:** O rate limiter atual não persiste estado entre instâncias, o que significa que em cenários de escala horizontal (múltiplos pods/containers), os limites podem ser contornados. Para operações financeiras, isso é um risco de segurança concreto. **(-10)**

**Fatores de penalização:**
- Rate limiter in-memory (-10)
- Isar v3 EOL pode causar falhas em runtime (-5)
- Anti-cheat duplicado pode causar validações inconsistentes (-3)
- Sem testes de carga para validar robustez sob pressão (-5)

**Fatores de bonificação:**
- Sealed failures (+8)
- Sentry integrado (+5)
- Offline-first (+10)
- Idempotência financeira (+12)
- RLS + testes de penetração (+10)
- HMAC + audit logging (+5)
- Queue-based webhook processing (+5)

---

## 4. Escalabilidade — 68/100 (Bom)

**Definição:** Design do banco de dados, funções stateless, estratégia de caching, e potenciais gargalos de escala.

### Justificativa

- **Edge Functions serverless são inerentemente escaláveis:** As 59 Edge Functions no Supabase são stateless por natureza, escalando horizontalmente sem configuração. Isso é uma escolha arquitetural sólida para escala. Contudo, a dependência do Supabase como provider único cria risco de vendor lock-in. **(+10)**

- **Schema de banco maduro com 131 migrações:** 32+ tabelas com RLS e 131 migrações indicam um schema que evoluiu de forma controlada e disciplinada. Migrações versionadas permitem reprodutibilidade e rollback. Contudo, não há evidência de particionamento, sharding ou estratégias para tabelas de alto volume (atividades GPS, transações de OmniCoins). **(-5)**

- **Rate limiter in-memory impede escala horizontal:** Este é o gargalo mais concreto. Em cenário de múltiplas instâncias (que é o cenário natural de escala), o rate limiter perde eficácia. Para um sistema financeiro, isso é bloqueador de escala. **(-12)**

- **Sem evidência de caching estratégico:** Não há menção de Redis, CDN para assets estáticos do portal, ou caching de queries frequentes. Rankings, leaderboards e dashboards de KPIs seriam candidatos naturais para caching. A ausência de cache pode causar gargalos em consultas repetitivas. **(-8)**

- **Queue-based webhook processing é positivo:** O processamento de webhooks (Strava, pagamentos) via filas previne perda de eventos e permite processamento assíncrono. Isso é escalável, mas a implementação específica (qual sistema de filas?) impacta o teto de escala. **(+5)**

**Fatores de penalização:**
- Rate limiter in-memory (-12)
- Sem caching evidenciado (-8)
- Sem estratégia de particionamento de dados (-5)
- Vendor lock-in Supabase (-5)
- Sem testes de carga (-5)

**Fatores de bonificação:**
- 59 Edge Functions stateless (+10)
- 131 migrações controladas (+5)
- Queue-based webhooks (+5)
- Offline-first reduz carga no servidor (+3)

---

## 5. Clareza do Produto — 58/100 (Adequado)

**Definição:** O produto comunica claramente o que faz? Labels, tutoriais, onboarding e documentação voltada ao usuário são adequados?

### Justificativa

- **Documentação técnica excepcional (212 docs), mas voltada ao desenvolvedor:** A vasta documentação do projeto (ARCHITECTURE.md, AUDIT files, ADRs, etc.) é referência para times de engenharia. Porém, documentação técnica não é documentação de produto. Não há evidência de help center, FAQs, guias de usuário ou documentação voltada ao cliente final (assessoria ou atleta). **(-15)**

- **Complexidade funcional alta sem evidência de guidance:** O produto oferece OmniCoins, XP, badges, desafios, campeonatos, ligas, missões, temporadas, parcerias, clearing, rankings, metas de grupo — uma quantidade enorme de conceitos. Sem tutoriais in-app, tooltips contextuais ou onboarding progressivo, o usuário (especialmente o gestor de assessoria) pode se sentir sobrecarregado. **(-12)**

- **Nomenclatura proprietária requer explicação:** "OmniCoins", "clearing", "auto-split", "temporadas" — esses termos podem não ser intuitivos para gestores de assessorias de corrida, que geralmente não têm background técnico ou financeiro. A clareza dos labels e a presença de explicações contextuais são críticas e não podem ser avaliadas positivamente sem evidência. **(-8)**

- **Portal B2B com KPIs e exportações sugere profissionalismo:** A presença de dashboards com KPIs, exportações e audit trail no portal indica preocupação com a experiência do gestor de assessoria. Se bem implementados, esses elementos comunicam valor profissional. **(+8)**

- **ASO (App Store Optimization) documentado:** A existência de ASO_SCREENSHOTS_GUIDE.md e ASO_STORE_DESCRIPTION.md indica preocupação com a comunicação do produto nas stores, o que é positivo para clareza na aquisição. **(+5)**

**Fatores de penalização:**
- Sem help center ou docs para usuário final (-15)
- Complexidade sem guidance (-12)
- Nomenclatura proprietária sem contexto (-8)
- Sem evidência de tooltips ou tutoriais in-app (-7)

**Fatores de bonificação:**
- 212 docs técnicos (+5)
- ASO documentado (+5)
- Portal com KPIs (+8)
- Design tokens (consistência visual) (+5)
- i18n ready (+2)

---

## 6. Maturidade do MVP — 76/100 (Muito Bom)

**Definição:** Completude funcional, prontidão para uso real, viabilidade do modelo de negócio e nível de acabamento do produto.

### Justificativa

- **Funcionalidades excedem significativamente o esperado de um MVP:** GPS tracking + anti-cheat + gamificação completa + economia de moeda + coaching + financeiro + social + parcerias + portal B2B — isso é escopo de produto em estágio de crescimento, não de MVP. A profundidade funcional é o ponto mais forte da maturidade. **(+20)**

- **Modelo de negócio articulado e implementado:** A economia de OmniCoins (1 coin = US$ 1) com custódia, clearing entre assessorias, multi-gateway de pagamento com auto-split e taxas de plataforma demonstra um modelo de negócio pensado e implementado tecnicamente. Poucos MVPs chegam a esse nível de sofisticação no modelo de receita. **(+12)**

- **Infraestrutura de produção presente:** Sentry para monitoramento, CI/CD com 4 workflows, 263 testes, RLS com testes de penetração, audit trail. A infraestrutura necessária para operar em produção está substancialmente presente. **(+10)**

- **Sem validação de mercado mencionada:** Não há evidência de usuários reais, assessorias operando na plataforma ou métricas de uso. Um MVP, por definição, deve validar hipóteses de mercado. Sem essa validação, a maturidade é técnica, não comercial. **(-12)**

- **Dívidas técnicas identificadas criam risco para evolução:** Isar v3 EOL, rate limiter in-memory, anti-cheat duplicado, BLoC bypass, widget test gap — essas dívidas, embora não bloqueiem o funcionamento atual, criam risco acumulado para evolução e manutenção. **(-8)**

**Fatores de penalização:**
- Sem usuários em produção (-12)
- Dívida técnica acumulada (-8)
- Isar v3 EOL como risco de dependência (-5)
- Sem publicação automatizada (-3)
- Dark mode hardcoded (acabamento) (-2)

**Fatores de bonificação:**
- Escopo funcional excepcional (+20)
- Modelo de negócio implementado (+12)
- Infraestrutura de produção (+10)
- 131 migrações (schema maduro) (+5)
- 212 docs (+3)

---

## Tabela Consolidada

| # | Dimensão | Pontuação | Peso Sugerido | Classificação |
|---|---|:---:|:---:|---|
| 1 | Engenharia | **78** | 25% | Muito Bom |
| 2 | UX | **62** | 10% | Bom |
| 3 | Robustez | **80** | 20% | Muito Bom |
| 4 | Escalabilidade | **68** | 10% | Bom |
| 5 | Clareza do Produto | **58** | 10% | Adequado |
| 6 | Maturidade do MVP | **76** | 25% | Muito Bom |

**Média ponderada sugerida:** (78×0.25) + (62×0.10) + (80×0.20) + (68×0.10) + (58×0.10) + (76×0.25) = **74.3**

---

## Observações Metodológicas

1. **Limitação de acesso:** As pontuações são baseadas nos dados fornecidos (métricas de código, lista de features, fraquezas conhecidas), sem acesso direto ao app rodando, screenshots ou gravações de uso. Dimensões como UX e Clareza do Produto são as mais impactadas por essa limitação.

2. **Viés de completude:** O produto apresenta uma quantidade incomum de features para um MVP, o que eleva notas de maturidade e engenharia, mas pode não refletir a qualidade individual de cada feature.

3. **Ausência de métricas de runtime:** Não há dados de performance em produção (tempo de resposta de APIs, crash rate, ANR rate, tempo de tracking GPS). Essas métricas impactariam diretamente Robustez e Escalabilidade.

4. **Pontuações são pontos no tempo:** As notas refletem o estado atual do produto. Resolver os 3 bloqueadores críticos (Isar v3, rate limiter, widget tests) poderia elevar a média em 5-8 pontos.

---

*Documento gerado como parte da auditoria completa do Omni Runner.*
*Próximo documento: AUDIT_FINAL_REPORT.md*
