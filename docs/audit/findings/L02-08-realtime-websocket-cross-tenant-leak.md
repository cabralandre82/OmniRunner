---
id: L02-08
audit_ref: "2.8"
lens: 2
title: "Realtime / Websocket — Cross-tenant leak"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "rls", "mobile", "migration", "reliability"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L02-08] Realtime / Websocket — Cross-tenant leak
> **Lente:** 2 — CTO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** APP (Flutter via `supabase_flutter`) + BACKEND
**Personas impactadas:** Atleta, Assessoria
## Achado
O projeto usa Realtime (pubspec declara `supabase_flutter`). Tabelas adicionadas a `supabase_realtime` vazam se RLS não filtrar nos eventos. Não verifiquei migration `supabase_realtime` direto, mas o padrão genérico é: Realtime aplica RLS via `auth.uid()` do subscriber. As policies `custody_accounts` estão com role `'professor'` (ver [1.43]) → **atletas e coaches nunca recebem eventos de custody** (bem). Porém, policies de `coaching_members`, `wallets`, `sessions` podem permitir vazamento — atleta A inspeciona seu cliente WebSocket e altera filtros para receber eventos de atleta B. RLS em `wallets` precisa restringir a `user_id = auth.uid()`.
## Risco / Impacto

Vazamento de saldo, sessão, ranking por inspeção de WebSocket.

## Correção proposta

Auditar cada tabela com REPLICA IDENTITY ou em `ALTER PUBLICATION supabase_realtime ADD TABLE X`. Confirmar RLS FOR SELECT é restritivo.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.8).