# `coin_ledger` Tamper Evidence — Hash Chain Spec

**Status:** Specified (2026-04-21), implementation deferred to
Wave 3.
**Owner:** finance + security
**Related:** L01-41, L19-01 (`coin_ledger` partitioning),
L04-07 (PII redaction), L03-08 (custody invariants),
`docs/runbooks/CHARGEBACK_RUNBOOK.md`.

## The threat

A Supabase Dashboard user with `service_role` (today: ~3 staff +
the on-call rotation) could in principle execute:

```sql
UPDATE coin_ledger
   SET delta_coins = -99999
 WHERE id = '...uuid...';
```

…and the only forensic trail would be Supabase's audit logs
(retention: 90 days; not export-controlled by us). For a
financial system, **internal-fraud resistance** is a
must-have-by-Year-2 requirement, not a paranoid nice-to-have.

## Decision: per-row hash chain in a sibling table

We will **not** mutate `coin_ledger` itself (it is partitioned,
hot, and SECURITY DEFINER-written by the financial RPCs — adding
columns there expands surface area). Instead we add a sibling
write-once table:

```sql
CREATE TABLE public.coin_ledger_hash_chain (
  ledger_id      uuid PRIMARY KEY REFERENCES coin_ledger(id),
  prev_hash      bytea NOT NULL,
  row_hash       bytea NOT NULL,
  -- Materialized snapshot of the columns the hash covers, so
  -- recomputation does not need to read coin_ledger again
  -- (defence-in-depth: detects the case where coin_ledger was
  -- mutated AND the chain row was deleted to hide it — the
  -- snapshot here would still disagree with current
  -- coin_ledger and would prove tampering).
  snapshot       jsonb NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.coin_ledger_hash_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coin_ledger_hash_chain FORCE  ROW LEVEL SECURITY;

-- service_role only. No UPDATE / DELETE policy at all → table
-- is logically WORM (write-once read-many) for non-superusers.
CREATE POLICY chain_service_select ON public.coin_ledger_hash_chain
  FOR SELECT TO service_role USING (true);
CREATE POLICY chain_service_insert ON public.coin_ledger_hash_chain
  FOR INSERT TO service_role WITH CHECK (true);
```

`row_hash` is the SHA-256 of the canonical concatenation:

```
sha256(
  prev_hash ||
  ledger_id ||
  user_id ||
  delta_coins ||
  reason ||
  ref_id ||
  created_at_ms
)
```

`prev_hash` is the `row_hash` of the previous row in the same
**partition** (`coin_ledger` is monthly-partitioned; chain is
restarted at the partition boundary so each month's chain can
be verified independently and offline-archived once closed).

A `BEFORE INSERT` trigger on each `coin_ledger_YYYY_MM`
partition computes and inserts the corresponding chain row in
the same transaction.

## Why a sibling table, not a column

- **Backward compatibility.** No SECURITY DEFINER function
  that touches `coin_ledger` needs to know about the chain.
- **Independent retention.** Chain rows are written once and
  archived to cold storage at partition close (along with the
  partition itself). Verification can be done from S3.
- **Smaller blast radius.** A bug in the trigger only blocks
  inserts into the chain table; finance RPCs continue to write
  to `coin_ledger` and the chain catches up via a backfill job.
  (We accept the tradeoff that "chain catches up" means there
  is a window where chain entries lag — see "Verification
  cadence" below.)

## Verification cadence

- **Daily cron** (`verify-coin-ledger-chain`) walks the **last
  closed day** of every partition and recomputes `row_hash`
  forward, comparing to stored `row_hash`. Any mismatch:
  - Pages on-call with severity `critical`.
  - Inserts a row into `audit_logs` with
    `event_domain='security'`,
    `action='coin_ledger.tamper_detected'`,
    `metadata={ledger_id, expected_hash, stored_hash}`.
  - Triggers the `CHARGEBACK_RUNBOOK` containment workflow.
- **Quarterly** the closed partitions are signed (Ed25519
  signature over the last `row_hash` of the chain) and the
  signature is committed to a public Git repo
  (`omnirunner/ledger-attestations`) so that any third party
  can verify "as of YYYY-MM-DD, the closing chain head was X".

## Out of scope (deliberately)

- **Per-row signatures** by the writing service. Would require
  a service KMS, key rotation policy, and signing latency on
  every burn/mint. The chain head signature published quarterly
  buys 95% of the assurance at 5% of the operational cost.
- **Streaming WAL to a write-once external DB.** Considered;
  rejected because (a) it duplicates Supabase's own
  point-in-time-recovery backups, and (b) a malicious DBA
  could in principle disable the streaming. The Git-published
  chain head is harder to suppress.
- **`pgaudit`.** Considered; rejected because it logs to the
  same Postgres instance an attacker would already be on. The
  chain table approach forces the attacker to write a *valid*
  next chain row, which requires knowing the previous hash —
  trivially detectable when verification runs.

## Implementation phases

| Phase | Scope                                                        | When           |
|-------|--------------------------------------------------------------|----------------|
| 0     | This spec ratified (L01-41 closed as `correction_type: spec`) | 2026-04-21     |
| 1     | `coin_ledger_hash_chain` table + INSERT trigger on current partition | 2026-Q3 (Wave 3) |
| 2     | Daily verifier + alerting                                    | 2026-Q3        |
| 3     | Quarterly signing + public attestation repo                  | 2027-Q1 (Year 2) |

Phase 1 is small (~150 LOC + tests). The reason it is not in
this batch is that it touches the hot write path of every
financial RPC and needs its own dedicated PR + load test, not a
slot in a 50-finding sweep.

## See also

- `supabase/migrations/20260112000000_coin_ledger_partitioning.sql` (L19-01)
- `docs/runbooks/CHARGEBACK_RUNBOOK.md` (L03-13 / L03-20)
- `docs/runbooks/LEDGER_PII_REDACTION_RUNBOOK.md` (L04-07)
