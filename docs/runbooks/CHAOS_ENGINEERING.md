# Chaos Engineering — Cadence and Playbook

**Status:** Ratified (2026-04-21)
**Owner:** SRE + platform
**Related:** L20-09, L20-08 (SLOs), L20-13 (error budget),
L06-04 (cron health), L06-05 (Edge retry wrapper),
L01-12 (Redis fail_closed policy).

## Question being answered

> "We have rate limits, retries, fail-open / fail-closed
> policies — but no test that they actually work end-to-end
> when an upstream goes down. How do we get GameDay reps
> without an actual incident?"

## Decision

**Quarterly chaos exercises** with a fixed scenario rotation,
in the staging environment first, then in production with a
small blast-radius window. No paid chaos tooling (Gremlin,
Chaos Mesh) — bash + Supabase admin + Vercel project flags
are enough at our scale.

### Cadence

- **Q1, Q4** (Jan / Oct) — staging-only.
- **Q2, Q3** (Apr / Jul) — production, scheduled in a
  pre-announced 1-hour window during low-traffic Sunday
  morning (08:00-09:00 BRT, < 5% of weekly load per
  `business-health` data).

Six exercises per year total (3 staging + 3 prod). Each
exercise pages on-call as the "incident commander" for the
session.

### Scenario rotation

| # | Scenario                                            | Steady-state hypothesis we're verifying |
|---|-----------------------------------------------------|----------------------------------------|
| 1 | Disable Upstash Redis (block at the network level)  | Rate-limited routes fail-closed (L01-12); non-rate-limited routes keep working; alert fires within 5 min. |
| 2 | Kill Supabase Edge Function `send-push` mid-execution | Retry wrapper (L06-05) replays from idempotency boundary; user receives push within 10 min. |
| 3 | Force Postgres lag > 30 s on read replica           | Read paths still 200 from primary; staleness banner shows in admin UI; no double-charge / double-mint. |
| 4 | Block Resend (transactional email)                  | Email-dependent flows (NF-e, password reset, parental consent) queue + retry; alert fires; no data loss. |
| 5 | Flood `/api/coins/distribute` with 100 RPS for 60 s | Per-group rate limit holds at 5/min; non-distribute routes p95 latency stays < 500 ms. |
| 6 | Stripe webhook 503 for 5 min                        | Idempotency layer L18-02 deduplicates retries; payment state reconciles within 10 min. |

We rotate through the 6 over a year; each scenario gets one
staging run + one prod run per year.

### Pre-flight checklist (must all be ✓ before starting)

- [ ] Error budget for the affected SLO has > 50% remaining
      this month (do NOT run chaos when we're already burning
      down).
- [ ] No active incident or scheduled maintenance.
- [ ] On-call has acknowledged the calendar invite for the
      window.
- [ ] PagerDuty escalation muted for the chosen scenario's
      alert rules (so we don't double-page).
- [ ] Pre-snapshot of business-health metrics + Sentry rate
      saved to `docs/sre/chaos-runs/<date>.md`.
- [ ] Rollback path tested in staging the week prior.

### During the exercise

- Inject the failure (typically a single command — `redis-cli
  CLIENT KILL ID *` or `vercel env rm UPSTASH_URL`).
- Watch the dashboard. Note the time-to-detect (TTD) — the
  gap between injection and the first alert firing.
- Note the time-to-mitigate (TTM) — the gap from injection to
  the system reaching steady state on the degraded path.
- Don't fix anything during the exercise. Note what you would
  have done and pull it into the post-mortem.

### Post-flight (within 48 h)

- Write a 1-page post-mortem in
  `docs/sre/chaos-runs/<date>.md` with:
  - Hypothesis being tested.
  - TTD, TTM, blast radius (number of users affected if any).
  - What broke that we didn't expect.
  - Action items with owners and due dates.
- File any non-trivial action items as audit findings or
  Linear tickets (don't let them rot in the post-mortem doc).

### Hard stop conditions (abort the exercise immediately)

- Any P1 alert NOT related to the injected failure.
- Custody / clearing invariants (`check_custody_invariants`)
  failing.
- More than 50 users hit by the failure (we estimate from the
  business-health throughput at the time of injection).

### Why no Gremlin / Chaos Mesh

Considered. Rejected for v1:

1. **Cost.** Gremlin starts at USD 1k/month for the smallest
   team plan. We're targeting 6 exercises/year — manual
   bash + Vercel CLI is < USD 0.
2. **Vercel-Postgres-Edge architecture** is mostly managed —
   we don't have a Kubernetes cluster for Chaos Mesh to
   misbehave inside of. The chaos surfaces we care about
   (Redis, Postgres, Edge, third-party APIs) are best
   exercised by upstream-side blocks, not pod kills.
3. **Operational hygiene matters more than tool
   sophistication** at our scale. A spreadsheet + a discord
   thread is enough to coordinate a 6-person team.

Re-evaluate when: team > 15 engineers, or when we run our own
infra for any production component (e.g. self-hosted Postgres
read replicas).

## See also

- `docs/sre/SRE_RUNBOOK.md` (general)
- `docs/runbooks/EDGE_RETRY_WRAPPER_RUNBOOK.md` (L06-05)
- `docs/runbooks/RATE_LIMIT_FAIL_CLOSED.md` (L01-12)
- `docs/observability/ALERT_POLICY.md`
