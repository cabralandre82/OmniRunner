# Feature flag audit policy (L08-11)

> **Status:** spec ratified · **Owner:** Platform · **Last
> updated:** 2026-04-21 · **Implementation gate:** L06-06
> (feature-flag service)

## Why this exists

We don't have a feature-flag service yet — L06-06 is the
finding tracking that work. But every feature-flag rollout in
the wild eventually hits the question "**who flipped this
yesterday at 3 a.m.?**". This runbook codifies the audit
contract BEFORE the service ships, so the implementation
team can build it right the first time.

## Contract

Whenever a `feature_flags` row is created, updated, or
deleted, the change MUST land in `audit_logs` as a structured
row:

```
event_domain        = 'feature_flag'
event_schema_version = 1   -- L18-09 dotted-domain naming
action              = 'feature_flag.created'
                    | 'feature_flag.toggled'
                    | 'feature_flag.rolled_out'
                    | 'feature_flag.archived'
                    | 'feature_flag.deleted'
actor_user_id       = <auth.uid() of the admin>
actor_kind          = 'user'  -- L01-49 actor_kind taxonomy
metadata            = jsonb {
  "flag_key":      "challenges_v2_streak_grace",
  "flag_id":       "<uuid>",
  "before_value":  <the old jsonb config>,
  "after_value":   <the new jsonb config>,
  "rollout_pct":   42,                          -- when applicable
  "scope":         "all" | "group:<uuid>" | "user:<uuid>",
  "reason":        "<free-text from the admin UI>"
}
```

Both `before_value` and `after_value` are mandatory on every
update so a future incident can answer "what was this set to
between 2026-05-04 14:30 and 2026-05-04 15:12?" with a single
`audit_logs` window query.

## Enforcement (database trigger)

When the `feature_flags` table is created, the migration MUST
ship a trigger that ENFORCES the audit-log write:

```sql
CREATE OR REPLACE FUNCTION fn_audit_feature_flag_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_action text;
BEGIN
  v_action := CASE TG_OP
    WHEN 'INSERT' THEN 'feature_flag.created'
    WHEN 'UPDATE' THEN 'feature_flag.toggled'
    WHEN 'DELETE' THEN 'feature_flag.deleted'
  END;

  INSERT INTO audit_logs (
    event_domain, event_schema_version, action,
    actor_user_id, actor_kind, metadata
  )
  VALUES (
    'feature_flag', 1, v_action,
    auth.uid(), 'user',
    jsonb_build_object(
      'flag_key',     COALESCE(NEW.flag_key, OLD.flag_key),
      'flag_id',      COALESCE(NEW.id, OLD.id),
      'before_value', CASE WHEN TG_OP IN ('UPDATE','DELETE')
                           THEN to_jsonb(OLD) END,
      'after_value',  CASE WHEN TG_OP IN ('INSERT','UPDATE')
                           THEN to_jsonb(NEW) END
    )
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_audit_feature_flag
AFTER INSERT OR UPDATE OR DELETE ON feature_flags
FOR EACH ROW EXECUTE FUNCTION fn_audit_feature_flag_change();
```

Why a trigger and not a service-layer audit? Because every
service-layer audit eventually has a code path that forgets to
log. A trigger guarantees no flip ever lands without a paper
trail.

## Counter-pressure for a shared "system" actor

When a flag is auto-rolled-back by an SLO breach (e.g. the
canary pipeline detects a regression and reverts the flag),
the trigger writes `actor_kind = 'system'` with
`actor_user_id = NULL` and the `metadata.reason` field gets
populated with the breach signal name (`"slo_burn_rate_p99"`).
This keeps the audit trail consistent with the actor taxonomy
introduced in L01-49.

## Read surface

The flag-history dashboard reads through an admin-only RPC:

```sql
CREATE FUNCTION fn_feature_flag_history(p_flag_key text, p_limit int DEFAULT 50)
RETURNS TABLE (...)
SECURITY DEFINER ...
```

Restricted to `platform_admins` membership (L13-08 pattern).

## Metrics emission (L06-09)

In addition to the audit log, every flag flip emits a
`metrics.feature_flag.toggle` counter with tags
`{ flag_key, scope, before_value_truthy, after_value_truthy }`
so the SRE dashboard graphs flag-flip activity over time.

## Testing requirements

When the L06-06 implementation lands, the migration MUST ship
with these regression tests in
`tools/test_l08_11_feature_flag_audit.ts`:

1. INSERT into `feature_flags` produces exactly one `audit_logs`
   row with `action = 'feature_flag.created'` and
   `before_value IS NULL`.
2. UPDATE produces exactly one row with both values.
3. DELETE produces exactly one row with `after_value IS NULL`.
4. RLS bypass attempt (anon client trying to mutate) is
   rejected at the policy layer; trigger never fires.
5. System rollback path (migration-level UPDATE without
   `auth.uid()`) writes `actor_kind = 'system'` and
   `actor_user_id = NULL`.

## Cross-references

* `docs/audit/findings/L08-11-feature-flags-quando-6-6-implementar-precisam-de.md`
* `docs/audit/findings/L06-06-feature-flag-service.md` — gating
  implementation
* L18-09 — audit_logs event_domain taxonomy
* L01-49 — actor_kind taxonomy
