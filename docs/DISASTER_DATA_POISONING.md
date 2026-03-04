# DISASTER SCENARIO: DATA POISONING

**Date**: 2026-03-04  
**Analyst**: Principal Security Engineer (Simulated)  
**Scope**: Invalid status values, oversized payloads, NULL injection, string injection, type confusion, temporal corruption

---

## 6.1 Invalid Status Values

### 6.1.1 Tables WITH CHECK Constraints on Status

| Table | Column | Allowed Values | File |
|-------|--------|---------------|------|
| `sessions` | `status` | SMALLINT (0-N), no CHECK — relies on app conventions | `full_schema.sql:63` |
| `seasons` | `status` | `'upcoming','active','settling','completed'` | `full_schema.sql:102-103` |
| `challenges` | `status` | `'pending','active','completing','completed','cancelled','expired'` | `full_schema.sql:504-505` |
| `challenge_participants` | `status` | `'invited','accepted','declined','withdrawn'` | `full_schema.sql:545-546` |
| `coaching_members` | `role` | `'admin_master','coach','assistant','athlete'` | `fix_coaching_roles.sql:97-98` |
| `coaching_subscriptions` | `status` | `'active','late','paused','cancelled'` | `financial_engine.sql:33-34` |
| `coaching_financial_ledger` | `type` | `'revenue','expense'` | `financial_engine.sql:48` |
| `coaching_workout_assignments` | `status` | `'planned','completed','missed'` | `workout_builder.sql:43-44` |
| `workout_delivery_batches` | `status` | `'draft','publishing','published','closed'` | `workout_delivery.sql:24-25` |
| `workout_delivery_items` | `status` | `'pending','published','confirmed','failed'` | `workout_delivery.sql:40-41` |
| `billing_purchases` | `status` | `'pending','paid','fulfilled','cancelled'` | `billing_portal_tables.sql:112-113` |
| `billing_events` | `event_type` | `'created','payment_confirmed','fulfilled','cancelled','refunded','note_added'` | `billing_portal_tables.sql:161-168` |
| `coin_ledger` | `reason` | Extensive CHECK with ~25 allowed values | `wallet_reconcile.sql:86-100` |
| `support_tickets` | `status` | `'open','answered','closed'` | `support_tickets.sql:5` |
| `support_messages` | `sender_role` | `'staff','platform'` | `support_tickets.sql:18` |
| `strava_event_queue` | `status` | `'pending','processing','completed','failed'` | `scale_indexes_and_rls.sql:296` |
| `friendships` | `status` | `'pending','accepted','declined','blocked'` | `full_schema.sql:341-342` |
| `coaching_plans` | `billing_cycle` | `'monthly','quarterly'` | `financial_engine.sql:18-19` |
| `coaching_plans` | `status` | `'active','inactive'` | `financial_engine.sql:21-22` |

### 6.1.2 Tables WITHOUT CHECK Constraints on Status

| Table | Column | Type | Risk |
|-------|--------|------|------|
| `sessions` | `status` | `SMALLINT` | No CHECK — any integer value accepted. App uses 0,1,2,3,4 but DB allows -32768 to 32767. Queries like `status >= 3` could return unexpected rows if negative values are inserted. |
| `workout_delivery_events` | `type` | `TEXT NOT NULL` | No CHECK — any string accepted. The type column has no constraint; values like `'HACKED'` would be stored without error. |
| `profiles` | `platform_role` | `TEXT` | No CHECK constraint on allowed values. Combined with the UPDATE vulnerability from Task 1, this is critical. |

**⚠️ FINDING [MEDIUM]**: `sessions.status` is a SMALLINT with no CHECK constraint. While RLS prevents athletes from modifying others' sessions, a compromised service-role key or a SECURITY DEFINER function bug could insert rows with `status = 99`, breaking all queries that assume `status >= 3` means "completed and verified."

