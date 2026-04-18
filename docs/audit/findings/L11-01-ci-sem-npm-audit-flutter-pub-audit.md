---
id: L11-01
audit_ref: "11.1"
lens: 11
title: "CI sem npm audit / flutter pub audit"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["mobile", "portal", "testing", "supply-chain", "ci"]
files:
  - .github/workflows/security.yml
  - .osv-scanner.toml
  - portal/package.json
  - portal/package-lock.json
correction_type: process
test_required: true
tests:
  - .github/workflows/security.yml
linked_issues: []
linked_prs:
  - "commit:HEAD"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Gate `npm audit --audit-level=critical` (passa: 0 critical hoje) + osv-scanner para portal+omni_runner. 4 high vulns transitivas em Next.js 14/15 e 1 em vitest 3 estão allowlistadas em `.osv-scanner.toml` com `ignoreUntil=2026-07-17` — clearance final depende de upgrade major (Next 16, Vitest 4) escopado em follow-up separado. `npm audit fix` não-breaking aplicado nesta PR já reduziu 19 → 10 vulns."
---
# [L11-01] CI sem npm audit / flutter pub audit
> **Lente:** 11 — Supply Chain · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** CI / supply chain
**Personas impactadas:** Plataforma (security/SRE), DevOps

## Achado
`.github/workflows/portal.yml` rodava lint/test/build/e2e/k6 mas **nenhum
passo de security scan**. `flutter.yml` idem. CVE em `next`, `@supabase/ssr`,
`zod`, `framer-motion` etc. passava despercebido em builds por semanas.

## Risco / Impacto
- Vulnerabilidades críticas em deps transitivas chegam a produção sem alerta.
- LGPD Art. 46 exige "medidas de segurança técnicas" — auditoria de
  dependências é baseline. Sem isso, a plataforma fica em desconformidade
  caso ocorra breach via CVE conhecido > 7 dias.
- Fornecedores B2B (assessorias, parceiros futuros L16-04) cada vez mais
  exigem evidência de scan contínuo (NIST SSDF, ISO 27001).

## Correção implementada

Workflow novo `.github/workflows/security.yml` com 5 jobs em paralelo:

### 1. `npm-audit` — Portal (Node)
Dois passos:

- **Gate** (`set -e`): `npm audit --audit-level=critical` — falha o build se
  qualquer CVE crítica aparecer. Calibração escolhida porque o estado atual
  é 0 critical / 4 high (todas em `next` 14/15 — clearance requer major bump
  para Next 16, escopado em follow-up).
- **Informacional** (`continue-on-error: true`): roda `--audit-level=high` e
  emite GitHub Actions `::warning` + sobe `npm-audit-high.json` como
  artifact (retenção 30d). Visibilidade contínua para o time sem bloquear o
  merge.

### 2. `osv-scanner` — Portal + Flutter
Roda `google/osv-scanner-action@v2.0.0` contra `portal/package-lock.json` E
`omni_runner/pubspec.lock` simultaneamente. Lê `.osv-scanner.toml` que
mantém allowlist timeboxed (`ignoreUntil=2026-07-17`) das vulns conhecidas
+ justificativa por advisory. Block-on-critical por padrão. Sobe SARIF
para integração futura com GitHub Security tab.

### 3. `gitleaks` — Cross-cutting
Documentado em L11-03.

### 4-5. `sbom-portal` + `sbom-flutter` — CycloneDX SBOMs
Documentado em L11-02.

### 6. Hardening do `npm audit fix` não-breaking
Aplicado nesta mesma PR. Impacto: 19 vulns → 10 vulns (somente
`package-lock.json` mudou, `package.json` intacto). Removidas:
- `serialize-javascript` <=7.0.4 (RCE via RegExp.flags)
- `terser-webpack-plugin` (depende de serialize-javascript vulnerável)
- `undici` 7.0.0-7.23.0 (6 advisories: WebSocket overflow, smuggling, CRLF
  injection, memory consumption)
- `@vitest/coverage-v8` indireta (parcial — vitest core ainda 3.x)
- 5 outras transitivas auto-corrigíveis

### 7. Local pre-commit (lefthook)
`gitleaks` adicionado a `lefthook.yml` (skip-on-missing-binary para
desenvolvedores que ainda não instalaram). Defesa em camadas: catch
local antes do CI quando possível.

### 8. NPM scripts
- `npm run security:audit` → equivalente local do gate
  (`npm audit --audit-level=critical`)
- `npm run security:audit:report` → relatório completo high+

## Follow-ups (escopados separadamente)

1. **L11-01-followup-next16-upgrade** — Next.js 14 → 16 (4 high vulns
   clearance). Requer regression test de todas rotas + middleware +
   Sentry + integração Vercel. Estimado: 8-13 pontos.
2. **L11-01-followup-vitest4-upgrade** — Vitest 3 → 4 (esbuild dev SSRF).
   Dev-only; impacto reduzido. Estimado: 3-5 pontos.
3. **L11-01-followup-gh-security-tab** — habilitar `permissions:
   security-events: write` em todos os workflows e enviar SARIF para
   GitHub Security tab (centraliza dashboard de vulns). Estimado: 2 pontos.

## Teste de regressão
- `.github/workflows/security.yml` é executado em todo PR contra `master`
  + push para `master` + cron semanal (segunda 06:00 UTC).
- Local: `cd portal && npm run security:audit` deve sair com exit 0.
- Local: `cd portal && npm run security:audit:report` lista as 10 vulns
  remanescentes (todas allowlistadas).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.1).
- `2026-04-17` — Correção implementada: workflow `security.yml` (5 jobs), `.osv-scanner.toml` com allowlist timeboxed, `npm audit fix` não-breaking (19→10 vulns), pre-commit hook gitleaks, npm scripts locais. Follow-ups L11-01-followup-next16-upgrade + L11-01-followup-vitest4-upgrade documentados para clearance dos 4 high remanescentes. Promovido a `fixed`.
