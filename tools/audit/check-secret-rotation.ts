/**
 * check-secret-rotation.ts — L06-11 runbook contract guard.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const DOC = resolve(__dirname, "..", "..", "docs", "runbooks", "SECRET_ROTATION_RUNBOOK.md");
if (!existsSync(DOC)) { console.error(`[FAIL] missing ${DOC}`); process.exit(1); }
const md = readFileSync(DOC, "utf8");

const requiredSecrets = [
  "SUPABASE_SERVICE_ROLE_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "MP_WEBHOOK_SECRET",
  "ASAAS_API_KEY",
  "STRAVA_CLIENT_SECRET",
];

const checks: Array<[string, boolean]> = [
  ["title — secret rotation runbook",    /Secret Rotation/i.test(md)],
  ["cadence — 90 days default",          /90\s*days|90\s*dias/i.test(md)],
  ["cadence — 180 days for service_role", /180\s*days|180\s*dias/i.test(md)],
  ...requiredSecrets.map<[string, boolean]>((s) => [
    `inventory — ${s}`, md.includes(s),
  ]),
  ["procedure — five-step universal",     /five-step|cinco passos|1\.\s+\*\*Generate\*\*/i.test(md)],
  ["procedure — _NEXT slot pattern",      /_NEXT/.test(md)],
  ["procedure — _PREV slot pattern",      /_PREV/.test(md)],
  ["emergency — leak SLA 30 minutes",     /30\s*minutes|30\s*minutos/i.test(md)],
  ["emergency — LGPD Art. 48 notification", /Art\.?\s*48/.test(md)],
  ["audit_logs — secret_rotation category", /secret_rotation/.test(md)],
  ["crossref — webhooks/verify.ts",       /webhooks\/verify\.ts/.test(md)],
  ["crossref — L10-11 inventory",         /L10-11/.test(md)],
  ["history — revision table",            /Histórico/.test(md)],
];

let failed = 0;
for (const [n, ok] of checks) { if (ok) console.log(`[OK]   ${n}`); else { failed++; console.error(`[FAIL] ${n}`); } }
console.log(`\n${checks.length - failed}/${checks.length} secret-rotation checks passed.`);
if (failed) process.exit(1);
