---
id: L10-04
audit_ref: "10.4"
lens: 10
title: "Sem WAF explícito"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: []
files: []
correction_type: code
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
# [L10-04] Sem WAF explícito
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Vercel fornece edge WAF básico, mas não há regras customizadas (bloquear `User-Agent: sqlmap`, geo-fence Supabase a países operados, limite país × rate).
## Correção proposta

— Vercel Firewall rules: bloquear por IP/country/UA/path + integrar Cloudflare (tier pago) se risco aumentar.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.4).