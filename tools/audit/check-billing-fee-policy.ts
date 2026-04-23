/**
 * check-billing-fee-policy.ts — L09-08 CI guard.
 * Also verifies the ADR-0001 companion file is in place.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const MIG = resolve(
  ROOT,
  "supabase/migrations/20260421440000_l09_08_billing_fee_policy.sql",
);
const ADR = resolve(ROOT, "docs/adr/ADR-0001-provider-fee-ownership.md");
const ADR_INDEX = resolve(ROOT, "docs/adr/README.md");
const ADR_TEMPLATE = resolve(ROOT, "docs/adr/TEMPLATE.md");
const FINDING = resolve(
  ROOT,
  "docs/audit/findings/L09-08-provider-fee-usd-2-12-onus-ao-cliente.md",
);

interface R { name: string; ok: boolean; detail?: string; }
const results: R[] = [];
const push = (n: string, ok: boolean, d?: string) =>
  results.push({ name: n, ok, detail: d });
const safe = (p: string, l: string) => {
  try { return readFileSync(p, "utf8"); }
  catch { push(l, false, `missing: ${p}`); return null; }
};

const mig = safe(MIG, "migration present");
if (mig) {
  push("migration present", true);
  push(
    "billing_fee_policy singleton table declared",
    /CREATE TABLE IF NOT EXISTS public\.billing_fee_policy/.test(mig),
  );
  push(
    "id CHECK pins singleton (id = 1)",
    /PRIMARY KEY CHECK \(id = 1\)/.test(mig),
  );
  push(
    "gateway_passthrough column present with default true",
    /gateway_passthrough\s+boolean NOT NULL DEFAULT true/.test(mig),
  );
  push(
    "disclosure_template column NOT NULL",
    /disclosure_template\s+text NOT NULL DEFAULT/.test(mig),
  );
  push(
    "adr_reference default ADR-0001",
    /adr_reference\s+text NOT NULL DEFAULT 'ADR-0001'/.test(mig),
  );
  push(
    "RLS enabled + forced",
    /ENABLE ROW LEVEL SECURITY[\s\S]+?FORCE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "authenticated SELECT policy present",
    /POLICY billing_fee_policy_read[\s\S]+?FOR SELECT[\s\S]+?TO authenticated/.test(
      mig,
    ),
  );
  push(
    "service_role FOR ALL policy present",
    /POLICY billing_fee_policy_service[\s\S]+?FOR ALL[\s\S]+?TO service_role/.test(
      mig,
    ),
  );
  push(
    "seed row inserted",
    /INSERT INTO public\.billing_fee_policy \(id, gateway_passthrough/.test(mig),
  );
  push(
    "helper fn_billing_fee_policy() STABLE SECURITY DEFINER",
    /FUNCTION public\.fn_billing_fee_policy\(\)[\s\S]+?STABLE[\s\S]+?SECURITY DEFINER[\s\S]+?SET search_path = public, pg_catalog, pg_temp/.test(
      mig,
    ),
  );
  push(
    "helper grants EXECUTE to authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_billing_fee_policy\(\) TO authenticated, service_role/.test(
      mig,
    ),
  );
  push(
    "touch trigger bumps updated_at",
    /CREATE TRIGGER trg_billing_fee_policy_touch[\s\S]+?BEFORE UPDATE/.test(mig),
  );
  push(
    "self-test block present",
    /\$L09_08_selftest\$/.test(mig),
  );
  push(
    "self-test asserts default gateway_passthrough=true",
    /default gateway_passthrough must be true/.test(mig),
  );
  push(
    "self-test asserts CHECK blocks second row",
    /CHECK on id=1 should have rejected insert/.test(mig),
  );
  push(
    "self-test asserts touch trigger advances updated_at",
    /updated_at did not advance/.test(mig),
  );
}

const adr = safe(ADR, "ADR-0001 present");
if (adr) {
  push("ADR-0001 present", true);
  push("ADR-0001 Status: Accepted", /\*\*Status:\*\* Accepted/.test(adr));
  push("ADR-0001 declares Date", /\*\*Date:\*\*/.test(adr));
  push(
    "ADR-0001 references L09-08",
    /Related finding\(s\):[\s\S]*?L09-08/.test(adr),
  );
  push(
    "ADR-0001 names options considered (>=3)",
    /1\. \*\*Option A|Platform-absorbs|Pass-through|Configurable/.test(adr) &&
      (adr.match(/Option |Platform-absorbs|Pass-through|Configurable/g) ?? []).length >= 3,
  );
  push(
    "ADR-0001 Decision section names the chosen option",
    /## Decision[\s\S]+?Pass-through by default/.test(adr),
  );
  push(
    "ADR-0001 cross-links the migration",
    /20260421440000_l09_08_billing_fee_policy\.sql/.test(adr),
  );
  push(
    "ADR-0001 cross-links REFUND_POLICY",
    /REFUND_POLICY\.md/.test(adr),
  );
}

const adrIndex = safe(ADR_INDEX, "docs/adr/README.md present");
if (adrIndex) {
  push("docs/adr/README.md present", true);
  push(
    "README indexes ADR-0001",
    /\[ADR-0001[^\]]+\]\(\.\/ADR-0001-provider-fee-ownership\.md\)/.test(
      adrIndex,
    ),
  );
  push(
    "README declares Status values vocabulary",
    /Proposed[\s\S]+?Accepted[\s\S]+?Superseded/.test(adrIndex),
  );
}

const adrTemplate = safe(ADR_TEMPLATE, "docs/adr/TEMPLATE.md present");
if (adrTemplate) {
  push("docs/adr/TEMPLATE.md present", true);
  push(
    "TEMPLATE has required sections",
    /## Context[\s\S]+?## Options considered[\s\S]+?## Decision[\s\S]+?## Consequences/.test(
      adrTemplate,
    ),
  );
}

const finding = safe(FINDING, "L09-08 finding present");
if (finding) {
  push(
    "finding references ADR-0001",
    /ADR-0001-provider-fee-ownership\.md|ADR-0001/.test(finding),
  );
  push(
    "finding references migration",
    /20260421440000_l09_08_billing_fee_policy\.sql/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} billing-fee-policy checks passed.`);
if (failed > 0) {
  console.error("\nL09-08 invariants broken. See docs/adr/ADR-0001-provider-fee-ownership.md.");
  process.exit(1);
}
