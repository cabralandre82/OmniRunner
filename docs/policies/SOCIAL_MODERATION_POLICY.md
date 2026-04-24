# Social Feed Moderation Policy

**Status:** Ratified (2026-04-21)
**Owner:** product + legal + trust&safety
**Regulatory ref:** Marco Civil da Internet Art. 19 (notice-and-
takedown), LGPD Art. 18 (data subject rights), STF ADI 5527.
**Related:** L05-14, L04-12 (admin masking), L21-10 (anti-cheat
public flagging).

## Question being answered

> "Posts, comments and reactions exist on the feed but there's
> no `reports` table, no moderation queue, and no auto-hide
> threshold. A coach who is being cyber-bullied by their own
> athletes has no in-app remediation path. Marco Civil Art. 19
> shields us only if we react diligently to a notice — without
> a report flow we can't argue diligence."

## Decision

**Per-content `social_reports` table + lightweight admin
moderation queue + auto-hide at 3 distinct reports.** No AI
content moderation in v1.

### Schema

```sql
CREATE TABLE public.social_reports (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_kind text NOT NULL CHECK (content_kind IN ('post','comment','reaction')),
  content_id   uuid NOT NULL,
  reporter_id  uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reason       text NOT NULL CHECK (length(reason) BETWEEN 10 AND 500),
  category     text NOT NULL CHECK (category IN (
    'harassment','spam','hate','sexual','violence',
    'misinformation','impersonation','privacy','other'
  )),
  evidence     jsonb,             -- screenshots URL list, optional
  created_at   timestamptz NOT NULL DEFAULT now(),
  resolved_at  timestamptz,
  resolved_by  uuid REFERENCES profiles(id),
  resolution   text CHECK (resolution IN ('upheld','dismissed','escalated_legal'))
);

CREATE UNIQUE INDEX uniq_report_one_per_user_per_content
  ON public.social_reports (content_kind, content_id, reporter_id)
  WHERE resolved_at IS NULL;

ALTER TABLE public.social_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_reports FORCE  ROW LEVEL SECURITY;

CREATE POLICY report_owner_insert ON public.social_reports
  FOR INSERT TO authenticated
  WITH CHECK (reporter_id = auth.uid());

CREATE POLICY report_owner_select ON public.social_reports
  FOR SELECT TO authenticated
  USING (reporter_id = auth.uid());

CREATE POLICY report_admin_all ON public.social_reports
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM profiles
     WHERE id = auth.uid() AND platform_role = 'admin'
  ));
```

### Auto-hide trigger

When the `count(distinct reporter_id) >= 3` for the same
`content_id` and none have been dismissed, set the post's
`hidden_at` automatically. The post is invisible to everyone
except the author and platform admins until a moderator either
dismisses or upholds the reports.

### Moderation queue UI

A new `/platform/moderation` screen (admin-only):

- Lists `social_reports WHERE resolved_at IS NULL` ordered by
  number of distinct reporters (descending) then `created_at`.
- Shows the original content (post / comment / reaction) +
  metadata (author, group, original timestamps).
- Action buttons: **Dismiss** (mark all reports for this content
  as `dismissed`, un-hide), **Uphold** (mark `upheld`, keep
  hidden, optionally suspend author for 24/72 h), **Escalate
  to legal** (page legal channel via DPO runbook L04-11).
- Every action is logged to `audit_logs` with
  `event_domain='trust_safety'`.

### Marco Civil Art. 19 mapping

- **Notice = `social_reports` row** with a clear reason
  string. The reporter's identity is recorded but masked from
  the reported author (we surface "an athlete in your group
  reported this" — never the name).
- **Diligence SLA**: every open report must be reviewed within
  72 hours (the threshold beyond which Marco Civil case law
  starts considering the platform negligent). Cron job
  `social-reports-sla-watch` pages on-call when the oldest
  unresolved report > 60 hours, giving 12 h buffer.
- **Judicial order takedown**: an admin sets
  `resolution='upheld'` AND posts a manual `audit_logs` row
  with `metadata.judicial_order_ref` to satisfy the discovery
  trail.

## Why no AI moderation in v1

We considered Perspective API / OpenAI Moderation. Rejected for
v1 because:

1. The user base is small (< 10k MAU) and concentrated in
   coaching groups, where the existing community moderation
   (coach + admin_master) catches 80% of issues before they
   surface to a feed report.
2. PII concerns: shipping every post to a third-party API is
   itself an LGPD data flow that needs DPIA + DPA negotiation.
3. False-positive cost is high in Portuguese (Brazilian slang
   trips most moderation models). Manual review with a clear
   queue is better than auto-actioning on bad signals.

When MAU > 50k or the queue p95 review time exceeds 24h, we
revisit. Re-evaluation triggers documented in
`docs/runbooks/MONOREPO_TOOLING_DECISION.md` style.

## Implementation status

- **Spec:** ratified (this doc).
- **`social_reports` table + RLS + indexes:** Wave-3 migration.
- **Auto-hide trigger:** Wave-3 migration.
- **`/platform/moderation` UI:** Wave-3.
- **SLA watch cron:** Wave-3, follows the L12-04 cron-sla-monitor
  pattern.
