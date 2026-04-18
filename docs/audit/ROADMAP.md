# ROADMAP — Execução das Correções em Ondas

> **Atualizado:** 2026-04-17
> **Status do overall:** Onda 0 em preparação

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
| 1 | `L09-04` | 125 | fix-pending | Nota fiscal não emitida em withdrawals (regulatório fiscal) |
| 2 | `L01-02` | 100 | 🟡 in-progress | FX rate client-supplied em `/api/custody/withdraw` (fraude direta) |
| 3 | `L01-17` | 100 | 🟡 in-progress | Asaas API Key armazenada em texto puro |
| 4 | `L04-03` | 100 | 🟡 in-progress | Sem registro de consentimento (LGPD Art. 8) |
| 5 | `L04-01` | 80 | 🟡 in-progress | `fn_delete_user_data` incompleta (LGPD Art. 48) |
| 6 | `L18-03` | 80 | 🟡 in-progress | SECURITY DEFINER sem SET search_path |
| 7 | `L04-04` | 64 | 🟡 in-progress | Dados de saúde/biométricos sem proteção reforçada (LGPD Art. 11) |
| 8 | `L01-44` | 60 | 🟡 in-progress | Migration drift em `platform_fee_config.fee_type` CHECK |
| 9 | `L02-01` | 60 | 🟡 in-progress | `distribute-coins` não-atômico ⭐ (exemplar, correção pronta) |
| 10 | `L19-01` | 60 | 🟡 in-progress | `coin_ledger` não particionada |
| 11 | `L19-05` | 60 | 🟡 in-progress | Falta `FOR UPDATE NOWAIT` em locks críticos |
| 12 | `L01-03` | 50 | 🟡 in-progress | `/api/distribute-coins` fallback silencioso (cross-ref L02-01) |
| 13 | `L02-02` | 50 | 🟡 in-progress | `execute_burn_atomic` exceções engolidas |
| 14 | `L14-03` | 45 | 🟡 in-progress | Swagger-UI carregado de unpkg sem SRI |
| 15 | `L05-01` | 40* | 🟡 in-progress | Swap race entre accept/cancel (*override manual — double-spend direto) |

**Progresso Onda 0:** 14/15 em `in-progress` (L02-01, L01-03, L01-44, L14-03, L02-02, L18-03, L19-05, L01-02, L05-01, L04-01, L19-01, L01-17, L04-03, L04-04) — **~93%** do escopo rumo ao fixed.

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

### Escopo

- Testes de regressão para **todos** os fluxos financeiros (portal + edge)
- Observabilidade: Sentry, estruturar `logger.error`, correlation IDs em todas rotas
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
