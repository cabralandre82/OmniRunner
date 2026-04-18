# ROADMAP — Execução das Correções em Ondas

> **Atualizado:** 2026-04-17
> **Status do overall:** Onda 0 ✅ concluída (15/15 fixed, E2E verde) — Onda 1 em execução (17/177 fixed: supply chain quinteto L11-01/02/03/04/09 + observabilidade SRE L20-01/02/03/04/05/07/08 + runbooks financeiros L06-01 + kill switches L06-06 + custody idempotency L01-04 + swap TTL L05-02 + swap ADR cessão de crédito L02-07/ADR-008)

A auditoria identificou **348 findings** distribuídos em **23 lentes** (69 🔴 critical, 123 🟠 high, 127 🟡 medium, 17 🟢 safe, 12 ⚪ não-auditados). Corrigir todos em paralelo seria caótico. Esta estratégia distribui o trabalho em **4 ondas** com objetivos bem definidos e critérios de saída mensuráveis.

**Triage executado** — `tools/audit/triage.ts` aplicou scoring heurístico (exploitability × blast_radius × irreversibility) sobre os 69 criticals, promovendo **15 para Onda 0** ("stop the bleeding") e **54 para Onda 1** ("foundation"). Ver [`TRIAGE.md`](./TRIAGE.md) para racional detalhado de cada item.

---

## Princípios

1. **Stop the bleeding primeiro**: criticals que podem gerar perda financeira, exposição LGPD ou compromisso de autenticação vão para Onda 0.
2. **Fundação antes da escala**: testes, observabilidade e idempotência (Onda 1) são pré-requisitos para tocar features novas com segurança.
3. **Uma onda termina quando seus exit criteria estão verdes**, não por calendário — ritmo vs. qualidade.
4. **Não começar uma onda com dívida da anterior aberta** (exceto itens `deferred` explicitamente justificados).

---

## Onda 0 — "Stop the bleeding" (15 findings)

**Duração alvo:** 1-2 sprints (5-10 dias úteis)
**Foco:** findings 🔴 critical que representam risco imediato de perda financeira, vazamento de secrets, violação LGPD grave ou migration drift que quebra fresh installs.

### Escopo (ordem de priorização por score do TRIAGE)

| Pri | ID | Score | Status | Título |
|---|---|---|---|---|
| 1 | `L09-04` | 125 | 🟢 fixed | Nota fiscal não emitida em withdrawals (regulatório fiscal) |
| 2 | `L01-02` | 100 | 🟢 fixed | FX rate client-supplied em `/api/custody/withdraw` (fraude direta) |
| 3 | `L01-17` | 100 | 🟢 fixed | Asaas API Key armazenada em texto puro |
| 4 | `L04-03` | 100 | 🟢 fixed | Sem registro de consentimento (LGPD Art. 8) |
| 5 | `L04-01` | 80 | 🟢 fixed | `fn_delete_user_data` incompleta (LGPD Art. 48) |
| 6 | `L18-03` | 80 | 🟢 fixed | SECURITY DEFINER sem SET search_path |
| 7 | `L04-04` | 64 | 🟢 fixed | Dados de saúde/biométricos sem proteção reforçada (LGPD Art. 11) |
| 8 | `L01-44` | 60 | 🟢 fixed | Migration drift em `platform_fee_config.fee_type` CHECK |
| 9 | `L02-01` | 60 | 🟢 fixed | `distribute-coins` não-atômico ⭐ (exemplar) |
| 10 | `L19-01` | 60 | 🟢 fixed | `coin_ledger` particionada por mês |
| 11 | `L19-05` | 60 | 🟢 fixed | `lock_timeout=2s` em RPCs financeiras |
| 12 | `L01-03` | 50 | 🟢 fixed | `/api/distribute-coins` fallback silencioso (cross-ref L02-01) |
| 13 | `L02-02` | 50 | 🟢 fixed | `execute_burn_atomic` exceções engolidas |
| 14 | `L14-03` | 45 | 🟢 fixed | Swagger-UI self-hosted (sem unpkg) |
| 15 | `L05-01` | 40* | 🟢 fixed | Swap race entre accept/cancel (cancel_swap_order race-safe) |

