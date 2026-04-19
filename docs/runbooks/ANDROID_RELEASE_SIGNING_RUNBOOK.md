# Android Release Signing & Hardening Runbook (L01-30 / L01-31)

Operational guide for the Android **release-signing safety net** (L01-31)
plus the **R8/ProGuard obfuscation+shrink** posture (L01-30) that together
make the production APK both correctly-signed and not-trivially-reverse-
engineered. Covers the gradle invariants in
`omni_runner/android/app/build.gradle`, the keep rules at
`omni_runner/android/app/proguard-rules.pro`, the secrets restored by
`.github/workflows/release.yml`, and the structural lints at
`tools/test_l01_31_android_signing.sh` and `tools/test_l01_30_android_minify.sh`.

> Audience: release on-call + CI maintainers triaging a failed
> `release` workflow run, and developers rotating the production
> upload-key. Read time ~ 6 min.

---

## Threat model — 60-second recap

The original `build.gradle` did this when `key.properties` was missing:

```groovy
signingConfig keystorePropertiesFile.exists()
    ? signingConfigs.release
    : signingConfigs.debug   // ← silent fallback, the L01-31 vuln
```

Two failure modes both ship a broken artifact without raising an alarm:

1. **CI loses (or never restored) the keystore secret.**
   Fastlane pushes a debug-signed APK to Firebase App Distribution and an
   AAB to Google Play. Play Store rejects the bundle (different upload
   key); Firebase happily serves the debug-signed APK to every beta
   tester until someone notices.
2. **Operator manually drags the APK into the Play Console** thinking it
   is release-signed. Play binds the debug key as the upload key for the
   application, locking out every future legitimate release until Play
   Support intervenes (multi-week recovery, cannot be self-served).

The fix is two-sided:

- **Build side** (`build.gradle`): refuse to assemble any release variant
  when `key.properties` is missing, with a `GradleException` that
  references this runbook.
- **CI side** (`release.yml`): restore `key.properties` and the
  `.keystore` from repository secrets *before* invoking fastlane, then
  wipe both files on cleanup.

---

## Required secrets

Both must be present on the repository (or reusable workflow caller) for
the `release` workflow to succeed.

| Secret name                | Format                                              | How to mint                                                                                       |
|----------------------------|-----------------------------------------------------|---------------------------------------------------------------------------------------------------|
| `ANDROID_KEYSTORE_BASE64`  | base64 (no line wraps) of the binary `.keystore`    | `base64 -w0 omnirunner-release.keystore \| gh secret set ANDROID_KEYSTORE_BASE64`                 |
| `ANDROID_KEY_PROPERTIES`   | full text of `key.properties` with real passwords   | `gh secret set ANDROID_KEY_PROPERTIES < omni_runner/android/key.properties`                       |

The workflow validates both secrets exist and that
`ANDROID_KEY_PROPERTIES` contains all four required keys
(`storePassword`, `keyPassword`, `keyAlias`, `storeFile`) before invoking
fastlane. A missing secret aborts with a `::error title=L01-31::` annotation.

---

## Local development

For everyday `flutter build apk --debug` work nothing changes — the
gradle guard only fires for **release** task graphs.

When you need to test ProGuard/R8 output locally without provisioning
the production keystore, use the explicit override:

```bash
flutter build apk --release -PallowReleaseDebugSigning=true
```

A loud Gradle warning is emitted on every such build:

```
[L01-31] ⚠ allowReleaseDebugSigning=true — release artifact will be DEBUG-SIGNED.
         This APK MUST NOT be uploaded to Play Store / Firebase App Distribution.
```

CI is forbidden from passing that flag; the structural lint
(`tools/test_l01_31_android_signing.sh`) rejects any `release.yml` that
references it.

---

## How the `release` workflow uses these

```text
┌───────────────────────────────────────────────────────────────────┐
│ release.yml                                                       │
│                                                                   │
│  1. Checkout + setup Java/Flutter/Ruby                            │
│  2. Restore Android release signing (L01-31)                      │
│      ─ decode ANDROID_KEYSTORE_BASE64 → app/omnirunner-release.keystore │
│      ─ write ANDROID_KEY_PROPERTIES   → android/key.properties    │
│      ─ chmod 600 both files                                       │
│      ─ assert all four required keys present                      │
│  3. Verify gradle release-signing invariants (L01-31)             │
│      ─ runs tools/test_l01_31_android_signing.sh                  │
│  4. fastlane build_apk → flutter build apk --release              │
│      ─ gradle now finds key.properties, signs with release key    │
│  5. fastlane deploy_play_store / deploy_firebase_distribution     │
│  6. Cleanup signing material (always)                             │
│      ─ rm -f android/key.properties                                │
│      ─ rm -f android/app/omnirunner-release.keystore               │
└───────────────────────────────────────────────────────────────────┘
```

