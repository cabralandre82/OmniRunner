/**
 * check-iof-calculator.ts
 *
 * L09-05 — CI guard for the pure-domain IOF primitive
 * (portal/src/lib/iof).  Enforces schema shape, kind coverage,
 * RIOF rate literals, test coverage and cross-references.
 */

import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  if (!existsSync(path)) { push(label, false, `missing: ${path}`); return null; }
  return readFileSync(path, "utf8");
}

const types = safeRead(
  resolve(ROOT, "portal/src/lib/iof/types.ts"),
  "types.ts present",
);
const calc = safeRead(
  resolve(ROOT, "portal/src/lib/iof/calculator.ts"),
  "calculator.ts present",
);
const index = safeRead(
  resolve(ROOT, "portal/src/lib/iof/index.ts"),
  "index.ts present",
);
const tests = safeRead(
  resolve(ROOT, "portal/src/lib/iof/calculator.test.ts"),
  "calculator.test.ts present",
);

// ────────────────────────────────────────────────────────────────────
// types.ts
// ────────────────────────────────────────────────────────────────────
if (types) {
  const kinds = [
    "credito_pj",
    "credito_pf",
    "cambio_brl_usd_out",
    "cambio_brl_usd_in",
    "seguro_vida",
    "seguro_saude",
    "seguro_outros",
    "titulo_privado",
    "derivativo",
    "cessao_credito_onerosa",
  ];
  for (const k of kinds) {
    push(`types — IofOperationKind includes "${k}"`, new RegExp(`"${k}"`).test(types));
  }

  push("types — IofInput is readonly", /interface IofInput/.test(types) && /readonly kind/.test(types));
  push("types — IofComputation is readonly", /interface IofComputation/.test(types) && /readonly effectiveRatePct/.test(types));
  push(
    "types — collectedBy union includes asaas/omni/none",
    /"asaas" \| "omni" \| "none"/.test(types),
  );
  push("types — IofInputError declared", /class IofInputError extends Error/.test(types));

  const errorCodes = [
    "non_positive_amount",
    "non_integer_amount",
    "unsupported_kind",
    "missing_taxpayer",
    "negative_duration",
    "invalid_operation_date",
  ];
  for (const c of errorCodes) {
    push(`types — IofInputError code "${c}"`, new RegExp(`"${c}"`).test(types));
  }

  const rateConstants: Record<string, string> = {
    IOF_CREDITO_ADICIONAL_PCT: "0.38",
    IOF_CREDITO_PF_DAILY_PCT: "0.0082",
    IOF_CREDITO_PJ_DAILY_PCT: "0.0041",
    IOF_CREDITO_MAX_DAYS: "365",
    IOF_CAMBIO_BRL_USD_OUT_PCT: "0.38",
    IOF_CAMBIO_BRL_USD_IN_PCT: "0.38",
    IOF_SEGURO_VIDA_PCT: "0.38",
    IOF_SEGURO_SAUDE_PCT: "2.38",
    IOF_SEGURO_OUTROS_PCT: "7.38",
    IOF_TITULO_PRIVADO_PCT: "1.5",
    IOF_DERIVATIVO_PCT: "0.005",
  };
  for (const [name, value] of Object.entries(rateConstants)) {
    const re = new RegExp(`${name}\\s*=\\s*${value.replace(".", "\\.")}`);
    push(`types — ${name} = ${value}`, re.test(types));
  }

  push("types — no Supabase import", !/from\s+["']@\/lib\/supabase/.test(types));
  push("types — no fetch / NextResponse", !/NextResponse|\bfetch\(/.test(types));
}

// ────────────────────────────────────────────────────────────────────
// calculator.ts
// ────────────────────────────────────────────────────────────────────
if (calc) {
  push("calc — exports computeIof", /export function computeIof/.test(calc));
  push("calc — uses banker's rounding helper", /bankerRound/.test(calc));

  const branchGuards = [
    "credito_pj",
    "credito_pf",
    "cambio_brl_usd_out",
    "cambio_brl_usd_in",
    "seguro_vida",
    "seguro_saude",
    "seguro_outros",
    "titulo_privado",
    "derivativo",
    "cessao_credito_onerosa",
  ];
  for (const b of branchGuards) {
    push(`calc — handles kind "${b}"`, new RegExp(`case "${b}"`).test(calc));
  }

  push(
    "calc — exhaustiveness guard via never",
    /const _never:\s*never/.test(calc),
  );
  push(
    "calc — validates non-integer principal",
    /Number\.isInteger\(/.test(calc) && /non_integer_amount/.test(calc),
  );
  push(
    "calc — validates non-positive principal",
    /non_positive_amount/.test(calc),
  );
  push(
    "calc — validates credito without taxpayer",
    /missing_taxpayer/.test(calc) && /credito_/.test(calc),
  );
  push(
    "calc — caps durationDays at IOF_CREDITO_MAX_DAYS",
    /Math\.min\(.*,\s*IOF_CREDITO_MAX_DAYS\s*\)/.test(calc),
  );
  push(
    "calc — cessão returns 0% and collectedBy=none",
    /kind:\s*"cessao_credito_onerosa"/.test(calc) &&
      /collectedBy:\s*"none"/.test(calc) &&
      /effectiveRatePct:\s*0/.test(calc),
  );
  push(
    "calc — cessão cites ADR-008",
    /ADR-008/.test(calc),
  );
  push(
    "calc — cessão cites CTN art. 63 I",
    /CTN art\. 63 I/.test(calc),
  );
  push(
    "calc — every strategy sets legalReference",
    (calc.match(/legalReference:/g) ?? []).length >= 6,
  );
  push(
    "calc — credit/câmbio point to Asaas as collector",
    /collectedBy:\s*"asaas"/.test(calc),
  );
  push(
    "calc — no Supabase / fetch / IO imports",
    !/from\s+["']@\/lib\/supabase/.test(calc) &&
      !/\bfetch\(/.test(calc) &&
      !/NextResponse|createClient/.test(calc),
  );
  push(
    "calc — Asaas reconciliation warning on credit",
    /mirrors the amount for reconciliation/i.test(calc) ||
      /Asaas.*reconciliação/i.test(calc),
  );
}

// ────────────────────────────────────────────────────────────────────
// index.ts
// ────────────────────────────────────────────────────────────────────
if (index) {
  push("index — re-exports types", /export \* from "\.\/types"/.test(index));
  push("index — exports computeIof from calculator", /computeIof/.test(index));
}

// ────────────────────────────────────────────────────────────────────
// tests
// ────────────────────────────────────────────────────────────────────
if (tests) {
  const testTopics = [
    "input validation",
    "câmbio",
    "crédito",
    "cessão de crédito onerosa",
    "seguros",
    "audit envelope shape",
  ];
  for (const topic of testTopics) {
    push(
      `tests — describes "${topic}"`,
      new RegExp(`describe\\(.*${topic.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`, "i").test(tests),
    );
  }
  push(
    "tests — verifies banker's rounding path",
    /banker/.test(tests),
  );
  push(
    "tests — verifies cap warning for credit > 365 days",
    /exceeds RIOF cap|durationDays=1000/.test(tests),
  );
  push(
    "tests — verifies cessão returns 0",
    /cessao_credito_onerosa/.test(tests) &&
      /effectiveRatePct\)?\.toBe\(0\)|iofAmountCents\)?\.toBe\(0\)/.test(tests),
  );
  push(
    "tests — asserts collectedBy=asaas on câmbio",
    /collectedBy.*asaas/i.test(tests),
  );
  push(
    "tests — asserts collectedBy=none on cessão",
    /collectedBy.*none/i.test(tests),
  );
  push(
    "tests — JSON serialisability round-trip",
    /JSON\.stringify/.test(tests),
  );
}

// ────────────────────────────────────────────────────────────────────
// Finding cross-reference
// ────────────────────────────────────────────────────────────────────
const finding = safeRead(
  resolve(ROOT, "docs/audit/findings/L09-05-iof-nao-recolhido-em-swap-inter-cliente.md"),
  "L09-05 finding present",
);
if (finding) {
  push(
    "finding — references portal/src/lib/iof",
    /portal\/src\/lib\/iof/.test(finding),
  );
  push(
    "finding — references CI guard",
    /audit:iof-calculator|check-iof-calculator/.test(finding),
  );
  push(
    "finding — references ADR-008 and L09-01",
    /ADR-008/.test(finding) && /L09-01/.test(finding),
  );
  push(
    "finding — status marked fixed",
    /status:\s*fixed/.test(finding),
  );
}

// ────────────────────────────────────────────────────────────────────
// Summary
// ────────────────────────────────────────────────────────────────────
let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} iof-calculator checks passed.`,
);
if (failed > 0) {
  console.error("\nL09-05 invariants broken.");
  process.exit(1);
}
