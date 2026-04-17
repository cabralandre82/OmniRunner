---
id: L01-30
audit_ref: "1.30"
lens: 1
title: "Android — Falta de ProGuard/R8"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["anti-cheat", "mobile", "edge-function", "observability", "reliability"]
files:
  - supabase/functions/_shared/anti_cheat.ts
  - omni_runner/android/app/build.gradle
correction_type: process
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
# [L01-30] Android — Falta de ProGuard/R8
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** APP (Flutter/Android)
**Personas impactadas:** Todos os usuários Android
## Achado
`omni_runner/android/app/build.gradle:87-94` não habilita `minifyEnabled`/`shrinkResources`/`proguardFiles` no release buildType. APK release é fully readable. Classes, strings (incluindo provavelmente constantes de URL Supabase, keys de env não-secretos, lógica anti-cheat) expostas a engenharia reversa trivial.
## Risco / Impacto

Reverse engineering do anti-cheat pipeline (`supabase/functions/_shared/anti_cheat.ts` — as thresholds seriam inferíveis por comparação com requests). Exposição de constantes de integração.

## Correção proposta

```groovy
  buildTypes {
    release {
      signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
      minifyEnabled true
      shrinkResources true
      proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
  }
  ```
  Criar `proguard-rules.pro` com keeps para Flutter, Firebase, Sentry, Supabase, health plugin.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.30]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.30).