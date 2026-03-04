# AUDIT_INTEGRATIONS.md — External Integrations Audit

**Date:** 2026-03-04  
**Scope:** Strava, TrainingPeaks, Wearables/BLE, Export (GPX/TCX/FIT), Payments (Stripe, Mercado Pago)

---

## 1. Strava Integration

### 1.1 Architecture Overview

Strava is the **primary data source** for activity data. The integration spans:

| Layer | Files | Responsibility |
|-------|-------|---------------|
| **Domain** | `i_strava_auth_repository.dart`, `i_strava_upload_repository.dart`, `strava_auth_state.dart`, `strava_upload_status.dart`, `strava_upload_request.dart` | Contracts, state models |
| **Data** | `strava_auth_repository_impl.dart`, `strava_http_client.dart`, `strava_upload_repository_impl.dart`, `strava_secure_store.dart` | OAuth, HTTP, upload, token storage |
| **Presentation** | `strava_connect_controller.dart` | UI ↔ data bridge |
| **Edge Functions** | `strava-webhook/index.ts`, `strava-register-webhook/index.ts` | Webhook processing, registration |
| **Failure Types** | `integrations_failures.dart`, `strava_failures.dart` | Sealed error hierarchy |

### 1.2 OAuth Flow

**File:** `strava_auth_repository_impl.dart`

| Step | Implementation | Status |
|------|---------------|--------|
| Browser auth | `FlutterWebAuth2` with `omnirunnerauth://` scheme | ✅ Solid |
| Code exchange | `POST /oauth/token` via `StravaHttpClient` | ✅ |
| Token storage | `StravaSecureStore` (FlutterSecureStorage) | ✅ Secure |
| Token refresh | Auto-refresh on expired token check | ✅ |
| Revoked handling | Clears tokens, sets `StravaReauthRequired` | ✅ |
| Disconnect | `POST /oauth/deauthorize` + clear local | ✅ Best-effort deauth |

**Error handling in auth:**
- `AuthCancelled` — user taps back or denies consent
- `AuthFailed` — network/server error during exchange
- `TokenExpired` — refresh token missing or invalid
- `AuthRevoked` — 401 during token refresh (user revoked on Strava)
- `PlatformException` — OS-level browser cancel

**Assessment:** ✅ Comprehensive. All OAuth failure modes are handled with proper state transitions.

### 1.3 HTTP Client & Retry Logic

**File:** `strava_http_client.dart`

| Feature | Implementation |
|---------|---------------|
| Base URL management | Constants: `_baseUrl`, `_apiBase`, `_oauthBase` |
| Retry (5xx) | Exponential backoff, max 5 retries, delays: 2s, 4s, 8s, 16s, 32s |
| Retry (network) | Same exponential backoff |
| Rate limit (429) | Parses `Retry-After` header, throws `UploadRateLimited` |
| Auth (401) | Throws `TokenExpired` — caller handles refresh and replay |
| Client error (4xx) | Throws `UploadRejected` — no retry (correct) |
| Timeouts | Upload: 60s, Default: 15s, Poll: 10s |

**Assessment:** ✅ Excellent retry strategy. Clean separation of retryable vs non-retryable errors.

### 1.4 Upload Flow

**File:** `strava_upload_repository_impl.dart`

| Step | Implementation |
|------|---------------|
| Upload POST | Multipart file with retry wrapper |
| 401 on upload | Refresh token once, replay request |
| Polling | Up to 10 polls (3s × 5, then 5s × 5) |
| Timeout | `UploadProcessingTimeout` after 10 polls |
| Duplicate detection | Strava error containing "duplicate" → `StravaUploadDuplicate` (treated as success) |
| Status parsing | Exhaustive sealed type matching (`Queued`, `Processing`, `Ready`, `Duplicate`, `Error`) |

**Assessment:** ✅ Well-architected. Upload status state machine is clean and handles all terminal states.

### 1.5 Webhook (Server-Side)

**File:** `supabase/functions/strava-webhook/index.ts`

