---
id: L23-01
audit_ref: "23.1"
lens: 23
title: "Workout delivery em massa sem preview por atleta"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "reliability", "coach", "rpc", "preview"]
files:
  - supabase/migrations/20260421720000_l23_01_bulk_assign_preview.sql
  - tools/audit/check-bulk-assign-preview.ts
correction_type: rpc
test_required: true
tests:
  - tools/audit/check-bulk-assign-preview.ts
linked_issues: []
linked_prs: []
owner: coach-tooling
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Introduz RPC read-only `public.fn_bulk_assign_preview(p_group_id,
  p_athlete_ids[], p_target_date, p_planned_tss)` que gera matriz de
  risco "atleta × alerta" ANTES do bulk-assign ser gravado. Retorna
  jsonb envelope com:

  - `counts` {green, yellow, red, gray}
  - `athletes[]` com `risk_level`, `reasons[]`,
    `workouts_confirmed_7d/14d`, `upcoming_week_count`,
    `last_confirmed_at`

  Risk rules (derivadas dos sinais disponíveis hoje via
  workout_delivery_items — sem depender de tabelas que ainda não
  existem como injury_reports ou subjective_wellness):

  - 🔴 **red**   — ≥7 treinos confirmados em 7d (volume excessivo,
                   >1/dia em média) OR ≥5 treinos na fila desta
                   semana (overbooked).
  - 🟡 **yellow**— ≥5 confirmados em 7d OR ≥3 na fila desta semana.
  - ⚪ **gray**  — 0 confirmados em 14d (sem baseline de carga)
                   OR perfil não é atleta do grupo.
  - 🟢 **green** — caso contrário.

  Gates:
  - P0001 INVALID_INPUT: p_group_id null, p_athlete_ids vazio ou
    > 500 entradas (DoS guard).
  - P0002 GROUP_NOT_FOUND: p_group_id inexistente.
  - P0010 UNAUTHORIZED: auth.uid() null ou role ≠ (coach|assistant).

  Propriedades:
  - `SECURITY DEFINER`, `STABLE` (read-only; nunca escreve em
    qualquer tabela), `search_path = public, pg_temp`.
  - `REVOKE FROM PUBLIC` + `GRANT EXECUTE TO authenticated`.
  - **Nunca toca coin_ledger/wallets** (marker L04-07-OK reforçando
    política L22-02 OmniCoin challenge-only).

  Ordenação do array retornado: red → yellow → gray → green, dentro
  de cada grupo por `display_name`. UX safer-first: atletas de
  maior risco aparecem primeiro, coach confirma com 1 clique ou
  ajusta individual com 2 cliques.

  CI guard `audit:bulk-assign-preview` (60+ asserts) valida assinatura,
  SECURITY DEFINER, STABLE, thresholds de classificação, gates de
  erro, envelope shape, grants, ausência de escrita no ledger.

  Futura evolução: quando tabelas de injury-report ou subjective-
  wellness existirem, estender CTE `classified` para incorporar
  sinais adicionais sem quebrar o contrato externo.
---
# [L23-01] Workout delivery em massa sem preview por atleta
> **Lente:** 23 — Treinador · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Backend / Coach tooling
**Personas impactadas:** Coach (200+ atletas), atleta (redução de sobrecarga/lesão)

## Achado
`staff_workout_assign_screen.dart` atribui workout a atletas sem preview individual — coach de 200 atletas distribuía pacote genérico sem ver carga recente ou número de treinos já agendados, aumentando risco de overtraining e lesão.

## Risco / Impacto
- Atleta lesiona → reputação do coach quebra, churn da assessoria;
- Atleta em overtraining não performa nas provas → cancela assinatura;
- Coach sem ferramenta para triagem individual opta por atribuir pouco (perde valor) ou atribuir demais (compromete atleta).

## Correção aplicada

### 1. RPC `fn_bulk_assign_preview`
`supabase/migrations/20260421720000_l23_01_bulk_assign_preview.sql` introduz função read-only que:
- valida input (group_id, athletes ≤ 500, existência do grupo);
- gate de autorização — apenas coach/assistant do grupo;
- deriva risk signals de `workout_delivery_items` existente (confirmed 7d/14d + upcoming week);
- retorna jsonb envelope com counts e per-athlete rows ordenadas red-first.

### 2. Risk classification (baseada em dados disponíveis)
- 🔴 **red**: ≥7 confirmados em 7d ou ≥5 agendados nesta semana.
- 🟡 **yellow**: ≥5 confirmados em 7d ou ≥3 agendados nesta semana.
- ⚪ **gray**: 0 confirmados em 14d (sem baseline) ou não é atleta do grupo.
- 🟢 **green**: baseline presente + carga dentro de thresholds.

### 3. Postura de segurança
- `SECURITY DEFINER` + `STABLE` + `search_path = public, pg_temp`.
- Revoga PUBLIC, concede EXECUTE a authenticated apenas.
- Self-test interno valida registry do proc, SD, volatility, grant.

### 4. OmniCoin invariant
RPC **não toca `coin_ledger` nem `wallets`** — marker `L04-07-OK` reforça política L22-02 (OmniCoin challenge-only).

### 5. CI guard (`tools/audit/check-bulk-assign-preview.ts`)
60+ asserts validando assinatura (`uuid, uuid[], date, numeric`), SECURITY DEFINER, STABLE, search_path pinned, thresholds de classificação (exatamente 7/5/3), envelope shape (7 chaves top + 10 per-athlete), ordenação red-first, REVOKE/GRANT, ausência de INSERT em coin_ledger.

## Teste de regressão
- `npm run audit:bulk-assign-preview` — 60+ asserts.
- Smoke integration: chamar RPC com athletes de grupo de teste e validar contagem de risk levels.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.1).
- `2026-04-21` — Fixed via migration `20260421720000_l23_01_bulk_assign_preview.sql` + CI guard `audit:bulk-assign-preview`. UI screen consumirá o envelope jsonb em PR separado de mobile (já há precedente no `staff_workout_assign_screen.dart`).
