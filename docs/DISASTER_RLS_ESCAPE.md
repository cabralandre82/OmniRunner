# DISASTER SCENARIO: RLS BREACH ATTEMPTS (TENANT ESCAPE)

**Date**: 2026-03-04  
**Analyst**: Principal Security Engineer (Simulated)  
**Scope**: PostgREST direct access, RPC/Edge tenant escape, ID enumeration, privilege escalation  
**Actors**: Staff-A (group A), Athlete-A (group A), Staff-B (group B), Athlete-B (group B)

---

## 5.1 Direct Table Access via PostgREST

### 5.1.1 `coaching_members` — Cross-group read?

**RLS Policy** (`20260218000000_full_schema.sql:819-826`):
```sql
CREATE POLICY "coaching_members_group_read" ON public.coaching_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm2
      WHERE cm2.group_id = coaching_members.group_id
        AND cm2.user_id = auth.uid()
    )
  );
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-A reads group B members | `GET /coaching_members?group_id=eq.<group_B_id>` | **BLOCKED** — policy requires caller to be a member of the same group_id |
| Staff-A reads group B members | Same query | **BLOCKED** — same policy applies |
| Athlete-A reads own group members | `GET /coaching_members?group_id=eq.<group_A_id>` | **ALLOWED** — by design: any group member can see co-members |

**Note**: No INSERT/UPDATE/DELETE policies exist on `coaching_members`. All mutations go through SECURITY DEFINER functions (`fn_approve_join_request`, `fn_remove_member`). Direct INSERT/UPDATE/DELETE via PostgREST is **BLOCKED** by the absence of permissive policies (RLS defaults to deny).

**Verdict**: ✅ SECURE — Cross-group read blocked; no direct mutation possible.

---

### 5.1.2 `coaching_workout_assignments` — Can athlete see other athletes' workouts?

**RLS Policies** (`20260304100000_workout_builder.sql:134-154`):
```sql
-- Staff: full access scoped to own group
CREATE POLICY "staff_assignments_all"
  ON public.coaching_workout_assignments FOR ALL USING (
    EXISTS (SELECT 1 FROM coaching_members cm
      WHERE cm.group_id = coaching_workout_assignments.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach'))
  );

-- Athlete: read own only
CREATE POLICY "athlete_assignments_select"
  ON public.coaching_workout_assignments FOR SELECT USING (
    athlete_user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM coaching_members cm
      WHERE cm.group_id = coaching_workout_assignments.group_id
        AND cm.user_id = auth.uid())
  );
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-A reads Athlete-B's assignments (same group) | `GET /coaching_workout_assignments?athlete_user_id=eq.<B_id>` | **BLOCKED** — policy requires `athlete_user_id = auth.uid()` |
| Athlete-A reads Athlete-B's assignments (different group) | Same query with group B IDs | **BLOCKED** — both filters fail |
| Staff-A reads group B's assignments | `GET /coaching_workout_assignments?group_id=eq.<B_id>` | **BLOCKED** — staff policy requires membership in that group |

**Verdict**: ✅ SECURE — Athletes can only see their own assignments.

---

### 5.1.3 `workout_delivery_items` — Can Athlete-A see Athlete-B's deliveries?

**RLS Policies** (`20260305000000_workout_delivery.sql:122-135`):
```sql
CREATE POLICY items_staff_all ON workout_delivery_items
  FOR ALL USING (
    EXISTS (SELECT 1 FROM coaching_members cm
      WHERE cm.group_id = workout_delivery_items.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach','assistant'))
  );

CREATE POLICY items_athlete_select ON workout_delivery_items
  FOR SELECT USING (athlete_user_id = auth.uid());
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-A reads Athlete-B's delivery items | `GET /workout_delivery_items?athlete_user_id=eq.<B_id>` | **BLOCKED** — policy checks `athlete_user_id = auth.uid()`, B_id ≠ A_id |
| Athlete-A reads all items in group A | `GET /workout_delivery_items?group_id=eq.<A_id>` | **PARTIAL** — returns only rows where `athlete_user_id = auth.uid()` |

**Verdict**: ✅ SECURE — Athlete only sees own delivery items.

---

### 5.1.4 `workout_delivery_events` — Can athlete write events for other athletes?

**RLS Policies** (`20260305000000_workout_delivery.sql:158-174`):
```sql
CREATE POLICY events_athlete_insert ON workout_delivery_events
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM workout_delivery_items di
      WHERE di.id = workout_delivery_events.item_id
        AND di.athlete_user_id = auth.uid())
  );
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-A inserts event for Athlete-B's item | `POST /workout_delivery_events` with B's item_id | **BLOCKED** — policy requires the referenced `item_id` to belong to `auth.uid()` |
| Athlete-A inserts event with arbitrary group_id | Same, but faking group_id | **BLOCKED** — the item_id lookup still constrains to own items |

