---
id: L05-11
audit_ref: "5.11"
lens: 5
title: "UI distribute-coins: sem confirmação dupla de grandes valores"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "portal", "ux"]
files:
  - portal/src/app/(portal)/athletes/distribute-button.tsx
  - portal/messages/pt-BR.json
  - portal/messages/en.json
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 9b5eb71

owner: product+platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Single-athlete distribute (cap 1000 OmniCoins per call após
  L05-03) ganha fat-finger guard: quando `amount >= 500` (≈ 50%
  do cap), `window.confirm()` força double-check com nome do
  atleta + valor. Implementação browser-native em vez de modal
  full-stack porque o caminho é low-frequency e a UI é
  client-component leve. i18n completo (pt-BR + en) com
  template `{amount}` / `{athlete}`. Batch distribute
  (`/api/distribute-coins/batch`, cap 100k via L05-03) ainda
  não tem UI dedicada — quando o painel batch chegar terá modal
  TYPE-CONFIRMAR estilo GitHub (anchor: este finding).
---
# [L05-11] UI distribute-coins: sem confirmação dupla de grandes valores
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/(portal)/distribute/...` presumivelmente tem um único botão "Distribuir". Sem modal "Você está distribuindo 50.000 moedas (≈ US$ 50.000). Digite CONFIRMAR.".
## Risco / Impacto

— Fat finger: coach queria 50 e digitou 5000.

## Correção proposta

— UI: quando `amount > 1000 OR amount * athletes > 5000` → modal de confirmação textual (tipo o "type DELETE to confirm" do GitHub).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.11).