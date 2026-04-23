---
id: L11-06
audit_ref: "11.6"
lens: 11
title: "Dependências com ^ permitem breaking minor"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["portal", "supply-chain", "deps", "reproducibility", "lint"]
files:
  - .npmrc
  - portal/.npmrc
  - package.json
  - portal/package.json
  - tools/audit/check-npm-dependency-pinning.ts
correction_type: config
test_required: true
tests:
  - tools/audit/check-npm-dependency-pinning.ts
linked_issues: []
linked_prs:
  - "local/d609c78 — fix(deps): pin critical npm packages + .npmrc save-exact (L11-06)"
owner: platform
runbook: docs/runbooks/NPM_DEPENDENCY_PINNING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Landed 2026-04-21 in three layers:

  LAYER 1 — .npmrc (both at workspace root AND portal/):
    save-exact=true      # npm install foo writes exact version
    save-prefix=         # explicit empty prefix (defence in depth)
    engine-strict=true   # npm refuses install on engine mismatch

  LAYER 2 — manifest pins to EXACT semver (no caret/tilde) for 8 boundary
  packages that own product contracts:
    portal/package.json:
      next                14.2.35   (was ^14.2.15 resolved to 14.2.35)
      @supabase/ssr       0.8.0     (auth cookie contract)
      @supabase/supabase-js 2.97.0  (RPC + RLS error shape)
      zod                 4.3.6     (schema contract; 3→4 type-break risk)
      @sentry/nextjs      10.40.0   (observability boundary)
    package.json (root):
      tsx                 4.21.0    (was ^4.19.2 resolved to 4.21.0)
      lefthook            2.1.1     (pre-commit runner)
      js-yaml             4.1.1     (audit registry parser)

  Leaf / caret-OK deps untouched intentionally — full lockdown is a
  follow-up (L11-06-ext); this PR tightens the boundary surface.

  LAYER 3 — CI guard `npm run audit:npm-dependency-pinning`
  (tools/audit/check-npm-dependency-pinning.ts) with 3 sub-checks:

    1. npmrc: both files exist + each contains save-exact=true and
       save-prefix= lines; missing either fails closed.

    2. criticals: every CRITICAL_PACKAGES entry passes isExactVersion():
       rejects ^, ~, >=, <=, >, <, hyphen ranges, ||, * / x, file:,
       link:, git*, https?:, github:, npm:, workspace: protocols.
       Accepts plain semver + prerelease + build metadata.

    3. specifiers: scans ALL deps (not just criticals) for `*`, `latest`,
       `x` — nondeterministic resolution banned everywhere.

  Smoke-tested: (a) reintroducing "zod": "^4.3.6" fails with
  "must be an exact semver (no ^, ~, ranges, or aliases)" pointing at
  portal/package.json; (b) reintroducing "sonner": "latest" fails with
  "uses banned specifier 'latest' tag". Current tree: 0 regressions.

  RUNBOOK (docs/runbooks/NPM_DEPENDENCY_PINNING_RUNBOOK.md):
    • Policy matrix mapping each critical package → contract it owns →
      pinning rule.
    • 6 operational playbooks (security advisory upgrade flow; accidental
      caret reintroduction; guard fails on a legitimate caret; Dependabot
      / Renovate auto-PRs; *latest* sneak-in; lockfile drift).
    • Detection signals table.
    • Cross-refs to L11-05 (secure storage sibling), L11-07 (sqlcipher
      EOL — different remediation), L11-08 (Flutter SDK pinning —
      Dart-side analogue), L11-01/02/03/04/09 (supply-chain sextet
      already in Onda 0), L17-05 (@sentry/nextjs.getActiveSpan contract
      consumer).

  Decision NOT to use: a full-lockdown policy (pin EVERY leaf dep). The
  guard would flag hundreds of false positives during routine
  maintenance; the product contract is owned by the 8 boundary packages
  identified above. Leaf packages are caret-OK provided they don't use
  `*` / `latest` (the specifiers check catches that).

  Verified: both `npm install` runs succeed idempotently; `npm ls` in
  both workspaces shows exactly the pinned versions; portal lint clean;
  portal logger vitest suite (14 tests) green; audit:verify (348
  findings), audit:email-platform (6 invariants),
  audit:shared-prefs-sensitive-keys (891 dart files) all stay green
  alongside this change.
