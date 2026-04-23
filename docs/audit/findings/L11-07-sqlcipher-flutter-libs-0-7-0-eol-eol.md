---
id: L11-07
audit_ref: "11.7"
lens: 11
title: "sqlcipher_flutter_libs: ^0.7.0+eol — \"eol\" = end of life"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "reliability", "supply-chain", "fixed"]
files:
  - omni_runner/pubspec.yaml
  - tools/audit/check-sqlcipher-eol.ts
  - docs/adr/009-sqlcipher-eol-migration.md
  - docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md
  - package.json
  - .github/dependabot.yml
correction_type: process
test_required: true
tests:
  - tools/audit/check-sqlcipher-eol.ts
linked_issues: []
linked_prs:
  - "local:6c661f7 fix(mobile/deps): pin sqlcipher_flutter_libs + EOL CI guard (L11-07)"
  - "local:TBD docs(audit): close L11-07 (SQLCipher EOL pin + ADR-009 + runbook + guard)"
owner: mobile
runbook: docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Pin-and-watch posture (ADR-009), not a full migration. The acute
  supply-chain risk of an EOL package is "a transitive name-squat
  publishes as 0.7.1+malicious and `pub get` silently picks it up";
  the exact pin + CI guard kills that. The residual "CVE exposure"
  risk on the frozen SQLCipher binaries is handled by a watch
  protocol (GHSA feeds for sqlcipher/sqlite) and ADR-009 §"Exit
  criteria". An actual migration to `sqlite3_flutter_libs` +
  app-layer AES-GCM is queued for Onda 2 or when a trigger fires
  (whichever comes first) — see runbook Section 4.5.

  Three-layer defence:
    1. Exact pin: `sqlcipher_flutter_libs: 0.7.0+eol` in
       omni_runner/pubspec.yaml (no caret), preceded by a 10-line
       warning block referencing L11-07, the ADR, and the runbook.
    2. ADR-009 documenting the threat model, three evaluated
       migration options (A/B/C with effort + cons), the preferred
       option, and the exit criteria. Paired with the operational
       runbook which includes 7 playbooks and a detection-signals
       table.
    3. CI guard (`npm run audit:sqlcipher-eol`) that rejects pin
       drift, missing warning block, missing ADR, missing runbook,
       missing Dependabot ignore entry.

  Cross-references in the runbook to L11-06 (same philosophy, NPM
  side), L11-05 (secure-storage policy covers the DB encryption
  key), L11-08 (Flutter SDK pinning — future trigger via NDK bump),
  L01-30/31 (ProGuard §7 stays correct for the pinned version),
  C-03 (PRAGMA key raw-hex format — closed by the Option A
  migration).
---
# [L11-07] sqlcipher_flutter_libs: ^0.7.0+eol — "eol" = end of life
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)

**Camada:** Mobile / Supply chain
**Personas impactadas:** Mobile engineering, Security on-call, Release engineering.

## Achado

Linha do `pubspec.yaml` explicitamente marcava EOL — `sqlcipher_flutter_libs: ^0.7.0+eol`. O código cifra o banco local mas depende de biblioteca sem manutenção upstream; caret em cima do `+eol` era sem sentido (o pacote nunca mais publicará) **e** perigoso (um name-squatter publicando `0.7.1+malicious` como "fork" seria selecionado silenciosamente por `flutter pub get`).

## Risco / Impacto

- CVE futuro em SQLCipher ou SQLite (o parser bundled) não será corrigido upstream; app exposto até migração.
- Risco AGUDO: transitive name-squat fork silenciosamente puxado pelo caret.
- Dependabot não propõe upgrades (já ignorado em `drift-and-storage` group), mas um engenheiro rodando `dart pub add sqlcipher_flutter_libs` ou `flutter pub upgrade --major-versions` reintroduz caret por default.
- LGPD: não podemos simplesmente remover criptografia — o banco local contém histórico de treinos, GPS traces e session tokens.

## Correção aplicada (2026-04-21)

