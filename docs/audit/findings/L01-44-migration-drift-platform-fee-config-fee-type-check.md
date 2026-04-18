---
id: L01-44
audit_ref: "1.44"
lens: 1
title: "Migration drift — platform_fee_config.fee_type CHECK + INSERT 'fx_spread'"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
tags: ["finance", "migration", "ux", "reliability"]
files:
  - supabase/migrations/20260228170000_custody_gaps.sql
  - supabase/migrations/20260417130000_fix_platform_fee_config_check.sql
  - tools/integration_tests.ts
correction_type: migration
test_required: true
tests:
  - tools/integration_tests.ts
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Correção implementada em 2026-04-17: nova migration canônica + edição forward-compat em 170000 + 2 testes de integração. L01-13 corrigido junto (cross-ref; enum portal/fees atualizado)."
---
# [L01-44] Migration drift — platform_fee_config.fee_type CHECK + INSERT 'fx_spread'
> **Lente:** 1 — CISO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** in-progress (correção pronta, aguardando PR)
**Camada:** BACKEND
**Personas impactadas:** DevOps, CFO (em fresh install)
## Achado
`20260228150001_custody_clearing_model.sql:17` cria CHECK com `('clearing', 'swap', 'maintenance')`.
  - `20260228170000_custody_gaps.sql:40-42` tenta `INSERT ... ('fx_spread', 0.75)`.
  - A CHECK **REJEITA** o INSERT de 'fx_spread' → migration 170000 **FALHA** em instalação fresh.
  - Só migration `20260319000000_maintenance_fee_per_athlete.sql:18` finalmente expande CHECK para incluir `'fx_spread'`.
  - Em um banco existente que já passou 170000 antes da CHECK ser apertada, vai funcionar por acidente histórico.
## Risco / Impacto

Reprovisão de ambientes (staging, preview, onboarding novo dev) **quebra**. Disaster recovery de backup + replay de migrations desde zero **quebra**.

## Correção proposta

Criar migration de repair imediatamente:
  ```sql
  -- 20260417000001_fix_platform_fee_config_check.sql
  ALTER TABLE public.platform_fee_config DROP CONSTRAINT IF EXISTS platform_fee_config_fee_type_check;
  ALTER TABLE public.platform_fee_config ADD CONSTRAINT platform_fee_config_fee_type_check
    CHECK (fee_type IN ('clearing','swap','maintenance','billing_split','fx_spread'));
  ```
  E editar `20260228170000` para incluir o DROP/ADD CHECK antes do INSERT. Também: adicionar CI step que faz `supabase db reset && supabase db push` em cada PR.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.44]`.

## Correção implementada

**Data:** 2026-04-17 (mesma sessão da auditoria)

### Timeline do drift reconstruída

| Migration | Efeito em `platform_fee_config` |
|---|---|
| `20260228150001` | CREATE TABLE — `CHECK (fee_type IN ('clearing','swap','maintenance'))` |
| `20260228170000` | INSERT `('fx_spread', 0.75)` — **FALHA em fresh install** (CHECK rejeita) |
| `20260305100000` | CREATE TABLE IF NOT EXISTS (noop; tabela já existe, CHECK não muda) |
| `20260316000000` | DROP/ADD CHECK adiciona `billing_split` — **ainda sem fx_spread** |
| `20260319000000` | Cria `platform_revenue` com CHECK amplo — mas `platform_fee_config` **continua sem fx_spread** |

**Consequência em produção**: linha `fx_spread` pode existir (se 170000 rodou antes da CHECK ser apertada) ou não (se 170000 falhou). `getFxSpreadRate` em `portal/src/lib/custody.ts` lê essa linha — se ausente, default 0% é usado → saques em moeda local sem spread.

**Consequência em fresh install / DR**: replay desde zero **quebra** em 170000.

### Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `supabase/migrations/20260417130000_fix_platform_fee_config_check.sql` | **NOVO** — canonical source of truth: DROP/ADD CHECK com 5 valores + INSERT idempotente + alinha `platform_revenue` + NOTICE se algum seed estiver faltando |
| `supabase/migrations/20260228170000_custody_gaps.sql` | Edição forward-compat: adiciona DROP/ADD CHECK **antes** do INSERT `fx_spread`. Idempotente. Safe para DBs que já aplicaram (Supabase rastreia por filename). |
| `portal/src/app/api/platform/fees/route.ts` | zod enum estendido com `"fx_spread"` — fecha L01-13 (cross-ref) |
| `portal/src/app/platform/fees/page.tsx` | `FEE_LABELS.fx_spread` adicionado com label + descrição operacional |
| `portal/src/app/api/platform/fees/route.test.ts` | +2 testes: aceita `fee_type='fx_spread'` e `fee_type='billing_split'` |
| `tools/integration_tests.ts` | +2 testes DB: todas as 5 rows canônicas seedadas + CHECK rejeita fee_type inválido |

### Propriedades garantidas

- **Fresh install funciona**: `supabase db reset && supabase db push` não quebra em 170000.
- **Idempotência em produção**: as migrations podem rodar novamente sem side-effects destrutivos.
- **Canonical source of truth**: comment na CONSTRAINT lista os 5 valores válidos e enumera o checklist para adicionar novos (CHECK + zod enum + FEE_LABELS).
- **UX em crise cambial**: admin pode alterar `fx_spread` via UI imediatamente (antes precisava SQL direto no DB).

### Como verificar no staging

```bash
# 1. Fresh install não quebra
supabase db reset

# 2. fx_spread seedada
psql -c "SELECT fee_type, rate_pct FROM platform_fee_config ORDER BY fee_type;"
# Esperado: billing_split, clearing, fx_spread, maintenance, swap

# 3. UI lista e permite editar
# Abrir /platform/fees — deve mostrar 5 rows incluindo "FX Spread (Saques)"

# 4. Tentativa de INSERT de fee_type inválido é rejeitada
psql -c "INSERT INTO platform_fee_config (fee_type, rate_pct) VALUES ('bogus', 1);"
# Esperado: ERROR ... check constraint "platform_fee_config_fee_type_check"

# 5. Integration tests passam
cd portal && npm ci
NODE_PATH=portal/node_modules npx tsx tools/integration_tests.ts
# Esperado: L01-44 tests ✓
```

### Cross-refs

- `L01-13` (CISO, Medium): mesma raiz — enum portal não tinha fx_spread. **Fechado junto** (status → in-progress).
- `L17-02` (VP Eng): ausência de CI que faz `supabase db reset` em cada PR. Atualmente `supabase.yml` tem `supabase start` que RUNS migrations contra fresh DB, mas o finding sugere adicionar smoke test explícito de fresh-install consistency.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.44).
- `2026-04-17` — Correção implementada (2 migrations + 2 arquivos portal + testes). Status: `in-progress`.