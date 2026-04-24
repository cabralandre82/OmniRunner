# External financial audit policy (L09-12)

> **Status:** ratified · **Owner:** Finance + CRO · **Cadence:** annual from Year 2 · **Last updated:** 2026-04-21

## Decision

Engage an **independent external auditor** for a financial
audit starting **Year 2 of operation** (calendar year 2027,
covering fiscal year 2026). Audit scope: financial statements
+ custody-balance reconciliation + clearing-pipeline integrity.

This is **voluntary** at this stage of the company — Brazilian
law does not require statutory audit until we either (a)
classify as a financial institution under BCB Resolução
80/2021 (which we explicitly do NOT — see ADR-008 / L02-07
"clearing not cessão de crédito") or (b) cross the BRL 78 M
revenue threshold for the Lei das S.A. statutory audit
trigger. Both are well beyond our current trajectory.

We do this voluntarily because:

1. **Trust signal for assessorias.** When a coaching academy
   sees "audited by <Big 4>" on the public security page, the
   buying decision shortens. This is the highest-ROI item in
   the trust ladder — bigger than ISO 27001 or SOC 2.
2. **Custody reconciliation.** OmniCoins are off-chain
   liabilities to the issuing assessoria. An external auditor
   independently verifies that the supply minted = supply
   redeemed + supply forfeited + supply outstanding (the
   `check_custody_invariants` invariant from L03-08 +
   L03-15), and signs the report.
3. **Surface latent risks.** External audit teams ask
   different questions than internal lens audits. Even
   with our 23-lens internal cadence, we expect ~5-10 net new
   findings per engagement that internal review missed.

## Vendor shortlist

In order of preference for our scale (single-digit FTE,
< BRL 5 M revenue):

| Vendor                            | Rationale                                                    |
|-----------------------------------|---------------------------------------------------------------|
| BDO Brasil                        | Mid-market practice; fintech experience; reasonable fee      |
| Grant Thornton Brasil             | Similar profile; strong on multi-tenant SaaS                 |
| Mazars Brasil                     | LGPD + tech-stack experience; Europe-style reporting        |
| Big 4 (Deloitte / EY / KPMG / PwC)| Aspirational; revisit when revenue > BRL 10 M                |

All four mid-market firms quoted in 2025 H2 in the
BRL 80-150k range for a Year 2 first engagement. The Big 4
quotes started at BRL 350k — not justified yet.

## Scope

### In scope (Year 2)

* Financial statements (balance sheet + income statement +
  cash flow) per CPC ME / SCP standard.
* **Custody-balance reconciliation**:
  for each `coaching_group`, prove that
  `SUM(coin_ledger.delta_coins WHERE issuer_group_id = X)`
  == `SUM(wallets.balance_coins WHERE issuer_group_id = X)`.
  We hand the auditor a `SECURITY DEFINER` read-only RPC
  that runs `check_custody_invariants()` (L03-08) plus a
  per-group breakdown.
* **Clearing-pipeline integrity**: every settlement in
  `clearing_settlements` has a matching paired ledger entry
  (the L02-07 / ADR-008 invariant) and the dispute / refund
  path is traceable end-to-end.
* **Revenue recognition**: Stripe + MercadoPago + Asaas
  invoices reconcile to our `billing_events` and the
  monthly closing matches the platform-fee accrual policy
  ratified in L09-08.

### Out of scope (Year 2)

* SOC 2 Type II — separate engagement, evaluated in Year 3.
* PCI DSS — N/A; we use Stripe Hosted Checkout and never see
  PAN data (audit confirmation in scope, not full PCI cert).
* Penetration testing — handled separately by the L10-10
  pentest program.

## Pre-audit checklist (Year 1)

Before the Year 2 engagement opens, we MUST have:

1. **Audit-ready ledger.** `coin_ledger` is append-only with
   trigger enforcement (L01-49 actor_kind included). [DONE]
2. **Reconcile-ready RPCs.** `check_custody_invariants` and
   `check_clearing_invariants` callable read-only by the
   auditor's role with row-level visibility on every group.
   [DONE — L03-08 + L02-07]
3. **Domain audit log.** `audit_logs` has
   `event_domain + event_schema_version` so the auditor can
   reconstruct any single business event by domain pivot.
   [DONE — L18-09]
4. **Document repository.** `docs/policies/`,
   `docs/runbooks/`, `docs/legal/` and `docs/security/`
   directories with up-to-date policies. [DONE — Wave 1]
5. **Contract templates.** ToS + privacy policy + DPA + SCC
   for international transfers. [DONE — L04-15]
6. **External NDA.** Signed with each shortlist vendor
   before scoping calls.
7. **Audit dossier.** A single `docs/security/audit-dossier/`
   directory with the Year-1 close-of-books materials,
   ledger CSV exports, custody invariants results, and links
   to every relevant runbook. [TODO — Year 1 Q4]

Items 1-6 are complete or shipping in Wave 2. Item 7 is the
final gate before we sign the Year 2 engagement.

## Cost model

| Year   | Vendor                          | Estimate (BRL) | Notes                                        |
|--------|---------------------------------|----------------|----------------------------------------------|
| Year 1 | (none)                          | 0              | Pre-audit checklist + dossier preparation.   |
| Year 2 | BDO / Grant Thornton / Mazars   | 80k-150k       | First engagement. Includes scoping.          |
| Year 3 | Same vendor, possibly + SOC 2   | 120k-220k      | SOC 2 Type II evaluated.                     |
| Year 4 | Annual cadence stabilises       | 100k-180k      | Re-bid every 3 years to avoid lock-in.       |

Budget owner: CFO. Approval gate: annual budget cycle.

## Findings → audit workflow

External auditor findings land in `docs/audit/findings/` with:

* `id` — `L09-12-EA<YYYY>-NN`.
* `severity` — auditor's rating mapped to our 4-tier scale.
* `linked_prs` — fix commit hash.
* `note` — full reference to the engagement letter +
  management-letter PDF in
  `docs/security/audit-dossier/<YYYY>/`.

This integrates with the same SCORECARD.md tracking we use
for internal audit + pentest findings.

## Cross-references

* `docs/audit/findings/L09-12-auditoria-externa-financeira-inexistente.md`
* `docs/adrs/ADR-008-coins-not-cessao-de-credito.md`
* L02-07 — clearing not cessão de crédito
* L03-08 — global custody conservation invariant
* L18-09 — audit_logs domain taxonomy
* L09-08 — billing fee policy
* L10-10 — pentest program (sibling assurance activity)
