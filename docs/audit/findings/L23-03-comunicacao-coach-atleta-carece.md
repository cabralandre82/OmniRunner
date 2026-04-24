---
id: L23-03
audit_ref: "23.3"
lens: 23
title: "Comunicação coach ↔ atleta carece"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "migration", "personas", "coach", "messaging"]
files:
  - supabase/migrations/20260421710000_l23_03_workout_messages.sql
correction_type: code
test_required: true
tests:
  - tools/audit/check-workout-messages.ts
linked_issues: []
linked_prs:
  - c0d5a76
owner: coach-platform
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  `public.workout_messages` é a primitiva canônica para conversas
  inline coach↔atleta ancoradas em um `workout_delivery_items.id`.
  Thread é **append-only** (no edit, no delete), cada mensagem carrega
  `body_text` (≤ 2000 chars) e/ou `audio_url` (HTTPS, duração 1-90 s).
  `chk_workout_messages_has_payload` impede bolha vazia;
  `chk_workout_messages_audio_shape` obriga URL HTTPS + duração
  válida; `chk_workout_messages_no_self_message` bloqueia auto-envio.

  RLS scope tri-party: participante envia/lê (`from_user_id = uid` ou
  `to_user_id = uid`) + staff do grupo (`admin_master`, `coach`,
  `assistant`) lê para moderação. Todas as políticas INSERT/UPDATE/
  DELETE diretas são **bloqueadas** (`WITH CHECK false` / `USING
  false`) — a única rota de escrita autorizada é o RPC `SECURITY
  DEFINER` `fn_workout_message_send(item_id, body_text, audio_url,
  audio_duration_sec)`, que (i) exige `auth.uid()`, (ii) resolve o
  recipiente a partir do `athlete_user_id` do item para staff, ou o
  coach canônico do grupo para reply do atleta, (iii) rejeita
  não-participante com P0004, item inexistente com P0002, payload
  vazio com P0005.

  `fn_workout_message_mark_read(message_id)` é recipient-only com
  `FOR UPDATE`, idempotente (retorna `false` se já lida). O trigger
  `fn_workout_messages_read_at_guard` garante que (a) `read_at` só é
  gravado uma vez, (b) nenhuma outra coluna (`body_text`, `audio_url`,
  `audio_duration_sec`, `from_user_id`, `to_user_id`, `created_at`)
  pode ser mutada via UPDATE. `fn_workout_message_unread_count()` é
  `STABLE SECURITY DEFINER` scoped a `auth.uid()` para a UI render o
  badge sem expor dados de outro atleta.

  Índices cobrem (a) thread read `(workout_delivery_item_id,
  created_at)` para abrir o chat, (b) partial `(to_user_id, created_at
  DESC) WHERE read_at IS NULL` para unread inbox, (c) `(group_id,
  created_at DESC)` para staff moderation overview.

  Coin policy: O RPC de envio **não** toca `coin_ledger` em
  circunstância alguma — mensagens são feature de produto, não
  gatilho de OmniCoin (reforça L22-02). O guard CI tem teste
  dedicado de ausência da string `coin_ledger` na migration.

  Self-test inline na migration valida: tabela presente, 4 CHECKs
  presentes, RLS habilitada, ausência de policies INSERT/UPDATE/
  DELETE permissivas, 3 RPCs presentes como SECURITY DEFINER,
  trigger de read_at presente, índice partial de unread presente.
  49 invariantes via `audit:workout-messages`.
---
# [L23-03] Comunicação coach ↔ atleta carece
> **Lente:** 23 — Treinador · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Banco + RLS + RPCs
**Personas impactadas:** Coach, Assistant, Admin Master, Atleta amador (assessoria)

## Achado
`announcements` (broadcast) e `support_tickets` (1:1 formal) cobriam só os extremos da pirâmide de comunicação. Faltava a **mensagem inline em cada workout** — a conversa curta e contextualizada que mantém o coach dentro do Omni em vez de usar WhatsApp paralelo.

## Risco / Impacto
Coach que abandona o app para falar via WhatsApp transforma o Omni Runner em planilha cara — perde stickiness, perde dados, perde o loop de feedback pedagógico. Para assessoria esportiva que cobra mensalidade, é o produto perdendo motivo de existir.

## Correção aplicada

Migration `supabase/migrations/20260421710000_l23_03_workout_messages.sql` introduz a tabela `public.workout_messages` como thread append-only ancorado em `workout_delivery_items.id`. Payload: `body_text` (≤ 2000 chars) e/ou `audio_url` (HTTPS, duração 1–90 s em `audio_duration_sec`). Quatro CHECK constraints bloqueiam mensagem vazia, texto gigante, áudio com URL não-HTTPS / duração fora da janela, e auto-envio (from = to).

RLS tri-party: participantes (`from_user_id` ou `to_user_id`) leem, staff do grupo (`admin_master` / `coach` / `assistant` em `coaching_members`) lê para moderação. Todas as policies INSERT/UPDATE/DELETE diretas são negadas (`WITH CHECK false`, `USING false`) — escrita só via RPCs `SECURITY DEFINER`.

RPCs:

1. `fn_workout_message_send(item_id, body_text, audio_url, audio_duration_sec)` — resolve o recipiente do item (`athlete_user_id` se staff envia; coach canônico do grupo se atleta responde), valida payload, cobra `auth.uid()`, retorna `uuid`. SQLSTATEs: P0001 (sem auth), P0002 (item não existe), P0003 (grupo sem coach para reply), P0004 (caller não-participante), P0005 (payload vazio).
2. `fn_workout_message_mark_read(message_id)` — recipient-only com `FOR UPDATE`, idempotente (retorna `false` se já lida). P0001/P0002/P0004 conforme acima.
3. `fn_workout_message_unread_count()` — `STABLE SECURITY DEFINER` retorna bigint do inbox do caller para o badge na UI.

Trigger `fn_workout_messages_read_at_guard` (BEFORE UPDATE) garante append-only em produção: `read_at` só pode ser gravado uma vez, e nenhuma outra coluna pode ser mutada via UPDATE — mesmo service_role passa pelo guard no caminho normal.

Índices:
- `idx_workout_messages_thread (workout_delivery_item_id, created_at)` — thread read.
- `idx_workout_messages_recipient_unread (to_user_id, created_at DESC) WHERE read_at IS NULL` — unread inbox.
- `idx_workout_messages_group (group_id, created_at DESC)` — staff moderation.

Self-test inline valida a forma 100% dentro da transação de deploy (tabela, 4 CHECKs, RLS, policies negativas, 3 RPCs SECURITY DEFINER, trigger de read_at, índice partial).

Coin-ledger policy: o guard CI `audit:workout-messages` tem um teste dedicado de **ausência** de `coin_ledger` na migration — consistente com a política L22-02 de que OmniCoins são challenge-only.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.3]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.3).
- `2026-04-21` — Fixed via `supabase/migrations/20260421710000_l23_03_workout_messages.sql` + guard `tools/audit/check-workout-messages.ts` (49 invariantes).