The cleanup runs with `if: always()` so the secrets cannot leak even on
a build failure between steps 3 and 6.

---

## Symptom → diagnosis → fix

### Symptom A — `release.yml` fails at the *Restore Android release signing* step

```
::error title=L01-31::Missing ANDROID_KEYSTORE_BASE64 or ANDROID_KEY_PROPERTIES secret.
```

**Diagnosis.** The repository or environment is missing one (or both) of
the two L01-31 secrets, or the workflow inherited from a fork that lacks
them.

**Fix.**
1. `gh secret list -R omni-runner/omni-runner` → confirm both are absent.
2. Re-run the *How to mint* commands from the table above with the
   keystore stored in your password manager (`omnirunner-release.keystore`
   is **not** in git; it lives in 1Password under `Engineering / Android
   Release Keystore`).
3. Re-run the failed workflow.

### Symptom B — Gradle aborts with `L01-31 — Release build aborted`

Seen during `flutter build apk --release` locally **or** in CI after the
restore step ran.

**Diagnosis.**
- *Locally*: you forgot to `cp android/key.properties.example
  android/key.properties` and fill in real values.
- *In CI*: the restore step succeeded (otherwise step A above would have
  fired), but the file was wiped between steps. Inspect the workflow
  YAML for any rogue `rm -rf android/` or `git clean -fdx` between the
  restore and the build.

**Fix.**
- Locally: complete the keystore setup (see `key.properties.example`).
- CI: revert the offending step, or move it after `Cleanup signing
  material`.

### Symptom C — Play Console rejects the AAB with "upload key mismatch"

Seen post-deploy when the AAB *was* signed but with the wrong key.

**Diagnosis.** The keystore restored from
`ANDROID_KEYSTORE_BASE64` is not the upload key Play Store has on file.
Either the secret was rotated without updating Play, or the wrong
`.keystore` was base64-encoded into the secret.

**Fix.**
1. `keytool -list -v -keystore omnirunner-release.keystore -storepass …`
   on the local source-of-truth keystore — note the SHA-1.
2. In Play Console → *App integrity* → confirm the registered upload
   certificate SHA-1 matches.
