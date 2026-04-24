# Mobile Offline Session Backup

**Status:** Specified (2026-04-21), implementation in Wave 3.
**Owner:** mobile + reliability
**Related:** L05-19, L05-13 / L08-04 (sessions coherence),
L08-12 (offline analytics queue), `omni_runner/lib/data/local/`.

## Question being answered

> "An athlete runs 25 km offline (Drift queues the session
> rows), then loses or replaces the phone before the next time
> the app reaches the server. Today the run is gone — Drift is
> a local SQLite file, not backed up by iOS/Android by default
> for app data. What's our backup strategy?"

## Decision

**Three layers, ordered by user friction.**

### Layer 1 — Eager push (today, baseline)

The mobile app already pushes finalised sessions to Supabase
the moment connectivity returns. This is the default code path
in `omni_runner/lib/sync/session_sync_service.dart`. For the
common case (athlete pauses at a café with WiFi after a run)
this is sufficient.

### Layer 2 — Daily pending-sessions email digest (Wave-3)

When a session lives in the Drift `sessions` table for **> 24 h**
without a successful sync **and** the app has email-on-file,
the next time the app opens (network or not) it queues a job
that emails the user a copy of the raw session payload (CSV +
GPX) **encrypted with the user's account password-derived key**
so we don't need server-side keys to deliver it.

The email arrives whether or not the device ever syncs again.
If the user gets a new phone, restoring is as simple as
forwarding the email to themselves and tapping "Import". This
mirrors the pattern from Strava's "your last run is at risk"
email.

Trigger conditions:

- `pending_session.created_at < now() - INTERVAL '24 h'`
- `profile.email IS NOT NULL`
- `device.last_sync_attempt_status != 'success'` for the
  pending row.
- Email-quota gate: at most 1 pending-sessions email per user
  per 24 h, regardless of session count.

### Layer 3 — Manual export from settings (Wave-3)

A new screen `Settings → Pending Runs` lists every Drift
session that hasn't synced. For each row:

- "Try sync now" → fires `session_sync_service.sync(id)` once,
  surfaces the failure reason if any.
- "Send to my email" → emits the same encrypted payload as
  Layer 2 on demand.
- "Export to file" → writes the GPX + CSV to the OS-native
  Files app. Useful when the athlete wants to import to
  Strava / Garmin Connect manually.
- "Delete" → hard-removes the local row. Confirm dialog
  warns that the data is unrecoverable.

## Why we don't use FlutterSecureStorage as a backup

The original finding suggested mirroring sessions to
`flutter_secure_storage`. We rejected this for three reasons:

1. **iOS / Android secure storage is also wiped on factory
   reset / phone change** — same failure mode as Drift. It
   buys nothing for the "lost phone" scenario.
2. **Secure storage is for tokens, not bulk data.** A 25 km
   run has ~ 1500 GPS points (~ 200 KB GPX). 50 unsynced runs
   would push close to the 1 MB per-key effective limit on
   Android Keystore.
3. **It would create a confusing 'two sources of truth'
   problem** with Drift — sync logic would have to reconcile
   both stores on every flush.

## Why not iCloud / Google Drive auto-backup

The Flutter app does not opt into iOS automatic-backup
(`UIFileSharingEnabled`) or Android `allowBackup` for the
data directory by design — those backup channels are
unencrypted at rest in many configurations and would put GPS
trajectories on third-party storage without explicit user
consent. We could revisit this with a per-user opt-in toggle,
but that is a separate spec.

## Implementation outline

```dart
// lib/sync/pending_sessions_digest_worker.dart
class PendingSessionsDigestWorker {
  final SessionLocalRepo _repo;
  final EncryptedExportService _export;
  final EmailService _email;

  Future<void> run() async {
    final stale = await _repo.findUnsyncedOlderThan(
      const Duration(hours: 24),
    );
    if (stale.isEmpty) return;

    final email = await _profileRepo.email();
    if (email == null) return;

    if (await _quota.exceededFor(email, const Duration(hours: 24))) {
      return;
    }

    final payload = await _export.encryptedZip(
      sessions: stale,
      passwordKey: await _accountKey.derive(),
    );
    await _email.send(
      to: email,
      template: 'pending_sessions_digest',
      attachments: [payload],
    );

    await _quota.markSent(email);
    await _audit.log(
      eventName: 'mobile.pending_sessions.digest_sent',
      properties: {'session_count': stale.length},
    );
  }
}
```

The worker piggybacks on the L08-12 `WorkManager` /
`BGProcessingTask` infrastructure for offline analytics
(periodic, network-aware).

## See also

- `docs/runbooks/MOBILE_OFFLINE_ANALYTICS.md` (L08-12) —
  sibling worker pattern.
- `docs/audit/findings/L08-04-*` — sessions coherence
  invariants (L05-13 / L08-04 enforce that any session we
  ship server-side passes the GPS / moving-time check).