Postura **pin-and-watch** — vide ADR-009 para o threat-model completo, opções avaliadas e critérios de saída.

### Defesa em 3 camadas

1. **Pin exato** em `omni_runner/pubspec.yaml` — `sqlcipher_flutter_libs: 0.7.0+eol` (sem caret, sem range), com bloco de comentário de 10 linhas acima declarando L11-07 + referências ao ADR-009 e ao runbook.
2. **ADR-009** (`docs/adr/009-sqlcipher-eol-migration.md`) documenta:
   - Threat-model (3 categorias de CVE: KDF, SQL parser, memory safety; mitigações pré-existentes).
   - 3 opções de migração avaliadas (A: `sqlite3_flutter_libs` + AES-GCM layer; B: SQLCipher fork via CMake; C: community fork) com prós, contras, esforço.
   - Opção A preferida (fecha C-03 de PRAGMA key injection como side-effect).
   - 5 critérios de saída (CVSS ≥ 7.0 em código path exercised, deprecação Flutter 4 de NDK < r27, rejeição da store, security review, customer contratual).
3. **Runbook operacional** (`docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md`) com 7 playbooks:
   - (4.1) "Devo fazer upgrade?" → não, aponte para ADR.
   - (4.2) Advisory/CVE fire → triage + decisão em 4 passos.
   - (4.3) Dependabot abre PR → fechar + patchar group config.
   - (4.4) CI guard falha → root-cause 4 ramos.
   - (4.5) Executar migração (trigger fired) → 7 passos incluindo data migration resumable + feature flag gradual rollout.
   - (4.6) Fork proposto → security review ou rejeição documentada.
   - (4.7) Security review flags EOL → verificação contra exit criteria.
4. **CI guard** (`tools/audit/check-sqlcipher-eol.ts`, `npm run audit:sqlcipher-eol`) enforça 5 invariantes: pin exato + warning block contíguo de ≥ 4 linhas citando L11-07 + ADR presente e válido + runbook presente e cross-linked + Dependabot ignore entry no `drift-and-storage` group.

### Verificação

- `npm run audit:sqlcipher-eol` → ✅ clean.
- `npm run audit:verify` → 348 findings validados, sem regressão.
- Smoke-tests do guard: (i) caret reintroduzido em pubspec → `pin_drift` flagado; (ii) Dependabot ignore removido → `missing_dependabot_ignore` flagado; ambos revertem clean.
- `flutter analyze` → no issues found.
- `flutter pub deps` → `sqlcipher_flutter_libs 0.7.0+eol` resolvido exatamente.

## Referência narrativa

Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.7]`.

## Histórico

- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.7).
- `2026-04-21` — ✅ **Fixed** (commits `6c661f7` fix + TBD docs). Postura pin-and-watch: (1) pin exato em `omni_runner/pubspec.yaml` (sem caret) com warning block 10 linhas, (2) ADR-009 com threat-model + 3 opções de migração (A preferred: `sqlite3_flutter_libs` + AES-GCM; fecha C-03) + 5 exit criteria, (3) runbook operacional com 7 playbooks (upgrade-request, CVE-fires, dependabot-PR, CI-fail, execute-migration, fork-proposed, security-review) + detection signals table, (4) CI guard `check-sqlcipher-eol.ts` enforçando pin exato + warning block ≥ 4 linhas + ADR/runbook presence + Dependabot ignore. Risk aguda (name-squat via caret) neutralizada; risco residual (CVE upstream) sob watch via GHSA feeds. Migração real queued para Onda 2 ou trigger event. Cross-refs: L11-06 (mesma filosofia NPM), L11-05 (DB key via PrefsSafeKey), L11-08 (futuro trigger via Flutter SDK bump), L01-30/31 (ProGuard §7 OK para versão pinada), C-03 (fecha-se na migração Option A). Verificação: `audit:sqlcipher-eol` green, `audit:verify` 348 findings, `flutter analyze` zero issues, `flutter pub deps` resolve `0.7.0+eol` exatamente.
