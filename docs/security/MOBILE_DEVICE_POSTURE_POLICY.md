# Mobile Device Posture (DPI) Policy

**Status:** Ratified (2026-04-21), implementation in Wave 3.
**Owner:** mobile + security
**Related:** L10-13, L21-10 (anti-cheat), L01-15 (JWT
revocation), `omni_runner/lib/core/`.

## Question being answered

> "The Flutter app does not detect root/jailbreak, attached
> debugger, Frida hooks, emulator-in-prod, or APK integrity
> tampering. A jailbroken phone with a Frida hook can spoof
> GPS, replay sessions, or scrape OmniCoins. What's our
> posture model?"

## Decision

**Two-tier posture: SOFT for general usage, HARD for
financial actions.** No-cost detection for v1; Play Integrity
+ App Attest in v2.

### Posture signals (v1, free)

Implemented via `flutter_jailbreak_detection` +
`device_info_plus`. Composed at app start and re-evaluated on
every financial action:

```dart
class DevicePosture {
  final bool isRooted;
  final bool isOnEmulator;
  final bool isDebuggerAttached;
  final bool isApkSigningValid;   // Android only
  final bool isIosBundleIdValid;   // iOS only

  PostureLevel get level {
    if (isRooted || (!isApkSigningValid && Platform.isAndroid)) {
      return PostureLevel.compromised;
    }
    if (isOnEmulator || isDebuggerAttached) {
      return PostureLevel.suspicious;
    }
    return PostureLevel.healthy;
  }
}

enum PostureLevel { healthy, suspicious, compromised }
```

### Posture signals (v2, billable)

When user count justifies the cost:

- **Android: Play Integrity API** (`com.google.android.play:integrity`).
  Call quota is free up to 10k req/day; we batch one call per
  user per day on first financial action.
- **iOS: App Attest** (`DeviceCheck.framework`). Free, but
  requires a per-app Apple key and a server-side verifier.

The signal from these APIs supersedes the `isApkSigningValid`
heuristic above and is much harder to spoof.

### Enforcement matrix

| Action surface             | `healthy` | `suspicious`                | `compromised` |
|----------------------------|-----------|-----------------------------|---------------|
| Login / browse content     | allow     | allow                       | allow + warn  |
| Start a session (record GPS) | allow     | allow                       | allow + warn  |
| Submit / sync session      | allow     | allow + flag for anti-cheat (L21-10) | allow + heavy flag |
| Distribute coins (coach)   | allow     | allow + audit_logs flag     | **block** + 451 to API |
| Claim championship reward  | allow     | allow + audit_logs flag     | **block** |
| Withdraw OmniCoins         | allow     | **2FA challenge**           | **block** |
| Swap accept                | allow     | allow + audit_logs flag     | **block** |

"Allow + warn" = a one-time non-dismissable banner explaining
that some financial features are restricted on this device.
"Block" = the action button is disabled and tapping it shows
a modal "Por segurança, esta operação não está disponível
neste dispositivo. Acesse pelo portal web para concluir."

### Server-side correlation

Mobile sends `X-Device-Posture: {level, signals_hash}` on
every request. The portal stores it in `audit_logs.metadata`
for the action and uses it to:

- Route a `compromised`-tier withdraw attempt to manual review
  even if the client-side block fails.
- Power a daily report `posture-suspicious-actors` that lists
  user_ids with > 3 `suspicious`/`compromised` actions in the
  last 7 days for the security team to triage.

Server NEVER blocks based purely on the client-asserted
signal — it is advisory + auditable. The hard server-side
controls (rate limits, daily caps, withdraw 2FA) keep working
regardless of what the client claims.

## Why no JWT revocation tied to posture

Tempting to "kill the session if posture is compromised", but:

1. The compromise might be benign (developer phone, QA
   device).
2. The attacker can't control the JWT issuance — that goes
   through the backend. A `compromised` device can use the
   app, but cannot drain money because withdraw is blocked
   server-side.
3. Killing the session would require posture telemetry
   server-side, which means a posture-spoofing client could
   then trigger arbitrary mass-logout. Bad failure mode.

## Implementation status

- **Spec:** ratified (this doc).
- **v1 detection (`flutter_jailbreak_detection`):** Wave-3,
  ~ 1 day.
- **Action enforcement matrix wired into financial Bloc
  layer:** Wave-3, ~ 3 days.
- **Server-side `audit_logs` correlation + daily report:**
  Wave-3, ~ 1 day.
- **v2 (Play Integrity + App Attest):** Year-2 or when
  withdraw fraud > BRL 5k/month.
