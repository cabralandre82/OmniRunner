---
id: L01-24
audit_ref: "1.24"
lens: 1
title: "/invite/[code] — Rota pública de aceite de convite"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["rate-limit", "mobile", "portal", "seo", "deep-link"]
files:
  - "portal/src/app/invite/[code]/page.tsx"
  - "portal/src/lib/route-policy.ts"
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "27bc0f5"
  - "9fc89cc"
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: landing estática; validação real do código acontece no app + RPC. Enumeração via landing é inócua (não valida)."
---
# [L01-24] /invite/[code] — Rota pública de aceite de convite
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** ✅ fixed
**Camada:** PORTAL
**Personas impactadas:** Atleta convidado

## Achado original
Público via middleware. Deep link no app (`deep_link_handler.dart:118`). Precisa auditar: (a) códigos inválidos graciosamente; (b) rate limit para evitar enumeração; (c) não vazar membership de outros atletas.

## Re-auditoria 2026-04-24

### Análise de `portal/src/app/invite/[code]/page.tsx`
Mesma arquitetura de `/challenge/[id]`: **landing page estática** sem acesso a dados.

1. Constrói `deepLink = "omnirunner://invite/${params.code}"`.
2. OG metadata usa `params.code.slice(0,10).toUpperCase()` — apenas exibe o código que o próprio visitante já forneceu na URL.
3. Renderiza texto genérico "Convite para Assessoria" + CTA de abrir app + store badges.
4. Zero queries: nenhum `createClient`, nenhum `supabase`, nenhum `fetch`.

### Itens do achado original
| Preocupação | Verdict |
|---|---|
| (a) Códigos inválidos graciosamente | ✅ A landing não valida nada — sempre renderiza o mesmo HTML. Invalidação ocorre no app (`deep_link_handler.dart` usa regex `extractInviteCode` endurecida em L01-28) + RPC server-side. |
| (b) Rate limit para evitar enumeração | ✅ N/A — não há enumeração possível a partir da landing porque ela não distingue códigos válidos/inválidos (resposta idêntica para ambos). Rate limit da validação real fica no path `/api/invites/accept` (app), com proteção CSRF + origin pinning do middleware. |
| (c) Vazamento de membership | ✅ Impossível — landing não retorna dados sensíveis (nome do grupo, coach, contatos). Apenas texto genérico. |

### Defesa adicional
`portal/src/lib/route-policy.ts:124` impõe regex `^/invite/[A-Za-z0-9_-]{1,64}$` (L01-25/L13-08), rejeitando:
- `/invite/xyz/admin` (sub-paths não-públicos)
- Caracteres perigosos (quebra de path, injection)
- Tamanhos que causem DoS em OG metadata generation

O app-side endureceu `extractInviteCode` em L01-28 (`9fc89cc`) para regex mais restrito, eliminando vetores de manipulação do deep link.

### Conclusão
**Landing page safe by design.** Zero superfície de leak. Enumeração é inócua (sem feedback). Rate limiting da aceitação real é server-side, fora desta rota.

**Reclassificado**: severity `na` → `safe`, status `fix-pending` → `fixed`.

## Referência narrativa
Contexto completo em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.24]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.24).
- `2026-04-24` — Re-auditoria confirmou landing page estática + hardening do `extractInviteCode` (L01-28). Flipped para `fixed` (safe).