| Feature | Implementation |
|---------|---------------|
| Subscription validation | GET handler with `hub.verify_token` |
| Activity processing | POST handler for `create` events |
| Token refresh | Fetches stored tokens, refreshes if expired, updates DB |
| GPS data fetch | Fetches activity details + streams (latlng, altitude, time, heartrate) from Strava API |
| GPS storage | Stores points in Supabase Storage (JSON) |
| Session creation | Upserts to `sessions` table in Postgres |
| Anti-cheat | Distance, duration, pace, GPS jumps, teleports, no-motion, vehicle detection |
| Post-processing | Triggers `eval_athlete_verification`, `recalculate_profile_progress`, `evaluate_badges_retroactive` |

**Anti-cheat checks:**
- `haversine` distance calculation between GPS points
- Speed/cadence correlation analysis (vehicle suspected)
- GPS jump detection (large distance between consecutive points)
- Teleport detection (impossibly fast movement)
- No-motion pattern detection
- Integrity flags array pushed to session record

**Assessment:** ✅ Comprehensive webhook handler with strong anti-cheat. One concern:

⚠️ **No dead-letter queue** — if webhook processing fails after Strava delivery, the event may be lost. Strava retries webhooks but has a limited retry window.

### 1.6 Webhook Registration

**File:** `supabase/functions/strava-register-webhook/index.ts`

- One-time admin operation (requires service_role JWT)
- Checks for existing subscriptions before creating
- Returns existing subscription if already registered

**Assessment:** ✅ Clean. Idempotent registration.

### 1.7 Strava Risks

| Risk | Severity | Detail |
|------|----------|--------|
| No dead-letter queue for webhook failures | Medium | Events could be lost if processing fails after Strava delivery |
| Token refresh race condition | Low | Two concurrent requests could both attempt refresh — `StravaSecureStore` writes would serialize via SecureStorage |
| Webhook anti-cheat is synchronous | Medium | Complex GPS analysis in webhook handler could hit edge function timeout |

---

## 2. TrainingPeaks Integration (Frozen)

### 2.1 Feature Flag Guard

The integration is protected by `trainingpeaks_enabled` feature flag:

| Location | Guard | Status |
|----------|-------|--------|
| `trainingpeaks-oauth/index.ts` | `feature_flags.trainingpeaks_enabled` | ✅ Guarded |
| `trainingpeaks-sync/index.ts` | `feature_flags.trainingpeaks_enabled` | ✅ Guarded |
| `portal/.../trainingpeaks/page.tsx` | `feature_flags.trainingpeaks_enabled` | ✅ Guarded — shows "Funcionalidade indisponível" |
| `staff_workout_assign_screen.dart` | `trainingpeaks_enabled` check | ✅ Guarded |
| `athlete_device_link_screen.dart` | `trainingpeaks_enabled` check | ✅ Guarded |

### 2.2 Edge Functions

**`trainingpeaks-oauth/index.ts`:**
- Actions: `authorize` (redirect to TP), `callback` (token exchange), `refresh`
- Feature flag check at the top — returns 403 if disabled
- Stores tokens in `coaching_device_links` table

**`trainingpeaks-sync/index.ts`:**
- Actions: `push` (send workouts to TP), `pull` (import from TP)
- Feature flag check at the top — returns 403 if disabled
- Updates `coaching_tp_sync` status table

### 2.3 Freeze Completeness

**Assessment:** ✅ **Freeze appears complete.** All entry points (edge functions, app screens, portal pages) check the feature flag. When disabled:
- Edge functions return 403
- Portal page shows "Funcionalidade indisponível"
- App screens conditionally hide TP UI

⚠️ **Minor concern:** The portal `trainingpeaks/page.tsx` reads `group_id` cookie (not `portal_group_id` like other portal pages). This is a separate issue from the freeze but could cause problems when the feature is re-enabled.

---

## 3. Wearables / BLE (Heart Rate Monitors)

### 3.1 Architecture

