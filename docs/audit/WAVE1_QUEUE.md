# Wave 1 — Próximos 50 Candidatos (Execution Queue)

> Atualizado: 2026-04-21 · Curadoria automática via `tools/audit/triage.ts`
> reranqueada com penalty para itens estratégicos/policy/produto que dependem
> de stakeholders externos (legal, CFO, design, product). Detalhes em
> `docs/audit/ROADMAP.md` Onda 1.

**Posição atual:** 93/179 fixed (Onda 1).
**Pista:** 50 entregas correção engenharia → 127/179 (71 %), libera Onda 2.

**Progresso Batch A (Custody & Finance):** ✅ 5/5 — L05-09 ✓, L05-07 ✓, L12-05 ✓, L09-09 ✓, L04-07 ✓.
**Progresso Batch B (Cron / Reliability):** ✅ 5/5 — L06-05 ✓, L12-09 ✓, L12-06 ✓, L12-07 ✓ (+ L07-06 co-fix), L12-08 ✓.
**Progresso Batch C (DBA / Schema Cleanup):** ✅ 4/4 — L19-04 ✓ · L19-08 ✓ · L19-06 ✓ · L08-05 ✓.
**Progresso Batch D (Sessions / Data Integrity):** ✅ 2/2 — L08-04 ✓ · L08-03 ✓.
**Progresso Batch E (Security & Auth):** ✅ 4/4 — L10-09 ✓ · L10-07 ✓ · L10-08 ✓ · L07-04 ✓.

## Critério de pontuação

`severity_weight − 2·effort_points − strategic_penalty + tag_bonuses + correction_type_bonus`

- `severity`: critical=100, high=60, medium=30
- `strategic_penalty=90` para itens que precisam legal/produto/CFO multi-quarter
- `tags`: +10 migration, +8 atomicity, +7 finance, +6 rls, +5 cron/sre, +4 testing
- `correction_type`: +8 migration, +6 code, +4 config, −4 process

## Fila — Top 50 (execução em ordem)

### 🟢 Batch A — Custody & Finance (5 entregas, partilham `custody_*` + `wallets`)

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 1 | L05-09 | high | 5 | 3 | Deposit `custody_deposits` — sem cap diário antifraude |
| 2 | L05-07 | high | 5 | 3 | Swap: `amount` mínimo US$ 100 inviabiliza grupos pequenos |
| 3 | L12-05 | high | 12 | 3 | `auto-topup-hourly` — cobrança automática sem cap diário |
| 4 | L09-09 | high | 9 | 3 | Contratos privados (termo de adesão do clube, termo de atleta) inexistentes |
| 5 | L04-07 | high | 4 | 3 | `coin_ledger.reason` retém PII embutida (LGPD) |

### 🟢 Batch B — Cron / Reliability (5 entregas, partilham `cron_run_state` + `pg_cron`)

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 6 | L06-05 | high | 6 | 3 | Edge Functions sem retry em falha de `pg_net` |
| 7 | L12-09 | high | 12 | 3 | `lifecycle-cron` dispara notificações idempotência não garantida |
| 8 | L12-06 | high | 12 | 3 | `archive-old-sessions` roda como função pesada sem batch |
| 9 | L12-07 | high | 12 | 3 | Horário UTC → usuários BR veem "meia-noite Brasil" em jobs/relatórios |
| 10 | L12-08 | high | 12 | 3 | `clearing-cron` em 02:00 — consolida D-1 antes de fim do dia em UTC-3 |

### 🟢 Batch C — DBA / Schema Cleanup (4 entregas, partilham `pg_indexes` + `pg_constraint`)

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 11 | L19-04 | high | 19 | 3 | ✅ `idx_ledger_user` vs `idx_coin_ledger_user_created` — duplicidade sem limpeza (fixed 2026-04-21) |
| 12 | L19-08 | high | 19 | 3 | ✅ Constraints CHECK sem nome padronizado (fixed 2026-04-21) |
| 13 | L19-06 | high | 19 | 3 | ✅ JSONB em `audit_logs.metadata` sem índice GIN (fixed 2026-04-21) |
| 14 | L08-05 | high | 8 | 3 | ✅ Views de progressão sem filtro de atletas inativos (fixed 2026-04-21) |

