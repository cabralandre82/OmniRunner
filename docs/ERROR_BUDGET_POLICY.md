# Error Budget Policy — Omni Runner

> **Audit ref:** L20-13
> **Version:** 1.0
> **Effective:** 2026-04-23
> **Owner:** SRE / Platform

This policy defines what happens when an SLO is at risk of being
missed. It exists because without consequences, SLOs become
aspirational and devolve into "wishful targets". The policy is
**enforced** by CI/CD automation, not by goodwill.

---

## 1. Definitions

- **SLO** — Service Level Objective; defined in
  `observability/slo.yaml` (OpenSLO 1.0 source of truth).
- **Error budget** — `(1 − SLO_target) × measurement_window`
  expressed in either time (e.g. minutes of downtime allowed per
  30 days) or events (e.g. errors allowed per 1M requests).
- **Burn rate** — fraction of monthly error budget consumed per
  unit time. Burn rate of `1.0` = on track to consume exactly
  100% of budget over the window. Burn rate of `2.0` = on track
  to consume **200%** (= violate SLO) by end of window.
- **Budget consumption** — cumulative percentage of the monthly
  error budget already spent.

---

## 2. Tiers and trigger thresholds

| Tier | Budget consumption | Burn rate | Action |
|---|---|---|---|
| **Green**  | < 50 %  | < 1.0  | Normal operations. Ship features. |
| **Yellow** | 50–80 % | 1.0–2.0 | Code freeze on **non-reliability** features. Reliability work prioritized. |
| **Orange** | 80–100 % | 2.0–4.0 | Hard code freeze. Only reliability/security/compliance fixes. Postmortems mandatory. |
| **Red**    | > 100 %  | > 4.0  | All non-fix deploys blocked. War-room. Rollback latest release if change-correlated. |

Tier is computed daily by the `error-budget-monitor` job (in
`tools/observability/error-budget.ts`). The latest tier is written
to `audit_logs.category='slo'` and exposed at
`/api/internal/error-budget`.

---

## 3. Enforcement

### 3.1 GitHub deploy gate

The reusable workflow `.github/workflows/error-budget-gate.yml`
exposes a single output `tier`. Production deploy workflows MUST
include:

```yaml
jobs:
  deploy:
    needs: [error-budget-gate]
    if: needs.error-budget-gate.outputs.tier != 'red'
    steps:
      ...
```

For Orange/Yellow tiers, the job auto-comments on the PR with a
required reviewer override (`@omnirunner/sre-leads`).

### 3.2 PR labels

PRs touching reliability paths (migrations, runbooks, CI guards)
get auto-label `reliability` and bypass the freeze.

### 3.3 Manual override

A human override is allowed only when **all** apply:

1. Approver is on `@omnirunner/sre-leads`.
2. The deploy is a security or LGPD/BCB compliance fix.
3. Override is recorded in `audit_logs.category='slo_override'`
   with `reason` text.

---

## 4. Replenishment

The error budget resets at the **start of each calendar month**
in the project's primary timezone (America/Sao_Paulo). Carry-over
is **not** allowed: a month with 0 budget consumed does not give
the next month 200%.

If a single incident consumes > 50% of monthly budget, the SRE
team **must** schedule a 5-Why postmortem within 5 business days
and link the corrective actions in `audit_logs`.

---

## 5. Incident classification

| Class | Definition | Example |
|---|---|---|
| **P1** | User-visible degradation of a critical path; pages SRE. | `/api/custody/withdraw` 5xx > 1 % for 5 min |
| **P2** | User-visible degradation of a non-critical path. | `/api/dashboard` 5xx > 5 % for 10 min |
| **P3** | Internal-only degradation; no customer impact yet. | DB replication lag > 30 s |
| **P4** | Anomaly without immediate impact. | Unusual log volume spike |

Each class consumes budget at a different weight (P1 = 4×, P2 =
2×, P3 = 1×, P4 = 0×) so that "lots of small flaps" does not
mask "one big outage".

---

## 6. Reporting

A monthly report is published at `docs/observability/reports/`
on the 1st of every month showing:

- Final tier of the previous month.
- Top 5 incidents by budget consumed.
- Action items still open.
- Trend vs prior 3 months.

The report is attached to the all-hands deck.

---

## 7. Cross-references

- `docs/observability/SLO.md` — SLO definitions (L20-02).
- `observability/slo.yaml` — machine-readable source.
- `docs/runbooks/LOGS_SEARCHABLE.md` — log retention (L20-10).
- L06-12 — `/api/readiness` for SLO probes.

---

## 8. Histórico

| Versão | Data | Mudança |
|---|---|---|
| 1.0 | 2026-04-23 | Política inicial — fecha L20-13. |
