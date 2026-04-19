---
id: L19-03
audit_ref: "19.3"
lens: 19
title: "Indexes redundantes em sessions"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["portal", "migration", "performance", "reliability"]
files:
  - supabase/migrations/20260218000000_full_schema.sql
  - supabase/migrations/20260419110001_l19_drop_redundant_indexes.sql
correction_type: migration
test_required: true
tests:
  - tools/test_l19_dba_health.ts
linked_issues: []
linked_prs:
  - 0893093
owner: platform-data-eng
runbook: docs/runbooks/DBA_BLOAT_AND_INDEX_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido em 2026-04-19 via migration `20260419110001_l19_drop_redundant_indexes.sql`.

  A auditoria flagou `idx_sessions_user_start` (duplicata de
  `idx_sessions_user`). Ampliando a investigação com a query proposta
  no finding, encontramos 16 índices redundantes no schema `public`
  (14 tabelas). Categorizados em 6 grupos:

  - **(a) UNIQUE-constraint shadow** (4 índices): `asaas_customer_map`,
    `coaching_device_links`, `coaching_workout_assignments`,
    `training_plan_weeks`.
  - **(b) PK shadow** (2 índices): `coaching_announcement_reads`,
    `strava_connections`.
  - **(c) UNIQUE single-column shadow** (3 índices): `running_dna`,
    `session_journal_entries`, `token_intents`.
  - **(d) Sibling overlap com mesmas colunas** (4 índices):
    `coaching_member_status`, `coaching_members`,
    `challenge_participants`, `workout_delivery_items`.
  - **(e) `LIKE INCLUDING ALL` clone duplication** (1):
    `coin_ledger_archive_issuer_group_id_idx1`.
  - **(f) Audit-flagged exato** (2): `idx_sessions_user_start`,
    `idx_sessions_strava_dedup`.

  Para evitar regressão, a migration também cria
  `pg_indexes_redundant_pairs()` (helper SQL service-role-only) que
  retorna qualquer par de índices com mesma coluna+predicado após
  normalizar nome+whitespace. O test
  `tools/test_l19_dba_health.ts` chama esse helper e falha CI se
  qualquer migration futura introduzir nova duplicata.

  Cobertura de teste: 33 assertions (16 DROPPED + 16 KEPT + 1
  redundant-pair audit) — todas passam após `supabase migration up`.

  Runbook operacional: `docs/runbooks/DBA_BLOAT_AND_INDEX_RUNBOOK.md`.
---
# [L19-03] Indexes redundantes em sessions
> **Lente:** 19 — DBA · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
—

```79:81:supabase/migrations/20260218000000_full_schema.sql
CREATE INDEX idx_sessions_user ON public.sessions(user_id, start_time_ms DESC);
CREATE INDEX idx_sessions_status ON public.sessions(user_id, status);
CREATE INDEX idx_sessions_verified ON public.sessions(user_id) WHERE is_verified = true;
```

Adicionado depois em `20260303700000_portal_performance_indexes.sql:7`:

```sql
CREATE INDEX idx_sessions_user_start
  ON public.sessions (user_id, start_time_ms DESC);
```
## Correção proposta

— Auditar todos índices duplicados:

```sql
SELECT tablename, array_agg(indexname) AS dups
FROM (
  SELECT tablename, indexname,
         pg_get_indexdef(indexrelid) AS def
  FROM pg_indexes i JOIN pg_stat_user_indexes s ON i.indexname = s.indexrelname
  WHERE schemaname = 'public'
) x
GROUP BY tablename, regexp_replace(def, 'idx_\w+', 'idx_')
HAVING COUNT(*) > 1;
```

Dropar duplicados. Regra de code review: novo index deve ser justificado por query real em `pg_stat_statements`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.3).