---
id: L03-02
audit_ref: "3.2"
lens: 3
title: "Congelamento de preços / taxas"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "atomicity", "migration", "testing", "cfo"]
files:
  - "supabase/migrations/20260421170000_l03_02_freeze_clearing_fee_at_emission.sql"
  - "tools/test_l03_02_freeze_clearing_fee.ts"
correction_type: migration+schema+rpc
test_required: true
tests:
  - "tools/test_l03_02_freeze_clearing_fee.ts"  # 16 tests, PG sandbox
  - "supabase/migrations/20260421170000_l03_02_freeze_clearing_fee_at_emission.sql"  # self-test in-migration
linked_issues: []
linked_prs:
  - 99671cb
owner: cfo
runbook: "docs/runbooks/CLEARING_FEE_FREEZE_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L03-02] Congelamento de preços / taxas
> **Lente:** 3 — CFO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** BACKEND · DATABASE
**Personas impactadas:** Plataforma, Assessoria emissora, CFO, Compliance

## Achado (estado pré-fix)

`execute_burn_atomic` — em toda a cadeia de migrations
`20260228160001_burn_plan_atomic.sql:139-142` →
`20260417140000_execute_burn_atomic_hardening.sql:179-183` →
`20260419130000_l18_wallet_mutation_guard.sql:459-463` — lê `rate_pct` de
`platform_fee_config` **no momento do burn**, não no momento da emissão das
coins:

```sql
SELECT rate_pct INTO v_fee_rate
  FROM public.platform_fee_config
 WHERE fee_type = 'clearing' AND is_active = true;
v_fee_rate := COALESCE(v_fee_rate, 3.0);
```

Consequência: se a plataforma ajustar `clearing` de 3.0% para 5.0% entre a
emissão da coin (T=0) e o burn dela (T=6 meses depois), a **assessoria
emissora paga 5% ao invés dos 3% que constavam quando ela emitiu**. Inverso
é simétrico: drop de 3% → 1% gera perda de receita prometida.

Impacto por lente:
- **CFO** — não consegue justificar o rate usado em settlement contestada
  (`clearing_settlements.fee_rate_pct` existia mas armazenava o rate no
  momento do *burn*, não da emissão).
- **Compliance** — histórico de fees inconsistente em auditoria: um
  `UPDATE` em `platform_fee_config` reescreve a verdade para todos os
  burns futuros, e não há tabela de histórico de rates.
- **Assessorias emissoras** — risco regulatório/contratual: a plataforma
  pode unilateralmente elevar a taxa e afetar coins já em trânsito.

## Correção aplicada — 2026-04-21

Implementação em **um único PR** com schema + backfill + duas RPCs
reescritas + helper + self-test:

### 1. Schema — snapshot imutável por linha de emissão

**`supabase/migrations/20260421170000_l03_02_freeze_clearing_fee_at_emission.sql`**

- Nova coluna `coin_ledger.clearing_fee_rate_pct_snapshot` `numeric(5,2)`
  (nullable, CHECK 0-100). Grava uma **cópia imutável** da rate vigente
  em `platform_fee_config` no exato momento da emissão.
- Partial INCLUDE index `idx_ledger_issue_snapshot (user_id, issuer_group_id)`
  cobrindo `delta_coins, clearing_fee_rate_pct_snapshot` para acelerar o
  weighted-avg per-issuer sem impactar o schema particionado existente.
- Nova coluna `clearing_settlements.fee_rate_source` `text NOT NULL`
  com CHECK `('snapshot_weighted_avg', 'live_config_fallback')` —
  CFO usa essa coluna no dashboard de reconciliação para distinguir o
  caminho normal do caminho defensivo (legacy).

### 2. Backfill one-shot

`DO $backfill$ ... $backfill$` atualiza todas as emissões pré-migration
com a rate ativa em 2026-04-21 (`3.00%` no seed atual). Após o deploy,
qualquer mudança futura de rate **NÃO** afeta retroativamente emissões
existentes — é a melhor aproximação possível sem tabela de histórico de
rates (documentada no COMMENT da coluna).

### 3. `emit_coins_atomic` — snapshot na emissão

Passa a ler `platform_fee_config.rate_pct (fee_type='clearing')` antes do
INSERT no ledger e **grava o valor no novo campo**. Nada mais muda da
semântica L02-01 + L19-01 + L05-03 anterior (idempotência via
`coin_ledger_idempotency`, mesma assinatura, mesmos erros `P0001/P0002/P0003`).

