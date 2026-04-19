---
id: L10-05
audit_ref: "10.5"
lens: 10
title: "CSP hardened ([1.31]) mas sem report-uri"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["security-headers", "portal", "observability", "csp", "rls"]
files:
  - portal/src/lib/security/csp.ts
  - portal/src/app/api/csp-report/route.ts
  - portal/src/app/api/csp-report/route.test.ts
  - portal/src/middleware.ts
  - portal/src/lib/route-policy.ts
correction_type: code
test_required: true
tests:
  - portal/src/app/api/csp-report/route.test.ts
  - portal/src/lib/security/csp.test.ts
linked_issues: []
linked_prs: ["c41fef7"]
owner: portal-team
runbook: docs/runbooks/CSP_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Implementado em conjunto com L01-38 (CSP nonce-based hardening).

  - **Builder** (`lib/security/csp.ts`) emite ambas as formas de
    diretiva de reporting:
      ; report-uri /api/csp-report
      ; report-to csp-endpoint
    Firefox/Safari só honram a primeira; Chromium 73+ prefere a
    segunda. Browsers podem mandar para as duas — o handler dedup
    por shape antes de logar.
  - **`Report-To` header** é construído por
    `buildReportToHeader("/api/csp-report")` e setado no
    `tagResponse` da middleware (mesma response que carrega o CSP),
    ligando o group-name `csp-endpoint` ao endpoint.
  - **Sink** (`app/api/csp-report/route.ts`) suporta os dois
    payload shapes:
      • Legacy `application/csp-report`: `{ "csp-report": {...} }`
      • Modern `application/reports+json`: `[{ type, body: {...} }]`
    Normaliza em uma única struct `NormalisedViolation` e classifica:
      • `script-src*` (script-src, script-src-elem, script-src-attr)
        → `logger.warn` + `Sentry.captureMessage` (warning) com
        tags `csp_directive` e `csp_blocked_uri` para roteamento
        em alert rules.
      • Demais directives → `logger.info` (sem Sentry, evita ruído
        de tightening false positives).
    Sempre responde 204 (mesmo em parse error) para não vazar
    estado interno para um payload potencialmente atacante.
    Cap de 8 KiB no body + rate limit per-process de 60/60 s
    protegem o pipeline de log/Sentry contra browser mal-configurado
    em loop.
  - **Roteamento público**: `/api/csp-report` está em
    `PUBLIC_ROUTES` (`lib/route-policy.ts`). Browsers enviam reports
    sem cookie de sessão; gating em auth derrubaria silenciosamente
    todo report de página de login, OAuth callback, e os primeiros
    milissegundos de qualquer page load.

  Cobertura: 13 testes em `csp-report/route.test.ts` cobrindo
  parser dos dois shapes, severidade routing, rate limiter e
  oversize handling. Veja `docs/runbooks/CSP_RUNBOOK.md` para
  symptom→fix matrix (Symptom D específico para flooding de
  Sentry com `csp.violation.script_src`).
---
# [L10-05] CSP hardened ([1.31]) mas sem report-uri
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** PORTAL
**Personas impactadas:** Plataforma + atletas (observability gap)
## Achado original
`portal/next.config.mjs` CSP não tem `report-uri` nem `report-to`. Violações não são detectadas — qualquer XSS que tentou e foi bloqueado pelo CSP não deixa rastro, e qualquer regressão (re-introdução de inline script) é descoberta apenas quando um usuário reporta página em branco.

## Risco / Impacto
Operacional/segurança: incidentes de XSS bloqueados não chegam ao SIEM. Equipe não consegue diferenciar "fix de L01-38 está estável em produção" vs "fix está silenciosamente quebrado em uma página obscura".

## Correção aplicada
Sink `/api/csp-report` aceita os dois payload shapes (legacy + reports+json), normaliza, classifica severidade (script-src* → Sentry warning; resto → info-only) e bounds o pipeline com cap de body + rate limit. Builder emite `report-uri` + `report-to`; middleware emite `Report-To`. `PUBLIC_ROUTES` inclui o endpoint para que browsers possam reportar sem sessão.

Veja `note` no frontmatter para o trace técnico completo e `docs/runbooks/CSP_RUNBOOK.md` para o runbook operacional.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.5).
- `2026-04-17` — Corrigido em `c41fef7` junto com L01-38. Sink `/api/csp-report` + diretivas `report-uri`/`report-to` no header + `Report-To` payload no response. 13 testes cobrindo parser, severidade e proteções. Runbook em `docs/runbooks/CSP_RUNBOOK.md`.
