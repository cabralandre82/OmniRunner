---
id: L01-30
audit_ref: "1.30"
lens: 1
title: "Android — Falta de ProGuard/R8"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["anti-cheat", "mobile", "android", "obfuscation", "release-pipeline", "reverse-engineering"]
files:
  - omni_runner/android/app/build.gradle
  - omni_runner/android/app/proguard-rules.pro
  - .github/workflows/release.yml
  - tools/test_l01_30_android_minify.sh
  - docs/runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md
  - docs/runbooks/README.md
correction_type: process
test_required: true
tests:
  - tools/test_l01_30_android_minify.sh
linked_issues: []
linked_prs:
  - "fb62982"
owner: app-team
runbook: docs/runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Defesa em três camadas, alinhada com L01-31 (mesmo build.gradle / mesmo runbook):

  1. **Gradle release block** (`omni_runner/android/app/build.gradle`):
     adiciona `minifyEnabled true`, `shrinkResources true` e
     `proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'`.
     Comentário explicando o threat-model fica colado ao bloco L01-31 — as
     duas defesas de release travel juntas.

  2. **`proguard-rules.pro`** (novo): nove seções nomeadas, alinhadas com
     o grafo de dependências real do `pubspec.yaml`:
       §1 toggles globais (`-keepattributes` para Sentry symbolication,
          `-dontobfuscate` comentado como escape-hatch);
       §2 Flutter framework + `GeneratedPluginRegistrant`;
       §3 plugins JNI/reflection (flutter_secure_storage,
          flutter_blue_plus, mobile_scanner+ML Kit, health/Health Connect,
          flutter_foreground_task, geolocator, permission_handler,
          flutter_web_auth_2, google_sign_in, sign_in_with_apple,
          image_picker, share_plus, GMS Wearable);
       §4 Sentry;
       §5 Firebase + Google Play Services + Gson;
       §6 Supabase / Realtime / GoTrue;
       §7 Drift + SQLCipher;
       §8 noise: kotlinx coroutines, OkHttp, Okio, Conscrypt,
          BouncyCastle, OpenJSSE, Kotlin Metadata, enums, Parcelable,
          native methods;
       §9 **anti-keep banner**: deliberadamente NÃO lista keeps para
          `lib.domain.usecases.integrity_detect_*`. R8 mangleia os nomes
          de classe e *inlining* das constantes de threshold para os
          call-sites, movendo o anti-cheat de "trivial em jadx" para
          "exige correlação multi-sessão". Adicionar um keep aqui
          re-abre L01-30 — o lint estrutural rejeita.

  3. **CI + structural lint**:
     - `.github/workflows/release.yml`: novo step "Verify gradle
       release-minify invariants (L01-30)" rodando logo após o lint
       L01-31 e antes do `fastlane build_apk` — falha rápido se alguém
       desativar minify/shrink ou remover o `proguard-rules.pro`.
     - `tools/test_l01_30_android_minify.sh`: seis invariantes
       grep-based (sub-second, roda sem SDK Android):
         (i) `minifyEnabled true` presente;
         (ii) sem `minifyEnabled false` explícito;
         (iii) `shrinkResources true` presente;
         (iv) `proguardFiles ... 'proguard-rules.pro'` corretamente
              encadeado;
         (v) `proguard-rules.pro` referencia `integrity_detect` e
             `L01-30` (banner §9 vivo);
         (vi) NENHUM `-keep` aponta para `integrity_detect`;
         (vii) `-dontobfuscate` está presente apenas comentado.

  Validação local: criamos a regressão (`minifyEnabled true → false`),
  o script falhou com exit-code 1 reportando `(i)` e `(ii)`. Restaurado
  e o script volta a passar (commit `fb62982`).

  Decisão deliberada de escopo:
  - **Não** refatoramos os detectores de integridade para esconder mais
    metadata (e.g. mover thresholds para `gen-l10n`-style assets
    cifrados): isso aumentaria a barra mas não muda a classe de
    vulnerabilidade — um atacante motivado lendo dump de RAM ainda
    recupera. R8+inlining é o sweet-spot de custo/benefício para High
    sem virar projeto épico.
  - **Não** habilitamos ainda `enableR8.fullMode` (R8 in "full mode") —
    requer sweep de `-dontwarn` adicionais e validação caso-a-caso de
    plugins Kotlin. Roteado para Wave 2 se telemetria de crash em
    release pedir.
  - O runbook ANDROID_RELEASE_SIGNING_RUNBOOK ganhou uma seção R8
    completa (Symptoms F + G, "Adding a keep rule when a new plugin
    breaks", "Validating R8 output without the production keystore",
    escape-hatch). README do diretório de runbooks atualizado.
---
# [L01-30] Android — Falta de ProGuard/R8
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed (`fb62982`)
**Camada:** APP (Flutter/Android)
**Personas impactadas:** Todos os usuários Android

## Achado original

`omni_runner/android/app/build.gradle:87-94` (pre-fix) não habilitava
`minifyEnabled` / `shrinkResources` / `proguardFiles` no `release`
buildType. APK release shipping fully readable: classes, strings
(constantes Supabase, env keys não-secretos), e — crucial — a lógica de
detecção de batota em `lib/domain/usecases/integrity_detect_*.dart`
ficavam expostas a `apktool d` / `jadx` em segundos.

## Risco / Impacto

- **Reverse engineering do anti-cheat pipeline**: as thresholds de
  `IntegrityDetectSpeed`, `IntegrityDetectTeleport` e
  `IntegrityDetectVehicle` seriam inferíveis em poucos minutos, e a
  validade server-side em `supabase/functions/_shared/anti_cheat.ts`
  passa a ser bypassável só ajustando a fraude para ficar 1% abaixo
  de cada threshold conhecido.
- **Exposição de constantes de integração** (URLs Supabase, IDs
  públicos de Sentry, etc.) facilita reconnaissance.
- **Tamanho de APK**: sem `shrinkResources`, drawables/strings
  órfãos viajavam no bundle Play Store (~6-10% de bloat).

## Correção aplicada (`fb62982`)

```groovy
buildTypes {
    release {
        // … bloco L01-31 (signing) …
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                      'proguard-rules.pro'
    }
}
```

`omni_runner/android/app/proguard-rules.pro` (novo) carrega keeps
seccionados para Flutter, Sentry, Firebase+GMS, Supabase, Drift+
SQLCipher e cada plugin JNI/reflexivo do `pubspec.yaml`. A seção §9
deliberadamente NÃO lista keeps para `lib.domain.usecases.integrity_
detect_*` — esse é o ponto inteiro do fix.

`tools/test_l01_30_android_minify.sh` é o lint estrutural que protege
o build.gradle + proguard-rules.pro contra regressão (seis invariantes,
sub-second, sem SDK). Rodando em CI logo após o lint L01-31, em
`.github/workflows/release.yml`, antes do `fastlane build_apk`.

Para troubleshooting (adicionar keeps quando R8 reclamar de um plugin
novo, validar sem keystore, escape-hatch `-dontobfuscate`), ver a nova
seção R8 do runbook
[`docs/runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md`](../../runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.30]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.30).
- `2026-04-17` — Corrigido em `fb62982` (gradle minify+shrink+proguardFiles, proguard-rules.pro, CI lint, runbook).
