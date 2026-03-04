# Rollback Runbook

## 1. Rollback Last Migration

```sql
-- 1. Identify the last applied migration
SELECT * FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 5;

-- 2. Manually reverse the migration DDL (Supabase does not support automatic down migrations).
--    Open the migration file in supabase/migrations/ and write the inverse SQL.
--    Example: if the migration added a column, DROP it; if it created an index, DROP INDEX, etc.

-- 3. After reversing, delete the migration record so it won't be considered applied:
DELETE FROM supabase_migrations.schema_migrations WHERE version = '<MIGRATION_VERSION>';
```

> Always test rollback SQL in a staging branch (`supabase db reset` on a branch) before running in production.

## 2. Point-in-Time Recovery (PITR)

1. Go to **Supabase Dashboard → Project → Database → Backups**.
2. Select **Point in Time** tab.
3. Choose the target timestamp (before the incident).
4. Click **Restore** — this creates a new project with the restored state.
5. Verify data integrity, then swap DNS / connection strings.

> PITR is available on Pro plan and above. Recovery window is up to 7 days.

## 3. Feature Flag Emergency Procedures

Feature flags are stored in `feature_flags` table.

```sql
-- Disable a feature immediately
UPDATE feature_flags SET enabled = false WHERE key = '<FLAG_NAME>';

-- Disable all flags at once (emergency kill switch)
UPDATE feature_flags SET enabled = false;
```

In the Flutter app, `FeatureFlags` class polls on startup. Users need to restart the app to pick up changes (or wait for next background refresh cycle).

In the Portal, flags are checked server-side on each request — changes take effect immediately.

## 4. Edge Function Rollback

```bash
# Redeploy the previous version from git
git checkout <PREVIOUS_COMMIT> -- supabase/functions/<function-name>/
supabase functions deploy <function-name> --project-ref <REF>

# Or disable a function entirely via dashboard:
# Dashboard → Edge Functions → select function → Settings → Disable
```

## 5. Portal (Next.js) Rollback

```bash
# If deployed via Vercel: revert to previous deployment in Vercel dashboard
# Deployments → find last stable build → "..." menu → Promote to Production

# If self-hosted:
git checkout <PREVIOUS_COMMIT>
npm run build && pm2 restart portal
```

## 6. Emergency Contacts

| Role              | Contact                          |
|-------------------|----------------------------------|
| DB Admin          | Check internal team directory    |
| Supabase Support  | support@supabase.io / Dashboard  |
| On-call Engineer  | Check PagerDuty / internal wiki  |

## 7. Incident Checklist

1. **Assess** — identify blast radius (which users/features affected).
2. **Mitigate** — disable feature flag or rollback migration.
3. **Communicate** — notify affected users if needed.
4. **Fix** — deploy corrected code/migration.
5. **Post-mortem** — document root cause and prevention steps.
