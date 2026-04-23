---
id: L11-08
audit_ref: "11.8"
lens: 11
title: "Flutter sdk: '>=3.8.0 <4.0.0' — permite 3.9, 3.10…"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "supply-chain", "fixed"]
files:
  - omni_runner/pubspec.yaml
  - .tool-versions
  - .github/workflows/release.yml
  - .github/workflows/flutter.yml
  - .github/workflows/security.yml
  - omni_runner/analysis_options.yaml
  - tools/audit/check-flutter-sdk-pinning.ts
  - docs/runbooks/FLUTTER_SDK_PINNING_RUNBOOK.md
  - package.json
correction_type: process
test_required: true
tests:
  - tools/audit/check-flutter-sdk-pinning.ts
linked_issues: []
linked_prs:
  - "local/924416b — fix(mobile/sdk): pin Dart/Flutter to single-minor + CI guard (L11-08)"
owner: mobile
runbook: docs/runbooks/FLUTTER_SDK_PINNING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Single-minor SDK pin + cross-workflow alignment + CI guard. Pre-fix
  state: pubspec `sdk: '>=3.8.0 <4.0.0'` allowed Dart 3.9/3.10/3.11
  to all resolve against the same pubspec (language-spec drift
  possible); release.yml was on flutter-version 3.22.x while
  flutter.yml + security.yml were on 3.41.x — release APKs were
  built with a different toolchain than CI tested with. Fix in three
  layers:
    1. Narrow pubspec to `sdk: '>=3.11.0 <3.12.0'` and
       `flutter: '>=3.41.0 <3.42.0'` (single-minor window matching
       the CI flutter-version). Keeps patch updates floating, rejects
       minor drift.
    2. Repo-level `.tool-versions` for asdf/fvm: flutter 3.41.1 /
       dart 3.11.0 / nodejs 20. Local dev gets exactly the CI
       toolchain with `asdf install`.
    3. CI guard `check-flutter-sdk-pinning.ts` (`npm run
       audit:flutter-sdk-pinning`) enforcing: pubspec single-minor
       ranges on BOTH sdk + flutter; warning block >=4 lines
       mentioning L11-08; .tool-versions dart/flutter minor matches
       pubspec; every `flutter-version:` line across
       `.github/workflows/*.yml` matches the pubspec minor;
       runbook exists + cross-links the guard.

  Side-effect cleanup: narrower pubspec range surfaced a
  deprecated lint (`avoid_null_checks_in_equality_operators`,
  deprecated in Dart 3.11) that had been hidden by the wider
  compat mode; removed from analysis_options.yaml.

  Smoke-tested: widened pubspec → sdk_range_too_wide flagged;
  planted 3.99.x in flutter.yml → workflow_flutter_drift on all
  3 jobs; both revert clean.

  Cross-refs: L11-06 (same pinning philosophy NPM side), L11-07
  (Flutter major bump is an explicit exit criterion in ADR-009),
  L11-05 (FlutterSecureStorage sensitive to language-spec
  regressions), L01-30/31 (ProGuard rules versioned alongside
  Flutter — single-minor keeps them stable).
---
# [L11-08] Flutter sdk: '>=3.8.0 <4.0.0' — permite 3.9, 3.10…
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)

**Camada:** Mobile / Supply chain
**Personas impactadas:** Mobile engineering, Release engineering, DevOps on-call.

## Achado

`omni_runner/pubspec.yaml` declarava `environment.sdk: '>=3.8.0 <4.0.0'` — faixa ampla que permite qualquer Dart 3.x a resolver o pubspec. Dart tem histórico de breaking changes em minor (null-safety rollout, sound-mode migration, extension-type semantics). Além disso, `release.yml` usava `flutter-version: '3.22.x'` enquanto `flutter.yml` + `security.yml` estavam em `3.41.x` — silent toolchain divergence entre CI test e release build.

## Risco / Impacto

- Dev A roda Flutter 3.41 (Dart 3.11), dev B roda Flutter 3.42 (Dart 3.12), CI roda Flutter 3.41. Type-inference e lint pass diferentes → bugs que passam em uma máquina e quebram em outra.
- Release APK compilado com Flutter 3.22 enquanto CI testa com 3.41 → release-only crashes, não cobertos por CI. Esse é um supply-chain leak real.
- `dart pub add` reintroduz caret nas deps e, sem guard, minor bumps escorregam.

## Correção aplicada (2026-04-21)