**Verdict**: ✅ SECURE — Athletes can only write events for their own items.

---

### 5.1.5 `sessions` — Can athlete read other athlete's sessions?

**RLS Policies** (`20260218000000_full_schema.sql:85-93`):
```sql
CREATE POLICY "sessions_own_read" ON sessions
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "sessions_own_insert" ON sessions
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "sessions_own_update" ON sessions
  FOR UPDATE USING (auth.uid() = user_id);
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-A reads Athlete-B's sessions | `GET /sessions?user_id=eq.<B_id>` | **BLOCKED** — `auth.uid() = user_id` fails |

**⚠️ FINDING**: There is no staff-read policy on `sessions`. Staff access to athlete session data is handled via SECURITY DEFINER RPCs (`fn_athlete_session_stats`, `fn_compute_kpis_batch`, `staff_group_member_ids()`). This is secure by design — staff cannot browse raw session rows via PostgREST, only aggregated data via RPCs.

**Verdict**: ✅ SECURE — Strictly own-data access.

---

### 5.1.6 `wallets` — Can athlete read/modify other wallets?

**RLS Policy** (`20260218000000_full_schema.sql:249-252`):
```sql
CREATE POLICY "wallets_own_read" ON wallets
  FOR SELECT USING (auth.uid() = user_id);
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-A reads Athlete-B's wallet | `GET /wallets?user_id=eq.<B_id>` | **BLOCKED** |
| Athlete-A updates own wallet (e.g., balance_coins=999999) | `PATCH /wallets?user_id=eq.<A_id>` | **BLOCKED** — no UPDATE policy exists |
| Athlete-A inserts fake wallet | `POST /wallets` | **BLOCKED** — no INSERT policy exists |

**Verdict**: ✅ SECURE — Read-only own wallet; no direct mutation possible. All wallet mutations go through SECURITY DEFINER RPCs (`increment_wallet_balance`, `reconcile_wallet`) which are `service_role` only.

---

### 5.1.7 `coin_ledger` — Can athlete see other users' transactions?

**RLS Policy** (`20260218000000_full_schema.sql:276-279`):
```sql
CREATE POLICY "ledger_own_read" ON coin_ledger
  FOR SELECT USING (auth.uid() = user_id);
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-A reads Athlete-B's ledger | `GET /coin_ledger?user_id=eq.<B_id>` | **BLOCKED** |
| Athlete-A inserts fake ledger entry | `POST /coin_ledger` | **BLOCKED** — no INSERT policy |

**Note**: `fn_sum_coin_ledger_by_group` (`20260308000000_scale_indexes_and_rls.sql:378-394`) is granted to `authenticated` and aggregates by `issuer_group_id` without checking the caller's membership. Any authenticated user can call `SELECT fn_sum_coin_ledger_by_group(<any_group_id>)` and get the total coins issued by that group.

**⚠️ FINDING [MEDIUM]**: `fn_sum_coin_ledger_by_group` lacks group membership check. An attacker could enumerate group IDs and learn the total coin issuance per group. This leaks financial intelligence.

**Verdict**: ⚠️ PARTIAL — Row-level read is secure; aggregate RPC leaks group-level financial data.

---

### 5.1.8 `challenge_participants` — Can athlete see who's in challenges they're not in?

**RLS Policy** (`20260218000000_full_schema.sql:559-567`):
```sql
CREATE POLICY "challenge_parts_own_read" ON challenge_participants
  FOR SELECT USING (
    auth.uid() = user_id
    OR EXISTS (SELECT 1 FROM challenge_participants cp2
      WHERE cp2.challenge_id = challenge_participants.challenge_id
        AND cp2.user_id = auth.uid())
  );
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-B (not in challenge X) reads challenge X participants | `GET /challenge_participants?challenge_id=eq.<X>` | **BLOCKED** — neither condition is met |
| Athlete-A (in challenge X) reads all participants of X | Same query | **ALLOWED** — by design: co-participants can see each other |

