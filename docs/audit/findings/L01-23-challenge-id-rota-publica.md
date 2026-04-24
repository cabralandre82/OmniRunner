---
id: L01-23
audit_ref: "1.23"
lens: 1
title: "/challenge/[id] — Rota pública"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["gps", "pii", "mobile", "portal", "deep-link"]
files:
  - "portal/src/app/challenge/[id]/page.tsx"
  - "portal/src/lib/route-policy.ts"
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "27bc0f5"
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: landing page puramente estática, deep-link only, zero queries DB, zero PII."
---
# [L01-23] /challenge/[id] — Rota pública
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** ✅ fixed
**Camada:** PORTAL
**Personas impactadas:** Atleta (recebendo convite), Público

## Achado original
`/challenge/` em `PUBLIC_PREFIXES`. Conteúdo não lido. Preocupação: exposição de nomes, emails, GPS tracks.

## Re-auditoria 2026-04-24

### Análise de `portal/src/app/challenge/[id]/page.tsx`
A página é **landing page estática** (Server Component puro) que:

1. Constrói `deepLink = "omnirunner://challenge/${params.id}"`.
2. Gera OG metadata via `buildOgMetadata({ title: "Desafio aberto — Omni Runner", description: ... #${shortId} ... })` — onde `shortId = params.id.slice(0,8).toUpperCase()`. Apenas exibe o ID truncado que o próprio visitante forneceu.
3. Renderiza: título genérico, subtexto genérico, botão "Abrir no App", store badges.
4. Inclui `<meta http-equiv="refresh" content="3;url=..."/>` para auto-redirect ao app.

**Zero acesso a dados**: nenhum `createClient()`, nenhum `supabase`, nenhum `fetch`, nenhuma query. Não expõe nome, email, GPS, participantes — porque nada é lido do servidor.

### Defesa adicional
`portal/src/lib/route-policy.ts:123` impõe regex `^/challenge/[A-Za-z0-9_-]{1,64}$` (L01-25/L13-08 já fixado), impedindo:
- `/challenge/xxx/admin` (sub-path não é público)
- IDs com characters inválidos
- IDs longos o suficiente para causar DoS em OG metadata

### Conclusão
**Landing page safe by design.** Não há risco porque não há superfície de leak — é HTML estático derivado apenas do `params.id`. A validação/autorização real do desafio acontece no app (deep-link handler) e no backend (RPCs que o app chama após abrir).

**Reclassificado**: severity `na` → `safe`, status `fix-pending` → `fixed`.

## Referência narrativa
Contexto completo em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.23]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.23).
- `2026-04-24` — Re-auditoria confirmou landing page estática sem queries. Flipped para `fixed` (safe).
