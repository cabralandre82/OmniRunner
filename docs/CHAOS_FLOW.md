# Chaos de Fluxo — Chaos Testing Report

**Date:** 2026-03-04  
**Scope:** Out-of-order actions, race conditions, double-click, navigation races, state machine violations, concurrent user actions  
**Repository:** /home/usuario/project-running

---

## 1. OUT-OF-ORDER ACTIONS

### 1.1 Workout Delivery Flow

#### 1.1.1 Athlete confirms BEFORE staff marks as published

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/migrations/20260305000000_workout_delivery.sql` lines 346-384, `fn_athlete_confirm_item` |
| **Scenario** | Athlete opens delivery screen, sees item with `status='pending'` (UI only shows `published` in `listPublishedItems`). But if athlete has direct API access or cached stale data showing an item, and calls `fn_athlete_confirm_item` for a pending item. |
| **Analysis** | `listPublishedItems` filters `.inFilter('status', ['published'])` — athlete never sees pending items in the app. The RPC `fn_athlete_confirm_item` has `WHERE id = p_item_id AND status = 'published'`. If status is `pending`, the UPDATE affects 0 rows. The function still inserts into `workout_delivery_events` with type `ATHLETE_CONFIRMED`. Result: **orphan event** (event says confirmed but item stays pending). |
| **What breaks** | Audit trail inconsistency; event suggests confirmation that never happened. |
| **Severity** | **MINOR** — Athlete cannot trigger this via normal UI; only via API abuse. Event is misleading but no data corruption. |

#### 1.1.2 Staff generates items BEFORE creating batch

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/migrations/20260305000000_workout_delivery.sql` lines 214-292, `fn_generate_delivery_items` |
| **Scenario** | Staff clicks "Generate Items" without first creating a batch. |
| **Analysis** | `fn_generate_delivery_items` requires `p_batch_id`. It fetches the batch; if not found, `v_group_id IS NULL` and raises `batch_not_found`. Portal UI shows "Generate Items" only when `b.status === 'draft'`, and batch must exist. |
| **What breaks** | RPC returns error; no silent failure. |
| **Severity** | **None** — Properly guarded. |

#### 1.1.3 Delivery batch closed but items still pending

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/migrations/20260305000000_workout_delivery.sql`, `portal/src/app/(portal)/delivery/page.tsx` |
| **Scenario** | Staff closes a batch (`status='closed'`) while some items remain `pending` or `published`. |
| **Analysis** | No migration or RPC enforces that all items must be in a terminal state before closing. The batch status (`draft` → `publishing` → `published` → `closed`) does not gate item-level operations. Staff can close batch with pending items; athletes can still confirm published items. No constraint prevents this. |
| **What breaks** | Operational confusion; orphaned "pending" items in a closed batch. Staff may not realize some athletes never confirmed. |
| **Severity** | **MINOR** — Data integrity preserved; UX/ops clarity degraded. |

---

### 1.2 Billing Flow

#### 1.2.1 Webhook arrives before checkout is recorded

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/functions/create-checkout-mercadopago/index.ts`, `webhook-mercadopago/index.ts` |
| **Scenario** | MP webhook fires before `billing_purchases` row exists (e.g., network race). |
| **Analysis** | Checkout flow: (1) create `billing_purchases` (status=pending), (2) create MP Preference with `external_reference` = purchase_id, (3) redirect user. The purchase row is created *before* the redirect. Webhook looks up payment by MP API, gets `external_reference` = our purchase_id. If webhook arrives before checkout completes, `external_reference` would not exist yet — but checkout creates the purchase first, so this race is unlikely. |
| **What breaks** | If it occurred: webhook would get `external_reference` for a non-existent purchase. Lookup by ID would fail; webhook returns `ignored: true` or similar. |
| **Severity** | **MINOR** — Flow order makes this rare; no double-credit risk. |

#### 1.2.2 Refund processed before fulfillment

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/functions/webhook-mercadopago/index.ts` lines 321-327 |
| **Scenario** | Payment is approved, webhook starts processing. Before `fn_fulfill_purchase` completes, MP sends a refund notification (e.g., chargeback, user cancels). |
| **Analysis** | Webhook handles `refunded` separately: it only calls `insertEvent(db, purchaseId, "refunded", {...})`. It does NOT revert `billing_purchases.status` or claw back credits. If fulfillment already ran, credits are allocated and stay allocated. Refund event is logged but no operational reversal. |
| **What breaks** | **Credits granted but money refunded** — assessoria keeps tokens despite refund. |
| **Severity** | **CRITICAL** — Financial inconsistency; requires manual reconciliation. |

---

### 1.3 Challenge Flow

#### 1.3.1 Challenge settled before it ends

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/functions/settle-challenge/index.ts` lines 117-122 |
| **Scenario** | Malicious or buggy client calls `settle-challenge` with `challenge_id` for an active challenge. |
| **Analysis** | Query: `query.in("status", ["active", "completing"]).lte("ends_at_ms", nowMs)`. Even with `challenge_id` specified, `lte("ends_at_ms", nowMs)` is required. Challenges that have not ended are excluded. |
| **What breaks** | Cannot force-settle an active challenge. |
| **Severity** | **None** — Properly guarded. |

