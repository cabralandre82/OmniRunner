# Policy — Coin balance when an athlete leaves a group (L05-18)

> **Status:** ratified · **Owner:** Finance + Product · **Last updated:** 2026-04-21

## Decision

When an athlete is removed from a `coaching_group` (either by the
admin master or via self-leave), the OmniCoin balance issued by that
group's wallet is **forfeited back to the group** at the moment of
removal. Concretely:

```
removed_at:
  - DELETE FROM coaching_members WHERE user_id = ? AND group_id = ?
  - INSERT INTO coin_ledger
      (user_id, issuer_group_id, delta_coins, reason, ...)
    VALUES
      (athlete_user_id, group_id, -<coins_from_group>, 'membership.removed', ...)
  - UPDATE wallets SET balance_coins = balance_coins - <coins_from_group>
    WHERE user_id = athlete_user_id AND issuer_group_id = group_id
  - INSERT INTO coin_ledger
      (group_id_owner, delta_coins, reason)
    VALUES
      (group_id, +<coins_from_group>, 'membership.return.from_athlete')
```

Result: the athlete's wallet for that group is zeroed; the group
re-credits the freed supply and may reissue it.

## Why not "athlete keeps the coins"?

OmniCoins are **only** redeemable inside the issuing assessoria's
own challenges (see `docs/audit/findings/L04-07-OK` policy and the
README OmniCoin policy section). A coin held by an athlete who is no
longer a member has **no redemption path** — it cannot fund a
challenge, cannot be swapped (swap requires same-group counterparty,
L01-05), cannot be burned through clearing (clearing requires active
issuer relationship, L02-07/ADR-008). Holding the balance forever is
indistinguishable from forfeiting it from the athlete's perspective
but materially worse for accounting (orphan balances inflate
liabilities on the platform side).

## Why not "athlete cashes out at fair value"?

OmniCoins are **explicitly not currency**. Reading them as a
withdrawable asset would re-classify the platform as a payment
service (BCB Resolução 80/2021, requiring SCD/SEP licensing). The
ADR-008 stance is that coins are loyalty units pinned to the
issuer's challenges; converting on departure would invalidate that
classification.

## Operational rules

1. **Forfeiture is unilateral and immediate.** No grace period. The
   athlete is informed in the removal flow ("you will lose
   <X> coins"). There is no UI to "claim" coins after departure.
2. **Audit trail is mandatory.** Both ledger lines (`-<coins>` and
   `+<coins>`) MUST share the same `reason_code` namespace
   (`membership.removed` for the debit, `membership.return.from_athlete`
   for the credit) and carry a `reference_id` pointing at the
   `coaching_members` row that was removed. This is the only
   plausible audit pivot for "where did these coins go?".
3. **Re-joining does NOT restore coins.** The forfeit is permanent.
   If the athlete later rejoins the group, they start with a balance
   of 0 from that group and can earn anew. (We discussed a 30-day
   "limbo" period; rejected because it adds a cron job + edge cases
   without product traction.)
4. **Cross-group balances are unaffected.** An athlete in groups
   A and B who leaves A keeps every coin issued by B. Wallet rows
   are partitioned per `(user_id, issuer_group_id)` already
   (L01-04) so the forfeiture is naturally scoped.

## Implementation outline

The actual implementation will land in a follow-up migration
(`fn_handle_athlete_leaves`). It MUST:

* run inside the same transaction as the `coaching_members` delete
  so a partial failure doesn't strand half the state,
* update `wallets.balance_coins` AND `coin_ledger` atomically
  (`execute_burn_atomic` cannot be reused — it expects a clearing
  context — so we ship a sibling `execute_membership_forfeit_atomic`),
* be `SECURITY DEFINER` with explicit `SET search_path = public`,
  invoked by the existing `fn_remove_member` flow,
* log to `audit_logs` with `event_domain = 'membership'` and
  `event_schema_version = 1` (L18-09),
* emit a Sentry event when the forfeit value exceeds an
  alert threshold (default: 100k coins) so finance reviews unusual
  removals.

A unit-of-account zero-balance invariant is added to
`check_custody_invariants` (L03-08): no wallet row may have
`balance_coins < 0` after forfeit; pending-balance during the txn
is fine because the txn commits atomically.

## References

* `docs/audit/findings/L05-18-moeda-fica-em-wallet-do-atleta-que-saiu.md`
* `docs/audit/findings/L04-07-omni-coins-policy-only-challenges.md`
* `docs/adrs/ADR-008-coins-not-cessao-de-credito.md`
* L02-07 — clearing not cessão de crédito
* L03-08 — global custody conservation check