### 🟢 Batch D — Sessions / Data Integrity (2 entregas, partilham `sessions` schema)

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 15 | L08-04 | high | 8 | 3 | ✅ Análise de `sessions` por `moving_ms` aceita NULL e 0 (fixed 2026-04-21) |
| 16 | L08-03 | high | 8 | 3 | ✅ Sem índice de analytics time-series em `sessions` (fixed 2026-04-21) |

### 🟢 Batch E — Security & Auth (4 entregas, mistas)

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 17 | L10-09 | high | 10 | 3 | ✅ Falta defesa anti credential stuffing no Mobile/Portal (fixed 2026-04-21) |
| 18 | L10-07 | high | 10 | 3 | ✅ Edge Functions confiam no JWT sem validar `audience`/`issuer` (fixed 2026-04-21) |
| 19 | L10-08 | high | 10 | 3 | ✅ Logs de acesso sensíveis sem imutabilidade (fixed 2026-04-21) |
| 20 | L07-04 | high | 7 | 3 | ✅ Flutter deep link Strava OAuth sem state validation (fixed 2026-04-21) |

### 🟢 Batch F — Plumbing / DX (4 entregas, em `portal/src/lib/*`)

**Progresso Batch F (Plumbing / DX):** ✅ 4/4 — L17-05 ✓ · L17-03 ✓ · L17-04 ✓ · L15-04 ✓ (fixed 2026-04-21 — email platform: outbox + provider abstraction + send-email edge fn).

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 21 | L17-05 | high | 17 | 3 | ✅ Logger silencia errors não-`Error` (fixed 2026-04-21) |
| 22 | L17-03 | high | 17 | 3 | ✅ `withErrorHandler` usa `any` em `routeArgs` (fixed 2026-04-21) |
| 23 | L17-04 | high | 17 | 3 | ✅ Testes em `portal/src/lib/qa-*.test.ts` > 800 linhas (fixed 2026-04-21) |
| 24 | L15-04 | high | 15 | 3 | ✅ Sem email transactional platform (Resend/Postmark) (fixed 2026-04-21) |

### 🟡 Batch G — Mobile / Flutter (4 entregas, em `omni_runner/`)

**Progresso Batch G (Mobile / Flutter):** ✅ 4/4 — L11-05 ✓ · L11-06 ✓ · L11-07 ✓ · L11-08 ✓.

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 25 | L11-05 | high | 11 | 3 | ✅ `flutter_secure_storage` ^10 mas release usa `shared_preferences` (fixed 2026-04-21) |
| 26 | L11-06 | high | 11 | 3 | ✅ Dependências com `^` permitem breaking minor (fixed 2026-04-21) |
| 27 | L11-07 | high | 11 | 3 | ✅ `sqlcipher_flutter_libs: ^0.7.0+eol` — end of life (fixed 2026-04-21) |
| 28 | L11-08 | high | 11 | 3 | ✅ `Flutter sdk: '>=3.8.0 <4.0.0'` permite 3.9, 3.10… (fixed 2026-04-21) |

### 🟢 Batch H — Mobile UX & Coach features (10 entregas, code-tractable)

**Progresso Batch H (Mobile UX):** 🟢 10/10 — L21-06 ✓, L22-05 ✓, L22-06 ✓, L22-08 ✓, L22-09 ✓, L23-06 ✓, L23-07 ✓, L23-11 ✓, L23-13 ✓, L23-14 ✓.

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 29 | L21-06 | high | 21 | 3 | ✅ Polyline GPS resolução baixa (`distanceFilter` 5 m) (fixed 2026-04-21) |
| 30 | L22-05 | high | 22 | 3 | ✅ Grupos locais sem descoberta por proximidade (fixed 2026-04-21) |
| 31 | L22-06 | high | 22 | 3 | ✅ Voice coaching parcial (sem TTS por bracket) (fixed 2026-04-21) |
| 32 | L22-08 | high | 22 | 3 | ✅ Desafio de grupo (viralização entre amigos) (fixed 2026-04-21) |
| 33 | L22-09 | high | 22 | 3 | ✅ Progress celebration tímida (fixed 2026-04-21) |
| 34 | L23-06 | high | 23 | 3 | ✅ Plano mensal/trimestral não periodizado (fixed 2026-04-21) |
| 35 | L23-07 | high | 23 | 3 | ✅ Análise coletiva (grupo) limitada (fixed 2026-04-21) |
| 36 | L23-11 | high | 23 | 3 | ✅ Relatórios para atleta (resumo mensal do coach) (fixed 2026-04-21) |
| 37 | L23-13 | high | 23 | 3 | ✅ Feedback do atleta (RPE, dor, humor) não requerido (fixed 2026-04-21) |
| 38 | L23-14 | high | 23 | 3 | ✅ "Corrida de teste" (time trial) agendada (fixed 2026-04-21) |

