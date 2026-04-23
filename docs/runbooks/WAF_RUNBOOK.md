# WAF Runbook

**Scope:** `portal` (Next.js on Vercel) + public marketing surfaces.
**Finding:** [`L10-04`](../audit/findings/L10-04-sem-waf-explicito.md).
**Owner:** Platform Security.
**Review cadence:** quarterly, or after any security incident.

---

## 1. Layers

We operate three WAF layers, deliberately overlapping so a failure in
one does not open the others.

| Layer | Surface | What it does | Where it lives |
| --- | --- | --- | --- |
| **L1 — Edge (Vercel Firewall)** | All HTTP ingress | IP deny-list, country geo-fence, global rate limits, UA templates. Configured out-of-band via Vercel dashboard. | Vercel project → Security → Firewall rules |
| **L2 — In-process (portal middleware)** | `/` and `/api/*` on Next | Short-curated UA and path deny-lists; fail-closed 403; O(1) checks before auth/DB. | `portal/src/lib/security/waf.ts` + `portal/src/middleware.ts` |
| **L3 — Cloudflare (tier pago, contingency)** | DNS / DDoS | Held in reserve. If Vercel edge proves insufficient during incident, front the apex with Cloudflare and enable Managed Rulesets (OWASP Core, known-bot). | Not deployed in steady state; see §4. |

L2 exists so we can **assert invariants in CI** (`audit:waf`). L1 and
L3 are operational and live outside the repository.

## 2. L1 — Vercel Firewall baseline rules

The baseline rules MUST be present on the project at all times. If
they are removed or mutated they are to be restored from this
document (runbook-as-source-of-truth).

1. **UA deny: known scanners.** Block when
   `request.headers['user-agent']` matches
   `sqlmap|nikto|nmap|masscan|havij|acunetix|nessus|wpscan|hydra|dirbuster|gobuster|zgrab|zmap|shodan`
   (case-insensitive). Same list as L2 — kept in sync manually.
2. **Geo-fence — service role.** Block all ingress to
   `/api/custody/webhook` that does not come from Stripe or Asaas
   published IP ranges (BR/IE/US). Complements the in-process
   allow-list in `enforceWebhookIpAllowlist`.
3. **Geo-fence — platform admin.** Alert (do not block) on
   `/platform/*` requests from outside BR, PT, US. Platform admins
   travel; the alert routes to #security-ops.
4. **Global rate limit.** 100 req/10 s per IP on `/api/auth/*` and
   `/api/password-reset/*`. Complements in-process `ratelimit.ts`.
5. **Known-exploit path 410.** Respond 410 Gone to `/wp-admin/*`,
   `/phpmyadmin/*`, `/.env`, `/.git/*` — saves the L2 round-trip
   and signals "stop scanning" to polite bots.

Rule IDs in Vercel should carry the tag `L10-04` so routine export
/ diff can be compared against this runbook.

## 3. L2 — In-process WAF (`portal/src/lib/security/waf.ts`)

**Policy.** Allow-everything-then-deny. Only explicit matches block.

**Scope.**
- UA deny-list: `WAF_BLOCKED_UA_SUBSTRINGS` — 14 entries, case-
  insensitive `String.includes`.
- Path deny-list: `WAF_BLOCKED_PATH_FRAGMENTS` — 19 entries, case-
  sensitive `String.includes`.
- Allow-list override: `WAF_EXPLICIT_ALLOW_PATHS` — currently
  `/.well-known/security.txt` (required by RFC 9116 for L10-01).

**Wiring.** `portal/src/middleware.ts` calls `evaluateWaf` BEFORE
origin pinning and BEFORE CSRF. A block returns `403 Forbidden`
with `x-request-id` and the CSP/version headers still applied (via
`tagResponse`) so downstream telemetry is consistent.

**Observability.** Every block emits
`metrics.increment("waf.blocked", { rule })` with `rule ∈ {"ua",
"path"}`. Dashboards under Grafana → `portal.middleware.waf` alert
if blocks spike > 500/min (possible wide scan) or drop to zero for
> 24 h (possible bypass).

**Changing the lists.**
1. Open a PR that edits `waf.ts` and adds the corresponding test in
   `waf.test.ts`.