**Verdict**: ✅ SECURE — Only co-participants can see each other.

---

### 5.1.9 `billing_purchases` — Can athlete see other groups' purchases?

**RLS Policy** (`20260221000011_billing_portal_tables.sql:143-151`):
```sql
CREATE POLICY "billing_purchases_admin_read" ON billing_purchases
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM coaching_members cm
      WHERE cm.group_id = billing_purchases.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master')
  );
```

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete-A reads any billing purchases | `GET /billing_purchases` | **BLOCKED** — requires `admin_master` role |
| Staff-A (coach) reads own group's purchases | Same query | **BLOCKED** — requires `admin_master`, not `coach` |
| Staff-A reads group B purchases | `GET /billing_purchases?group_id=eq.<B_id>` | **BLOCKED** — Staff-A is not admin_master of group B |

**Verdict**: ✅ SECURE — Admin-master only, group-scoped.

---

### 5.1.10 `support_tickets` — Can athlete read other users' tickets?

**RLS Policies** (`20260226120000_support_tickets.sql:43-91`):
```sql
CREATE POLICY "staff_read_own_tickets" ON support_tickets
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM coaching_members cm
      WHERE cm.group_id = support_tickets.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','professor','assistente'))
  );
```

**⚠️ FINDING [LOW]**: The support_tickets RLS policies use legacy role names `'professor'` and `'assistente'` instead of the canonicalized `'coach'` and `'assistant'`. After the migration `20260303300000_fix_coaching_roles.sql` which changed all role values, these policies will **never match** because no rows in `coaching_members` have those role values anymore.

| Attack | Vector | Result |
|--------|--------|--------|
| Athlete reads any ticket | `GET /support_tickets` | **BLOCKED** — no athlete policy exists |
| Staff-A (coach) reads own group tickets | Same query | **BLOCKED** — policy checks for 'professor', not 'coach' ❌ |
| Platform admin reads all | Works via separate `platform_read_all_tickets` policy | **ALLOWED** |

**Impact**: Staff can no longer read or create support tickets via PostgREST. Only the platform admin policy still works. This is a **functional regression**, not a security hole — it fails closed.

**Verdict**: ⚠️ REGRESSION — Stale role names cause staff lockout from support tickets.

---

## 5.2 RPC / Edge Function Tenant Escape

### 5.2.1 `fn_create_delivery_batch(group_id_of_B)`

**Code** (`20260307000000_chaos_fixes.sql:24-69`):
```sql
SELECT cm.role INTO v_role
FROM coaching_members cm
WHERE cm.group_id = p_group_id AND cm.user_id = auth.uid()
LIMIT 1;

IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
  RAISE EXCEPTION 'forbidden';
END IF;
```

**Attack**: Staff-A calls `fn_create_delivery_batch(group_B_id, ...)`.  
**Result**: **BLOCKED** — The function checks `coaching_members` for the caller's membership in the target group. Staff-A is not a member of group B, so `v_role` is NULL → exception.

---

### 5.2.2 `fn_mark_item_published` — Can an athlete call it?

**Code** (`20260305000000_workout_delivery.sql:300-343`):
```sql
SELECT cm.role INTO v_role
FROM coaching_members cm
WHERE cm.group_id = v_group_id AND cm.user_id = auth.uid();

IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
  RAISE EXCEPTION 'forbidden';
END IF;
```

**Grant** (`20260306000000_comprehensive_security_hardening.sql:482-487`):
```sql
GRANT EXECUTE ON FUNCTION public.fn_mark_item_published TO authenticated;
```

