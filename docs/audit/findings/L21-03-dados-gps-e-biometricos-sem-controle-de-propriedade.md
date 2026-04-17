---
id: L21-03
audit_ref: "21.3"
lens: 21
title: "Dados GPS e biométricos sem controle de propriedade (dilema do patrocínio)"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "rls", "integration", "migration", "performance", "personas"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L21-03] Dados GPS e biométricos sem controle de propriedade (dilema do patrocínio)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Atleta elite do clube X patrocinado por marca Y. Dados ficam em:

- `sessions`, `athlete_health_data` ([4.4] proposto): property do atleta via LGPD.
- `coaching_groups → clube X`: property do clube por contrato.
- `strava_connections`: compartilhado com Strava.
- Omni Runner pode agregar em "top elites" visível a todos.

Não há campo/política diferenciando "propriedade científica" (biomarcadores) de "propriedade comercial" (tempos de corrida).
## Risco / Impacto

— Atleta assina contrato com clube novo; clube anterior retém dados (violação LGPD + quebra contratual). Ou Omni Runner usa para "marketing agregado" ("top 10 atletas da plataforma: João, Maria…") — expõe segredo de treino.

## Correção proposta

—

```sql
ALTER TABLE athlete_health_data ADD COLUMN data_ownership jsonb DEFAULT '{
  "primary": "athlete",
  "licensed_to": [],
  "share_policy": "private"
}'::jsonb;

-- UI: athlete chooses whether performance data can be published in "top athletes"
ALTER TABLE profiles ADD COLUMN visibility_preferences jsonb DEFAULT '{
  "profile_discoverable": true,
  "pace_public": false,
  "hr_public": false,
  "sponsor_can_read_all": false
}'::jsonb;
```

Export-and-go: `/api/export/my-data` ([4.15]) inclui **transferência** (JSON signed) que outro clube pode importar ao atleta assinar lá.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.3).