#### 1.3.2 Participant withdraws after settlement

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/functions/settle-challenge/index.ts` lines 138-174, 403-412 |
| **Scenario** | Settlement starts; Participant A is in `accepted` list. During computation, A withdraws. Settlement writes results including A. |
| **Analysis** | `settle-challenge` fetches participants once (`status='accepted'`). Withdrawal updates `challenge_participants.status` to `withdrawn`. There is no re-fetch before writing. Results and `coin_ledger` entries are written for all participants in the initial fetch. A withdrawn user could receive coins/refunds despite having withdrawn. |
| **What breaks** | Withdrawn participant may receive settlement outcome (coins) incorrectly. |
| **Severity** | **MAJOR** — Wallet/ledger inconsistency; edge case but possible under concurrent load. |

---

## 2. DOUBLE-CLICK / RAPID FIRE

### 2.1 Flutter — Buttons Without Guards

| File | Line | Button/Action | Guard | Severity |
|------|------|---------------|-------|----------|
| `staff_challenge_invites_screen.dart` | 317-325 | `onRespond(inviteId, accept)` Accept/Decline | `_loading` covers whole screen but no per-button disable; two rapid clicks can invoke `_respond` twice before first `setState` | **MAJOR** |
| `profile_screen.dart` | 482-496 | `_signOut`, `_requestDeleteAccount` | No `_saving` or similar on these buttons | **MAJOR** |
| `more_screen.dart` | 259 | `_signOut(context)` | No loading guard | **MAJOR** |
| `wallet_screen.dart` | 49-50 | `RefreshWallet` | No debounce; user can spam refresh | **MINOR** |
| `challenge_details_screen.dart` | 307-308, 722-723 | `CancelChallengeRequested`, `DeclineChallengeRequested` | No per-action loading; bloc handles but button stays clickable | **MINOR** |
| `announcement_create_screen.dart` | 121 | `_save` in app bar | Has `_saving` guard at line 55 and 186 | OK |
| `staff_championship_manage_screen.dart` | 423-440 | `_openChampionship`, `_cancelChampionship`, `_inviteGroup`, `_generateBadgeQr` | No `_loading`/`_saving` flags; these trigger async RPCs | **MAJOR** |
| `athlete_device_link_screen.dart` | 222 | `_toggleLink(provider)` | No loading guard during link/unlink | **MAJOR** |
| `support_screen.dart` | 355 | Form submit in `_NewTicketDialog` | No `_submitting` guard; form can be submitted twice | **MAJOR** |
| `staff_disputes_screen.dart` | 460-463 | Confirm send/receive buttons in dialog | Dialog closes on confirm; limited double-tap window | **MINOR** |

### 2.2 Flutter — Buttons With Guards (Good Examples)

| File | Pattern |
|------|---------|
| `staff_workout_assign_screen.dart` | `onPressed: _saving ? null : _assign` |
| `athlete_delivery_screen.dart` | `isConfirming` per item via `_confirmingIds` |
| `athlete_workout_day_screen.dart` | `_completing ? null : _markCompleted` |
| `export_screen.dart` | `_exporting ? null : _export` |
| `today_screen.dart` | `debounceTimer` for journal save |

### 2.3 Portal — Forms and Buttons

| File | Component | Guard | Notes |
|------|-----------|-------|------|
| `delivery-actions.tsx` | `CreateBatchForm` | `if (loading) return` | OK |
| `delivery-actions.tsx` | `GenerateItemsButton` | `if (loading) return` | OK |
| `delivery-actions.tsx` | `PublishButton` | `disabled={loading}` | OK |
| `delivery-actions.tsx` | `CopyPayloadButton` | No guard for clipboard | Low risk |
| Portal API routes | Server actions | No client-side debounce | Depends on server idempotency |

---

## 3. NAVIGATION RACE CONDITIONS

### 3.1 Flutter — `mounted` Checks

| File | Pattern | Assessment |
|------|---------|------------|
| `staff_workout_assign_screen.dart` | `if (!mounted) return` after assign, before SnackBar | OK |
| `profile_screen.dart` | Multiple `if (!mounted) return` after awaits | OK |
| `athlete_delivery_screen.dart` | `if (mounted)` before setState; `if (!mounted) return` before SnackBar | OK |
| `athlete_workout_day_screen.dart` | `if (!mounted) return` before HapticFeedback | OK |
| `today_screen.dart` | `if (!ctx.mounted) return` in journal save | OK |
| `export_screen.dart` | `if (!mounted) return` before modal | OK |
| `more_screen.dart` | `if (!context.mounted) return` | OK |
| `challenge_details_screen.dart` | `_tryAutoSettle` uses `.then((_) { if (!mounted) return; ... })` | OK |

### 3.2 Flutter — Missing or Risky Checks

| File | Location | Risk |
|------|----------|------|
| `staff_challenge_invites_screen.dart` | `_respond` — `setState` and `_loadInvites`; `mounted` checked before SnackBar but not before `_loadInvites` | If user navigates away during `_respond`, `_loadInvites` may run on unmounted widget |
| `staff_championship_manage_screen.dart` | Various RPC handlers — some branches use `mounted` inconsistently | Potential setState after unmount |
| `athlete_my_status_screen.dart` | `_assign` flow — similar to staff_workout_assign | Generally OK |

### 3.3 Rapid Back/Forward Navigation

- No specific handling for rapid route changes. Blocs and async flows can complete after the user has left the screen.
- **Impact:** Stale updates (e.g., refresh) may overwrite newer data if user navigates back. Low severity in most screens.

---

## 4. STATE MACHINE VIOLATIONS

### 4.1 `workout_delivery_items.status`

| Transition | Allowed | Enforced By |
|------------|---------|-------------|
| `pending` → `published` | Yes | `fn_mark_item_published` (WHERE status='pending') |
| `published` → `confirmed` | Yes | `fn_athlete_confirm_item` (WHERE status='published') |
| `published` → `failed` | Yes | Same RPC |
| `confirmed` → `published` | No | RPC returns `already_confirmed`; UPDATE requires status='published' |
| `failed` → `published` | No | Same |
| `confirmed` → `failed` | No | Terminal state |

**Assessment:** State machine is enforced at DB level. No rollback paths.

### 4.2 `billing_purchases.status`

| Transition | Allowed | Enforced By |
|------------|---------|-------------|
| `pending` → `paid` | Yes | Webhook (WHERE status='pending') |
| `paid` → `fulfilled` | Yes | `fn_fulfill_purchase` (FOR UPDATE, status='paid') |
| `pending` → `cancelled` | Yes | Webhook |
| `fulfilled` → `paid` | No | No update path |
| `fulfilled` → `cancelled` | No | Refund does not change status |

**Gap:** Refund does not transition status. `fulfilled` + refund event = inconsistent business state.

### 4.3 `challenge_participants.status`

| Transition | Allowed | Enforced By |
|------------|---------|-------------|
| `invited` → `accepted` | Yes | `challenge-accept-group-invite` |
| `accepted` → `withdrawn` | Yes | `challenge-join` or similar |
| `withdrawn` → `accepted` | Unknown | No reverse-withdraw RPC found |

**Assessment:** No explicit rollback from `withdrawn` to `accepted`. Withdrawal during settlement can still cause inconsistent results (see §1.3.2).

---

## 5. CONCURRENT USER ACTIONS

### 5.1 Two Staff Edit Same Workout Template

| Aspect | Finding |
|--------|---------|
| **Location** | `staff_workout_builder_screen.dart`, `coaching_workout_templates` |
| **Scenario** | Staff A and B edit the same template concurrently. |
| **Analysis** | No optimistic locking (`updated_at` / version column). Last write wins. Changes by one staff can overwrite the other. |
| **What breaks** | Lost updates; confusion about who changed what. |
| **Severity** | **MAJOR** — Common in multi-coach assessorias. |

### 5.2 Coach Removes Member While Member Mid-Action

| Aspect | Finding |
|--------|---------|
| **Location** | `coaching_members` RLS, various screens |
| **Scenario** | Member is on `athlete_workout_day_screen`, starts confirming. Coach removes them from group. |
| **Analysis** | RLS policies filter by `coaching_members`. Once removed, subsequent queries return no rows. In-flight request (e.g., `fn_athlete_confirm_item`) may already have started; it checks `athlete_user_id = auth.uid()` — membership is not re-checked mid-RPC. If RPC passes ownership check, it completes. |
| **What breaks** | Member may complete action (e.g., confirm delivery) after removal. Edge case; RPC is user-scoped. |
| **Severity** | **MINOR** — Rare; outcome is usually acceptable. |

### 5.3 Admin Disables Feature Flag While Users Use It

| Aspect | Finding |
|--------|---------|
| **Location** | `feature_flags`, `trainingpeaks-sync`, `trainingpeaks-oauth` |
| **Scenario** | Admin sets `trainingpeaks_enabled = false` while athletes have sync in progress. |
| **Analysis** | Edge functions check the flag at request start. In-flight requests complete; new requests are rejected. No graceful degradation for mid-flow sync. |
| **What breaks** | Partial sync state; some data pushed, some not. User sees inconsistent experience. |
| **Severity** | **MINOR** — Feature flags are rarely toggled during peak use. |

---

## Summary of Critical/Major Findings

| ID | Finding | Severity |
|----|---------|----------|
| F1 | Refund processed before/after fulfillment — credits not clawed back | **CRITICAL** |
| F2 | Participant withdraws during settlement — may still receive coins | **MAJOR** |
| F3 | Staff challenge invites Accept/Decline — double-click can double-respond | **MAJOR** |
| F4 | Profile/More sign-out and delete-account — no loading guards | **MAJOR** |
| F5 | Staff championship manage — open/cancel/invite/generate QR without guards | **MAJOR** |
| F6 | Athlete device link toggle — no loading guard | **MAJOR** |
| F7 | Support screen new ticket form — can submit twice | **MAJOR** |
| F8 | Two staff editing same workout template — last write wins | **MAJOR** |

---

*Report generated by Chaos Testing analysis. No files were modified.*