| File | Responsibility |
|------|---------------|
| `i_heart_rate_source.dart` | Interface contract |
| `ble_heart_rate_source.dart` | BLE scanning, connecting, HR stream |
| `ble_reconnect_manager.dart` | Exponential backoff reconnection |
| `parse_heart_rate_measurement.dart` | BLE characteristic data parsing |
| `heart_rate_sample.dart` | Data model (timestampMs, bpm) |
| `debug_hrm_screen.dart` | Debug/testing screen |

### 3.2 BLE Heart Rate Source

**File:** `ble_heart_rate_source.dart`

| Feature | Implementation |
|---------|---------------|
| BLE library | `flutter_blue_plus` |
| HR characteristic UUID | `00002a37-0000-1000-8000-00805f9b34fb` (standard Bluetooth SIG) |
| Device scanning | Scans with timeout, filters for HR service |
| Connection | Connect to selected device, discover services, subscribe to notifications |
| Last device persistence | SharedPreferences (`ble_hr_last_device_id`, `ble_hr_last_device_name`) |
| Auto-reconnect | `BleReconnectManager` on unexpected disconnect |

### 3.3 Reconnect Manager

**File:** `ble_reconnect_manager.dart`

| Parameter | Value |
|-----------|-------|
| Max attempts | 10 (configurable) |
| Base delay | 1 second |
| Max delay | 30 seconds |
| Backoff schedule | 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s, 30s, 30s |
| Success callback | `onReconnected` |
| Give-up callback | `onGaveUp` |
| Retry callback | `onRetry(attempt, delay)` |

**Assessment:** ✅ Clean, testable, well-designed reconnection logic. Test coverage confirmed (`ble_reconnect_manager_test.dart`).

### 3.4 HR Data Parsing

**File:** `parse_heart_rate_measurement.dart`

Parses the Bluetooth Heart Rate Measurement characteristic per Bluetooth SIG spec.

**Test coverage:** `parse_hr_measurement_test.dart` exists.

### 3.5 BLE Risks

| Risk | Severity | Detail |
|------|----------|--------|
| No battery level monitoring | Low | Could drain HR monitor battery without user knowledge |
| No multi-device support | Low | Only one HR device at a time |
| BLE permission handling | Medium | Need to verify runtime permission requests for Android 12+ (BLUETOOTH_CONNECT, BLUETOOTH_SCAN) |

---

## 4. Export (GPX / TCX / FIT)

### 4.1 Architecture

| File | Responsibility |
|------|---------------|
| `i_export_service.dart` | Interface |
| `export_service_impl.dart` | Router to format-specific encoders |
| `gpx_encoder.dart` | GPX 1.1 XML generation |
| `tcx_encoder.dart` | TCX XML generation |
| `fit_encoder.dart` | FIT binary generation |
| `export_screen.dart` | UI: format selection, progress, error |
| `export_sheet_controller.dart` | Export flow controller |
| `share_export_file.dart` | OS share sheet integration |
| `how_to_import_screen.dart` | Import guide for users |

### 4.2 Encoder Status

| Format | Status | Notes |
|--------|--------|-------|
| **GPX** | ✅ Implemented | GPX 1.1, includes lat/lng/alt/time/hr |
| **TCX** | ✅ Implemented | Includes GPS, HR, distance, laps |
| **FIT** | ✅ **Implemented** | Full FIT binary encoder with CRC, message definitions, records, laps, sessions, activities |

**Note:** The summary comment in `export_service_impl.dart` says FIT "currently throws `ExportNotImplemented`", but the actual `fit_encoder.dart` has a **full implementation** (322 lines) including:
- Correct FIT header (14 bytes, protocol 2.0)
- file_id, event, record, lap, session, activity messages
- Semicircle coordinate conversion
- Garmin epoch timestamp conversion
- CRC-16 checksum (nibble-processing FIT SDK variant)
- Haversine distance accumulation
- HR sample nearest-neighbor matching

**Assessment:** ⚠️ The doc comment in `export_service_impl.dart` is **stale** — FIT is fully implemented. This could mislead developers.