### 🟡 Batch I — Reach goals (12 entregas com mais incerteza)

| # | id | sev | L | ep | Título |
|---|---|---|---|---|---|
| 39 | L21-07 | high | 21 | 3 | Sem interoperabilidade com `.fit` real-time |
| 40 | L21-08 | high | 21 | 3 | Lap splits manuais inexistentes em tela de corrida |
| 41 | L21-09 | high | 21 | 3 | Calibração de GPS em pista (400 m outdoor) |
| 42 | L21-10 | high | 21 | 3 | Anti-cheat pode publicamente marcar elite como suspeito |
| 43 | L21-11 | high | 21 | 3 | Ghost mode não funciona para competições reais |
| 44 | L21-12 | high | 21 | 3 | Sem "team dashboard" para staff técnica |
| 45 | L22-04 | high | 22 | 3 | Feedback de ritmo só pós-corrida |
| 46 | L23-12 | high | 23 | 3 | Onboarding de novo atleta no clube |
| 47 | L20-06 | high | 20 | 3 | Status page pública inexistente |
| 48 | L16-02 | high | 16 | 3 | Sem custom domain por assessoria |
| 49 | L08-08 | high | 8 | 3 | `audit_logs` sem retenção / particionamento |
| 50 | L08-06 | high | 8 | 3 | Sem staging de data warehouse — queries OLAP contra OLTP |

## Itens explicitamente **deferidos** (precisam stakeholder externo)

Lente 9 — regulatório (BCB/KYC/COAF/IOF): `L09-01`, `L09-02`, `L09-03`, `L09-05`,
`L09-06`, `L09-07`, `L09-08` — bloqueiam em parecer legal/contábil.

Lente 10 — security policy: `L10-01` (bug bounty), `L10-02` (threat model),
`L10-03` (key distribution), `L10-04` (WAF), `L10-06` (SoD) — bloqueiam em
sign-off CISO/legal.

Lente 16 — produto B2B: `L16-01` (white-label), `L16-03` (B2B API), `L16-04`
(outbound webhooks), `L16-05` (brand schema), `L16-06` (OAuth telemetry) —
bloqueiam em product roadmap.

Lente 17 — refactor: `L17-02` (5378 linhas em `lib/` sem bounded context) —
multi-quarter restructure.

Lente 18 — refactor: `L18-04` (Flutter Clean Arch), `L18-05` (event bus) —
multi-quarter restructure.

Lente 21 — produto: `L21-03` (GPS ownership), `L21-04` (TSS/CTL/ATL),
`L21-05` (zonas custom) — bloqueiam em product+legal.

Lente 22/23 — produto: `L22-01`, `L22-02`, `L22-03`, `L22-07`, `L23-01`,
`L23-02`, `L23-03`, `L23-04`, `L23-05`, `L23-08`, `L23-09`, `L23-10` —
bloqueiam em UX/produto.

Lente 4 — política: `L04-05`, `L04-06`, `L04-08`, `L04-09`, `L04-10` —
bloqueiam em DPO/legal.

Lente 7 — i18n/UX: `L07-01`, `L07-02`, `L07-03`, `L07-05`, `L07-06` —
bloqueiam em product/i18n team.

Outros: `L05-04`, `L05-05`, `L05-06`, `L05-08` (championship UX), `L15-01`,
`L15-02`, `L15-03` (growth/marketing), `L19-07` (DBA tuning), `L11-05` é
re-posicionado em Batch G (atacável).

Total deferido: ~55 findings — viram backlog Onda 1.5/Onda 2 quando os
stakeholders entregarem inputs.