**⚠️ FINDING [LOW]**: `workout_delivery_events.type` is an unconstrained TEXT field. Arbitrary event types could be inserted by staff (who have INSERT access) or via SECURITY DEFINER functions, potentially confusing UI rendering or analytics queries.

**Impact on UI**: When the Flutter app encounters an unexpected status value, it depends on the `switch/case` or `if` logic in each screen. Missing cases typically fall through to a default/error state, which is safe. However, analytics queries that aggregate by status could produce incorrect results.

---

## 6.2 Oversized Payloads

### 6.2.1 `export_payload` in `workout_delivery_items`

**Definition** (`workout_delivery.sql:39`):
```sql
export_payload jsonb NOT NULL DEFAULT '{}'
```

**Size limit**: **NONE**. No CHECK constraint on `jsonb_sizeof()` or `length()`. PostgreSQL allows JSONB values up to ~1GB (TOAST compressed).

**Attack vector**: A SECURITY DEFINER function (`fn_generate_delivery_items`) generates the payload server-side from workout templates. The payload size is bounded by the template data, which is controlled by staff. However, a malicious staff member could create a template with extremely long `notes` fields, or a bug in the generation could produce oversized payloads.

**What happens with 100MB JSONB**: PostgreSQL will store it via TOAST (compressed), but:
- Reading it back causes full decompression → memory spike
- PostgREST will serialize it into the HTTP response → large response body
- Flutter app will attempt to JSON-decode it → potential OOM crash
- Network transfer time for millions of rows would be catastrophic

**Verdict**: ⚠️ **VULNERABLE** — No server-side size guard. Risk is medium because the payload is server-generated, not user-supplied directly.

### 6.2.2 `metadata` in `billing_events`

**Definition** (`billing_portal_tables.sql:171`):
```sql
metadata JSONB NOT NULL DEFAULT '{}'
```

**Size limit**: **NONE**. However, `billing_events` are only writable by `service_role` (no INSERT policy for authenticated users). The risk is limited to bugs in SECURITY DEFINER functions like `fn_fulfill_purchase`, which constructs a controlled metadata object.

**Verdict**: ✅ LOW RISK — Only service_role can write; payload is server-controlled.

### 6.2.3 `meta` in `workout_delivery_events`

**Definition** (`workout_delivery.sql:61`):
```sql
meta jsonb
```

**Size limit**: **NONE**. `meta` is nullable, no size constraint.

**Attack vector**: Athletes can insert delivery events for their own items (via `events_athlete_insert` RLS policy). The INSERT policy only validates that `item_id` belongs to the athlete — it does NOT validate the content of `meta`.

**Attack**:
```
POST /workout_delivery_events
Body: { "item_id": "<own_item>", "group_id": "<group>", "type": "ATHLETE_NOTE", "meta": <100MB JSON> }
```

**⚠️ FINDING [HIGH]**: An athlete can insert a `workout_delivery_events` row with an arbitrarily large `meta` JSONB payload. This can:
1. Bloat the database storage
2. Cause OOM when staff reads the events list
3. Denial of service against the group's delivery workflow

**Verdict**: 🔴 **VULNERABLE** — Athletes can inject arbitrarily large JSONB via delivery events.

### 6.2.4 Other JSONB columns without size limits

| Table | Column | Writable by | Risk |
|-------|--------|-------------|------|
| `coaching_workout_blocks.notes` | TEXT | Staff | LOW — staff-only |
| `session_journal_entries.notes` | TEXT | Athlete (own) | MEDIUM — no length limit, potential storage abuse |
| `coaching_announcements.body` | TEXT | Staff | LOW — has CHECK `length >= 1` but no upper bound |
| `coaching_athlete_notes.note` | TEXT | Staff | LOW — has CHECK `length >= 1` but no upper bound |

---

## 6.3 NULL Injection

### 6.3.1 Critical Columns with NOT NULL Constraints

Most critical columns are properly guarded:

