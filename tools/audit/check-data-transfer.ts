/**
 * check-data-transfer.ts — L04-10 CI guard.
 *
 * Enforces the cross-border data transfer policy:
 *   - document exists,
 *   - every processor is listed with region + legal basis,
 *   - Supabase row declares sa-east-1 (post-migration state),
 *   - PII minimisation for Sentry is referenced,
 *   - change procedure + decision log present,
 *   - cross-links to ROPA / BACKUP_POLICY / L04-09 preserved.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const POLICY = resolve(ROOT, "docs/compliance/DATA_TRANSFER.md");
const FINDING = resolve(
  ROOT,
  "docs/audit/findings/L04-10-transferencia-internacional-de-dados-supabase-us-sentry-us.md",
);

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const policy = safeRead(POLICY, "DATA_TRANSFER.md present");
if (policy) {
  push("DATA_TRANSFER.md present", true);

  const processors = [
    "Supabase",
    "Sentry",
    "Vercel",
    "Resend",
    "SendGrid",
    "Stripe",
    "Asaas",
    "Strava",
    "GitHub",
  ];
  for (const p of processors) {
    push(`processor ${p} listed`, new RegExp(`\\b${p}\\b`).test(policy));
  }

  push(
    "Supabase row declares sa-east-1 (post-migration)",
    /Supabase[\s\S]+?sa-east-1/.test(policy),
  );

  push(
    "Sentry row declares DPA + SCCs",
    /Sentry[\s\S]+?DPA[\s\S]+?SCCs/i.test(policy),
  );

  push(
    "Sentry PII minimisation cross-link (L20-05)",
    /L20-05/.test(policy) || /SENTRY_PII_REDACTION_RUNBOOK/.test(policy),
  );

  push(
    "LGPD Art. 33 legal bases mentioned",
    /Art\. 33/.test(policy),
  );
  push(
    "ANPD Resolução CD\\/ANPD SCCs referenced",
    /ANPD/.test(policy) && /SCCs/.test(policy),
  );

  push(
    "change procedure section present",
    /Change procedure|## 5\./.test(policy) &&
      /DPO delegate approval/.test(policy),
  );
  push(
    "decision log section present",
    /## 6\. Decision log/.test(policy) &&
      /- \*\*20\d\d-\d\d-\d\d\*\*/.test(policy),
  );
  push("BACKUP_POLICY cross-linked", /BACKUP_POLICY\.md/.test(policy));
  push("L04-09 runbook cross-linked", /L04-09/.test(policy));
  push(
    "ROPA cross-referenced",
    /ROPA\.md|Registro de Opera[cç][oõ]es/.test(policy),
  );
  push(
    "guard cross-link present",
    /npm run audit:data-transfer/.test(policy),
  );
}

const finding = safeRead(FINDING, "L04-10 finding present");
if (finding) {
  push(
    "finding references the policy",
    /docs\/compliance\/DATA_TRANSFER\.md/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} data-transfer checks passed.`);
if (failed > 0) {
  console.error("\nL04-10 invariants broken. See docs/compliance/DATA_TRANSFER.md.");
  process.exit(1);
}
