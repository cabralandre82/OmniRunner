---
id: L04-06
audit_ref: "4.6"
lens: 4
title: "Campo instagram_handle, tiktok_handle em profiles sem política de uso"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["rls", "rate-limit", "mobile"]
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
# [L04-06] Campo instagram_handle, tiktok_handle em profiles sem política de uso
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `profiles.instagram_handle` é lido via RLS `select_profile_public` (se existir). Não há:
- Toggle "esconder do público" independente do display_name.
- Validação (evitar links maliciosos, "@bitly/x").
- Rate limit de changes (evita impersonation: trocar o handle a cada 10 s).
## Risco / Impacto

— Stalkers usam Omni Runner como diretório de atletas por rede social.

## Correção proposta

— Adicionar `profile_public jsonb` com flags granulares (`show_instagram`, `show_tiktok`, `show_pace`, `show_location`) e aplicar na RLS de views públicas.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.6).