| Table | Column | NOT NULL | FK |
|-------|--------|----------|-----|
| `coaching_members.user_id` | ✅ YES | ✅ FK to auth.users |
| `coaching_members.group_id` | ✅ YES | ✅ FK to coaching_groups |
| `wallets.user_id` | ✅ YES (PK) | ✅ FK to auth.users |
| `coin_ledger.user_id` | ✅ YES | ✅ FK to auth.users |
| `coin_ledger.delta_coins` | ✅ YES | — |
| `coin_ledger.reason` | ✅ YES + CHECK | — |
| `sessions.user_id` | ✅ YES | ✅ FK to auth.users |
| `workout_delivery_items.group_id` | ✅ YES | ✅ FK to coaching_groups |
| `workout_delivery_items.athlete_user_id` | ✅ YES | ✅ FK to auth.users |
| `billing_purchases.group_id` | ✅ YES | ✅ FK to coaching_groups |
| `support_tickets.group_id` | ✅ YES | ✅ FK to coaching_groups |

### 6.3.2 What if `group_id` is NULL in `coaching_members`?

**Impossible** — `group_id uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE` (`full_schema.sql:805`). The NOT NULL + FK constraint prevents both NULL and dangling references.

### 6.3.3 What if `user_id` is NULL in `wallets`?

**Impossible** — `user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE` (`full_schema.sql:241`). As a PRIMARY KEY, it's implicitly NOT NULL.

### 6.3.4 Missing FK Constraints

| Table | Column | FK? | Risk |
|-------|--------|-----|------|
| `coin_ledger.ref_id` | TEXT (was UUID in original, then changed) | **NO FK** | Orphaned references possible. An `admin_adjustment` could reference a non-existent entity. No data integrity risk — purely an audit concern. |
| `coin_ledger.issuer_group_id` | UUID, nullable | **NO FK** | Added later without FK constraint. Could reference a non-existent group. |
| `workout_delivery_events.actor_user_id` | UUID, nullable | **NO FK** to auth.users | Could contain an arbitrary UUID not corresponding to any user. |
| `billing_events.actor_id` | UUID REFERENCES auth.users(id) | ✅ FK | — |

**⚠️ FINDING [LOW]**: `coin_ledger.issuer_group_id` lacks a FK constraint to `coaching_groups`. If a group is deleted (CASCADE), the ledger entries remain with orphaned group references. This is intentional (for audit trail preservation) but should be documented.

**⚠️ FINDING [LOW]**: `workout_delivery_events.actor_user_id` is nullable and has no FK. This is by design (system-generated events may have no actor), but allows insertion of arbitrary UUIDs.

---

## 6.4 String Injection (XSS)

### 6.4.1 Can HTML/script be injected into user-facing fields?

**Database-level**: PostgreSQL stores text as-is. There are no DB-level sanitization triggers. Fields like `display_name`, `notes`, `description` accept any UTF-8 string including `<script>`, `<img onerror=...>`, etc.

**Length constraints on critical fields**:
- `coaching_groups.name`: CHECK `length BETWEEN 3 AND 80` ✅
- `coaching_workout_templates.name`: CHECK `length BETWEEN 2 AND 120` ✅
- `support_tickets.subject`: CHECK `char_length BETWEEN 1 AND 200` ✅
- `support_messages.body`: CHECK `char_length BETWEEN 1 AND 5000` ✅
- `profiles.display_name`: **NO length limit** ⚠️
- `coaching_announcements.body`: CHECK `length >= 1` but **NO upper limit** ⚠️
- `session_journal_entries.notes`: **NO length limit** ⚠️

### 6.4.2 Flutter App — Unsafe Rendering?

Flutter uses `Text()` widgets by default, which render strings as plain text — **not** as HTML. There is no `HtmlWidget` or `WebView` rendering user-generated content in the codebase.

**Searched for**: `dangerouslySetInnerHTML` equivalent in Flutter (e.g., `flutter_html`, `Html()` widget, `WebView`).

**Result**: No HTML rendering of user-generated content was found in the Flutter presentation layer.

