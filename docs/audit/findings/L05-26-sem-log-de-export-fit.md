---
id: L05-26
audit_ref: "5.26"
lens: 5
title: "Zero delivery confirmation: coach não sabe se .fit chegou ao relógio"
severity: high
status: fixed
wave: 0
discovered_at: 2026-04-24
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["workout", "observability", "coach", "fit-export", "delivery"]
files:
  - supabase/migrations/20260424140000_l05_26_workout_export_log.sql
  - supabase/functions/generate-fit-workout/index.ts
  - portal/src/app/api/training-plan/workouts/[id]/export.fit/route.ts
  - portal/src/app/(portal)/workouts/assignments/page.tsx
correction_type: code
test_required: true
tests:
  - portal/src/app/api/training-plan/workouts/[id]/export.fit/route.test.ts
linked_issues: []
linked_prs: ["fd16d7b"]
owner: platform-workout
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-26] Zero delivery confirmation: coach não sabe se .fit chegou ao relógio

> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 0 · **Status:** fix-pending

**Camada:** DB + Edge + Portal (+ App deferred)
**Personas impactadas:** coach (não vê a entrega), atleta (não consegue provar que enviou), suporte (sem pivot pra diagnosticar "o treino não chegou")

## Achado

A Edge Function `generate-fit-workout` e a nova rota portal `export.fit`
geram o binário `.fit` e devolvem para o cliente, mas **não persistem
nada**. Isso gera uma cadeia de blind-spots:

1. **Coach não sabe se o atleta baixou o treino**: depois de atribuir
   para 30 atletas, o coach não consegue filtrar "quem ainda não puxou
   o `.fit`?" — ele só vê `status IN (planned, completed, missed)`,
   que mede execução (post-hoc) e não preparação.
2. **Atleta não tem recibo**: num conflito ("coach, não recebi o
   treino"), a única prova é o log server-side, que não existe.
3. **Suporte sem pivot**: ticket "o treino veio torto no Garmin do
   João" não tem dado para cruzar com a versão do template / hora de
   geração / device_hint.
4. **Ops sem métrica**: não dá para monitorar "% de atribuições que
   viraram export" — sinal básico de ativação do produto.

A auditoria `L22-10` já levantou falta de ACK no watch, mas o gap
anterior (antes até de chegar no watch) é que **não registramos nem
que o `.fit` foi gerado**.

## Impacto

- Coach reporta 2-3x/semana: "não sei se a atleta X baixou o treino".
- Time de CS não consegue corroborar atleta sem abrir Supabase logs
  (que só retêm 7 dias e não indexam por user/template).
- Métrica de ativação "D7 template→export" inexistente → não sabemos
  se o produto está sendo usado.
- Quando chegar delivery_ack do watch (Wave C via WorkoutKit /
  SDK Connect IQ), a tabela de log precisa já existir como spine.

## Correção proposta

### Schema

Nova tabela `coaching_workout_export_log` (insert-only, TTL 365d via
`pg_cron` em rodada futura):

```sql
id              uuid PK
group_id        uuid NOT NULL → coaching_groups
actor_user_id   uuid NOT NULL → auth.users  -- quem pediu (atleta ou coach)
template_id     uuid NOT NULL → coaching_workout_templates
assignment_id   uuid           → coaching_workout_assignments (opcional)
surface         text NOT NULL CHECK ('app' | 'portal')
kind            text NOT NULL CHECK ('generated' | 'shared' | 'failed')
bytes           int
device_hint     text           -- 'garmin', 'polar', null
share_target    text           -- iOS/Android share_sheet target (futuro)
error_code      text           -- quando kind='failed'
created_at      timestamptz NOT NULL DEFAULT now()
```

RLS:
- Staff (coach/admin/assistant) lê rows do próprio grupo.
- Atleta lê próprias rows (`actor_user_id = auth.uid()`).
- INSERT: `actor_user_id = auth.uid()` AND caller é membro do grupo.

View `v_assignment_last_export` (distinct on assignment_id, ordered by
created_at desc) para lookups O(1) por assignment.

### Edge Function

`generate-fit-workout/index.ts`:
- Lê `template.group_id` (já precisa para RLS do template, custo 0).
- Depois de encodar bytes com sucesso, **insere log row** via client
  user-scoped (respeita RLS). Falha do insert **não** bloqueia o
  retorno do `.fit` (log é observabilidade, não critical path).

### Portal API

`/api/training-plan/workouts/[id]/export.fit/route.ts` também insere
(`surface='portal'`, `actor_user_id = user.id`, `assignment_id = null`).

### Portal UI

`workouts/assignments/page.tsx`: nova coluna **"Relógio"** mostrando
- `—` se nunca exportado
- `📱 enviado há Xh` se última export `surface='app'`
- `🖥️ gerado há Xh` se apenas portal (coach testou, atleta não puxou)

Join faz via `v_assignment_last_export`.

### Flutter (deferido para slice 3)

App mandar um segundo evento `kind='shared'` quando SharePlus retornar
resultado OK. Requer build nativo → pulo por enquanto.

## Teste de regressão

- Unit (API route): confirma insert na tabela em cenário 200.
- Unit (API route): log insert falhando **não** quebra o 200 (best-effort).
- SQL migration self-check: RLS deny para cross-group reads.
- Manual: coach vê "Relógio" column nas assignments após atleta baixar.

## Cross-refs

- L22-10 (fixed-docs) — ACK nativo do watch via WorkoutKit / Connect IQ
  (Wave C). `coaching_workout_export_log` é a spine onde esses ACKs vão
  pousar quando chegarem.
- L05-25 (fixed) — portal export; agora também loga.
- L05-21/22/23 (fixed) — sem log, bugs de encoder ficaram invisíveis
  por meses; esta tabela fecha o loop de diagnóstico.

## Histórico

- `2026-04-24` — Descoberto durante Wave B de vistoria de passagem de treino.
- `2026-04-24` — Fixed (slice 2): schema + Edge Function + Portal route inserts + UI column.