2. Update §2 above if the new rule belongs at the edge too.
3. `npm run audit:waf` must pass — it enforces list presence,
   middleware wiring, test coverage, and runbook cross-links.
4. Review + merge. Do NOT hot-patch the prod middleware — ship via
   regular release so the deny-list change lands in the same
   audit trail as the code.

## 4. L3 — Cloudflare escalation

Cloudflare is an **incident-response lever**, not a default layer.
Trigger it when:
- Vercel Firewall hits its rule-count ceiling during a live attack,
  or
- a sustained L7 DDoS exceeds what Vercel's shared-tenant capacity
  can absorb.

Steps (abridged):
1. Move DNS for `app.omnix.run` to Cloudflare (pre-staged zone file
   kept in `ops/cloudflare/app.omnix.run.zone`).
2. Enable Managed Rulesets:
   - OWASP Core Ruleset (high sensitivity).
   - Cloudflare Managed Ruleset — Rate Limiting pack.
   - Bot Fight Mode: "Moderate" at minimum, "Strict" during active
     attack.
3. Page-level rules:
   - `/api/custody/*` → Under Attack Mode (Security Level High).
   - `/api/auth/*` → 10 req/min/IP.
4. Keep Cloudflare in "proxy" mode (orange cloud) for at least
   7 days post-incident, then roll back via DNS switch.
5. File an ADR (Accepted) capturing what tripped the escalation
   and what permanent changes (if any) are needed.

## 5. Incident playbooks

### 5.1 Scanner flood (L1 + L2 blocking heavily)

Symptoms: `waf.blocked` > 5000/min. `/wp-admin`, `/xmlrpc.php`,
sqlmap UAs dominate.

Response:
1. Export offending IPs from Vercel Firewall → add to
   `portal.ip_denylist` (L-ticket, 72 h TTL).
2. Do NOT silence alerts — the block already cost effectively
   nothing; alerts are informational.
3. File a followup card only if a new rule should be added to
   §2/§3.

### 5.2 Legitimate traffic blocked

Symptoms: user reports `403 Forbidden` at `/`. `x-request-id` in
ticket. Telemetry shows `waf.blocked` match.

Response:
1. Pull the raw UA and path from request logs via `request-id`.
2. Identify which deny-list fragment matched. If the match is a
   **false positive** against a legitimate integration:
   a. Add a PR removing / scoping the rule (test first, then
      module).
   b. Patch Vercel Firewall rule (§2) to match.
3. If the match was correct, respond to the user with an
   explanation that the traffic pattern is flagged and point them
   at `SECURITY.md` for reporting.

### 5.3 Provider webhook 403 flood

Symptoms: Stripe/Asaas dashboards show delivery failures; our
metrics show `waf.blocked` under `rule=path` on
`/api/custody/webhook`.

Response:
1. Confirm provider IP ranges are still in the Vercel allow-list
   and in `enforceWebhookIpAllowlist` (L13-07).
2. Check the provider's recent IP-range announcements — update
   both allow-lists.
3. Do NOT relax `waf.ts` path matches. The webhook path is never
   blocked by the L2 path list; this symptom is always an L1 or
   L13-07 issue.

## 6. Audit & cross-links

- Policy baseline: this document.
- Code: `portal/src/lib/security/waf.ts`.
- Middleware wiring: `portal/src/middleware.ts` — `evaluateWaf`.
- Tests: `portal/src/lib/security/waf.test.ts`.
- CI guard: `tools/audit/check-waf.ts` (`npm run audit:waf`).
- Related findings:
  - [`L10-04`](../audit/findings/L10-04-sem-waf-explicito.md) — this item.
  - [`L10-01`](../audit/findings/L10-01-nenhum-bug-bounty-disclosure-policy.md) — requires
    `/.well-known/security.txt` to bypass WAF path list.
  - [`L10-05`](../audit/findings/L10-05-csp-hardened-1-31-mas-sem-report-uri.md) — CSP still
    applied to WAF 403 responses via `tagResponse`.
  - [`L13-07`](../audit/findings/L13-07-public-routes-contem-api-custody-webhook-sem-ip.md) —
    webhook IP allow-list complements §5.3.
- ADR record: none today. Escalation to Cloudflare (L3) requires a
  new ADR at escalation time.