**Progresso Onda 0:** ✅ **15/15 fixed** (100 %). Validação end-to-end via `tools/validate-migrations.sh --run-tests`: 165/165 migrations aplicando em fresh `public` schema, 146/146 testes de integração verdes (2026-04-17). Cada finding linka ao commit do fix em `linked_prs:`.

Detalhes completos + correções em `docs/audit/findings/LXX-YY-*.md`.

### Exit criteria

- ✅ 100% dos 15 findings da Onda 0 em `status: fixed`
- ✅ `tools/audit/verify.ts` passando no CI para todos PRs que tocam `docs/audit/`
- ✅ Testes de regressão para cada um (concorrência em `distribute-coins`, FX tamper em withdraw, etc.)
- ✅ Zero discrepância em reconciliação de custódia por 48h em staging
- ✅ Secret vault implementado e Asaas keys migradas (L01-17)
- ✅ LGPD compliance verificada por legal (L04-01, L04-03, L04-04)

---

## Onda 1 — "Foundation" (177 findings: 54 criticals rebaixados + 123 high)

**Duração alvo:** 3-5 sprints
**Foco:** fundação que acelera as correções das demais ondas. Inclui 54 criticals que não sangram dinheiro diretamente mas estabelecem padrões (observability, idempotência unificada, runbooks, OpenAPI, tracing).

**Progresso atual:** 17/177 fixed:
- L11-01/02/03 — supply chain trinca (dep vuln scan, SBOM CycloneDX, gitleaks)
- L11-04 — Dependabot reorganizado em 27 grupos semânticos (10 portal + 13 mobile + 4 actions), majors isolados, security-updates separados, commit messages padronizados
- L11-09 — Least-privilege `permissions:` em 7 workflows + WIF opt-in (Firebase/Play OIDC) em release.yml + assert anti-prod Supabase em portal.yml + runbook canônico CI_SECRETS_AND_OIDC.md
- L20-01/02/04/05/07/08 — SRE foundation (financial-ops dashboard JSON, SLO catalog, Sentry adaptive sampler + severity tags, alert policy, DR runbook, postmortem template)
- L20-03 — Tracing distribuído end-to-end via Sentry/OTel: `portal/src/instrumentation.ts` + façade `lib/observability/tracing.ts` (`withSpan`/`currentTraceId`/`traceparent`/`continueTraceFromRequest`), auto-injeção de `trace_id`+`span_id` em `audit.ts` e `logger.ts`, exemplo wired em `/api/distribute-coins` (atributos OTel + `X-Trace-Id` echo), Flutter `TracedHttpClient` wrapper sobre `SentryHttpClient` com allowlist defensivo (`*.supabase.co`, `omnirunner.app/com.br`) garantindo zero leakage para Strava/Asaas/Google, runbook canônico `docs/observability/TRACING.md` (~400 linhas) — 25 novos testes verdes
- L06-01 — runbooks financeiros operacionais (custody incident, clearing stuck, withdraw stuck, chargeback, gateway outage, webhook backlog)
- L06-06 — kill switches operacionais (feature_flags estendida com category/scope/audit, helpers SQL+TS+Deno, wiring em 3 routes financeiras, admin UI corrigida)
- L01-04 — custody idempotency-key + cross-group ownership (UNIQUE composto, RPC `fn_create_custody_deposit_idempotent` com `was_idempotent`, `confirm_custody_deposit` agora exige `(deposit_id, group_id)`, header `x-idempotency-key` obrigatório no portal, defesa contra double-click/replay/cross-group enumeration)
- L05-02 — swap TTL/expiração (coluna `expires_at`, RPC `fn_expire_swap_orders` + cron `*/10 * * * *`, `execute_swap` rejeita expirado com P0005, portal aceita `expires_in_days` 1/7/30/90, HTTP 410 Gone para offers expiradas)
- L02-07/ADR-008 — swap formalizado como cessão de crédito off-platform (coluna `external_payment_ref` com CHECK constraint, `execute_swap` ganha 3º param + SQLSTATE P0006, validação tripla portal Zod+lib+DB, WARN log estruturado quando ref ausente, ADR documentando rejeição de gateway Stripe/MP)

### Escopo