**Verdict**: ✅ SECURE — Flutter renders all user content as plain text. XSS via the mobile app is not possible.

### 6.4.3 Portal (Next.js) — dangerouslySetInnerHTML?

**Searched**: `dangerouslySetInnerHTML` across all `.tsx` files in `/portal/src/`.

**Result**: **No instances found**. The Portal uses React's default JSX escaping, which automatically escapes HTML entities in `{variable}` expressions.

**Verdict**: ✅ SECURE — Portal does not use dangerouslySetInnerHTML. React's default escaping prevents XSS.

### 6.4.4 Stored XSS via Edge Functions

Edge functions return JSON responses (not HTML). Even if a malicious string is stored in the database, the Edge Function response format (`Content-Type: application/json`) prevents browser-based XSS interpretation.

**Verdict**: ✅ SECURE — JSON responses prevent XSS execution.

### 6.4.5 Remaining Risk — Email/Notification Rendering

If push notifications or emails render user-supplied `display_name` or `notes` in HTML context without escaping, XSS could occur. The `send-push` edge function sends push notifications — these go through OS notification APIs that render as plain text.

**Verdict**: ✅ LOW RISK — Push notifications are plain text.

---

## 6.5 Type Confusion

### 6.5.1 Edge Functions Accepting `req.json()` — Numeric Fields as Strings

**token-create-intent** (`supabase/functions/token-create-intent/index.ts:96-99`):
```typescript
if (typeof amount !== "number" || !Number.isInteger(amount) || amount <= 0 || amount > MAX_AMOUNT) {
  return jsonErr(400, "INVALID_AMOUNT", `amount must be integer 1..${MAX_AMOUNT}`, requestId);
}
```

✅ **Properly validated** — Checks `typeof amount !== "number"`, rejects strings, floats, negatives, and values over 100,000.

**settle-challenge** (`supabase/functions/settle-challenge/index.ts:95-114`):
Accepts `challenge_id` as a string UUID. If a non-UUID string is provided, the Supabase client will forward it to PostgREST, which will return a 400 (invalid UUID syntax). The `classifyError` handler converts this to `INVALID_INPUT`.

✅ **Handled** — Invalid UUIDs are caught by PostgREST/Postgres.

### 6.5.2 What if `amount` is negative in token intents?

**token-create-intent** (`index.ts:96`):
```typescript
amount <= 0 || amount > MAX_AMOUNT
```
✅ **BLOCKED** — Rejects negative and zero amounts.

**token-consume-intent**: Does not accept `amount` from the user — it reads it from the stored intent record. The amount was validated at creation time.

✅ **SECURE** — Amount is always positive.

**Database CHECK** (`full_schema.sql:242`):
```sql
balance_coins INTEGER NOT NULL DEFAULT 0 CHECK (balance_coins >= 0)
```
Even if a SECURITY DEFINER function attempted to make balance negative, the CHECK constraint would reject it.

### 6.5.3 What if `delta` is negative in wallet operations?

**fn_increment_wallets_batch** (`scale_indexes_and_rls.sql:93-135`):
```sql
SET balance_coins = balance_coins + (v_entry->>'delta')::int
```

This function accepts negative delta values — this is **by design** for burns and fees. The `CHECK (balance_coins >= 0)` on the `wallets` table prevents the balance from going below zero.

However, the function is `service_role` only:
```sql
GRANT EXECUTE ON FUNCTION fn_increment_wallets_batch(jsonb) TO service_role;
```

**Verdict**: ✅ SECURE — Negative deltas are intentional (for debits). The balance floor CHECK prevents going below zero.

### 6.5.4 Other type confusion vectors

| Function | Field | Validation | Status |
|----------|-------|-----------|--------|
| `token-create-intent` | `amount` | `typeof !== 'number'`, integer check, range check | ✅ |
| `token-create-intent` | `group_id` | UUID validated by Postgres | ✅ |
| `set-user-role` | `role` | Whitelist: `['ATLETA', 'ASSESSORIA_STAFF']` | ✅ |
| `challenge-join` | Various | Uses `requireFields` for presence, DB for type | ✅ |
| `fn_assign_workout` | All params | PL/pgSQL typed parameters reject wrong types | ✅ |

