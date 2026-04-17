# TRIAGE — Priorização dos Criticals

> **Gerado por** `tools/audit/triage.ts` em 2026-04-17.
> **Método**: score = exploitability × blast_radius × irreversibility (1 a 125).
> **Cutoff**: priority ≥ 45 → Onda 0; senão → Onda 1.

Ver racional completo do scoring em `tools/audit/triage.ts`.

## Resumo

- Total criticals: **69**
- Proposto Onda 0: **14**
- Proposto Onda 1: **55**
- Score médio: 35.1
- Score máximo: 125
- Score mínimo: 12

## Onda 0 — Stop the bleeding (priority ≥ 45)

| # | ID | Score | Expl | Blast | Irrev | Lente | Título |
|---|---|-------|------|-------|-------|-------|--------|
| 1 | [L09-04](./findings/L09-04-nota-fiscal-recibo-fiscal-nao-emitida-em-withdrawals.md) | **125** | 5 | 5 | 5 | L09 CRO | Nota fiscal / recibo fiscal não emitida em withdrawals |
| 2 | [L01-02](./findings/L01-02-post-api-custody-withdraw-criacao-e-execucao-de.md) | **100** | 4 | 5 | 5 | L01 CISO | POST /api/custody/withdraw — Criação e execução de saque em um único r |
| 3 | [L01-17](./findings/L01-17-post-api-billing-asaas-armazenamento-de-api-key.md) | **100** | 4 | 5 | 5 | L01 CISO | POST /api/billing/asaas — Armazenamento de API Key |
| 4 | [L04-03](./findings/L04-03-nao-ha-registro-de-consentimento-opt-in-explicito.md) | **100** | 5 | 5 | 4 | L04 CLO | Não há registro de consentimento (opt-in explícito LGPD Art. 8) |
| 5 | [L04-01](./findings/L04-01-fn-delete-user-data-e-incompleta-multiplas-tabelas.md) | **80** | 5 | 4 | 4 | L04 CLO | fn_delete_user_data é incompleta — múltiplas tabelas com PII não cober |
| 6 | [L18-03](./findings/L18-03-security-definer-sem-set-search-path-em-funcoes.md) | **80** | 5 | 4 | 4 | L18 Principal | SECURITY DEFINER sem SET search_path em funções antigas |
| 7 | [L04-04](./findings/L04-04-dados-de-saude-biometricos-dados-sensiveis-lgpd-art.md) | **64** | 4 | 4 | 4 | L04 CLO | Dados de saúde/biométricos (dados sensíveis, LGPD Art. 11) sem proteçã |
| 8 | [L01-44](./findings/L01-44-migration-drift-platform-fee-config-fee-type-check.md) | **60** | 5 | 4 | 3 | L01 CISO | Migration drift — platform_fee_config.fee_type CHECK + INSERT 'fx_spre |
| 9 | [L02-01](./findings/L02-01-distribute-coins-orquestracao-nao-atomica-entre-4-rpcs.md) | **60** | 4 | 5 | 3 | L02 CTO | distribute-coins — Orquestração não-atômica entre 4 RPCs (partial-fail |
| 10 | [L19-01](./findings/L19-01-coin-ledger-nao-e-particionada-tabela-crescendo-sem.md) | **60** | 5 | 4 | 3 | L19 DBA | coin_ledger não é particionada — tabela crescendo sem controle |
| 11 | [L19-05](./findings/L19-05-falta-for-update-nowait-em-funcoes-de-lock.md) | **60** | 5 | 4 | 3 | L19 DBA | Falta FOR UPDATE NOWAIT em funções de lock crítico |
| 12 | [L01-03](./findings/L01-03-post-api-distribute-coins-distribuicao-de-coins-a.md) | **50** | 2 | 5 | 5 | L01 CISO | POST /api/distribute-coins — Distribuição de coins a atleta |
| 13 | [L02-02](./findings/L02-02-execute-burn-atomic-excecoes-engolidas-em-custody-release.md) | **50** | 5 | 5 | 2 | L02 CTO | execute_burn_atomic — Exceções engolidas em custody_release_committed  |
| 14 | [L14-03](./findings/L14-03-api-docs-carrega-swagger-ui-de-unpkg-sem.md) | **45** | 5 | 3 | 3 | L14 Contracts | /api/docs carrega Swagger-UI de unpkg sem SRI |

## Onda 1 — Foundation (priority < 45)

| # | ID | Score | Expl | Blast | Irrev | Lente | Título |
|---|---|-------|------|-------|-------|-------|--------|
| 1 | [L03-20](./findings/L03-20-disputa-chargeback-stripe.md) | 40 | 2 | 5 | 4 | L03 CFO | Disputa / chargeback Stripe |
| 2 | [L05-01](./findings/L05-01-swap-race-entre-accept-e-cancel-do-dono.md) | 40 | 5 | 4 | 2 | L05 CPO | Swap: race entre accept e cancel do dono da oferta |
| 3 | [L06-01](./findings/L06-01-zero-runbook-financeiro-custodia-clearing-swap-withdraw.md) | 40 | 5 | 4 | 2 | L06 COO | Zero runbook financeiro — custódia, clearing, swap, withdraw |
| 4 | [L14-01](./findings/L14-01-74-route-handlers-46-documentados-em-openapi.md) | 40 | 5 | 4 | 2 | L14 Contracts | 74 route handlers, 46 documentados em OpenAPI |
| 5 | [L17-02](./findings/L17-02-5378-linhas-em-portal-src-lib-ts-e.md) | 40 | 5 | 4 | 2 | L17 VP Eng | 5378 linhas em portal/src/lib/*.ts e sem segregação por bounded contex |
| 6 | [L18-02](./findings/L18-02-idempotencia-ad-hoc-em-cada-rpc-padrao-nao.md) | 40 | 5 | 4 | 2 | L18 Principal | Idempotência ad-hoc em cada RPC — padrão não unificado |
| 7 | [L20-01](./findings/L20-01-sem-dashboard-consolidado-de-operacoes-financeiras.md) | 40 | 5 | 4 | 2 | L20 SRE | Sem dashboard consolidado de operações financeiras |
| 8 | [L20-02](./findings/L20-02-sem-slo-sli-definidos-impossivel-ter-alert-policy.md) | 40 | 5 | 4 | 2 | L20 SRE | Sem SLO/SLI definidos → impossível ter alert policy razoável |
| 9 | [L20-03](./findings/L20-03-sem-tracing-distribuido-opentelemetry.md) | 40 | 5 | 4 | 2 | L20 SRE | Sem tracing distribuído (OpenTelemetry) |
| 10 | [L21-03](./findings/L21-03-dados-gps-e-biometricos-sem-controle-de-propriedade.md) | 40 | 2 | 5 | 4 | L21 Atleta Pro | Dados GPS e biométricos sem controle de propriedade (dilema do patrocí |
| 11 | [L07-02](./findings/L07-02-onboarding-nao-distingue-papeis-atleta-coach-admin-master.md) | 32 | 4 | 4 | 2 | L07 CXO | Onboarding não distingue papéis (atleta, coach, admin_master) |
| 12 | [L08-02](./findings/L08-02-product-events-properties-jsonb-aceita-qualquer-payload-pii.md) | 32 | 2 | 4 | 4 | L08 CDO | product_events.properties jsonb aceita qualquer payload — PII leak ris |
| 13 | [L22-02](./findings/L22-02-conceito-de-moeda-omnicoin-confunde-amador.md) | 32 | 2 | 4 | 4 | L22 Atleta Amador | Conceito de "moeda / OmniCoin" confunde amador |
| 14 | [L03-01](./findings/L03-01-divergencia-de-formula-de-fee-ts-vs-sql.md) | 30 | 2 | 5 | 3 | L03 CFO | Divergência de fórmula de fee — TS vs SQL |
| 15 | [L03-13](./findings/L03-13-reembolso-estorno-nao-ha-funcao-reverse-burn-ou.md) | 30 | 2 | 5 | 3 | L03 CFO | Reembolso / Estorno — Não há função reverse_burn ou refund_deposit |
| 16 | [L06-02](./findings/L06-02-health-check-exibe-contagem-exata-de-violacoes-info.md) | 30 | 2 | 5 | 3 | L06 COO | Health check exibe contagem exata de violações (info leak operacional) |
| 17 | [L09-01](./findings/L09-01-modelo-de-coin-us-1-pode-ser-classificado.md) | 30 | 2 | 5 | 3 | L09 CRO | Modelo de "Coin = US$ 1" pode ser classificado como arranjo de pagamen |
| 18 | [L10-01](./findings/L10-01-nenhum-bug-bounty-disclosure-policy.md) | 30 | 5 | 3 | 2 | L10 CSO | Nenhum bug bounty / disclosure policy |
| 19 | [L11-01](./findings/L11-01-ci-sem-npm-audit-flutter-pub-audit.md) | 30 | 2 | 5 | 3 | L11 Supply Chain | CI sem npm audit / flutter pub audit |
| 20 | [L11-03](./findings/L11-03-sem-gitleaks-trufflehog-no-ci.md) | 30 | 2 | 5 | 3 | L11 Supply Chain | Sem gitleaks / trufflehog no CI |
| 21 | [L16-03](./findings/L16-03-sem-api-publica-para-parceiros-b2b.md) | 30 | 2 | 5 | 3 | L16 CAO | Sem API pública para parceiros B2B |
| 22 | [L19-03](./findings/L19-03-indexes-redundantes-em-sessions.md) | 30 | 5 | 3 | 2 | L19 DBA | Indexes redundantes em sessions |
| 23 | [L04-02](./findings/L04-02-edge-function-delete-account-deleta-auth-users-mesmo.md) | 24 | 2 | 4 | 3 | L04 CLO | Edge Function delete-account deleta auth.users mesmo quando fn_delete_ |
| 24 | [L05-02](./findings/L05-02-swap-nao-tem-ttl-expiracao-ofertas-ficam-para.md) | 24 | 2 | 4 | 3 | L05 CPO | Swap não tem TTL/expiração — ofertas ficam para sempre |
| 25 | [L05-03](./findings/L05-03-post-api-distribute-coins-amount-max-1000-conflita.md) | 24 | 2 | 4 | 3 | L05 CPO | POST /api/distribute-coins: amount max 1000 — conflita com grandes clu |
| 26 | [L10-02](./findings/L10-02-threat-model-formal-nao-documentado.md) | 24 | 2 | 4 | 3 | L10 CSO | Threat model formal não documentado |
| 27 | [L12-01](./findings/L12-01-reconcile-wallets-cron-existe-mas-nao-esta-agendado.md) | 24 | 2 | 4 | 3 | L12 Cron | reconcile-wallets-cron existe mas NÃO está agendado |
| 28 | [L13-01](./findings/L13-01-admin-only-routes-admin-professor-routes-ordem-importa.md) | 24 | 4 | 3 | 2 | L13 Middleware | ADMIN_ONLY_ROUTES + ADMIN_PROFESSOR_ROUTES — ordem importa, e está err |
| 29 | [L14-02](./findings/L14-02-sem-versionamento-de-path-api-v1.md) | 24 | 2 | 4 | 3 | L14 Contracts | Sem versionamento de path (/api/v1) |
| 30 | [L18-01](./findings/L18-01-duas-fontes-da-verdade-para-balance-de-wallet.md) | 24 | 2 | 4 | 3 | L18 Principal | Duas fontes da verdade para balance de wallet (wallets.balance_coins v |
| 31 | [L19-02](./findings/L19-02-delete-em-archive-cron-gera-table-bloat-massivo.md) | 24 | 2 | 4 | 3 | L19 DBA | DELETE em archive cron gera table bloat massivo |
| 32 | [L09-02](./findings/L09-02-ausencia-de-kyc-aml-para-grupos-com-custodia.md) | 20 | 2 | 5 | 2 | L09 CRO | Ausência de KYC/AML para grupos com custódia |
| 33 | [L02-09](./findings/L02-09-migration-drift-check-platform-fee-config-fee-type.md) | 18 | 2 | 3 | 3 | L02 CTO | Migration drift — CHECK platform_fee_config.fee_type (duplica 1.44) |
| 34 | [L07-01](./findings/L07-01-mensagens-de-erro-em-portugues-hardcoded-no-backend.md) | 18 | 2 | 3 | 3 | L07 CXO | Mensagens de erro em português hardcoded no backend |
| 35 | [L08-01](./findings/L08-01-producteventtracker-trackonce-tem-race-toctou.md) | 18 | 3 | 3 | 2 | L08 CDO | ProductEventTracker.trackOnce tem race TOCTOU |
| 36 | [L09-05](./findings/L09-05-iof-nao-recolhido-em-swap-inter-cliente.md) | 18 | 2 | 3 | 3 | L09 CRO | IOF não recolhido em swap inter-cliente |
| 37 | [L10-03](./findings/L10-03-service-role-key-distribuida-amplamente.md) | 18 | 2 | 3 | 3 | L10 CSO | Service-role key distribuída amplamente |
| 38 | [L11-02](./findings/L11-02-sem-sbom-software-bill-of-materials.md) | 18 | 2 | 3 | 3 | L11 Supply Chain | Sem SBOM (Software Bill of Materials) |
| 39 | [L12-03](./findings/L12-03-5-crons-sem-lock-overlap-risk.md) | 18 | 2 | 3 | 3 | L12 Cron | */5 * * * * crons sem lock — overlap risk |
| 40 | [L13-02](./findings/L13-02-nome-da-constante-ainda-em-portugues-admin-professor.md) | 18 | 2 | 3 | 3 | L13 Middleware | Nome da constante ainda em português (ADMIN_PROFESSOR_ROUTES) |
| 41 | [L13-03](./findings/L13-03-middleware-executa-query-db-a-cada-request-autenticado.md) | 18 | 2 | 3 | 3 | L13 Middleware | Middleware executa query DB a cada request autenticado |
| 42 | [L18-04](./findings/L18-04-architecture-flutter-viola-clean-arch-em-varios-pontos.md) | 18 | 2 | 3 | 3 | L18 Principal | Architecture: Flutter viola Clean Arch em vários pontos |
| 43 | [L21-04](./findings/L21-04-ausencia-de-training-load-tss-ctl-atl.md) | 18 | 2 | 3 | 3 | L21 Atleta Pro | Ausência de "training load" / TSS / CTL / ATL |
| 44 | [L21-05](./findings/L21-05-zonas-de-treino-pace-hr-nao-personalizaveis.md) | 18 | 2 | 3 | 3 | L21 Atleta Pro | Zonas de treino (pace/HR) não personalizáveis |
| 45 | [L22-01](./findings/L22-01-onboarding-nao-inclui-primeira-corrida-guiada.md) | 18 | 2 | 3 | 3 | L22 Atleta Amador | Onboarding não inclui "primeira corrida guiada" |
| 46 | [L23-02](./findings/L23-02-dashboard-de-overview-diario-para-coach-tem-100.md) | 18 | 2 | 3 | 3 | L23 Treinador | Dashboard de overview diário para coach tem 100-500 atletas |
| 47 | [L23-03](./findings/L23-03-comunicacao-coach-atleta-carece.md) | 18 | 2 | 3 | 3 | L23 Treinador | Comunicação coach ↔ atleta carece |
| 48 | [L23-04](./findings/L23-04-bulk-assign-semanal-ver-20260416000000-bulk-assign-and.md) | 18 | 2 | 3 | 3 | L23 Treinador | Bulk assign semanal (ver 20260416000000_bulk_assign_and_week_templates |
| 49 | [L09-03](./findings/L09-03-relatorio-de-operacoes-sos-coaf-inexistente.md) | 16 | 2 | 4 | 2 | L09 CRO | Relatório de Operações (SOS COAF) inexistente |
| 50 | [L12-02](./findings/L12-02-thundering-herd-em-02-00-04-00-utc.md) | 16 | 2 | 4 | 2 | L12 Cron | Thundering herd em 02:00–04:00 UTC |
| 51 | [L17-01](./findings/L17-01-witherrorhandler-nao-e-usado-em-endpoints-financeiros-critic.md) | 16 | 2 | 4 | 2 | L17 VP Eng | withErrorHandler não é usado em endpoints financeiros críticos |
| 52 | [L21-01](./findings/L21-01-max-speed-ms-12-5-m-s-invalida.md) | 12 | 2 | 3 | 2 | L21 Atleta Pro | MAX_SPEED_MS = 12.5 m/s invalida velocistas profissionais |
| 53 | [L21-02](./findings/L21-02-max-hr-bpm-220-inferior-a-realidade-de.md) | 12 | 2 | 3 | 2 | L21 Atleta Pro | MAX_HR_BPM = 220 inferior à realidade de atletas jovens |
| 54 | [L22-03](./findings/L22-03-plano-semanal-pessoal-ausente-para-solo-runner.md) | 12 | 2 | 3 | 2 | L22 Atleta Amador | Plano semanal pessoal ausente para solo runner |
| 55 | [L23-01](./findings/L23-01-workout-delivery-em-massa-sem-preview-por-atleta.md) | 12 | 2 | 3 | 2 | L23 Treinador | Workout delivery em massa sem preview por atleta |

## Rationale por finding (Onda 0)

### L09-04 — score 125

**Título:** Nota fiscal / recibo fiscal não emitida em withdrawals

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 5/5**: afeta plataforma inteira / todos tenants
- **Irreversibility 5/5**: violação regulatória fiscal (multa por operação)

### L01-02 — score 100

**Título:** POST /api/custody/withdraw — Criação e execução de saque em um único request

- **Exploitability 4/5**: admin_master comprometido/malicioso
- **Blast radius 5/5**: afeta plataforma inteira / todos tenants
- **Irreversibility 5/5**: perda financeira direta irrecuperável

### L01-17 — score 100

**Título:** POST /api/billing/asaas — Armazenamento de API Key

- **Exploitability 4/5**: admin_master comprometido/malicioso
- **Blast radius 5/5**: exposição cross-tenant ou secret compartilhado
- **Irreversibility 5/5**: secret vazado permite abuso persistente

### L04-03 — score 100

**Título:** Não há registro de consentimento (opt-in explícito LGPD Art. 8)

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 5/5**: afeta plataforma inteira / todos tenants
- **Irreversibility 4/5**: exposição PII sensível / violação LGPD alta gravidade

### L04-01 — score 80

**Título:** fn_delete_user_data é incompleta — múltiplas tabelas com PII não cobertas

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 4/5**: afeta todos usuários financeiros de 1+ tenants
- **Irreversibility 4/5**: exposição PII / violação LGPD

### L18-03 — score 80

**Título:** SECURITY DEFINER sem SET search_path em funções antigas

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 4/5**: afeta todos usuários financeiros de 1+ tenants
- **Irreversibility 4/5**: bypass de autorização / escalada de privilégio

### L04-04 — score 64

**Título:** Dados de saúde/biométricos (dados sensíveis, LGPD Art. 11) sem proteção reforçada

- **Exploitability 4/5**: admin_master comprometido/malicioso
- **Blast radius 4/5**: afeta dados pessoais de múltiplos usuários
- **Irreversibility 4/5**: exposição PII sensível / violação LGPD alta gravidade

### L01-44 — score 60

**Título:** Migration drift — platform_fee_config.fee_type CHECK + INSERT 'fx_spread'

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 4/5**: afeta todos usuários financeiros de 1+ tenants
- **Irreversibility 3/5**: corrupção de dados exigindo reconciliação manual

### L02-01 — score 60

**Título:** distribute-coins — Orquestração não-atômica entre 4 RPCs (partial-failure silencioso)

- **Exploitability 4/5**: admin_master comprometido/malicioso
- **Blast radius 5/5**: afeta plataforma inteira / todos tenants
- **Irreversibility 3/5**: corrupção de dados exigindo reconciliação manual

### L19-01 — score 60

**Título:** coin_ledger não é particionada — tabela crescendo sem controle

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 4/5**: afeta todos usuários financeiros de 1+ tenants
- **Irreversibility 3/5**: corrupção de dados exigindo reconciliação manual

### L19-05 — score 60

**Título:** Falta FOR UPDATE NOWAIT em funções de lock crítico

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 4/5**: afeta todos usuários financeiros de 1+ tenants
- **Irreversibility 3/5**: default (corrupção recuperável)

### L01-03 — score 50

**Título:** POST /api/distribute-coins — Distribuição de coins a atleta

- **Exploitability 2/5**: requer acesso interno (DB/CI)
- **Blast radius 5/5**: afeta plataforma inteira / todos tenants
- **Irreversibility 5/5**: inflação monetária / double-spend

### L02-02 — score 50

**Título:** execute_burn_atomic — Exceções engolidas em custody_release_committed e settle_clearing

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 5/5**: afeta plataforma inteira / todos tenants
- **Irreversibility 2/5**: DoS / downtime

### L14-03 — score 45

**Título:** /api/docs carrega Swagger-UI de unpkg sem SRI

- **Exploitability 5/5**: exploitável por qualquer requester não autenticado ou autenticado básico
- **Blast radius 3/5**: default (afeta subset de usuários)
- **Irreversibility 3/5**: default (corrupção recuperável)

## Overrides manuais

Findings cujo `wave` foi ajustado manualmente (bypass do heurístico). A regra de proteção em `tools/audit/triage.ts` respeita esses overrides em re-execuções.

| ID | Score heurístico | Wave proposto | Wave efetivo | Justificativa |
|---|---|---|---|---|
| [L05-01](./findings/L05-01-swap-race-entre-accept-e-cancel-do-dono.md) | 40 | 1 | **0** | Override manual Onda 1 → Onda 0: heurística de triage não capturou 'fundos transferidos em oferta cancelada' como perda financeira direta, mas trata-s |

## Como revisar / ajustar

1. Se discordar de um score, abra o finding (`docs/audit/findings/LXX-YY-*.md`) e edite o `wave:` no frontmatter manualmente.
2. Adicione justificativa no campo `note:` explicando por que o score heurístico não se aplica.
3. Rode `npm run audit:build` para regenerar SCORECARD.
4. Para rodar a triage novamente (se adicionar novos findings), execute `npx tsx tools/audit/triage.ts --apply`.