Postura: single-minor pin + cross-workflow alignment + CI guard.

### Defesa em 3 camadas

1. **Pin narrow em pubspec** — `omni_runner/pubspec.yaml`:
   ```yaml
   environment:
     sdk: '>=3.11.0 <3.12.0'
     flutter: '>=3.41.0 <3.42.0'
   ```
   Precedido de bloco de 10 linhas de comentário citando L11-08, CI workflows e runbook. Janela single-minor: upper bound é exatamente `lower.minor + 1` no mesmo major, patch `.0` — aceita patches (`3.11.1`, `3.11.2`, …), rejeita minor drift.
2. **`.tool-versions` em repo root** para asdf / fvm / pluggable toolchain managers: `flutter 3.41.1` / `dart 3.11.0` / `nodejs 20`. `cd <repo> && asdf install` dá ao dev exatamente a toolchain do CI.
3. **Alinhamento cross-workflow**: `.github/workflows/release.yml` mudado de `flutter-version: '3.22.x'` para `'3.41.x'` (matching `flutter.yml` + `security.yml`). Warning block cita L11-08 e aponta para o runbook.
4. **CI guard** `tools/audit/check-flutter-sdk-pinning.ts` (`npm run audit:flutter-sdk-pinning`) com 5 sub-checks:
   - **sdk_range / flutter_range** — valida janela single-minor em ambos `environment.sdk` e `environment.flutter`; rejeita ranges como `>=3.8.0 <4.0.0` (cross-major), `>=3.8.0 <3.13.0` (5-minor), one-sided ranges, missing bounds.
   - **warning_block** — ≥4 linhas `#` contiguous acima de `environment:` citando L11-08.
   - **tool_versions_drift** — `.tool-versions` contém `flutter <ver>` + `dart <ver>` com minor matching pubspec.
   - **workflow_flutter_drift** — scan de `.github/workflows/*.yml`; toda linha `flutter-version:` deve matchar a minor do pubspec. Zero exceções.
   - **runbook** — existe + cross-links `check-flutter-sdk-pinning`.

### Side-effect cleanup

A faixa narrower expõs um lint deprecado (`avoid_null_checks_in_equality_operators`, deprecated em Dart 3.11) que estava hidden pela faixa wider. Removido de `omni_runner/analysis_options.yaml`.

### Verificação

- `npm run audit:flutter-sdk-pinning` → ✅ clean.
- `npm run audit:verify` → 348 findings validados.
- `flutter analyze` → no issues found.
- `flutter test` → 2128/2128 passed.
- `flutter pub deps` → resolve com Flutter 3.41.1 + Dart 3.11.0.
- Smoke-tests: (i) widened sdk range → `sdk_range_too_wide` flagged; (ii) planted `3.99.x` em `flutter.yml` → `workflow_flutter_drift` em todas as 3 jobs; ambos revertem clean.

## Referência narrativa

Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.8]`.

## Histórico

- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.8).
- `2026-04-21` — ✅ **Fixed** (commit `924416b`). Single-minor SDK pin + cross-workflow alignment + CI guard em 4 camadas: (1) pubspec narrow `sdk: '>=3.11.0 <3.12.0'` + `flutter: '>=3.41.0 <3.42.0'` com 10-line warning block; (2) `.tool-versions` em repo root (flutter 3.41.1 / dart 3.11.0 / nodejs 20) para asdf/fvm/pluggable managers; (3) alinhamento cross-workflow — `release.yml` 3.22.x → 3.41.x (corrige divergence real: release APK ficava com toolchain diferente do CI test); (4) CI guard `check-flutter-sdk-pinning.ts` enforçando 5 invariants (single-minor em sdk+flutter, warning block, .tool-versions drift, workflow flutter drift, runbook presence). Side-effect: faixa narrow expôs lint deprecado `avoid_null_checks_in_equality_operators` — removido. Smoke-tested: widened pubspec → `sdk_range_too_wide`; planted 3.99.x em workflow → `workflow_flutter_drift` em 3 jobs; ambos revertem clean. Verificação: audit:flutter-sdk-pinning green, audit:verify 348 findings, flutter analyze zero issues, flutter test 2128/2128 passed. Cross-refs: L11-06 (mesma filosofia NPM), L11-07 (Flutter major = exit criterion ADR-009), L11-05 (FlutterSecureStorage sensitive a language-spec), L01-30/31 (ProGuard stable via single-minor), L11-03/09 (workflows shared). Zero regressão.
