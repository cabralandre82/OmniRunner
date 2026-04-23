/**
 * check-security-disclosure.ts
 *
 * L10-01 — CI guard for the public vulnerability disclosure policy.
 *
 * Fails closed if:
 *   1. `SECURITY.md` at repo root is missing.
 *   2. `portal/public/.well-known/security.txt` is missing.
 *   3. `security.txt` is missing required RFC 9116 fields.
 *   4. `security.txt` `Expires` is already in the past.
 *   5. `SECURITY.md` is missing the SLA table or the scope section.
 *   6. Disclosure runbook is missing or not cross-linked.
 *   7. Finding L10-01 is not cross-linked to the runbook.
 *
 * Usage: npm run audit:security-disclosure
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

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
    push(label, false, `file not found: ${path}`);
    return null;
  }
}

// 1. SECURITY.md at repo root
const securityMd = safeRead(resolve(ROOT, "SECURITY.md"), "SECURITY.md present");
if (securityMd) {
  push("SECURITY.md present", true);
  push(
    "SECURITY.md has reporting instructions",
    /security@omnirunner\.com/.test(securityMd),
  );
  push(
    "SECURITY.md declares scope (in + out)",
    /## Scope/.test(securityMd) &&
      /In scope/i.test(securityMd) &&
      /Out of scope/i.test(securityMd),
  );
  push(
    "SECURITY.md declares resolution SLA table",
    /Resolution SLAs?/i.test(securityMd) &&
      /Critical[\s\S]+?High[\s\S]+?Medium[\s\S]+?Low/.test(securityMd),
  );
  push(
    "SECURITY.md declares safe harbour",
    /[Ss]afe harbour|[Ss]afe harbor/.test(securityMd),
  );
  push(
    "SECURITY.md references the internal runbook",
    /SECURITY_DISCLOSURE_RUNBOOK\.md/.test(securityMd),
  );
  push(
    "SECURITY.md references security.txt",
    /security\.txt/.test(securityMd),
  );
  push(
    "SECURITY.md accepts PT + EN",
    /Portuguese/.test(securityMd) && /English/.test(securityMd),
  );
}

// 2. security.txt (RFC 9116)
const securityTxt = safeRead(
  resolve(ROOT, "portal/public/.well-known/security.txt"),
  "security.txt present",
);
if (securityTxt) {
  push("security.txt present", true);

  const required = ["Contact", "Expires", "Policy", "Canonical"];
  for (const field of required) {
    push(
      `security.txt declares ${field}`,
      new RegExp(`^${field}:`, "m").test(securityTxt),
    );
  }

  push(
    "security.txt declares Preferred-Languages",
    /^Preferred-Languages:\s*(pt|en)/m.test(securityTxt),
  );

  // Expires in the future (RFC 9116 §2.5.5)
  const expiresMatch = securityTxt.match(/^Expires:\s*(.+)$/m);
  if (expiresMatch) {
    const expiresAt = new Date(expiresMatch[1].trim());
    const valid = !Number.isNaN(expiresAt.getTime());
    push(
      "security.txt Expires is a valid date",
      valid,
      valid ? undefined : `unparseable: ${expiresMatch[1]}`,
    );
    if (valid) {
      const inFuture = expiresAt.getTime() > Date.now();
      push(
        "security.txt Expires is in the future (RFC 9116 §2.5.5)",
        inFuture,
        inFuture
          ? undefined
          : `expired at ${expiresAt.toISOString()} — rotate the file`,
      );
    }
  } else {
    push("security.txt Expires present", false, "no Expires: line found");
  }

  push(
    "security.txt Contact points at security@omnirunner.com",
    /Contact:\s*mailto:security@omnirunner\.com/.test(securityTxt),
  );

  push(
    "security.txt Canonical points at omnirunner.com",
    /Canonical:\s*https:\/\/omnirunner\.com\/\.well-known\/security\.txt/.test(
      securityTxt,
    ),
  );
}

// 3. Runbook
const runbook = safeRead(
  resolve(ROOT, "docs/runbooks/SECURITY_DISCLOSURE_RUNBOOK.md"),
  "runbook present",
);
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links the CI guard",
    /npm run audit:security-disclosure/.test(runbook),
  );
  push("runbook cross-links SECURITY.md", /SECURITY\.md/.test(runbook));
  push(
    "runbook cross-links L10-01",
    /L10-01/.test(runbook),
  );
  push(
    "runbook documents triage worksheet schema",
    /reporter:\s*<|received_at:\s*<|severity:\s*critical/.test(runbook),
  );
  push(
    "runbook documents the 14-day cadence",
    /(14 days|14-day|every 14)/.test(runbook),
  );
  push(
    "runbook includes hostile-reporter playbook",
    /[Hh]ostile|[Tt]hreatening to publish/.test(runbook),
  );
}

// 4. Finding cross-link sanity
const finding = safeRead(
  resolve(
    ROOT,
    "docs/audit/findings/L10-01-nenhum-bug-bounty-disclosure-policy.md",
  ),
  "finding present",
);
if (finding) {
  push(
    "finding references the runbook",
    /SECURITY_DISCLOSURE_RUNBOOK\.md/.test(finding),
  );
  push(
    "finding references SECURITY.md",
    /SECURITY\.md/.test(finding),
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
  `\n${results.length - failed}/${results.length} security-disclosure checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL10-01 invariants broken. See docs/runbooks/SECURITY_DISCLOSURE_RUNBOOK.md.",
  );
  process.exit(1);
}
