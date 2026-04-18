# Runbook: Disaster Recovery (DR) Procedure

> **Gatilho:** Quarterly drill (game-day) OU incidente real de perda total de
> banco de dados (corrupção, deleção catastrófica, comprometimento de
> credenciais).
> **Severidade esperada:** P0 (drill) ou SEV-0 (real)
> **SLO de recovery (real):** RTO 4h, RPO 24h (ver SLO catalog)
> **Linked findings:** L20-07 (this), L20-01 (dashboards), L20-08 (postmortem)
> **Última revisão:** 2026-04-17

---

## 0. Overview

Este runbook cobre **DOIS** modos:

- **Modo A: Drill trimestral (planejado)** — execução em sandbox isolado,
  zero impacto produção, valida que backups funcionam.
- **Modo B: DR real (incidente)** — restore de produção sob pressão.
  Procedimento mais rápido + envolve coordenação com Asaas (suspensão
  temporária de billing) + comunicação aos usuários.

> **CRÍTICO**: nunca executar passos do **Modo B** sem aprovação de 2
> sêniores (4-eye principle). Em drill, 1 operador é suficiente.

---

## Modo A — Drill trimestral (game-day)

### Cadência
- **Frequência:** 1× por trimestre (Q1=mar, Q2=jun, Q3=set, Q4=dez).
- **Janela**: terça-feira 14:00-16:00 UTC (não impacta usuários, Brasil
  ainda em horário comercial mas tráfego baixo).
- **Owner rotativo**: Platform team. Não executar sempre o mesmo dev —
  o objetivo é distribuir o conhecimento.
- **Game-day buddy**: 1 outro dev disponível em Slack para sanity-check.

### 1. Pré-flight (T-7d)
- [ ] Anunciar drill em Slack `#platform-ops`: "DR drill agendado para
  YYYY-MM-DD às 14:00 UTC. Owner: @dev. Buddy: @dev2."
- [ ] Confirmar quota do Supabase free tier não vai estourar com novo
  project (cap 2 free projects/org → fazer cleanup de drill anterior se
  necessário).
- [ ] Confirmar acesso a Supabase Dashboard com permissão de criar
  projects.
- [ ] Definir snapshot timestamp alvo: T-24h da hora do drill.

### 2. Execução (T0)
- [ ] Provisionar novo Supabase project sandbox:
  - Nome: `omni-runner-dr-drill-YYYYMMDD`
  - Region: mesma do prod (`sa-east-1` São Paulo)
  - Tier: free (não precisa PITR no sandbox, restore é one-shot)
- [ ] Anotar project ref em `notas/drill-YYYY-MM-DD.md`.
- [ ] Restore via Supabase CLI:
  ```bash
  # PITR snapshot disponível somente em projetos pagos (Pro tier).
  # Caso prod esteja em Free: usar export pg_dump diário (cron supabase
  # functions → S3 ou Backblaze). Adaptar comando abaixo conforme.
  supabase db restore \
    --project-ref <SANDBOX_REF> \
    --backup-id <SNAPSHOT_T_MINUS_24H>
  # Tempo esperado: 5-15min para DB de até 100GB.
  ```
- [ ] Aguardar Supabase confirmar restore concluído (status check via
  dashboard OU `supabase projects status <SANDBOX_REF>`).

### 3. Validação smoke
Conectar ao sandbox via psql e rodar **TODAS** as queries abaixo. Comparar
resultado com snapshot esperado (calculado no prod no momento T-24h via
script salvo em `tools/dr-baseline.sql`).

```sql
-- 3.1 — Volumetria de tabelas críticas
SELECT 'profiles'         AS table, COUNT(*) FROM public.profiles
UNION ALL SELECT 'coin_ledger',          COUNT(*) FROM public.coin_ledger
UNION ALL SELECT 'custody_accounts',     COUNT(*) FROM public.custody_accounts
UNION ALL SELECT 'custody_deposits',     COUNT(*) FROM public.custody_deposits
UNION ALL SELECT 'sessions',             COUNT(*) FROM public.sessions
UNION ALL SELECT 'asaas_webhook_events', COUNT(*) FROM public.asaas_webhook_events;

-- 3.2 — Invariants (DEVE retornar 0 violações)
SELECT * FROM check_custody_invariants();

-- 3.3 — Wallet drift (DEVE retornar 0 rows)
SELECT user_id, ledger_sum, wallet_balance, drift
FROM v_wallet_ledger_drift
WHERE drift != 0
LIMIT 10;

-- 3.4 — RLS sanity (sem service-role bypass)
SELECT COUNT(*) AS policies_total FROM pg_policies WHERE schemaname = 'public';
-- Esperado: o mesmo número que prod (registrar baseline em tools/dr-baseline.sql)

-- 3.5 — Functions sanity (count)
SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname LIKE 'fn_%';
```

### 4. Decisão go/no-go drill
- [ ] **PASS**: todos os counts batem com baseline ±0.1% (pequena
  divergência aceitável devido a writes nos 24h entre snapshot e drill).
- [ ] **FAIL**: discrepância > 1% OU invariant violations > 0 → **abrir
  incidente P1 imediatamente** (significa que um snapshot real seria
  insuficiente para recovery completo). Atualizar este runbook + abrir
  finding novo.

### 5. Cleanup
- [ ] Deletar Supabase project sandbox (UI → Settings → Delete project).
  Aguardar 7d antes de re-drill (cooldown anti-acidente).
- [ ] Atualizar `docs/runbooks/DR_PROCEDURE.md` se algum passo precisou
  de ajuste durante o drill.
