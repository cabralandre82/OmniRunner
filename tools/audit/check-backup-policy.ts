/**
 * check-backup-policy.ts
 *
 * L04-08 — CI guard for the backup / restore policy.
 *
 * Fails closed if:
 *   1. docs/compliance/BACKUP_POLICY.md missing.
 *   2. Retention matrix regresses (PITR / daily / weekly / monthly
 *      windows all required).
 *   3. LGPD erasure section disappears or loses the "30-day block"
 *      rule (we commit to blocking restore for 30 days after an
 *      erasure request).
 *   4. Staging obfuscation rules regress.
 *   5. Restore runbook missing or not cross-linked.
 *   6. Finding frontmatter does not reference the policy.
 *
 * Usage: npm run audit:backup-policy
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const POLICY = resolve(ROOT, "docs/compliance/BACKUP_POLICY.md");
const RUNBOOK = resolve(ROOT, "docs/runbooks/BACKUP_RESTORE_RUNBOOK.md");
const FINDING = resolve(
  ROOT,
  "docs/audit/findings/L04-08-backups-supabase-sem-politica-de-retencao-documentada.md",
);

interface CheckResult {
  name: string;
  ok: boolean;
  detail?: string;
}

const results: CheckResult[] = [];
function push(name: string, ok: boolean, detail?: string) {
  results.push({ name, ok, detail });
}

function safeRead(path: string, label: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    push(label, false, `missing: ${path}`);
    return null;
  }
}

const policy = safeRead(POLICY, "BACKUP_POLICY.md present");
if (policy) {
  push("BACKUP_POLICY.md present", true);

  push(
    "declares PITR window (7 days)",
    /PITR[\s\S]+?7 days/i.test(policy),
  );
  push(
    "declares daily snapshot window (14 days)",
    /Daily snapshots[\s\S]+?14 days/i.test(policy),
  );
  push(
    "declares weekly snapshot window (30 days)",
    /Weekly snapshots[\s\S]+?30 days/i.test(policy),
  );
  push(
    "declares monthly snapshot window (180 days)",
    /Monthly snapshots[\s\S]+?180 days/i.test(policy),
  );

  push(
    "LGPD erasure section present",
    /LGPD Art\. 18[\s\S]+?erasure/i.test(policy),
  );
  push(
    "declares 30-day restore block after erasure",
    /block restore[\s\S]+?30 days/i.test(policy),
  );
  push(
    "declares worst-case 180-day residual exposure",
    /180 days/.test(policy) && /residual|worst-case/i.test(policy),
  );

  push(
    "staging obfuscation rules declared",
    /ofuscad|obfuscat/i.test(policy) &&
      /strava/i.test(policy) &&
      /instagram/i.test(policy),
  );

  push(
    "quarterly restore drill cadence declared",
    /quarter|trimestr/i.test(policy),
  );

  push(
    "cross-border region declared (sa-east-1)",
    /sa-east-1/.test(policy),
  );

  push(
    "policy references L04-10 (cross-border transfer)",
    /L04-10/.test(policy),
  );
  push(
    "policy references L08-08 (per-table retention)",
    /L08-08/.test(policy),
  );
  push(
    "policy references L04-09 (third-party revocation)",
    /L04-09/.test(policy),
  );
  push(
    "policy cross-links the restore runbook",
    /BACKUP_RESTORE_RUNBOOK\.md/.test(policy),
  );
  push(
    "policy cross-links the CI guard",
    /npm run audit:backup-policy/.test(policy),
  );
}

const runbook = safeRead(RUNBOOK, "restore runbook present");
if (runbook) {
  push("restore runbook present", true);
  push(
    "runbook documents PITR procedure",
    /PITR restore/i.test(runbook),
  );
  push(
    "runbook documents snapshot restore procedure",
    /Snapshot restore/i.test(runbook),
  );
  push(
    "runbook documents post-restore PII scrubbing",
    /PII scrubbing/i.test(runbook) &&
      /DELETE FROM auth\.users/i.test(runbook),
  );
  push(
    "runbook documents staging obfuscation",
    /staging/i.test(runbook) && /UPDATE auth\.users/i.test(runbook),
  );
  push(
    "runbook documents quarterly drill",
    /quarterly|Qx/i.test(runbook),
  );
  push(
    "runbook cross-links the policy",
    /BACKUP_POLICY\.md/.test(runbook),
  );
  push(
    "runbook cross-links L10-08 (append-only)",
    /L10-08/.test(runbook),
  );
}

const finding = safeRead(FINDING, "L04-08 finding present");
if (finding) {
  push(
    "finding references the policy",
    /docs\/compliance\/BACKUP_POLICY\.md/.test(finding),
  );
  push(
    "finding references the restore runbook",
    /BACKUP_RESTORE_RUNBOOK\.md/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) {
    console.log(`[OK]   ${r.name}`);
  } else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}

console.log(
  `\n${results.length - failed}/${results.length} backup-policy checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL04-08 invariants broken. See docs/compliance/BACKUP_POLICY.md.",
  );
  process.exit(1);
}
