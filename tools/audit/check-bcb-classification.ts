/**
 * check-bcb-classification.ts
 *
 * L09-01 — CI guard for the BCB classification ADR document,
 * ensuring canonical sections, legal references and cross-refs
 * with L22-02 (OmniCoin policy), L09-06 (Asaas at-rest), L09-07
 * (refund policy) are preserved.
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

const doc = safeRead(
  resolve(ROOT, "docs/compliance/BCB_CLASSIFICATION.md"),
  "ADR present",
);

if (doc) {
  // ── Canonical section headings ─────────────────────────────────────
  push("section §1 Executive summary present", /^## 1\. Executive summary/m.test(doc));
  push("section §2 Analysis of options present", /^## 2\. Analysis of options/m.test(doc));
  push("section §3 Operational invariants present", /^## 3\. Operational invariants/m.test(doc));
  push("section §4 Enforcement guard present", /^## 4\. Enforcement/m.test(doc));
  push("section §5 Review triggers present", /^## 5\. Review triggers/m.test(doc));
  push("section §6 Review log present", /^## 6\. Review log/m.test(doc));

  // ── Mandatory legal references ────────────────────────────────────
  push("cites Lei 7.492/1986 Art. 16", /Lei 7\.492\/1986[\s\S]{0,100}Art\. 16/.test(doc));
  push("cites BCB Circular 3.885/2018", /BCB Circular 3\.885\/2018/.test(doc));
  push("cites BCB Resolução 80/2021", /BCB Resolução 80\/2021|Res\. BCB 80\/2021/.test(doc));
  push("cites Lei 9.613/1998 (PLD/FT)", /Lei 9\.613\/1998/.test(doc));
  push("cites Lei Complementar 105/2001 (sigilo bancário)", /Lei Complementar 105\/2001/.test(doc));
  push(
    "cites Circular BCB 3.978/2020 (COAF reporting)",
    /Circular BCB 3\.978\/2020/.test(doc),
  );
  push(
    "cites CMN/BCB Circular 3.682/2013",
    /CMN\/BCB Circular 3\.682\/2013/.test(doc),
  );

  // ── Option analysis ────────────────────────────────────────────────
  push("Option A (marketing-credit) present", /Option A[\s\S]{0,400}vale-benefício|Option A — Restringir/i.test(doc));
  push("Option A explicitly REJECTED", /Option A[\s\S]{0,1200}REJEITADA/.test(doc));
  push("Option B (Asaas partnership) present", /Option B — Parceria com IP autorizada/.test(doc));
  push("Option B explicitly CHOSEN", /Option B[\s\S]{0,3000}ESCOLHIDA/.test(doc));
  push("Option C (BCB IP authorisation) present", /Option C — Obter autorização BCB como IP/.test(doc));
  push("Option C explicitly REJECTED for Wave 1-2", /Option C[\s\S]{0,600}REJEITADA/.test(doc));
  push("Option C captures R\\$ 2 M capital requirement", /R\$ 2 milhões|capital (social )?mínimo R\$ 2 mi/i.test(doc));
  push("Option C mentions 18–24 months timeline", /18[–-]24 meses/.test(doc));

  // ── Enforcement invariants ────────────────────────────────────────
  push(
    "invariant: BRL never emitted outside Asaas",
    /Jamais emita BRL fora da Asaas|BRL (diretamente|directly|passa por.*Asaas)/i.test(doc),
  );
  push(
    "invariant: OmniCoin is challenge-only (links L22-02)",
    /L22-02/.test(doc) && /challenge/i.test(doc),
  );
  push(
    "invariant: custody is mirror not source",
    /espelho contábil|espelho.*Asaas|mirror/i.test(doc),
  );
  push(
    "invariant: withdrawal paths enumerated and closed-ended",
    /Três e apenas três caminhos|three and only three/i.test(doc),
  );
  push(
    "invariant: SoD — Asaas owns PLD/FT + COAF, not Omni Runner",
    /Asaas[\s\S]{0,200}(PLD\/FT|COAF|compliance)/i.test(doc),
  );

  // ── Cross-refs (L09-01 is not an island) ──────────────────────────
  push(
    "cross-refs L09-06 (Asaas at-rest encryption)",
    /L09-06|l09_06/i.test(doc),
  );
  push(
    "cross-refs L09-07 (refund/chargeback SLA)",
    /L09-07|L23-09/i.test(doc),
  );
  push(
    "cross-refs L22-02 (OmniCoin challenge-only policy)",
    /L22-02/.test(doc),
  );

  // ── Chosen posture is unambiguous ─────────────────────────────────
  push(
    "posture section calls out Option B explicitly",
    /Posture (escolhida|chosen)[:\s\S]{0,80}Option B|Option B.*ESCOLHIDA/i.test(doc),
  );

  // ── Review triggers include 4 canonical cases ─────────────────────
  push(
    "review trigger: Asaas loses authorisation",
    /Asaas[\s\S]{0,120}(perde|suspende|loses).*(autorização|authorisation|authorization)/i.test(doc),
  );
  push(
    "review trigger: volume passes R$ 250 mi threshold",
    /R\$ 250 mi/.test(doc),
  );
  push(
    "review trigger: regulatory scope change",
    /BCB publica norma|regulatory (update|change|scope)/i.test(doc),
  );
  push(
    "review trigger: multi-country expansion",
    /expansão para ES\/MX\/AR|SBS|CNBV|BCRA/.test(doc),
  );

  // ── Review log table shape ────────────────────────────────────────
  push(
    "review log has an initial row dated 2026-04-21",
    /\| 2026-04-21[\s\S]{0,200}Option B/.test(doc),
  );

  // ── CI guard self-reference ───────────────────────────────────────
  push(
    "ADR references its own CI guard command",
    /npm run audit:bcb-classification/.test(doc),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Finding self-reference
// ────────────────────────────────────────────────────────────────────────────

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L09-01-modelo-de-coin-us-1-pode-ser-classificado.md",
);
const finding = safeRead(findingPath, "L09-01 finding present");
if (finding) {
  push(
    "finding references ADR",
    /docs\/compliance\/BCB_CLASSIFICATION\.md/.test(finding),
  );
  push(
    "finding references CI guard",
    /audit:bcb-classification|check-bcb-classification/.test(finding),
  );
  push(
    "finding names chosen posture (Option B / Asaas partnership)",
    /Option B|Asaas|parceria/i.test(finding),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Summary
// ────────────────────────────────────────────────────────────────────────────

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} bcb-classification checks passed.`,
);
if (failed > 0) {
  console.error("\nL09-01 invariants broken.");
  process.exit(1);
}
