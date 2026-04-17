---
id: L23-03
audit_ref: "23.3"
lens: 23
title: "Comunicação coach ↔ atleta carece"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "migration", "personas", "coach"]
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
# [L23-03] Comunicação coach ↔ atleta carece
> **Lente:** 23 — Treinador · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `announcements` (broadcast) e `support_tickets` (1:1 formal). Sem mensagem inline em cada workout ("João, caprichei no seu treino hoje, bora que hoje é Z4!").
## Risco / Impacto

— Coach abandona Omni e usa WhatsApp paralelo → produto vira planilha cara, não ganha stickiness.

## Correção proposta

—

```sql
CREATE TABLE public.workout_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_delivery_item_id uuid REFERENCES workout_delivery_items(id),
  from_user_id uuid, to_user_id uuid,
  message text, audio_url text,
  read_at timestamptz, created_at timestamptz DEFAULT now()
);
```

Áudio opcional (coach grava 20 s, atleta ouve antes do treino). Fica dentro do app.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.3).