**Attack**: Athlete-A calls `fn_mark_item_published(some_item_id)`.  
**Result**: **BLOCKED** — The function is callable by any `authenticated` user (athletes included), but the internal role check rejects anyone not `admin_master` or `coach` in the item's group.

---

### 5.2.3 `fn_fulfill_purchase`

**Code** (`20260221000011_billing_portal_tables.sql:203-255`):
No caller role check inside the function — it trusts that only `service_role` can call it.

**Grant** (`20260306000000_comprehensive_security_hardening.sql:382-387`):
```sql
GRANT EXECUTE ON FUNCTION public.fn_fulfill_purchase TO service_role;
```
(Not granted to `authenticated`.)

**Attack**: Any authenticated user calls `fn_fulfill_purchase(some_purchase_id)`.  
**Result**: **BLOCKED** — Function is only executable by `service_role`. PostgREST calls with a user JWT will get "permission denied".

---

### 5.2.4 `fn_settle_challenge` (settle-challenge edge function)

The `settle-challenge` edge function (`supabase/functions/settle-challenge/index.ts:74-86`) uses `requireUser()` to authenticate, then queries challenges via the **user-scoped `db` client** (line 118: `db.from("challenges")`). This means:

1. The `challenges` table RLS policy (`challenges_participant_read`) only allows reading challenges where the caller is a participant.
2. The function can only settle challenges the caller participates in.
3. It then writes results using the same user-scoped client, which goes through RLS.

**⚠️ FINDING [MEDIUM]**: The settle-challenge function uses a user-scoped DB client for writes to `challenge_results` and `coin_ledger`. Since there are no INSERT policies for these tables for authenticated users, the inserts may silently fail (PostgREST returns 201 but inserts 0 rows). The function also calls `fn_increment_wallets_batch` which is `service_role` only — this RPC call will fail with "permission denied" when called via a user-scoped client.