### 4.3 Share Flow

**File:** `share_export_file.dart`

1. Write bytes to temp file in cache directory
2. Open OS share sheet via `share_plus`
3. Clean up temp file (best-effort, async)

Error handling:
- `ExportWriteFailed` if temp file write fails
- Share cancellation is silently accepted (non-error)
- Cleanup failures are silently swallowed (appropriate)

### 4.4 Export Screen UX

**File:** `export_screen.dart`

- Format selection (GPX, TCX, FIT)
- `CircularProgressIndicator` during export
- Error handling via `SnackBar` for `IntegrationFailure`
- First-use education: `_showPostExportSheet` with Garmin import instructions
- Tracks `has_seen_garmin_import_guide` via SharedPreferences

### 4.5 Export Risks

| Risk | Severity | Detail |
|------|----------|--------|
| Stale doc comment on FIT support | Low | Could mislead devs but doesn't affect runtime |
| No format validation post-encode | Medium | GPX/TCX XML not validated against schema; FIT binary not validated against SDK |
| Large route data | Medium | No chunking for very long runs (10k+ GPS points could be slow) |
| Test coverage | ✅ Good | `gpx_encoder_test.dart`, `tcx_encoder_test.dart`, `fit_encoder_test.dart`, `share_export_file_test.dart`, `export_service_impl_test.dart` |

---

## 5. Payment / Checkout

### 5.1 Architecture

**Two payment providers:**

| Provider | Edge Functions | Status |
|----------|---------------|--------|
| **Stripe** | `create-checkout-session`, `webhook-payments` | ✅ Active, production-ready |
| **Mercado Pago** | `create-checkout-mercadopago`, `webhook-mercadopago` | ✅ Active |

### 5.2 Stripe Checkout (`create-checkout-session`)

| Feature | Implementation |
|---------|---------------|
| Auth | `requireUser()` + JWT validation |
| Authorization | `admin_master` role check on `coaching_members` |
| Rate limiting | 10 requests / 60 seconds per user |
| Input validation | `requireJson`, `requireFields(["product_id", "group_id"])` |
| Product lookup | Validates active product from `billing_products` |
| Purchase record | Creates `billing_purchases` (status: pending) |
| Stripe session | `stripe.checkout.sessions.create()` with card + boleto + PIX (BRL) or card only |
| Session TTL | 30 minutes (`expires_at`) |
| Analytics | `billing_checkout_started` event (non-blocking) |
| Error handling | Structured errors with `classifyError`, request IDs, observability |

### 5.3 Stripe Webhook (`webhook-payments`)

| Feature | Implementation |
|---------|---------------|
| Signature verification | `stripe.webhooks.constructEventAsync()` with secret |
| Events handled | `checkout.session.completed`, `async_payment_succeeded`, `async_payment_failed`, `expired`, `charge.refunded`, `charge.dispute.created` |
| Idempotency L1 | `billing_events.stripe_event_id` UNIQUE constraint |
| Idempotency L2 | Conditional UPDATE `WHERE status = 'pending'` |
| Idempotency L3 | `fn_fulfill_purchase` checks `status = 'paid'` with `FOR UPDATE` lock |
| Fulfillment | `fn_fulfill_purchase` RPC (atomic: paid → fulfilled + credit allocation) |
| Cancellation | Only cancels if still pending |
| Refunds | Links refund event via `payment_reference` |
| Disputes | Records as `note_added` billing event |
| Invoice URL | Resolves receipt URL from Stripe charge |
| Analytics | `billing_payment_confirmed` / `billing_checkout_expired` / `billing_payment_failed` |

**Assessment:** ✅ **Excellent.** Triple-layer idempotency is production-grade. All Stripe event types are handled with proper state transitions.

### 5.4 Mercado Pago

**`create-checkout-mercadopago`:** Creates MP Preference and returns checkout URL.  
**`webhook-mercadopago`:** Processes IPN notifications for payment lifecycle.

Similar structure to Stripe handlers with idempotency and analytics.

