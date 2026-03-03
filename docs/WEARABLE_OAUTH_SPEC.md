# Wearable OAuth Specification

Status: **Specified — ready for implementation**

## Overview

This document specifies the OAuth integration flows for wearable providers
(Garmin Connect, Apple HealthKit) so that OmniRunner can ingest activity data
automatically from athletes' devices.

---

## 1. Garmin Connect API

### Authentication: OAuth 1.0a

Garmin uses a 3-legged OAuth 1.0a flow (not OAuth 2.0).

| Step | Endpoint / Action |
|------|-------------------|
| 1. Request token | `POST https://connectapi.garmin.com/oauth-service/oauth/request_token` |
| 2. User authorization | Redirect user to `https://connect.garmin.com/oauthConfirm?oauth_token=<token>` |
| 3. Access token | `POST https://connectapi.garmin.com/oauth-service/oauth/access_token` |

### Required credentials

- Consumer Key (issued by Garmin developer portal)
- Consumer Secret
- Callback URL: `https://<project-ref>.supabase.co/functions/v1/garmin-callback`

### Webhook setup

Garmin pushes activity summaries via webhooks registered in the developer portal.

| Webhook | Payload |
|---------|---------|
| Activity summary | Activity ID, distance, duration, calories, timestamps |
| Daily summary | Steps, heart-rate zones, stress |

Webhook URL: `https://<project-ref>.supabase.co/functions/v1/garmin-webhook`

### Data mapping

| Garmin field | OmniRunner field |
|--------------|------------------|
| `activityId` | `external_activity_id` |
| `distanceInMeters` | `distance_meters` |
| `durationInSeconds` | `duration_seconds` |
| `startTimeInSeconds` + `startTimeOffsetInSeconds` | `start_time_ms` |
| `averageHeartRateInBeatsPerMinute` | `avg_hr_bpm` |
| `averagePaceInMinutesPerKilometer` | `avg_pace_min_km` |

### Token storage

Store in `wearable_tokens` table:

```sql
CREATE TABLE wearable_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users NOT NULL,
  provider TEXT NOT NULL CHECK (provider IN ('garmin', 'apple', 'strava')),
  access_token TEXT NOT NULL,
  token_secret TEXT,          -- OAuth 1.0a only (Garmin)
  refresh_token TEXT,         -- OAuth 2.0 only
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, provider)
);

ALTER TABLE wearable_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own tokens"
  ON wearable_tokens FOR ALL
  USING (auth.uid() = user_id);
```

---

## 2. Apple HealthKit

### Authentication: On-device only

Apple HealthKit does **not** have a server-side OAuth flow. Authorization
happens entirely on the iOS device via the HealthKit framework.

| Step | Action |
|------|--------|
| 1. Request authorization | `HKHealthStore.requestAuthorization(toShare:read:)` |
| 2. Query workouts | `HKSampleQuery` / `HKAnchoredObjectQuery` for `HKWorkoutType` |
| 3. Sync to backend | App POSTs workout data to edge function |

### Required HealthKit data types

- `HKQuantityType.distanceWalkingRunning`
- `HKQuantityType.heartRate`
- `HKWorkoutType.workoutType()`
- `HKQuantityType.activeEnergyBurned`

### Sync strategy

1. Use `HKAnchoredObjectQuery` with a persisted anchor for incremental sync
2. On each anchor update, batch new workouts and POST to
   `https://<project-ref>.supabase.co/functions/v1/healthkit-sync`
3. Deduplicate via `(user_id, provider, external_activity_id)` unique constraint

### Privacy

- HealthKit data never leaves the device without explicit user consent
- The app only reads running/walking workout types
- No background upload without user-visible indication (Apple guideline)

---

## 3. Token refresh strategy

### Garmin (OAuth 1.0a)

- Garmin OAuth 1.0a tokens do **not** expire
- Tokens are revoked only if the user deauthorizes in Garmin Connect settings
- On 401 from Garmin API: mark token as revoked, prompt user to re-link

### Strava (OAuth 2.0 — already integrated)

- Access tokens expire after 6 hours
- Use `refresh_token` to obtain new access token before expiry
- Store `expires_at` and refresh proactively when `expires_at - now < 15min`

### Apple HealthKit

- No server tokens — authorization is session-based on device
- If authorization is revoked, `HKHealthStore.authorizationStatus` returns
  `.sharingDenied` and the app prompts re-authorization

---

## 4. Error handling flows

### Connection errors

| Scenario | Handling |
|----------|----------|
| OAuth callback fails | Show error screen, allow retry, log to Sentry |
| Token revoked by user | Mark `wearable_tokens.revoked_at`, show re-link prompt |
| Webhook payload invalid | Return 400, log structured error, skip processing |
| Duplicate activity | Upsert on `(user_id, provider, external_activity_id)`, return 200 |
| Rate limited by provider | Exponential backoff, retry up to 3 times |
| Network timeout on sync | Client retries with idempotency key |

### Data validation

- Reject activities with `distance_meters <= 0` or `duration_seconds <= 0`
- Reject activities older than 90 days (configurable)
- Reject activities with start_time in the future

---

## 5. Implementation effort estimate

| Task | Estimated hours |
|------|----------------|
| Garmin OAuth 1.0a flow (edge function + callback) | 4-6h |
| Garmin webhook receiver + data mapping | 2-3h |
| Apple HealthKit Flutter plugin integration | 3-4h |
| Apple HealthKit sync edge function | 2h |
| Token storage table + RLS | 1h |
| Re-link / revocation UI in app | 2h |
| Testing & edge cases | 3-4h |
| **Total per provider** | **4-8h** |
| **Total (both providers)** | **~20h** |

---

## 6. Prerequisites

- Garmin developer account with API access approved
- Apple Developer account with HealthKit entitlement
- `wearable_tokens` table deployed (see schema above)
- Edge functions for callback/webhook endpoints
- Flutter app: `health` package or native HealthKit plugin

---

## 7. Rollout plan

1. **Phase 1**: Garmin Connect integration (most requested by assessoria coaches)
2. **Phase 2**: Apple HealthKit integration (iOS users)
3. **Phase 3**: Unified wearable settings screen in app with connect/disconnect per provider