---

## 6.6 Temporal Corruption

### 6.6.1 `period_start > period_end` in delivery batches

**Table definition** (`workout_delivery.sql:18-28`):
```sql
CREATE TABLE workout_delivery_batches (
  period_start date,
  period_end date,
  ...
);
```

**No CHECK constraint** like `CHECK (period_end >= period_start)`.

**fn_create_delivery_batch** (`chaos_fixes.sql:24-66`): Accepts `p_period_start` and `p_period_end` directly, with no validation that start <= end.

**⚠️ FINDING [MEDIUM]**: A staff member can create a delivery batch where `period_start = '2026-12-31'` and `period_end = '2026-01-01'`. The `fn_generate_delivery_items` function filters assignments by:
```sql
AND (v_period_start IS NULL OR wa.scheduled_date >= v_period_start)
AND (v_period_end IS NULL OR wa.scheduled_date <= v_period_end)
```
With an inverted range, this query returns **zero rows** — the batch generates no items. This is a silent failure, not a crash.

**Verdict**: ⚠️ VULNERABLE to silent data loss — inverted date ranges produce empty batches.

### 6.6.2 `scheduled_date` in year 9999

**coaching_workout_assignments** (`workout_builder.sql:38-52`):
```sql
scheduled_date date NOT NULL
```

No range check. A coach could create an assignment for `scheduled_date = '9999-12-31'`.

**Impact**: The Flutter app likely filters assignments by date range near the current date, so the assignment would never appear. The DB would store it without issue. No crash, but wasted storage and confusion in admin views that show "all assignments."

**Verdict**: ⚠️ LOW RISK — Functional annoyance, not a security issue.

### 6.6.3 `created_at` manually set to the past

Most `created_at` columns have `DEFAULT now()`. When inserting via PostgREST, RLS policies don't prevent setting `created_at` to an arbitrary value.

**Example**: An athlete inserts a session with `created_at = '2020-01-01'`:
```sql
-- sessions INSERT policy:
FOR INSERT WITH CHECK (auth.uid() = user_id)
-- No restriction on created_at value
```

**Impact**:
- Sessions with past `created_at` could appear in historical analytics
- Leaderboard snapshots use `start_time_ms`, not `created_at`, so manipulation of `created_at` alone doesn't affect rankings
- `start_time_ms` is also user-provided (client-set) and has no server-side validation against current time

**⚠️ FINDING [MEDIUM]**: `sessions.start_time_ms` is user-provided with no server-side check against the current timestamp. An athlete could submit a session with `start_time_ms` set to a past leaderboard period to retroactively place on historical leaderboards. The `is_verified` flag and `integrity_flags` array are intended to mitigate this, but verification is async — there's a window where unverified sessions with fake timestamps could affect rankings.

**Verdict**: ⚠️ VULNERABLE — Temporal manipulation of `start_time_ms` can affect historical leaderboards before async verification catches it.

---

## 6.7 Additional Data Integrity Findings

### 6.7.1 `coaching_plans.monthly_price` allows zero

```sql
monthly_price numeric(10,2) NOT NULL CHECK (monthly_price >= 0)
```

A plan with `monthly_price = 0` is allowed, which could be intentional (free tier) but may bypass payment enforcement if the business logic assumes all plans are paid.

### 6.7.2 `coaching_financial_ledger.amount` must be positive

```sql
amount numeric(12,2) NOT NULL CHECK (amount > 0)
```

✅ No zero or negative amounts allowed. Properly enforced.

### 6.7.3 `coaching_workout_blocks` RPE and HR zone ranges

```sql
target_hr_zone int CHECK (target_hr_zone IS NULL OR target_hr_zone BETWEEN 1 AND 5)
rpe_target int CHECK (rpe_target IS NULL OR rpe_target BETWEEN 1 AND 10)
```