### 5.5 Payment Risks

| Risk | Severity | Detail |
|------|----------|--------|
| Fulfillment retry gap | Low | If `fn_fulfill_purchase` fails, purchase stays `paid` — needs manual intervention. Could add a cron to retry stuck `paid` purchases |
| No webhook retry verification | Low | If Stripe/MP retries exhaust, the event could be lost. Consider a reconciliation cron |
| Boleto payment window | Info | Async payments (boleto) have multi-day windows — session may expire before payment |
| Analytics swallowed errors | Info | Analytics failures are silently caught (correct — non-critical) |

---

## 6. Error Handling Hierarchy

### 6.1 Sealed Failure Types

**File:** `core/errors/integrations_failures.dart`

```
IntegrationFailure (sealed)
├── AuthCancelled           — User cancelled OAuth
├── AuthFailed              — OAuth flow error
├── TokenExpired            — Refresh token invalid
├── AuthRevoked             — Provider-side revocation
├── UploadRejected          — 4xx (no retry)
├── UploadNetworkError      — Network error (retryable)
├── UploadServerError       — 5xx (retryable)
├── UploadRateLimited       — 429 with retry-after
├── UploadProcessingTimeout — Poll timeout
├── ExportGenerationFailed  — Encoder error
├── ExportWriteFailed       — File I/O error
└── ExportNotImplemented    — Format not yet available
```

**Assessment:** ✅ Well-designed sealed hierarchy enables exhaustive pattern matching in BLoC/UI code.

---

## 7. Cross-Integration Summary

| Integration | OAuth | Retry | Error Types | Logging | Tests | Overall |
|-------------|-------|-------|-------------|---------|-------|---------|
| **Strava** | ✅ Complete | ✅ Exponential backoff (5 retries) | ✅ Sealed hierarchy | ✅ AppLogger | ✅ Auth + Upload tests | ✅ **Production-ready** |
| **TrainingPeaks** | ✅ Complete (frozen) | ❌ No retry in edge functions | ⚠️ Generic try/catch | ⚠️ console.error | ❌ No tests found | ⚠️ **Frozen, needs work before re-enable** |
| **BLE/Wearables** | N/A | ✅ Reconnect manager (10 attempts) | ✅ Proper error handling | ✅ AppLogger | ✅ Reconnect + parsing tests | ✅ **Solid** |
| **Export** | N/A | N/A | ✅ Sealed hierarchy | ✅ AppLogger | ✅ All encoders + share tests | ✅ **Good** |
| **Stripe** | N/A (API key) | N/A (webhook) | ✅ Structured errors | ✅ Structured JSON logs | ❌ No edge function tests | ✅ **Production-ready** |
| **Mercado Pago** | N/A (API key) | N/A (webhook) | ✅ Structured errors | ✅ Structured JSON logs | ❌ No edge function tests | ✅ **Production-ready** |

---

## 8. Recommendations

### Critical
1. **Add webhook dead-letter queue** for Strava — failed webhook events should be stored for retry, not silently lost

### High
2. **Add retry logic to TrainingPeaks edge functions** before re-enabling — currently no retry on TP API calls
3. **Add reconciliation cron for payment** — periodically check Stripe/MP for stuck `paid` purchases and retry fulfillment
4. **Update stale FIT encoder doc comment** in `export_service_impl.dart` — states FIT throws `ExportNotImplemented` but it's fully implemented

### Medium
5. **Add edge function tests** — Stripe/MP webhooks and TrainingPeaks sync functions have no automated tests
6. **Consider async anti-cheat processing** in Strava webhook — offload GPS analysis to a separate function to avoid timeout risk
7. **Fix portal TP page cookie mismatch** — uses `group_id` instead of `portal_group_id`

### Low
8. **Add BLE permission handling audit** — verify Android 12+ permission requests
9. **Add post-encode validation** for GPX/TCX XML output (schema validation)
10. **Add Strava token refresh lock** — prevent concurrent refresh attempts from racing