- [ ] Postar resumo em Slack `#platform-ops`:
  > Drill DR YYYY-MM-DD: ✅ PASS (RTO observed: 25min, deltas dentro de
  > tolerância). Próximo: YYYY-MM-DD.

### 6. Métricas a capturar
| Métrica | Target | Real (preencher) |
|---|---|---|
| RTO observed (provision → smoke OK) | < 60min | __ min |
| Restore duration (Supabase CLI) | < 30min | __ min |
| Smoke query suite duration | < 5min | __ min |
| Invariant violations | 0 | __ |
| Wallet drift rows | 0 | __ |

---

## Modo B — DR real (incidente)

### Pré-condições
- Banco de produção comprometido OU deletado OU corrompido a ponto de
  invariants reportarem violações em massa (>= 100 rows em
  `check_custody_invariants`).
- **Aprovação de 2 sêniores** (4-eye) registrada em Slack
  `#incidents` com timestamp.
- Asaas billing **suspenso** preventivamente para evitar webhook
  duplicado durante restore (chamar Asaas support: +55 47 3045-9100).

### 1. Contenção (T0 → T+15min)
- [ ] Pôr portal em **maintenance mode**: setar
  `MAINTENANCE_MODE=true` em Vercel env vars + redeploy.
  Middleware já trata: retorna 503 + página estática.
- [ ] Postar status:
  > **DEGRADADO**: estamos investigando incidente de banco de dados.
  > Saques e depósitos suspensos preventivamente. ETA atualizada a cada
  > 30min.

  Em status page (`status.omnirunner.com` quando L20-06 implementado) +
  Slack `#announcements` + email para usuários se >2h.

- [ ] Suspender Asaas billing (call support).
- [ ] Notificar Sentry release health para parar de auto-criar issues
  durante o restore.

### 2. Decisão de restore strategy (T+15min → T+30min)

| Cenário | Estratégia |
|---|---|
| Corrupção parcial em uma tabela | Restore seletivo via `pg_dump --table` do snapshot |
| Corrupção em coin_ledger / custody | PITR completo (acceptado RPO até 24h) |
| Deleção catastrófica (DROP DATABASE) | PITR completo |
| Comprometimento de credenciais | PITR completo + **rotar TODOS secrets antes de subir** (ver L01-17 runbook) |

### 3. Execução do restore (T+30min → T+3h30min)

#### Sub-cenário: PITR completo
```bash
# Identificar último snapshot saudável (antes do incidente)
supabase backups list --project-ref <PROD_REF> | head -10

# Restore para o MESMO project (sobrescreve estado atual — destrutivo!)
# Confirmar 2× com buddy antes de pressionar enter.
supabase db restore \
  --project-ref <PROD_REF> \
  --backup-id <BACKUP_ID> \
  --confirm
```

Tempo esperado para DB ~50GB: 30-45min.

#### Sub-cenário: Restore seletivo
```bash
# 1. Provisionar sandbox como no Modo A.
# 2. Restore PITR no sandbox.
# 3. pg_dump --table=<table> do sandbox.
# 4. pg_restore --data-only --table=<table> no prod.
# 5. Manualmente reconciliar invariants pós-restore.
```

### 4. Validação pós-restore
Rodar smoke do Modo A passo 3 contra prod (NÃO sandbox).

**Se invariants violations > 0 PÓS-restore**: NÃO subir maintenance.
Investigar até 0 violations OU aceitar risco com aprovação CTO.

### 5. Restart staged (T+3h30min → T+4h)
- [ ] Reativar Asaas billing (sem webhook history catch-up — eventos
  perdidos durante maintenance ficam para reconciliação manual via
  L09-04 runbook).
- [ ] Desabilitar maintenance mode em Vercel.
- [ ] Smoke test E2E manual: criar conta teste → depósito teste 10 BRL →
  withdraw teste 10 BRL → verificar coin_ledger consistente.
- [ ] Habilitar Sentry release health novamente.
- [ ] Postar status:
  > **OPERACIONAL**: restore concluído. Pequena janela de eventos
  > perdidos (de HH:MM a HH:MM) está sendo reconciliada manualmente.

### 6. Postmortem (T+24h)
- [ ] Criar postmortem usando `docs/postmortems/TEMPLATE.md`.
- [ ] Schedule retrospective com time + stakeholders em até 5 dias úteis.
- [ ] Atualizar este runbook se algum passo precisou de ajuste.
- [ ] Criar findings novos para gaps detectados.

---

## Apêndice A — Backup/PITR configuration audit

Verificar trimestralmente (pré-drill checklist):

```sql
-- Supabase paid tier expõe info via dashboard. Para Free tier:
-- backups dependem de pg_dump cron (Edge Function). Validar:
SELECT
  job_name,
  next_run,
  last_run,
  last_run_status
FROM cron.job
WHERE job_name LIKE 'backup_%';
```

Se PITR não estiver configurado e a plataforma está em Free tier:
**criar finding L20-07-followup-pitr-upgrade** para upgrade para Pro
($25/mo). Free tier oferece **APENAS** snapshots diários sem
point-in-time, o que invalida nosso RPO declarado de 24h (na prática
fica 24h-48h dependendo do horário do incidente).

## Apêndice B — Contatos de incidente

| Função | Quem | Contato |
|---|---|---|
| Supabase support | (pré-pago, premium tier 24/7) | support@supabase.io |
| Asaas suspensão de billing | suporte | +55 47 3045-9100 |
| Vercel | dashboard support | https://vercel.com/help |
| CTO (autorização Modo B) | @founder | (em PagerDuty) |
