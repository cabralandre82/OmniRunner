# Challenge Invite Viral-Loop Runbook

> **Finding:** [L22-08] Desafio de grupo (viralização entre amigos)
> **CI guard:** `npm run audit:challenge-invite-deep-link`
> **Source of truth:**
>
> - App side: `omni_runner/lib/domain/value_objects/challenge_invite_link.dart`
>   (canonical host constant), `omni_runner/lib/domain/services/challenge_invite_message_builder.dart`
>   (locale catalogue), `omni_runner/lib/domain/usecases/gamification/share_challenge_invite.dart`
>   (use-case), `omni_runner/lib/presentation/screens/challenge_invite_screen.dart`
>   ("Convidar via WhatsApp" UI).
> - Portal side: `portal/public/.well-known/assetlinks.json` (Android App
>   Links), `portal/public/.well-known/apple-app-site-association`
>   (iOS Universal Links).
> - Platform config: `omni_runner/android/app/src/main/AndroidManifest.xml`
>   (`autoVerify="true"`), `omni_runner/ios/Runner/Runner.entitlements`
>   (`applinks:omnirunner.app`).

## Why this runbook exists

L22-08 flagged that `challenge-create` already shipped but the UX for
inviting friends via WhatsApp was weak: share text was hard-coded in
Portuguese, the deep link was built inline as a raw string, and the
fallback for "WhatsApp not installed" was undefined. That turns what
should be the app's strongest viral loop — amateur runners inviting
friends to a private bet — into a dead end.

The fix routes every share surface through a single domain pipeline
(canonical link value object → locale-aware message builder → share
intent use-case → platform gateway) and wires a CI guard that fails
the build if the canonical host drifts out of sync with the
`.well-known/*` proofs served by the portal.

## Invariants (enforced by CI)

`npm run audit:challenge-invite-deep-link` fails closed if any of
these drift:

| # | Invariant                                                                                          | Why it matters                                                                                                                            |
| - | -------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | `ChallengeInviteLink.canonicalHost == 'omnirunner.app'`                                            | Released app versions parse the hard-coded host. Rotating it silently breaks every install older than the rotation.                        |
| 2 | `ChallengeInviteLink.pathSegment == 'challenge'`                                                   | Must match `paths: ["/challenge/*"]` in `apple-app-site-association` and `DeepLinkHandler._parse`.                                         |
| 3 | `portal/public/.well-known/assetlinks.json` exists, has a `package_name`, and a non-empty SHA-256. | Missing or empty fingerprints disables Android App Links auto-verification — recipients would land on the browser instead of the app.    |
| 4 | `portal/public/.well-known/apple-app-site-association` exists and lists `/challenge/*`             | iOS Universal Links are validated against this file at install time; without it, tapping a challenge link opens Safari, never the app.   |
| 5 | `ChallengeInviteMessageBuilder` references `AudioCoachLocale.{ptBR,en,es}` and exposes `buildWhatsAppUrl` | A rebase that drops a locale or the WhatsApp helper would silently revert the viral loop to the pre-L22-08 monolingual state.       |
| 6 | This runbook references `check-challenge-invite-deep-link` and the `L22-08` id                     | Mutual linkage guarantees future maintainers hit this page when the guard fails.                                                          |

## How the viral loop works end-to-end

1. User creates a challenge → `ChallengeInviteScreen` opens.
2. "Convidar via WhatsApp" button triggers `ShareChallengeInvite(
   challengeId, channel: whatsapp)` → returns a `ChallengeShareIntentEntity`
   whose `platformLaunchUrl` is `https://wa.me/?text=<encoded body>`.
3. `url_launcher.launchUrl(...)` opens WhatsApp's contact picker with the
   message pre-filled. Body contains the canonical deep link.
4. The recipient taps the link. Android and iOS resolve it against
   `.well-known/*` proofs:
   * **Android** — App Links (`autoVerify="true"`) — opens the app
     directly, no browser disambiguator.
   * **iOS** — Universal Links (`applinks:omnirunner.app`) — opens the
     app directly.
5. Inside the app, `DeepLinkHandler._parse(uri)` emits `ChallengeAction(id)`
   which the router navigates to the challenge details screen.
6. If the app is not installed, the link lands on the portal's web
   fallback page (future work — see "Web fallback" below) which deep-
   links to the App Store / Play Store.

## How to …

### Add a new locale

1. Add the variant to `AudioCoachLocale` (shared with the audio-coach
   subsystem) and update `AudioCoachLocale.fromTag`.
2. Add a branch per channel (`_whatsapp`, `_native`, `_fallbackTitle`)
   in `ChallengeInviteMessageBuilder`.
3. Append the locale to `ChallengeInviteMessageBuilder.supportedLocales`
   — the CI guard iterates this list.
4. Extend `challenge_invite_message_builder_test.dart` with
   locale-specific openers and a "contains the URL" assertion.

### Rotate the Android signing cert

1. Produce the new cert's SHA-256:
   ```bash
   keytool -list -v -keystore <release.keystore> -alias <alias> \
     | grep SHA256 | awk '{print $NF}'
   ```
2. **Append** the new fingerprint to the existing array in
   `portal/public/.well-known/assetlinks.json`. **Do not remove the old
   one** until every installed version signed with the old cert is
   below your force-upgrade floor — removing too early breaks
   Verify App Links for users on older app versions.
3. Deploy the portal.
4. Run `npm run audit:challenge-invite-deep-link` locally to confirm.

