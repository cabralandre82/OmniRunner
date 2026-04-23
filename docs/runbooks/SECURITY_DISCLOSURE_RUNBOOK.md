# Security disclosure runbook — L10-01

> **Internal** playbook for triaging vulnerability reports received
> through the channels declared in
> [`SECURITY.md`](../../SECURITY.md) and
> [`/.well-known/security.txt`](../../portal/public/.well-known/security.txt).
>
> **Finding:** [`L10-01`](../audit/findings/L10-01-nenhum-bug-bounty-disclosure-policy.md)
>
> **Guard CI:** `npm run audit:security-disclosure`

---

## 1. Intake channels

We watch **three** inboxes for reports. Anyone on the security
rotation must have access to all three.

1. `security@omnirunner.com` — primary email.
2. GitHub Security Advisories —
   <https://github.com/cabralandre82/OmniRunner/security/advisories>.
3. `#sec-triage` Slack channel — where the first two are forwarded
   automatically by the inbound integration (set up in the ops runbook;
   re-verify after each provider change).

Anything that arrives via a non-declared channel (DM to maintainer,
issue comment, tweet reply) should be **moved** to one of the above
within 24 hours — ask the reporter to resubmit via email and forward
their original message so we preserve context.

## 2. Acknowledgement (within 3 business days)

Reply from `security@omnirunner.com` with the template at
[`docs/runbooks/templates/vuln-acknowledgement.md`](./templates/)
— create if missing, it is a 3-paragraph thank-you + confirmation
that we received the report + promised SLA window for triage.

If the report contains credentials, PII of real users, or live
production payloads, immediately:

1. Remove the message from any shared channel (Slack `#sec-triage`
   unless the message has already been seen by the whole team).
2. Ask the reporter to **re-send** with redacted contents, keeping
   a minimal PoC only.
3. Rotate any credential / token that leaked. Treat as a **Medium**
   incident at minimum even if the report is determined out of scope.

## 3. Triage (within 10 business days)

Fill the triage worksheet (one per report) at
`docs/security/reports/<YYYY-MM-DD>-<slug>.md`:

```yaml
reporter: <name/handle/affiliation or "anonymous">
received_at: <ISO timestamp>
channel: email | gh-advisory | other
scope: in | out
severity: critical | high | medium | low | info
cvss_v31: <vector>
cvss_adjusted: <vector + rationale, +1 if custody/coin_ledger>
reproducible: yes | partially | no
affected_components: [list of files, endpoints, tables]
summary: <one paragraph>
```

Severity bumps we apply on top of raw CVSS:

- **+1** if the issue gives a way to move funds, modify
  `coin_ledger`, or bypass a custody / clearing invariant
  (L04, L05, L08, L10-08, L19 findings).
- **+1** if the issue exposes PII across tenants (cross-user
  leakage) vs single-user self-leak.
- **-1** if exploitation requires an already-compromised device
  **and** a compromised Supabase session token (double requirement).

## 4. Communication cadence

- **Every 14 days** until the report is closed, we send a status
  update from `security@omnirunner.com` with:
  - current state (triaging, implementing, rolling out, closed);
  - next expected milestone and when;
  - whether the reporter's help is still needed.
- If we need to extend the SLA, we tell the reporter **before** the
  deadline, not after.

## 5. Fix + disclosure

1. Land the fix under a private branch. Do **not** push to `master`
   before the fix is merged; commit messages travel to public CI.
2. For confirmed vulns, use a GitHub Security Advisory to coordinate
   CVE / GHSA issuance. Draft the advisory text before merging.
3. Merge on day-0 of disclosure. Publish advisory within 24 hours.
4. Credit the reporter in the advisory, unless they declined. Add
   them to `docs/security/hall-of-fame.md` (create on first credited
   report).

## 6. Bounty (current policy)

- Public bounty: **not yet**. L10-01 docs explain why.
- Retroactive rewards after the program launches: we track reporters
  in `docs/security/reports/` — when the program opens, revisit any
  High/Critical from the prior 12 months and process rewards manually.
- Non-monetary rewards we *can* give now: swag, OmniCoin credit for
  self/team, public credit, early access to a private bounty program
  when launched.

## 7. Playbooks

### 7.1 Reporter is hostile / threatening to publish before SLA

- Do not match hostility. Reply with: "We acknowledge your report.
  Our disclosure window is documented at SECURITY.md. We will share
  progress every 14 days until resolution."
- Escalate internally to CEO + Legal. Do not negotiate payment.
- If they publish early:
  - Treat as **zero-day in production**, full incident response.
  - Rotate keys, disable feature, notify users if data is at risk.
  - We still credit the reporter in the advisory (history wins; do
    not get into a "we'll punish them" spiral).

### 7.2 Report is actually out of scope

- Reply with the exact scope section from `SECURITY.md` quoted.
- Thank the reporter; offer OmniCoin swag even if out of scope, at
  team discretion.
- Close the triage worksheet with `severity: info`,
  `out_of_scope_reason: <one line>`.

### 7.3 Report is a duplicate

- Always link the original `docs/security/reports/*.md`.
- Credit **both** reporters if the duplicate is substantive; credit
  only the first if the duplicate is a copy-paste from public info
  (e.g., both reported a known CVE in a dependency).

### 7.4 Report comes with a PoC that already leaked / ran in prod

- Incident response mode. See `docs/runbooks/INCIDENT_RESPONSE.md`
  (if missing, treat this section as the skeleton).
- Do not delete the PoC from the mailbox — we need it for the RCA.
- Notify DPO within 24 hours if LGPD data subjects were affected
  (LGPD Art. 48).

### 7.5 The reporter wants to publish a blog post / talk

- Default stance: yes, after the fix is deployed and any customers
  with on-prem / private deployments have had 14 days to patch
  (we have none today; document will apply later).
- Offer to **review the draft** for accuracy and to provide a
  quote. Do not try to prevent publication — transparency wins.

## 8. What the CI guard enforces

`tools/audit/check-security-disclosure.ts` (`npm run audit:security-disclosure`)
fails closed if any of these regress:

- `SECURITY.md` is missing at repo root.
- `portal/public/.well-known/security.txt` is missing.
- `security.txt` is missing **Contact**, **Expires**, **Policy**,
  or **Canonical**.
- `security.txt` `Expires` is in the past (RFC 9116 requires a
  future value — stale files are worse than no file).
- `SECURITY.md` is missing the SLA table or the scope section.
- `SECURITY.md` is missing the runbook cross-link.

Run it locally before touching either file:

```bash
npm run audit:security-disclosure
```

## 9. Cross-links

- [`SECURITY.md`](../../SECURITY.md)
- [`/.well-known/security.txt`](../../portal/public/.well-known/security.txt)
- [`L10-01 finding`](../audit/findings/L10-01-nenhum-bug-bounty-disclosure-policy.md)
- [`L10-02 finding`](../audit/findings/L10-02-threat-model-formal-nao-documentado.md)
  (threat model — informs severity bumps)
- [`L10-03 finding`](../audit/findings/L10-03-service-role-key-distribuida-amplamente.md)
  (service-role key — most common incident cause we anticipate)
