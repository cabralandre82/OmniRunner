---
id: L01-31
audit_ref: "1.31"
lens: 1
title: "Android — Release assina com debug key se key.properties não existir"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["mobile", "reliability", "ci"]
files:
  - omni_runner/android/app/build.gradle
  - omni_runner/android/key.properties.example
  - .github/workflows/release.yml
  - tools/test_l01_31_android_signing.sh
  - docs/runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md
correction_type: process
test_required: true
tests:
  - tools/test_l01_31_android_signing.sh
linked_issues: []
linked_prs:
  - "fcd4dc8"
owner: app-team
runbook: docs/runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed via three-layer defence:

  1. **Gradle fail-loud** (`omni_runner/android/app/build.gradle`):
     The silent `signingConfigs.debug` ternary fallback is gone.
     Configuration-time detection inspects
     `gradle.startParameter.taskNames` for any `release` task; when one
     is requested without `key.properties`, a `GradleException` aborts
     the build with a runbook reference. An opt-in flag
     `-PallowReleaseDebugSigning=true` exists for local ProGuard/R8
     testing and emits a loud warning; CI is structurally forbidden
     from setting it.

  2. **CI restores the keystore from secrets**
     (`.github/workflows/release.yml`): a new "Restore Android release
     signing (L01-31)" step decodes `ANDROID_KEYSTORE_BASE64` →
     `omni_runner/android/app/omnirunner-release.keystore` and writes
     `ANDROID_KEY_PROPERTIES` → `omni_runner/android/key.properties`,
     verifies all four required keys (`storePassword`, `keyPassword`,
     `keyAlias`, `storeFile`), `chmod 600`s both files, then runs the
     structural lint *before* invoking fastlane. An always-on cleanup
     step wipes both files at the end, even on build failure.

  3. **Structural lint** (`tools/test_l01_31_android_signing.sh`):
     six invariants over `build.gradle` + `release.yml` —
     (a) no ternary debug fallback, (b) GradleException + L01-31
     reference present, (c) startParameter.taskNames detection wired,
     (d) override flag wired, (e) release.yml does NOT enable the
     override, (f) release.yml restores both secrets. Runs in <1s as a
     dedicated CI step; sub-second negative test confirmed it catches
     a re-introduced ternary fallback.

  Operational guide:
  [`docs/runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md`](../../runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md)
  covers symptom→fix matrix for the five canonical failure modes
  (missing secret, gradle abort, Play upload-key mismatch, debug
  override warning, lint failure) plus the upload-key rotation
  procedure.
---
# [L01-31] Android — Release assina com debug key se key.properties não existir
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-17)
**Camada:** APP (Flutter/Android)
**Personas impactadas:** CI/CD, stores
## Achado
`build.gradle:89-93` (pre-fix) caía silenciosamente em `signingConfigs.debug` se `key.properties` não existisse. Dois modos de falha:

1. CI sem o secret restaurado → fastlane publica APK debug-signed no Firebase App Distribution (servido a todos os beta-testers) e AAB rejeitado pelo Play Store ("upload key mismatch").
2. Operador arrasta o APK manualmente para Play Console assumindo que está release-signed → Play *fixa* a chave debug como upload key permanente, bloqueando releases futuras (recovery via Play Support, multi-semana).

## Correção aplicada
Defesa em três camadas (ver `note` no frontmatter para detalhes completos):

1. **Build** — `build.gradle` detecta release-tasks em
   `gradle.startParameter.taskNames` e aborta via `GradleException`
   quando `key.properties` está ausente. Flag opt-in
   `-PallowReleaseDebugSigning=true` para teste local de ProGuard/R8;
   warning ruidoso é emitido toda vez que ela está ativa.

2. **CI** — `release.yml` restaura keystore + `key.properties` de dois
   secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PROPERTIES`) antes
   do fastlane, valida campos obrigatórios, `chmod 600`, e limpa
   ambos com `if: always()` na saída.

3. **Lint estrutural** — `tools/test_l01_31_android_signing.sh`
   verifica seis invariantes (sem ternário debug, throw presente,
   detecção de release-task, flag wired, CI não habilita o override,
   CI restaura ambos os secrets). Rodando como step dedicado no
   release pipeline. Negative-test confirmou que reintroduzir o
   ternário falha o lint imediatamente.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.31]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.31).
- `2026-04-17` — Fix completo (commit `fcd4dc8`): gradle fail-loud + CI restore + structural lint + runbook operacional.