- ✅ **Supply chain (L11-01/02/03/04/09)** — npm audit + osv-scanner gate, SBOMs CycloneDX, gitleaks pre-commit + CI + weekly sweep, Dependabot agrupado por área semântica (27 grupos), permissions least-privilege em todos workflows + WIF/OIDC opt-in para Firebase/Play.
- ✅ **SRE foundation (L20-01/02/04/05/07/08)** — dashboard versionado, SLO/SLI canônicos com burn-rate alerting, Sentry tuning adaptativo (P1=100% / P4=0%), severity-based alert routing, DR drill protocol, blameless postmortem template.
- ✅ **Runbooks financeiros (L06-01)** — 6 runbooks operacionais (CUSTODY_INCIDENT, CLEARING_STUCK, WITHDRAW_STUCK, CHARGEBACK, GATEWAY_OUTAGE, WEBHOOK_BACKLOG) com SQL real, decisão por cenário, validação e postmortem mandatório. Indexados em `docs/runbooks/README.md` por severidade e tempo alvo.
- ✅ **Kill switches (L06-06)** — `feature_flags` estendida com `id`/`scope`/`category`/`reason`/`updated_by` + audit trigger imutável + helpers SQL/TS/Deno (fail-open semantics) + wiring em `/api/distribute-coins`, `/api/custody/withdraw`, `/api/swap` + admin UI com badge por categoria, motivo obrigatório e cache invalidation. Runbooks atualizados para usar schema real.
- ✅ **Custody idempotency (L01-04)** — `custody_deposits.idempotency_key` + UNIQUE parcial composto `(group_id, key)` + RPC `fn_create_custody_deposit_idempotent` (SELECT-first, race resolvido via `unique_violation`) + `confirm_custody_deposit(uuid, uuid)` exige match de ambos (mensagem genérica defende contra UUID enumeration) + header `x-idempotency-key` obrigatório no POST com formato UUIDv4/ULID validado + audit log skipa replays + 3 testes integration (replay/cross-group/non-existent).
- ✅ **Swap TTL/expiração (L05-02)** — `swap_orders.expires_at` (default 7d) + index parcial `(expires_at) WHERE status='open'` + RPC `fn_expire_swap_orders` (RETURNING ids) + pg_cron `swap-expire` a cada 10min + `execute_swap` rejeita `expires_at<now()` com SQLSTATE P0005 (defesa entre runs do cron) + portal `createSwapOffer(seller, amount, expiresInDays?)` com TTLs canônicos 1/7/30/90 + HTTP 410 Gone para offers expiradas + audit log carrega `expires_in_days`/`expires_at`. 3 integration tests cobrindo sweep idempotency, P0005+sweep cleanup e happy path.
- ✅ **Swap como cessão de crédito off-platform (L02-07/ADR-008)** — `swap_orders.external_payment_ref` opcional (4-200 chars, sem control chars, validado em CHECK constraint) + `execute_swap` ganha 3º param `p_external_payment_ref` + nova SQLSTATE P0006 (PAYMENT_REF_INVALID) + portal lib `acceptSwapOffer(orderId, buyer, ref?)` com validação client-side + Zod no route com triple-check (min/max/regex sem control chars) + WARN log estruturado quando accept ocorre sem ref (`logger.warn("swap.accept_without_external_payment_ref", { adr: "ADR-008" })`) + audit log enriquecido com `external_payment_ref`/`has_payment_ref`. ADR-008 formaliza modelo (cessão vs venda) + decisão de não migrar para gateway Stripe/MP. 13 novos tests (5 lib + 5 route + 3 integration).
- Testes de regressão para **todos** os fluxos financeiros (portal + edge)
- Observabilidade restante: OTel distributed tracing (L20-03), status page público (L20-06), structured logger correlation IDs em todas rotas
- LGPD: endpoints de exportação/deleção, consentimento versionado
- Anti-cheat: ajuste de thresholds para atletas de elite (`MAX_SPEED_MS`, `MAX_HR_BPM`) — Lente 21
- API versioning: `/api/v1/` formal + OpenAPI atualizado
- Rate limiting consistente em todas rotas sensíveis

### Exit criteria

- ✅ Cobertura de testes >= 70% em `portal/src/app/api/` e `supabase/functions/`
- ✅ Runbooks para top-10 alertas SRE documentados em `docs/audit/runbooks/`
- ✅ Dashboard Sentry com p99 e error rate por rota publicado internamente
- ✅ Todos findings 🟠 `wave: 1` fechados

---

## Onda 2 — "Scale" (127 findings 🟡 medium)

**Duração alvo:** 4–6 sprints
**Foco:** performance, UX, observability profunda, capacidades para atletas/treinadores.