---
# [L11-06] Dependências com ^ permitem breaking minor
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/package.json`: `next: ^14.2.15`, `zod: ^4.3.6`. Caret permite minor bumps que podem quebrar tipos (zod 4 ↔ 3).
## Correção proposta

— `^` aceitável para produção SE houver CI de integração robusto. Pinar exatos (`14.2.15`) para `next`, `@supabase/ssr` em `package.json` + `.npmrc` `save-exact=true`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.6).
- `2026-04-21` — ✅ **Fixed** (commit `d609c78`). Defesa em 3 camadas — (1) **`.npmrc`** em workspace root + `portal/` com `save-exact=true`, `save-prefix=` (explícito vazio, defence in depth), `engine-strict=true` — any future `npm install foo` writes exact version, não caret. (2) **Pins exatos** em 8 boundary packages que controlam contratos de produto: `portal/package.json` — `next@14.2.35` (era `^14.2.15` resolvido para 14.2.35, 20 patches à frente — rendering/routing/middleware contract), `@supabase/ssr@0.8.0` (auth cookie contract; minor bumps historicamente mudaram cookie names), `@supabase/supabase-js@2.97.0` (RPC + RLS error shape), `zod@4.3.6` (schema contract; 3↔4 type-break cascade real via `@asteasolutions/zod-to-openapi` peer-dep flip), `@sentry/nextjs@10.40.0` (observability; `getActiveSpan()` semantics consumed por L17-05); `package.json` root — `tsx@4.21.0` (era `^4.19.2` resolvido para 4.21.0 — entrypoint de TODO `npm run audit:*`), `lefthook@2.1.1` (pre-commit runner; controls `flutter-analyze`/`portal-lint`/`gitleaks`), `js-yaml@4.1.1` (audit registry parser). Leaf/caret-OK deps intencionalmente não tocadas — full lockdown (L11-06-ext) seria ruído em routine maintenance; este PR fecha só a superfície de boundary. (3) **CI guard** `npm run audit:npm-dependency-pinning` (`tools/audit/check-npm-dependency-pinning.ts`) com 3 sub-checks: (a) `npmrc` — ambos arquivos existem + contêm `save-exact=true` E `save-prefix=`; missing either fails closed; (b) `criticals` — cada `CRITICAL_PACKAGES` entry passa `isExactVersion()` que rejeita `^`/`~`/`>=`/`<=`/`>`/`<`/hyphen ranges/`||`/`*`/`x`/file:/link:/git*/https?:/github:/npm:/workspace: protocols; aceita plain semver + prerelease + build metadata; (c) `specifiers` — scans TODOS deps (não só criticals) para `*`/`latest`/`x` — nondeterministic resolution banned everywhere. **Smoke-tested**: reintroduzir `"zod": "^4.3.6"` falha com "must be an exact semver (no ^, ~, ranges, or aliases)" apontando `portal/package.json`; reintroduzir `"sonner": "latest"` falha com "uses banned specifier 'latest' tag". Tree atual: 0 regressions. **Runbook** `docs/runbooks/NPM_DEPENDENCY_PINNING_RUNBOOK.md`: policy matrix (cada critical → contrato → pinning rule), 3 files table, CI guard specification, 6 operational playbooks (security advisory upgrade flow com minimum fixed version check; accidental caret reintroduction via malformed .npmrc / wrong directory / hand-edit; guard fails em caret legítimo — requires code-owner signoff para remover package de CRITICAL_PACKAGES; Dependabot/Renovate auto-PR review; `*`/`latest` sneak-in via copy-paste; `npm ci` output different between machines — lockfile drift), detection signals, cross-refs (L11-05 secure storage sibling; L11-07 sqlcipher EOL - different remediation path porque EOL=no patches; L11-08 Flutter SDK pinning Dart-side analogue; L11-01/02/03/04/09 supply-chain sextet já em Onda 0; L17-05 `@sentry/nextjs.getActiveSpan` consumer). **Decisão arquitetural**: NÃO full-lockdown (pin every leaf dep) — guard ruidoso em routine maintenance + contract ownership está nos 8 boundary packages. Leaf packages caret-OK desde que não `*`/`latest` (specifiers check catches). **Verificação**: `npm install` idempotente em ambos workspaces; `npm ls` mostra exatamente versões pinadas; `portal npm run lint` clean; `portal npm test logger.test.ts` 14/14 green; `audit:verify` (348 findings), `audit:email-platform` (6 invariants), `audit:shared-prefs-sensitive-keys` (891 dart files) todos stay green.