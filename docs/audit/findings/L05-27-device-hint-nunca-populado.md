---
id: L05-27
audit_ref: "5.27"
lens: 5
title: "Export log: device_hint nunca é populado automaticamente"
severity: medium
status: fix-pending
wave: 0
discovered_at: 2026-04-24
fixed_at: null
closed_at: null
tags: ["workout", "observability", "coach", "fit-export", "delivery"]
files:
  - supabase/functions/generate-fit-workout/index.ts
  - portal/src/app/(portal)/workouts/assignments/page.tsx
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: platform-workout
runbook: null
effort_points: 1
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-27] Export log: device_hint nunca é populado automaticamente

> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 0 · **Status:** fix-pending

**Camada:** Edge Function + Portal UI
**Personas impactadas:** coach (vê "Atleta · 2h" na coluna Relógio mas não sabe se foi pro Garmin ou Polar), suporte (zero pivot quando ticket é "o .fit veio torto no Coros do João")

## Achado

A tabela `coaching_workout_export_log` (L05-26) tem coluna `device_hint`
com CHECK em `{garmin, coros, suunto, polar, apple_watch, wear_os, other}`,
mas a Edge Function `generate-fit-workout` e a rota portal `export.fit`
não populam esse campo — sempre inserem `NULL`.

Os dados necessários JÁ EXISTEM:

1. Para export iniciado pelo atleta (`surface='app'`), o resolvedor
   oficial é a view `v_athlete_watch_type` (migration
   `20260315000000_member_watch_type.sql`), que aplica a regra
   `COALESCE(watch_type_manual, device_link.provider)`.

2. A Edge Function já tem `actor_user_id` (obtido via `auth.getUser()`)
   e `group_id` (lido do template/assignment). Uma query adicional à
   view resolve o `device_hint` sem custo extra perceptível.

Sem `device_hint`:
- Coach não distingue "atleta Polar puxou" de "atleta Garmin puxou" no
  dashboard de assignments.
- Ops não consegue filtrar reclamações por plataforma ("Coros vem torto
  desde quarta").
- Quando vier ACK nativo (L22-10 Wave C), `device_hint` será a chave
  para cruzar export ↔ delivered events de plataformas diferentes.

## Impacto

- Coluna Relógio hoje mostra `📱 Atleta · 2h` — sem marca do relógio.
  Coach com 30 atletas não consegue perguntar "só os Polar tá vindo
  torto?" olhando a tabela.
- Dashboard futuro de funil (% export→delivered) fica cego por
  plataforma.

Low-severity porque não quebra funcionalidade, só cega observabilidade.

## Correção proposta

### Edge Function

Para `surface='app'` (atleta puxando pelo Flutter):

```ts
const { data: watchRow } = await supabase
  .from("v_athlete_watch_type")
  .select("resolved_watch_type")
  .eq("user_id", actorUserId)
  .eq("group_id", groupId)
  .maybeSingle();

const resolvedHint =
  watchRow?.resolved_watch_type && allowedHints.includes(watchRow.resolved_watch_type)
    ? watchRow.resolved_watch_type
    : deviceHint; // fallback pro que veio no body (se válido)
```

Para `surface='portal'` (coach baixando pelo portal): mantém `null`,
porque o destino é o próprio coach testando OU distribuição manual
offline — nenhuma das duas tem "watch de destino" conhecido do lado
do servidor.

Best-effort como todo o resto do log — falha na query não bloqueia
o retorno do `.fit`.

### Portal UI

`workouts/assignments/page.tsx`: enriquece o badge Relógio com o
device_hint quando presente:

- Antes: `📱 Atleta · 2h`
- Depois: `📱 Atleta · Garmin · 2h`

Se device_hint for null, volta ao formato anterior.

## Teste de regressão

- Manual: atleta com Garmin via `watch_type='garmin'` puxa treino →
  `coaching_workout_export_log.device_hint = 'garmin'`.
- Manual: atleta com Polar via `coaching_device_links.provider='polar'`
  puxa treino → `device_hint = 'polar'`.
- Manual: coach baixa pelo portal → `device_hint = null`.
- Manual: coluna Relógio mostra a marca do relógio.

Log-write best-effort, testes automatizados não cobrem a query
adicional porque dependeria de fixture de `v_athlete_watch_type` (view
sobre `coaching_members` + `coaching_device_links`), que duplicaria a
lógica já testada em `watch_type_compatibility_test.dart` (Dart).

## Cross-refs

- L05-26 (fixed) — tabela `coaching_workout_export_log` e view
  `v_assignment_last_export`, onde o dado enriquecido aparece.
- L05-24 (fixed) — `_fitProviders` incluindo Polar; device_hint agora
  reflete esse fix também no log.
- L22-10 (fixed-docs) — ACK nativo Wave C; device_hint será chave de
  join com delivered events.

## Histórico

- `2026-04-24` — Descoberto durante Wave B, depois da L05-26 criar a
  coluna sem preencher.
- `2026-04-24` — Fixed: Edge Function resolve via v_athlete_watch_type
  para surface='app'; UI enriquece badge.