### Change the canonical host

Do not do this lightly. Every released app version is hard-coded to
`omnirunner.app`. Procedure:

1. Publish the new host with the `.well-known/*` proofs mirrored.
2. Keep the old host live, serving an HTTP 302 to the new one on the
   `/challenge/{id}` path.
3. Ship a new app release with the updated `ChallengeInviteLink.canonicalHost`
   **and** `acceptedHosts` extended with both hosts.
4. Force-upgrade users off the old app version.
5. Only then remove the old host.

### Add a new share channel

1. Extend `ChallengeShareChannel` enum.
2. Add a `case` branch in `ChallengeInviteMessageBuilder.build`.
3. If the channel has a platform-specific URL (like `wa.me/?text=` for
   WhatsApp), add a `buildXyzUrl` helper and populate
   `ChallengeShareIntentEntity.platformLaunchUrl` in
   `ShareChallengeInvite`.
4. Add a button in `ChallengeInviteScreen` that routes through a
   channel-specific dispatcher (`_shareViaXyz`).
5. Add a unit test asserting the generated payload shape.

## Operational playbooks

### "Recipients open the browser instead of the app" (Android)

Symptom: tapping a `https://omnirunner.app/challenge/...` link opens a
browser tab on Android instead of launching the app.

Diagnosis:

1. `adb shell pm get-app-links <package>` — look for `Verified:` state
   on `omnirunner.app`. If it shows `ask` or `not approved`, App Links
   auto-verification failed.
2. On the device: `adb shell dumpsys package <package> | grep android:autoVerify`.
3. On the portal: `curl -fsSL https://omnirunner.app/.well-known/assetlinks.json`.
   Must return `Content-Type: application/json` and the SHA-256 must
   match the APK's release signing cert.
4. Run `npm run audit:challenge-invite-deep-link` locally — if it
   passes but verification still fails on device, the portal's served
   fingerprint likely diverged from the release signing cert.

Fix: see "Rotate the Android signing cert" above. If the mismatch
predates a release, hotfix the portal `assetlinks.json` with both
fingerprints and force-upgrade users.

### "Recipients open Safari instead of the app" (iOS)

Symptom: tapping the link opens Safari with the portal page rather than
launching the app.

Diagnosis:

1. `curl -fsSL https://omnirunner.app/.well-known/apple-app-site-association`
   — must return `Content-Type: application/json` (no `.json` in the
   path, no redirects, HTTPS only).
2. `/challenge/*` must be in the `paths` array. The CI guard checks
   this but cache propagation is Apple-side and can lag ~24 h.
3. On device: `Settings → Safari → Advanced → Website Data` — the
   AASA file is cached per device after install. If only some devices
   fail, force-delete the app and reinstall.

Fix: push a corrected AASA through the portal and wait for Apple to
re-fetch, which happens when the OS detects a new app install.

### "WhatsApp button does nothing"

Symptom: tapping "Convidar via WhatsApp" produces no visible effect.

Diagnosis:

1. Read app logs for the tag `ChallengeInvite` — `WhatsApp launch failed`
   indicates `url_launcher` rejected the URL.
2. Check `flutter pub deps | grep url_launcher` — plugin must be
   linked; on Android, `queries` block in `AndroidManifest.xml` must
   declare `whatsapp://` for Android 11+.

Fix: the UI already falls back to the native share sheet when
`url_launcher` returns `false`; ship a user-visible snackbar if the
fallback silently fires too often.

### "Shared link is in the wrong language"

Symptom: Brazilian user shares, recipient abroad receives Portuguese
copy and is confused.

This is intentional: the *sender's* locale drives the copy so the
message sounds natural to them. Senders rarely know the recipient's
preferred language, and WhatsApp's built-in translate handles the
inverse case. If a product decision ever wants recipient-side i18n,
it must happen on the web fallback page, not in the share body.

### "Want to add a custom image card to the share"

Out of scope for L22-08 (the finding explicitly marked the image card
as "generates image card" but the MVP ships text-only share to keep
the loop testable without a render pipeline). Follow-up work is
tracked alongside the reach-goal items in Batch I; see
`docs/audit/WAVE1_QUEUE.md`.

## Rollback

Rolling back L22-08 only touches the app layer:

1. Revert the app commit `fix(mobile/social): viral WhatsApp challenge invite`.
2. Leave the portal `.well-known/*` files in place — they predate the
   finding and are required by other features (`/invite/*`,
   `/refer/*`).
3. The CI guard `audit:challenge-invite-deep-link` only fires on files
   introduced by the fix; reverting the fix drops the guard too.

## Cross-references

- [`docs/UNIVERSAL_LINKS_SETUP.md`](../UNIVERSAL_LINKS_SETUP.md) —
  Platform-side Android App Links + iOS Universal Links setup.
- [`docs/audit/findings/L22-08-desafio-de-grupo-viralizacao-entre-amigos.md`](../audit/findings/L22-08-desafio-de-grupo-viralizacao-entre-amigos.md).
- [`docs/audit/findings/L07-04-flutter-deep-link-strava-oauth-sem-state-validation.md`](../audit/findings/L07-04-flutter-deep-link-strava-oauth-sem-state-validation.md)
  — unrelated but relevant deep-link security context.
- [`docs/runbooks/AUDIO_CUES_RUNBOOK.md`](./AUDIO_CUES_RUNBOOK.md) —
  reuses the same `AudioCoachLocale` value object for sender-side
  locale selection.