### Escopo

- TSS / CTL / ATL para atletas profissionais (Lente 21)
- Zonas customizáveis (HR + pace) — Lentes 21 + 22
- Dashboards priorizados para treinadores (Lente 23)
- Onboarding guiado para amadores (Lente 22)
- SEO + Open Graph + deep links (Lente 15)
- Acessibilidade WCAG AA (Lente 16)
- Otimização de queries custosas, materialized views (Lente 19)
- SLOs formais + alertas (Lente 20)

### Exit criteria

- ✅ NPS medido em-app para 3 personas (prof/amador/treinador) com baseline
- ✅ Lighthouse score >= 90 em todas páginas públicas do portal
- ✅ WCAG AA em checkout e onboarding validado com ferramenta automatizada + revisão manual
- ✅ 100% findings 🟠 fechados, 🟡 `wave: 2` em progresso

---

## Onda 3 — "Expansion" (29 findings: 17 safe + 12 N/A)

**Duração alvo:** contínua
**Foco:** capacidades avançadas, growth, automação interna.

### Escopo

- Race prediction, workout delivery, team management
- Integração TrainingPeaks/Garmin/Wahoo avançada
- Marketplace B2B2C (cross-selling entre assessorias)
- Automação de operações (alerts self-healing, auto-scaling)
- Dívida técnica remanescente (🟡 medium)
- Documentação viva (ADRs, runbooks, onboarding)

### Exit criteria

- ✅ Zero findings `fix-pending` para features em produção
- ✅ Releases semanais sem rollback por 8 semanas consecutivas
- ✅ Documentação de onboarding para dev júnior <= 2h tempo de setup

---

## Como acompanhar

- **Semanalmente**: `SCORECARD.md` é regerado; stand-up de 15min para revisar progresso por onda.
- **Por finding**: GitHub Issue + label `audit:LXX-YY` + milestone `Onda N` + `PR Closes #N`.
- **Exit de onda**: review formal com C-level + stakeholders técnicos antes de iniciar a próxima.

---

## Mapeamento findings → ondas (estado atual)

Alocação pós-triage. Ver `SCORECARD.md` para contagens ao vivo:

| Onda | Critical | High | Medium | Safe+N/A | Total |
|---|---|---|---|---|---|
| 0 | 15 | 0 | 0 | 0 | **15** |
| 1 | 54 | 123 | 0 | 0 | **177** |
| 2 | 0 | 0 | 127 | 0 | **127** |
| 3 | 0 | 0 | 0 | 29 | **29** |

**Total**: 348 findings.

Dos 29 findings "Onda 3": 17 🟢 safe (já verificados OK) e 12 ⚪ não-auditados (requerem re-auditoria focada).

### Findings exemplares completamente especificados

Os seguintes findings já têm **correção proposta + testes de regressão + SQL** prontos para consumo direto de PR (úteis como ponto de partida):

- `L02-01` — `distribute-coins` atomic (CTO) — **gold standard** de detalhe
- `L01-03` — `/api/distribute-coins` fallback silencioso — resolvido junto com L02-01 (`duplicate_of`)
- `L01-44` — migration drift em `platform_fee_config` — correção canônica + patch retroativo na histórica
- `L01-13` — `/api/platform/fees` sem suporte a `fx_spread` — resolvido junto com L01-44 (`duplicate_of`)
- `L14-03` — Swagger-UI self-host (remove dependência de unpkg)
- `L02-02` — `execute_burn_atomic` hardenizado (custody re-raise, settle log-and-continue + `clearing_failure_log`)
- `L18-03` — 26 SECURITY DEFINER em `public` hardenizadas com `SET search_path` + invariante bloqueadora
- `L19-05` — 9 RPCs financeiras com `SET lock_timeout = '2s'` + portal 55P03 → 503 retry-after
- `L01-02` — FX rate server-side authoritative via `platform_fx_quotes` + `.strict()` schema + endpoint read-only para UI
- `L05-01` — `cancel_swap_order` RPC com `FOR UPDATE` + ownership/status guards + SQLSTATE distinguíveis (P0001/P0002/P0003/P0004) → portal mapeia para 404/409/403/400/422/503
- Gradualmente, conforme o time converter outros findings da Onda 0 em PRs, estes também ganharão detalhamento similar.
