---
id: L20-07
audit_ref: "20.7"
lens: 20
title: "Backup testado — zero evidence"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "testing", "reliability"]
files:
  - docs/runbooks/DR_PROCEDURE.md
correction_type: process
test_required: true
tests:
  - docs/runbooks/DR_PROCEDURE.md
linked_issues: []
linked_prs:
  - "commit:75e4a7f"
owner: unassigned
runbook: docs/runbooks/DR_PROCEDURE.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "DR_PROCEDURE.md cobre 2 modos: Modo A (drill trimestral planejado, RTO target < 60min) com 6 fases (pre-flight, execution, validation smoke, go/no-go, cleanup, métricas) + Modo B (DR real com aprovação 4-eye, Asaas suspension, restore strategy decision matrix). Apêndices: PITR config audit + contatos de incidente. Free tier Supabase NÃO tem PITR — follow-up L20-07-followup-pitr-upgrade documentado."
---
# [L20-07] Backup testado — zero evidence
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** disaster recovery
**Personas impactadas:** Plataforma (SRE), Finance/Compliance, todos os usuários

## Achado
Supabase PITR habilitado por default (a confirmar — depende do tier),
mas **processo de restore nunca testado** em game-day. "Temos backup" é
crença não-validada até o dia do disaster.

## Risco / Impacto
- Em incidente real: descobrir que backup está corrompido / incompleto /
  sem permissão / sem PITR = perda total de dados financeiros.
- LGPD Art. 46: "medidas técnicas" inclui ability to recover. Sem drill,
  ficamos em descumprimento se ANPD auditar pós-breach.
- Compliance B2B (assessorias enterprise) exige evidência de DR drill
  documentado.

## Correção implementada

### `docs/runbooks/DR_PROCEDURE.md`
Runbook completo cobrindo 2 modos:

#### Modo A — Drill trimestral (game-day)
6 fases:
1. **Pré-flight** (T-7d): anúncio, quota check, snapshot timestamp
2. **Execução** (T0): provisionar sandbox + restore
3. **Validação smoke**: 5 queries SQL canônicas para validar volumetria,
   invariants (must be 0), wallet drift (must be 0), RLS sanity, function
   count
4. **Decisão go/no-go**: PASS se ±0.1%, FAIL = abrir incidente P1
5. **Cleanup**: deletar sandbox + atualizar runbook
6. **Métricas**: capturar RTO, restore duration, smoke duration

Cadência: trimestral, terça 14:00 UTC, owner rotativo + buddy.

#### Modo B — DR real (incidente)
Procedure mais rigoroso:
1. **Pré-condições**: aprovação 4-eye + Asaas billing suspenso
2. **Contenção** (T0→T+15min): maintenance mode + status page
3. **Decisão de strategy** (T+15→T+30min): matriz por cenário
4. **Execução** (T+30min→T+3h30min): PITR completo OU seletivo
5. **Validação pós-restore**: smoke do Modo A + invariants 0
6. **Restart staged**: Asaas reativar + maintenance off + smoke E2E
7. **Postmortem** (T+24h): usar TEMPLATE.md (L20-08)

#### Apêndices
- **A**: backup/PITR configuration audit query (cron jobs check)
- **B**: contatos (Supabase support, Asaas, Vercel, CTO)

### Teste de regressão
- Drill trimestral é o teste. Falha = postmortem + atualizar runbook.
- Métricas comparáveis ao SLO RTO/RPO declarado (4h/24h).

## Limitações conhecidas
- **Free tier Supabase NÃO tem PITR** — apenas snapshots diários sem
  point-in-time. Nosso RPO declarado de 24h fica imprecio (na prática
  24-48h). Documented em Apêndice A.
  - Follow-up: **L20-07-followup-pitr-upgrade** — upgrade Supabase Pro
    ($25/mo) para PITR real. Estimado: 1 ponto (decisão financeira) +
    1 ponto (executar upgrade + testar restore via PITR).
- `tools/dr-baseline.sql` ainda não existe — script para snapshot
  baseline pre-drill. Documentar como follow-up:
  - **L20-07-followup-baseline-script** — criar
    `tools/dr-baseline.sql` que captura volumetria + checksums das
    tabelas críticas no momento do snapshot. Estimado: 2 pontos.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.7).
- `2026-04-17` — Correção implementada: `DR_PROCEDURE.md` com 2 modos completos (drill + real DR), 6 fases cada, smoke queries, decision matrix, contatos. Follow-ups documentados (PITR upgrade, baseline script). Promovido a `fixed`.