**Attack**: User calls settle-challenge to settle a challenge they are in.  
**Result**: The RPC call to `fn_increment_wallets_batch` will **fail** because it requires `service_role`. This is both a **security non-issue** (no escalation) and a **functional bug** (settlement doesn't actually credit wallets when called by a regular user).

---

### 5.2.5 `fn_assign_workout`

**Code** (`20260307000000_chaos_fixes.sql:78-179`):
```sql
-- Check caller is staff
SELECT cm.role INTO v_caller_role
FROM coaching_members cm WHERE cm.group_id = v_group_id AND cm.user_id = v_uid;

IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
  RETURN jsonb_build_object('ok', false, 'code', 'NOT_STAFF', ...);
END IF;
```

**Attack**: Athlete calls `fn_assign_workout` to assign workouts to themselves.  
**Result**: **BLOCKED** — Role check rejects athletes.

---

### 5.2.6 `fn_athlete_confirm_item`

**Code** (`20260307000000_chaos_fixes.sql:226-272`):
```sql
IF v_athlete <> auth.uid() THEN RAISE EXCEPTION 'forbidden'; END IF;
```

**Attack**: Athlete-A calls `fn_athlete_confirm_item(item_belonging_to_B)`.  
**Result**: **BLOCKED** — Function checks `athlete_user_id = auth.uid()`.

---

### 5.2.7 Edge Functions — Group Ownership Validation

Reviewed edge functions that accept `group_id`:

| Function | Group check | Result |
|----------|------------|--------|
| `token-create-intent` | Checks `coaching_members` for caller role in group (line 102-112) | ✅ SECURE |
| `token-consume-intent` | Checks athlete affiliation in intent's group (line 143-156) | ✅ SECURE |
| `challenge-join` | Uses user-scoped DB, RLS enforces | ✅ SECURE |
| `settle-challenge` | Uses user-scoped DB, limited by challenge_participants RLS | ✅ SECURE (but functionally broken for wallet credits) |

---

## 5.3 ID Enumeration

### 5.3.1 UUID Discovery

All primary keys use `uuid` type (random v4 UUIDs). The UUID space is 2^122, making brute-force enumeration infeasible.

**However**, several APIs leak UUIDs in normal flows:
- Challenge participants reveal other user IDs (by design for co-participants)
- Group members reveal user IDs of co-members (by design)
- Leaderboard entries reveal user IDs (by design)

This is acceptable because even with a discovered UUID, RLS prevents unauthorized access to the target user's data.

### 5.3.2 Error Message Information Leakage

**Edge function error classification** (`supabase/functions/_shared/errors.ts`):
```typescript
export function classifyError(err: unknown) {
  // Maps internal DB errors to generic messages
  if (raw.includes("permission denied")) return { code: "FORBIDDEN", message: "Forbidden" };
  if (raw.includes("duplicate key"))      return { code: "CONFLICT", message: "Duplicate entry" };
  return { code: "DB_ERROR", message: "Internal error" };
}
```

**✅ GOOD**: The `classifyError` function strips internal Postgres details (table names, column names, SQL state) and returns generic messages. Internal function names are not leaked.

**⚠️ FINDING [LOW]**: Some SECURITY DEFINER functions use distinct exception messages that differentiate "not found" from "forbidden":

```sql
-- fn_athlete_confirm_item
IF v_group_id IS NULL THEN RAISE EXCEPTION 'item_not_found'; END IF;
IF v_athlete <> auth.uid() THEN RAISE EXCEPTION 'forbidden'; END IF;
```

An attacker probing random item IDs would get `item_not_found` for non-existent IDs and `forbidden` for existing items belonging to other users. This confirms **resource existence** to the attacker. However, since all IDs are UUIDs, this is **low practical risk**.

**Recommendation**: Use a uniform "not_found_or_forbidden" response for all cases.

---

## 5.4 Privilege Escalation

### 5.4.1 Can an athlete promote themselves to coach/admin?

**coaching_members.role CHECK constraint** (`20260303300000_fix_coaching_roles.sql:93-98`):
```sql
ALTER TABLE coaching_members
  ADD CONSTRAINT coaching_members_role_check
  CHECK (role IN ('admin_master', 'coach', 'assistant', 'athlete'));
```

**No UPDATE policy on coaching_members**: There is no RLS UPDATE policy on the `coaching_members` table. An athlete attempting `PATCH /coaching_members?id=eq.<own_id>` with `role=admin_master` will be **BLOCKED** by the absence of a permissive UPDATE policy (RLS defaults to deny).

**Via SECURITY DEFINER functions**: All membership mutations go through:
- `fn_approve_join_request` — controlled by staff
- `fn_remove_member` — controlled by staff with role hierarchy
- `fn_request_join` — can only request `athlete` or `coach` roles, and requires staff approval

```sql
-- fn_request_join (20260303300000_fix_coaching_roles.sql:383-416)
v_role := COALESCE(p_role, 'athlete');
IF v_role NOT IN ('athlete', 'coach') THEN
  RAISE EXCEPTION 'INVALID_ROLE';
END IF;
```

Even if a user requests `coach` role, it goes into a pending join request that requires admin_master approval.

**Via set-user-role edge function**: The `set-user-role` function (`supabase/functions/set-user-role/index.ts`) only modifies `profiles.user_role` (ATLETA/ASSESSORIA_STAFF) and is gated by `onboarding_state`. It does NOT modify `coaching_members.role`.

**Verdict**: ✅ SECURE — No path exists for an athlete to escalate to coach/admin.

### 5.4.2 Direct UPDATE on coaching_members role column

| Attack | Vector | Result |
|--------|--------|--------|
| Direct PATCH via PostgREST | `PATCH /coaching_members?user_id=eq.<self>&group_id=eq.<group>` with `{"role":"admin_master"}` | **BLOCKED** — No UPDATE RLS policy exists |
| Via fn_approve_join_request | Requires caller to be admin_master/coach of the target group | **BLOCKED** by authorization check |
| Insert duplicate membership with higher role | `POST /coaching_members` with `role=admin_master` | **BLOCKED** — No INSERT RLS policy + UNIQUE(group_id, user_id) constraint |

### 5.4.3 platform_role escalation

The `profiles.platform_role` column is used in many RLS policies to grant platform admin access. There is no CHECK constraint on its values, and the `profiles_update_own` policy allows:
```sql
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
```

**⚠️ FINDING [CRITICAL]**: A user can update their own profile row, and there is **no column-level restriction** preventing them from setting `platform_role = 'admin'`. The RLS policy allows any authenticated user to UPDATE their own profile row with arbitrary column values.

**Attack**:
```
PATCH /profiles?id=eq.<self_user_id>
Body: { "platform_role": "admin" }
```

**Result**: **POTENTIALLY VULNERABLE** — If `platform_role` is a column on the `profiles` table and no trigger or CHECK constraint prevents it, the user becomes a platform admin with read access to all support tickets, all CRM data, all audit logs, and all training sessions across all groups.

**Mitigation check**: We did NOT find a CHECK constraint or trigger protecting `platform_role`. The column was added in portal-related migrations but no write protection was applied.

**Severity**: 🔴 **CRITICAL** — This is the highest-severity finding in this audit.

---

## Summary Table

| ID | Table/Function | Attack | Severity | Status |
|----|---------------|--------|----------|--------|
| 5.1.1 | coaching_members | Cross-group read | — | ✅ Blocked |
| 5.1.2 | coaching_workout_assignments | Cross-athlete read | — | ✅ Blocked |
| 5.1.3 | workout_delivery_items | Cross-athlete read | — | ✅ Blocked |
| 5.1.4 | workout_delivery_events | Cross-athlete write | — | ✅ Blocked |
| 5.1.5 | sessions | Cross-athlete read | — | ✅ Blocked |
| 5.1.6 | wallets | Read/modify other wallet | — | ✅ Blocked |
| 5.1.7 | coin_ledger | Cross-user read | MEDIUM | ⚠️ fn_sum_coin_ledger_by_group leaks aggregate data |
| 5.1.8 | challenge_participants | Read non-participant challenges | — | ✅ Blocked |
| 5.1.9 | billing_purchases | Cross-group read | — | ✅ Blocked |
| 5.1.10 | support_tickets | Cross-group read | LOW | ⚠️ Stale role names = functional lockout |
| 5.2.1 | fn_create_delivery_batch | Cross-group create | — | ✅ Blocked |
| 5.2.2 | fn_mark_item_published | Athlete calls staff RPC | — | ✅ Blocked |
| 5.2.3 | fn_fulfill_purchase | Authenticated user calls service_role RPC | — | ✅ Blocked |
| 5.2.4 | settle-challenge | Cross-challenge settle | MEDIUM | ⚠️ Wallet credit fails silently |
| 5.2.5 | fn_assign_workout | Athlete self-assigns workout | — | ✅ Blocked |
| 5.2.6 | fn_athlete_confirm_item | Cross-athlete confirm | — | ✅ Blocked |
| 5.3.2 | Error messages | Existence leakage | LOW | ⚠️ Distinct not_found vs forbidden |
| 5.4.3 | profiles.platform_role | Self-escalation to platform admin | **CRITICAL** | 🔴 VULNERABLE |

---

## Remediation Priority

### P0 — Immediate (CRITICAL)

1. **profiles.platform_role self-escalation**: Add a trigger or column-level GRANT to prevent users from modifying `platform_role` via direct UPDATE. Options:
   - `REVOKE UPDATE (platform_role) ON profiles FROM authenticated;` (requires column-level grants)
   - Add a trigger: `IF NEW.platform_role IS DISTINCT FROM OLD.platform_role THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;`
   - Create a narrower UPDATE policy: `WITH CHECK (platform_role IS NOT DISTINCT FROM OLD.platform_role)`

### P1 — High

2. **fn_sum_coin_ledger_by_group**: Add group membership check or restrict to `service_role` only.
3. **settle-challenge wallet credits**: Switch to `adminDb` (service-role client) for wallet mutations, or call `fn_increment_wallets_batch` via service-role.

### P2 — Medium

4. **support_tickets stale role names**: Update RLS policies to use canonicalized role names (`'coach'`, `'assistant'` instead of `'professor'`, `'assistente'`).
5. **Error message uniformity**: Use consistent "not_found" for both non-existent and unauthorized resources.

---

## Methodology

- All RLS policies read from actual migration SQL files
- All SECURITY DEFINER functions analyzed for internal authorization checks
- All edge functions analyzed for `requireUser()` + group membership validation
- No code was modified during this analysis