3. If they diverge, follow Google's [upload-key reset
   procedure](https://support.google.com/googleplay/android-developer/answer/9842756)
   *before* re-running the workflow.

### Symptom D — Local build emits `[L01-31] ⚠ allowReleaseDebugSigning=true`

This is informational, not an error. The artifact at
`build/app/outputs/flutter-apk/app-release.apk` is **debug-signed** and
must not be uploaded anywhere user-facing. Use it only for ProGuard/R8
behaviour testing.

### Symptom E — `tools/test_l01_31_android_signing.sh` fails outside of CI

You probably edited `build.gradle` to simplify the release block. Run
the script (`bash tools/test_l01_31_android_signing.sh`) and address
each `[L01-31] FAIL` line — the messages map 1:1 to the invariants in
this runbook.

---

## R8 / ProGuard (L01-30)

### Why this section exists

Pre-fix the release APK shipped with `minifyEnabled false`. That made
class names, method names and string constants directly visible in the
dex with `apktool d` / `jadx`, including the integrity-detector
thresholds at `lib/domain/usecases/integrity_detect_*.dart` — i.e. the
exact constants a cheater needs to stay just under the speed/teleport
caps.

### What the gradle release block enables

```groovy
buildTypes {
    release {
        // … L01-31 signing block …
        minifyEnabled true                // ← R8 strips + renames
        shrinkResources true              // ← drops orphaned drawables
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                      'proguard-rules.pro'
    }
}
```

The custom `proguard-rules.pro` is split into nine sections — read the
header of that file for the full rationale. Section §9 deliberately
omits keeps for `lib.domain.usecases.integrity_detect_*` so R8 mangles
the class names and inlines threshold constants into call sites.

### Adding a keep rule when a new plugin breaks under R8

1. Build the APK — when R8 cannot resolve a reference it writes a
   suggestion file:

   ```text
   omni_runner/build/app/outputs/mapping/prodRelease/missing_rules.txt
   ```

2. Open the file. Each entry is a copy-paste-ready `-keep` directive.
   Paste it into the matching section of `proguard-rules.pro` (the
   sections are alphabetised by category).

3. Re-run `bash tools/test_l01_30_android_minify.sh` — it must still
   pass (the lint forbids only one specific target: any keep that names
   `integrity_detect`, which would re-open L01-30).

4. Build again, repeat until the missing-rules file is empty.

### Validating R8 output without the production keystore

Combine the L01-31 escape with the standard release build:

```bash
flutter build apk --release -PallowReleaseDebugSigning=true
```

The artifact is debug-signed (do **not** ship), but R8 / ProGuard /
resource shrinking all run with the production configuration, so what
you test locally matches what CI produces.

### Recovery escape-hatch

`proguard-rules.pro` carries a commented `-dontobfuscate` directive
near the top. Uncommenting it leaves shrinking + resource shrinking
on but disables renaming everywhere — useful as a temporary unblock
when a new plugin breaks under R8 in CI hours before a release.

This is the **only** sanctioned way to disable obfuscation. Reverting
`minifyEnabled` to `false` instead is forbidden by
`tools/test_l01_30_android_minify.sh` and will fail CI before
`fastlane build_apk` runs.

### Symptom F — Runtime crash *only* on release builds

Almost always a missing keep rule. Common shapes:

| Stack-trace pattern                                                         | Likely missing keep                              |
|-----------------------------------------------------------------------------|--------------------------------------------------|
| `ClassNotFoundException: com.google.firebase.…`                             | `-keep class com.google.firebase.** { *; }` (§5) |
| `NoSuchMethodError` on a `@SerializedName`-annotated model                  | The Gson `@keepclassmembers` rule in §6          |
| `UnsatisfiedLinkError: native …`                                            | `-keepclasseswithmembernames … native <methods>` (§8) |
| `MethodNotFoundException` from `flutter_blue_plus` / `mobile_scanner` etc.  | Plugin-specific rule in §3                       |
| `IncompatibleClassChangeError` deep in Sentry                               | The Sentry block in §4                           |

After adding the rule, run **both** lints to confirm no regression:

```bash
bash tools/test_l01_30_android_minify.sh
bash tools/test_l01_31_android_signing.sh
```

### Symptom G — `tools/test_l01_30_android_minify.sh` fails

Each `[L01-30] FAIL` line maps directly to one of the six invariants
listed in the script header. Common cases:

- `missing 'minifyEnabled true'` — someone removed it to "fix" a build.
  **Add the keep rule properly instead** (see "Adding a keep rule…" above).
- `keeps an integrity_detect symbol` — this one is intentional: the lint
  exists specifically to block this regression. Whatever runtime
  problem you were trying to fix has another solution.
- `missing commented '-dontobfuscate' escape-hatch` — restore the
  comment from the `proguard-rules.pro` template; the line is documented
  there for a reason.

---

## Rotating the upload key

1. Generate the new keystore with `keytool -genkey -v -keystore … -alias
   omni-runner-2 …` (use a new alias to avoid clashing with the existing
   one in the repo's secret).
2. Build a *temporary* AAB locally with the new key: copy the new
   keystore + key.properties under `omni_runner/android/`, run
   `flutter build appbundle --release`, save the resulting
   `app-release.aab`.
3. In Play Console → *App integrity* → request **upload key reset**,
   attaching the new `.aab`. Google approves within ~48h.
4. Once approved, update both repo secrets simultaneously:

   ```bash
   base64 -w0 omnirunner-release-2.keystore | gh secret set ANDROID_KEYSTORE_BASE64
   gh secret set ANDROID_KEY_PROPERTIES < omni_runner/android/key.properties
   ```

5. Trigger a no-op patch release (`workflow_dispatch` → `bump=patch`).
   The structural lint runs first, so a misconfigured rotation fails
   before any artifact is built.

---

## Related findings & files

- Audit finding (signing): [`docs/audit/findings/L01-31-android-release-assina-com-debug-key-se-key.md`](../audit/findings/L01-31-android-release-assina-com-debug-key-se-key.md)
- Audit finding (R8/ProGuard): [`docs/audit/findings/L01-30-android-falta-de-proguard-r8.md`](../audit/findings/L01-30-android-falta-de-proguard-r8.md)
- Gradle defence: [`omni_runner/android/app/build.gradle`](../../omni_runner/android/app/build.gradle)
- ProGuard keep rules: [`omni_runner/android/app/proguard-rules.pro`](../../omni_runner/android/app/proguard-rules.pro)
- CI restore + verify: [`.github/workflows/release.yml`](../../.github/workflows/release.yml)
- Structural lints: [`tools/test_l01_31_android_signing.sh`](../../tools/test_l01_31_android_signing.sh), [`tools/test_l01_30_android_minify.sh`](../../tools/test_l01_30_android_minify.sh)
- Local example: [`omni_runner/android/key.properties.example`](../../omni_runner/android/key.properties.example)
- Related: [`docs/security/CI_SECRETS_AND_OIDC.md`](../security/CI_SECRETS_AND_OIDC.md) — broader secret-handling posture (L11-09).
