/**
 * check-threat-model.ts
 *
 * L10-02 — CI guard for the formal threat model.
 *
 * Fails closed if:
 *   1. THREAT_MODEL.md is missing or empty.
 *   2. STRIDE walkthrough per trust boundary regresses.
 *   3. Review cadence / owner section disappears.
 *   4. Abuse cases section shrinks below 5 stories.
 *   5. Cross-link to SECURITY.md / L10-01 is lost.
 *
 * Usage: npm run audit:threat-model
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const PATH = resolve(ROOT, "docs/security/THREAT_MODEL.md");
const FINDING = resolve(
  ROOT,
  "docs/audit/findings/L10-02-threat-model-formal-nao-documentado.md",
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

let doc: string;
try {
  doc = readFileSync(PATH, "utf8");
} catch {
  push("THREAT_MODEL.md present", false, `missing at ${PATH}`);
  printAndExit();
  process.exit(1);
}
push("THREAT_MODEL.md present", true);

// Trust boundaries (6)
for (const tb of ["TB1", "TB2", "TB3", "TB4", "TB5", "TB6"]) {
  push(`declares ${tb} trust boundary`, new RegExp(`\\b${tb}\\b`).test(doc));
}

// STRIDE — all 6 letters with table rows
const stride = /Threat \| STRIDE \| Mitigation \| Status/;
push("STRIDE table header present", stride.test(doc));
for (const letter of ["S", "T", "R", "I", "D", "E"]) {
  push(
    `STRIDE table uses ${letter} category`,
    new RegExp(`\\| ${letter}(,|\\s*\\|)`).test(doc) ||
      new RegExp(`\\| [A-Z, ]*${letter}(,|\\s*\\|)`).test(doc),
  );
}

// DFD / actors / assets
push("Data-flow diagram (textual) present", /Data-flow diagram|\[A\] Strava API/.test(doc));
push("Actors section present", /### 2\.1 Actors/.test(doc));
push("Trust boundaries subsection present", /Trust boundaries/i.test(doc));
push("Assets ranked", /## 3\. Assets/.test(doc));
push("OmniCoin ledger listed as top asset", /OmniCoin ledger/.test(doc));
push(
  "Service-role key listed as asset",
  /Service-role key/.test(doc) || /service-role key/.test(doc),
);

// Abuse cases — at least 5
const abuseMatch = doc.match(/## 7\. Abuse cases[\s\S]+?(?=\n## )/);
if (abuseMatch) {
  const numberedStories = (abuseMatch[0].match(/\n\d+\. \*\*"/g) ?? []).length;
  push(
    "abuse-cases section lists >= 5 stories",
    numberedStories >= 5,
    `found ${numberedStories}`,
  );
} else {
  push("abuse-cases section lists >= 5 stories", false, "section missing");
}

// Severity bumps
push(
  "severity bump rules declared (+1 funds)",
  /\+1[\s\S]+?coin_ledger/.test(doc),
);
push(
  "severity bump rules declared (cross-tenant)",
  /\+1[\s\S]+?tenant/i.test(doc),
);

// Review cadence + owner
push(
  "review cadence documented (90 days OR major feature)",
  /90 days/.test(doc) && /major feature/i.test(doc),
);
push(
  "review history section present",
  /## 10\. Review history/.test(doc),
);
push(
  "review history has at least one dated entry",
  /- `20\d\d-\d\d-\d\d`/.test(doc),
);
push("owner declared", /\*\*Owner:\*\*/.test(doc));

// Guard cross-link
push(
  "THREAT_MODEL.md mentions the CI guard",
  /npm run audit:threat-model/.test(doc),
);

// Strava-only scope caveat must be acknowledged (post-Sprint 25)
push(
  "Strava-only scope note present (Sprint 25.0.0 delta)",
  /Strava-only/.test(doc) && /Sprint 25\.0\.0/.test(doc),
);

// SECURITY.md cross-link
push(
  "SECURITY.md cross-linked",
  /SECURITY\.md/.test(doc),
);

// L10-01 cross-link
push("L10-01 cross-linked", /L10-01/.test(doc));
push("L10-08 cross-linked", /L10-08/.test(doc));

// Finding references the threat model
try {
  const finding = readFileSync(FINDING, "utf8");
  push(
    "L10-02 finding references THREAT_MODEL.md",
    /docs\/security\/THREAT_MODEL\.md/.test(finding),
  );
} catch {
  push("L10-02 finding present", false, `missing at ${FINDING}`);
}

printAndExit();

function printAndExit(): void {
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
    `\n${results.length - failed}/${results.length} threat-model checks passed.`,
  );
  if (failed > 0) {
    console.error(
      "\nL10-02 invariants broken. See docs/security/THREAT_MODEL.md §9.",
    );
    process.exit(1);
  }
}