✅ Properly bounded.

---

## Summary Table

| ID | Category | Attack | Severity | Status |
|----|----------|--------|----------|--------|
| 6.1.1 | Invalid status | sessions.status accepts any SMALLINT | MEDIUM | ⚠️ No CHECK |
| 6.1.2 | Invalid status | delivery_events.type unconstrained | LOW | ⚠️ No CHECK |
| 6.2.1 | Oversized payload | export_payload no size limit | MEDIUM | ⚠️ Server-generated mitigates |
| 6.2.3 | Oversized payload | delivery_events.meta athlete-writable, no limit | **HIGH** | 🔴 VULNERABLE |
| 6.3.1 | NULL injection | Critical columns properly NOT NULL | — | ✅ Secure |
| 6.3.4 | FK integrity | coin_ledger.issuer_group_id no FK | LOW | ⚠️ Orphan possible |
| 6.4.2 | XSS - Flutter | Flutter renders as plain text | — | ✅ Secure |
| 6.4.3 | XSS - Portal | No dangerouslySetInnerHTML | — | ✅ Secure |
| 6.5.1 | Type confusion | Edge functions validate types | — | ✅ Secure |
| 6.5.2 | Negative amounts | token intents reject negative | — | ✅ Secure |
| 6.5.3 | Negative wallet delta | CHECK(balance >= 0) guards floor | — | ✅ Secure |
| 6.6.1 | Temporal | period_start > period_end allowed | MEDIUM | ⚠️ Silent empty batches |
| 6.6.3 | Temporal | sessions.start_time_ms user-controlled | MEDIUM | ⚠️ Historical leaderboard manipulation |

---

## Remediation Priority

### P0 — Immediate

1. **workout_delivery_events.meta size limit**: Add a CHECK constraint:
   ```sql
   ALTER TABLE workout_delivery_events
     ADD CONSTRAINT chk_meta_size CHECK (meta IS NULL OR pg_column_size(meta) <= 65536);
   ```
   Or use `length(meta::text) <= 65536` for a less precise but portable check.

### P1 — High

2. **sessions.status CHECK constraint**: Add `CHECK (status BETWEEN 0 AND 10)` or enumerate allowed values.
3. **profiles.platform_role CHECK + UPDATE protection**: Add `CHECK (platform_role IS NULL OR platform_role IN ('admin'))` and protect via trigger (see DISASTER_RLS_ESCAPE.md P0).
4. **workout_delivery_batches temporal validation**: Add `CHECK (period_end IS NULL OR period_start IS NULL OR period_end >= period_start)`.

### P2 — Medium

5. **profiles.display_name length limit**: Add `CHECK (length(display_name) <= 100)`.
6. **session_journal_entries.notes length limit**: Add `CHECK (notes IS NULL OR length(notes) <= 10000)`.
7. **sessions.start_time_ms range validation**: Add a trigger or CHECK that rejects timestamps more than 24 hours in the future or more than 1 year in the past:
   ```sql
   CHECK (start_time_ms BETWEEN EXTRACT(epoch FROM now() - interval '1 year') * 1000
                             AND EXTRACT(epoch FROM now() + interval '1 day') * 1000)
   ```
   Note: This would need to be a trigger since CHECK can't reference `now()` reliably.

### P3 — Low

8. **workout_delivery_events.type**: Add CHECK constraint with allowed values.
9. **coin_ledger.issuer_group_id**: Document the intentional lack of FK for audit trail preservation.
10. **coaching_announcements.body max length**: Add upper bound CHECK.

---

## Methodology

- All CHECK constraints read from actual migration SQL files
- JSONB columns identified from table definitions and checked for size constraints
- NOT NULL and FK constraints verified from CREATE TABLE statements
- Flutter rendering checked by searching for HTML widget usage
- Portal checked for dangerouslySetInnerHTML
- Edge function validation checked by reading actual TypeScript source
- No code was modified during this analysis