### 4. `execute_burn_atomic` — weighted-avg per issuer

Em vez de `SELECT platform_fee_config.rate_pct`, passa a chamar o novo
helper `fn_compute_clearing_fee_rate_for_issuer(athlete, issuer)` que
devolve `(rate_pct, source, sample_count, total_coins_emitted)` via
fórmula:

```sql
rate_pct := ROUND(
  SUM(delta_coins * clearing_fee_rate_pct_snapshot)
  / NULLIF(SUM(delta_coins) FILTER (WHERE snapshot IS NOT NULL), 0),
  2
);
```

- Se **todas** as linhas do issuer têm o mesmo snapshot (rate não mudou):
  resultado = snapshot.
- Se o admin alterou rate entre duas emissões do mesmo issuer: resultado
  = **média ponderada pelo volume emitido a cada rate** (aproximadamente
  FIFO sem per-coin tracking).
- Se todas as linhas são NULL (pré-migration + backfill skipped):
  fallback para `platform_fee_config.rate_pct` e
  `fee_rate_source='live_config_fallback'`.

### 5. Helper público read-only

`public.fn_compute_clearing_fee_rate_for_issuer(uuid, uuid)` — `STABLE`
`SECURITY DEFINER`, só `service_role` pode executar. Usado também por
tooling CFO/QA para **estimar o fee antes do burn** e pelos testes.

### 6. Auditoria per-settlement

`clearing_settlements.fee_rate_source` grava automaticamente qual
caminho foi usado em cada settlement. O dashboard de reconciliação do
CFO pode filtrar `WHERE fee_rate_source = 'live_config_fallback'` para
ver quanta exposição legacy ainda existe (deve convergir a 0% após
ciclo de archive/rotation do ledger).

## Escopo — o que **não** mudou

- `settle_clearing` (migration `20260228170000_custody_gaps.sql`) é
  inalterada — ela já usa `net_amount_usd/fee_amount_usd/gross_amount_usd`
  da linha de settlement e não recomputa a rate.
- `platform_revenue` INSERT dentro de `settle_clearing` também inalterado;
  ele usa o `v_fee` pré-computado (que agora reflete a rate congelada).
- `swap_orders` / `maintenance` — fora do escopo de L03-02 (tratam de
  outros fee_types e têm ciclo de vida diferente). Podem receber tratamento
  análogo em wave futura se necessário.

## Cobertura de testes

**`tools/test_l03_02_freeze_clearing_fee.ts`** — 16 testes PG sandbox:

- schema & registry (4): colunas criadas, função registrada, anon
  `permission_denied`.
- snapshot on emission (3): rate=3% grava 3.00; mudança de rate entre
  emissões gera snapshots diferentes; replay idempotente **não**
  sobrescreve snapshot já gravado.
- weighted-avg helper (5): rate única, dois rates peso 1:1, dois rates
  peso 3:1, zero emissões → fallback, apenas NULL snapshots → fallback.
- `execute_burn_atomic` freezing (4): intra-club sem settlement;
  interclub com rate única → fee frozen em 3% mesmo com live rate 9%;
  interclub com dois rates → fee = wavg 4%; interclub legacy NULL →
  `fee_rate_source='live_config_fallback'`.

Suite completa passa limpa em `http://127.0.0.1:54321` (local Supabase):

```
16 tests — ✓ 16 · ✗ 0
```

Self-test do migration (`DO $self_test$`) valida registro + coluna +
path de fallback em toda reaplicação da migration.

## Runbook operacional

Ver `docs/runbooks/CLEARING_FEE_FREEZE_RUNBOOK.md` para:
- Como **visualizar** exposição `live_config_fallback` no dashboard CFO.
- Como **reemitir** coins para corrigir snapshots errados (via
  `reverse_coin_emission_atomic` + `emit_coins_atomic`).
- Como **estimar** fee futuro de uma dupla (athlete, issuer) antes do burn.
- Procedimento de **mudança de `platform_fee_config`** (agora é
  forward-only: só afeta emissões futuras).

## Referência narrativa
Contexto completo e motivação detalhada em
[`docs/audit/parts/03-cfo.md`](../parts/03-cfo.md) — buscar pelo anchor
`[3.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.2).
- `2026-04-21` — **Fix shipped** (migration
  `20260421170000_l03_02_freeze_clearing_fee_at_emission.sql` + sandbox
  tests + runbook). Snapshot at emission + weighted-avg at burn. 16/16
  sandbox tests green. Back-compat: schema additive, assinaturas de RPC
  preservadas.
