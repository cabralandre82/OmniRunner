/**
 * check-waf.ts
 *
 * L10-04 — CI guard for the in-process WAF (defence-in-depth on top
 * of Vercel's edge firewall).
 *
 * Invariants:
 *   1. `portal/src/lib/security/waf.ts` exists and exports the three
 *      frozen lists (`WAF_BLOCKED_UA_SUBSTRINGS`,
 *      `WAF_BLOCKED_PATH_FRAGMENTS`, `WAF_EXPLICIT_ALLOW_PATHS`) plus
 *      the pure verdict helpers (`shouldBlockUserAgent`,
 *      `shouldBlockPath`, `evaluateWaf`).
 *   2. The module declares the default-allow posture (allow-list of
 *      known-good paths overrides the path deny-list).
 *   3. `portal/src/middleware.ts` imports and calls `evaluateWaf`
 *      **before** origin pinning and CSRF checks.
 *   4. A unit-test file lives next to the module.
 *   5. The WAF runbook `docs/runbooks/WAF_RUNBOOK.md` exists and
 *      enumerates the three layers (Edge/In-process/Cloudflare) +
 *      incident playbooks.
 *   6. Finding `L10-04` is cross-linked to the module, the middleware
 *      wiring, the tests, and the runbook.
 *   7. The runbook cross-links the expected companion findings.
 *
 * Usage: npm run audit:waf
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

const wafPath = resolve(ROOT, "portal/src/lib/security/waf.ts");
const waf = safeRead(wafPath, "waf.ts present");
if (waf) {
  push("exports WAF_BLOCKED_UA_SUBSTRINGS", /export const WAF_BLOCKED_UA_SUBSTRINGS\b/.test(waf));
  push("exports WAF_BLOCKED_PATH_FRAGMENTS", /export const WAF_BLOCKED_PATH_FRAGMENTS\b/.test(waf));
  push("exports WAF_EXPLICIT_ALLOW_PATHS", /export const WAF_EXPLICIT_ALLOW_PATHS\b/.test(waf));
  push("exports shouldBlockUserAgent", /export function shouldBlockUserAgent\b/.test(waf));
  push("exports shouldBlockPath", /export function shouldBlockPath\b/.test(waf));
  push("exports evaluateWaf", /export function evaluateWaf\b/.test(waf));
  push("UA list includes sqlmap", /"sqlmap"/.test(waf));
  push("UA list includes nikto", /"nikto"/.test(waf));
  push("UA list includes masscan", /"masscan"/.test(waf));
  push("path list includes /wp-admin", /"\/wp-admin"/.test(waf));
  push("path list includes /.env", /"\/\.env"/.test(waf));
  push("path list includes /.git/config", /"\/\.git\/config"/.test(waf));
  push("allow-list includes /.well-known/security.txt", /"\/\.well-known\/security\.txt"/.test(waf));
  push("UA matcher is case-insensitive", /toLowerCase\(\)/.test(waf));
  push(
    "default-allow posture declared in JSDoc",
    /allow-everything-then-deny/i.test(waf),
  );
  push(
    "lists are frozen (Object.freeze)",
    (waf.match(/Object\.freeze\(/g) || []).length >= 3,
  );
  push(
    "evaluateWaf orders UA before path",
    /uaVerdict[\s\S]{0,120}shouldBlockPath/.test(waf),
  );
}

const middlewarePath = resolve(ROOT, "portal/src/middleware.ts");
const middleware = safeRead(middlewarePath, "middleware.ts present");
if (middleware) {
  push(
    "middleware imports evaluateWaf",
    /from "@\/lib\/security\/waf"/.test(middleware) &&
      /\bevaluateWaf\b/.test(middleware),
  );
  push(
    "middleware calls evaluateWaf BEFORE origin pinning",
    (() => {
      const waf = middleware.indexOf("evaluateWaf(");
      const origin = middleware.indexOf("shouldEnforceOrigin(");
      return waf > 0 && origin > 0 && waf < origin;
    })(),
  );
  push(
    "middleware calls evaluateWaf BEFORE CSRF token check",
    (() => {
      const waf = middleware.indexOf("evaluateWaf(");
      const csrf = middleware.indexOf("shouldEnforceCsrf(");
      return waf > 0 && csrf > 0 && waf < csrf;
    })(),
  );
  push(
    "middleware emits waf.blocked metric",
    /metrics\.increment\("waf\.blocked"/.test(middleware),
  );
  push(
    "middleware returns 403 on WAF block",
    /!wafVerdict\.ok[\s\S]{0,260}status: 403/.test(middleware),
  );
  push(
    "middleware tags WAF response via tagResponse",
    /!wafVerdict\.ok[\s\S]{0,260}tagResponse\(/.test(middleware),
  );
}

const testPath = resolve(ROOT, "portal/src/lib/security/waf.test.ts");
const test = safeRead(testPath, "waf.test.ts present");
if (test) {
  push("tests import evaluateWaf", /evaluateWaf/.test(test));
  push(
    "tests cover every UA substring",
    /WAF_BLOCKED_UA_SUBSTRINGS\.map\(/.test(test),
  );
  push(
    "tests cover every path fragment",
    /WAF_BLOCKED_PATH_FRAGMENTS\.map\(/.test(test),
  );
  push(
    "tests assert allow-list wins",
    /\/\.well-known\/security\.txt/.test(test),
  );
  push(
    "tests assert UA wins over path",
    /UA verdict wins over path/.test(test) ||
      /rule\)\.toBe\("ua"\)/.test(test),
  );
}

const runbookPath = resolve(ROOT, "docs/runbooks/WAF_RUNBOOK.md");
const runbook = safeRead(runbookPath, "WAF_RUNBOOK.md present");
if (runbook) {
  push("runbook declares L1 Edge layer", /L1\s*—\s*Edge/.test(runbook));
  push("runbook declares L2 In-process layer", /L2\s*—\s*In-process/.test(runbook));
  push("runbook declares L3 Cloudflare layer", /L3\s*—\s*Cloudflare/.test(runbook));
  push("runbook lists Vercel baseline rules", /Vercel Firewall baseline/.test(runbook));
  push("runbook names scanner UA family", /sqlmap[|\\]/.test(runbook));
  push("runbook names geo-fence policy", /Geo-fence/i.test(runbook));
  push("runbook has incident playbook", /Incident playbooks/.test(runbook));
  push("runbook links to L10-04 finding", /L10-04-sem-waf-explicito\.md/.test(runbook));
  push("runbook links to L10-01 finding", /L10-01-nenhum-bug-bounty/.test(runbook));
  push("runbook links to L13-07 finding", /L13-07-public-routes-contem-api-custody-webhook/.test(runbook));
  push("runbook points at waf.ts module", /portal\/src\/lib\/security\/waf\.ts/.test(runbook));
  push("runbook points at tests", /waf\.test\.ts/.test(runbook));
  push("runbook points at CI guard", /npm run audit:waf/.test(runbook));
  push("runbook declares quarterly review", /quarterly/i.test(runbook));
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L10-04-sem-waf-explicito.md",
);
const finding = safeRead(findingPath, "L10-04 finding present");
if (finding) {
  push("finding references waf.ts", /portal\/src\/lib\/security\/waf\.ts/.test(finding));
  push("finding references middleware.ts", /portal\/src\/middleware\.ts/.test(finding));
  push("finding references waf.test.ts", /waf\.test\.ts/.test(finding));
  push("finding references WAF_RUNBOOK", /WAF_RUNBOOK\.md/.test(finding));
}

let passed = 0;
for (const r of results) {
  const tag = r.ok ? "[OK]  " : "[FAIL]";
  // eslint-disable-next-line no-console
  console.log(`${tag} ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  if (r.ok) passed += 1;
}
// eslint-disable-next-line no-console
console.log(`\n${passed}/${results.length} WAF invariants passed.`);
if (passed !== results.length) {
  // eslint-disable-next-line no-console
  console.error(
    "\nL10-04 WAF invariants broken. See docs/runbooks/WAF_RUNBOOK.md.",
  );
  process.exit(1);
}
