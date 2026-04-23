/**
 * check-offline-sync.ts
 *
 * L07-03 — CI guard for the offline-sync pure-domain module.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const dir = "portal/src/lib/offline-sync";
const types  = safeRead(resolve(ROOT, `${dir}/types.ts`),  "types.ts present");
const queue  = safeRead(resolve(ROOT, `${dir}/queue.ts`),  "queue.ts present");
const policy = safeRead(resolve(ROOT, `${dir}/policy.ts`), "policy.ts present");
const index  = safeRead(resolve(ROOT, `${dir}/index.ts`),  "index.ts present");
const qtest  = safeRead(resolve(ROOT, `${dir}/queue.test.ts`), "queue.test.ts present");
const ptest  = safeRead(resolve(ROOT, `${dir}/policy.test.ts`), "policy.test.ts present");

if (types) {
  push(
    "types: SyncEntryStatus includes all 5 states",
    /pending[\s\S]{0,20}in_flight[\s\S]{0,20}done[\s\S]{0,20}failed[\s\S]{0,20}dead_letter/.test(types),
  );
  push(
    "types: SyncEntryKind includes attendance_checkin + workout_completion + pairing_response",
    /attendance_checkin/.test(types)
      && /workout_completion/.test(types)
      && /pairing_response/.test(types),
  );
  push(
    "types: SyncEntry has attempts counter",
    /attempts: number/.test(types),
  );
  push(
    "types: SyncEntry has deadLetteredAt",
    /deadLetteredAt\?: number/.test(types),
  );
  push(
    "types: DEFAULT_RETRY_POLICY baseDelayMs = 15_000",
    /baseDelayMs: 15_000/.test(types),
  );
  push(
    "types: DEFAULT_RETRY_POLICY maxDelayMs ≈ 6h",
    /maxDelayMs: 6 \* 60 \* 60 \* 1000/.test(types),
  );
  push(
    "types: DEFAULT_RETRY_POLICY maxAttempts = 12",
    /maxAttempts: 12/.test(types),
  );
  push(
    "types: DEFAULT_RETRY_POLICY jitterRatio = 0.2",
    /jitterRatio: 0\.2/.test(types),
  );
  push(
    "types: DEFAULT_OFFLINE_ALERT_POLICY thresholds match finding",
    /pendingCountThreshold: 5/.test(types)
      && /oldestPendingAgeMsThreshold: 3 \* 24 \* 60 \* 60 \* 1000/.test(types),
  );
  push(
    "types: OfflineAlert severity enum",
    /info[\s\S]{0,30}warning[\s\S]{0,30}critical/.test(types),
  );
  push(
    "types: OfflineAlert code union (OK / PENDING_THRESHOLD / AGE_THRESHOLD / DEAD_LETTERS_PRESENT / BOTH)",
    /OK/.test(types)
      && /PENDING_THRESHOLD/.test(types)
      && /AGE_THRESHOLD/.test(types)
      && /DEAD_LETTERS_PRESENT/.test(types)
      && /BOTH/.test(types),
  );
}

if (queue) {
  push(
    "queue: pure (no fs/net/http imports)",
    !/from ["']node:(fs|http|net|child_process)["']/.test(queue)
      && !/require\(["']node:(fs|http|net|child_process)["']\)/.test(queue),
  );
  push(
    "queue: exports enqueue + pickReady + markInFlight + ack",
    /export function enqueue\b/.test(queue)
      && /export function pickReady\b/.test(queue)
      && /export function markInFlight\b/.test(queue)
      && /export function ack\b/.test(queue),
  );
  push(
    "queue: exports requeueDeadLetter",
    /export function requeueDeadLetter\b/.test(queue),
  );
  push(
    "queue: exports purgeCompleted",
    /export function purgeCompleted\b/.test(queue),
  );
  push(
    "queue: exports snapshot",
    /export function snapshot\b/.test(queue),
  );
  push(
    "queue: enqueue is idempotent on id collision",
    /state\.entries\.some\(\(e\) => e\.id === input\.id\)[\s\S]{0,200}return state/.test(queue),
  );
  push(
    "queue: ack(ok) transitions to done and stamps completedAt",
    /input\.result\.ok[\s\S]{0,400}status: "done"[\s\S]{0,200}completedAt: input\.now/.test(queue),
  );
  push(
    "queue: ack non-retryable dead-letters immediately",
    /!input\.result\.retryable[\s\S]{0,400}status: "dead_letter"[\s\S]{0,200}deadLetteredAt: input\.now/.test(queue),
  );
  push(
    "queue: ack retryable dead-letters after maxAttempts",
    /attempts >= policy\.maxAttempts[\s\S]{0,400}status: "dead_letter"/.test(queue),
  );
  push(
    "queue: pickReady honours nextAttemptAt <= now",
    /e\.nextAttemptAt <= input\.now/.test(queue),
  );
  push(
    "queue: pickReady sorts by nextAttemptAt ascending",
    /sort\(\(a, b\) => a\.nextAttemptAt - b\.nextAttemptAt/.test(queue),
  );
  push(
    "queue: markInFlight rejects non-pending entries",
    /markInFlight[\s\S]{0,400}e\.status !== "pending"[\s\S]{0,200}return e/.test(queue),
  );
  push(
    "queue: requeueDeadLetter resets attempts and status",
    /requeueDeadLetter[\s\S]{0,800}attempts: 0[\s\S]{0,200}status: "pending"/.test(queue)
      || /requeueDeadLetter[\s\S]{0,800}status: "pending"[\s\S]{0,200}attempts: 0/.test(queue),
  );
  push(
    "queue: snapshot reports oldestPendingAgeMs",
    /oldestPendingAgeMs/.test(queue),
  );
}

if (policy) {
  push(
    "policy: computeNextAttemptAt is pure",
    !/Date\.now\(\)/.test(policy),
  );
  push(
    "policy: exponential = base * 2^(attempts-1)",
    /Math\.pow\(2, exponent\)/.test(policy)
      && /Math\.max\(0, attempts - 1\)/.test(policy),
  );
  push(
    "policy: capped at maxDelayMs",
    /Math\.min\(uncapped, policy\.maxDelayMs\)/.test(policy),
  );
  push(
    "policy: jitter is ± band, not one-sided",
    /random\(\) \* 2 - 1/.test(policy),
  );
  push(
    "policy: evaluateAlert escalates dead letter to critical",
    /deadLetterPresent[\s\S]{0,200}"critical"[\s\S]{0,200}"DEAD_LETTERS_PRESENT"/.test(policy),
  );
  push(
    "policy: evaluateAlert uses AGE_THRESHOLD + PENDING_THRESHOLD + BOTH",
    /"AGE_THRESHOLD"/.test(policy)
      && /"PENDING_THRESHOLD"/.test(policy)
      && /"BOTH"/.test(policy),
  );
}

if (index) {
  push(
    "index re-exports types + policy + queue",
    /from "\.\/types"/.test(index)
      && /from "\.\/policy"/.test(index)
      && /from "\.\/queue"/.test(index),
  );
}

if (qtest) {
  push(
    "queue.test: covers enqueue idempotency",
    /enqueue is idempotent on id collision/.test(qtest),
  );
  push(
    "queue.test: covers pickReady ordering + limit",
    /pickReady respects nextAttemptAt and limit/.test(qtest),
  );
  push(
    "queue.test: covers dead-letter after maxAttempts",
    /dead-letters after maxAttempts/.test(qtest),
  );
  push(
    "queue.test: covers non-retryable dead-letter path",
    /dead-letters immediately/.test(qtest),
  );
  push(
    "queue.test: covers requeueDeadLetter",
    /requeueDeadLetter returns entry to pending/.test(qtest),
  );
  push(
    "queue.test: covers evaluateAlert DEAD_LETTERS_PRESENT",
    /DEAD_LETTERS_PRESENT/.test(qtest),
  );
  push(
    "queue.test: covers evaluateAlert BOTH",
    /BOTH/.test(qtest),
  );
}

if (ptest) {
  push(
    "policy.test: covers exponential doubling",
    /doubles delay on each attempt/.test(ptest),
  );
  push(
    "policy.test: covers cap at maxDelayMs",
    /respects maxDelayMs cap/.test(ptest),
  );
  push(
    "policy.test: covers jitter band",
    /jitter stays within/.test(ptest),
  );
  push(
    "policy.test: asserts non-negative timestamp",
    /never returns a negative timestamp/.test(ptest),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L07-03-app-mobile-sem-modo-offline-robusto-para-corridas.md",
);
const finding = safeRead(findingPath, "L07-03 finding present");
if (finding) {
  push(
    "finding references offline-sync module",
    /portal\/src\/lib\/offline-sync/.test(finding),
  );
  push(
    "finding references queue + retry primitives",
    /DEFAULT_RETRY_POLICY/.test(finding) || /evaluateAlert/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} offline-sync checks passed.`,
);
if (failed > 0) {
  console.error("\nL07-03 invariants broken.");
  process.exit(1);
}
