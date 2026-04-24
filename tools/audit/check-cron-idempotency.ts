#!/usr/bin/env tsx
/**
 * L12-11 — cron.schedule idempotency CI guard
 *
 * Every `cron.schedule(...)` call in supabase/migrations/*.sql MUST be
 * idempotent against a re-apply (rollback + reapply) of the migration.
 * Acceptable patterns:
 *
 *   (A) `IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = ...)`
 *   (B) `BEGIN PERFORM cron.unschedule(...) EXCEPTION WHEN OTHERS THEN NULL; END;`
 *   (C) `IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = ...) THEN cron.unschedule(...) END IF;`
 *
 * Legacy migrations that pre-date this guard are tolerated via the
 * baseline ratchet at tools/audit/baselines/cron-idempotency-baseline.txt.
 * NEW migrations must use one of the safe patterns or fail CI.
 */
import * as fs from "node:fs";
import * as path from "node:path";

const ROOT = path.resolve(__dirname, "../..");
const MIGRATIONS_DIR = path.join(ROOT, "supabase/migrations");
const BASELINE = path.join(ROOT, "tools/audit/baselines/cron-idempotency-baseline.txt");

type Hit = { file: string; line: number; jobname: string };

const SCHEDULE_RE = /cron\.schedule\s*\(\s*['"]([^'"]+)['"]/g;

function isIdempotent(text: string, idx: number, jobname: string): boolean {
  // window of ~30 lines before the schedule call
  const before = text.slice(Math.max(0, idx - 2000), idx);
  const guards = [
    new RegExp(`IF\\s+NOT\\s+EXISTS\\s*\\(\\s*SELECT[\\s\\S]*?cron\\.job[\\s\\S]*?jobname\\s*=\\s*['"]${jobname}['"]`, "i"),
    new RegExp(`PERFORM\\s+cron\\.unschedule\\s*\\(\\s*['"]${jobname}['"]`, "i"),
    new RegExp(`IF\\s+EXISTS\\s*\\([\\s\\S]*?cron\\.job[\\s\\S]*?jobname\\s*=\\s*['"]${jobname}['"][\\s\\S]*?cron\\.unschedule`, "i"),
  ];
  return guards.some((g) => g.test(before));
}

function stripLineComments(text: string): string {
  return text
    .split("\n")
    .map((l) => {
      const i = l.indexOf("--");
      if (i < 0) return l;
      // crude: skip strings; for our purpose comments dominate.
      return l.slice(0, i);
    })
    .join("\n");
}

function scan(): Hit[] {
  const hits: Hit[] = [];
  if (!fs.existsSync(MIGRATIONS_DIR)) return hits;
  for (const f of fs.readdirSync(MIGRATIONS_DIR)) {
    if (!f.endsWith(".sql")) continue;
    const fp = path.join(MIGRATIONS_DIR, f);
    const raw = fs.readFileSync(fp, "utf8");
    const text = stripLineComments(raw);
    SCHEDULE_RE.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = SCHEDULE_RE.exec(text))) {
      const jobname = m[1];
      if (!isIdempotent(text, m.index, jobname)) {
        const line = text.slice(0, m.index).split("\n").length;
        hits.push({ file: path.relative(ROOT, fp), line, jobname });
      }
    }
  }
  return hits;
}

function key(h: Hit): string {
  return `${h.file}:${h.line}:${h.jobname}`;
}

function readBaseline(): Set<string> {
  if (!fs.existsSync(BASELINE)) return new Set();
  return new Set(
    fs
      .readFileSync(BASELINE, "utf8")
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith("#")),
  );
}

function main() {
  const hits = scan();
  const baseline = readBaseline();
  const newViolations = hits.filter((h) => !baseline.has(key(h)));

  if (process.env.UPDATE_BASELINE === "1") {
    const lines = [
      "# L12-11 baseline — known legacy cron.schedule calls without idempotency guard.",
      "# DO NOT add new entries; new violations must use IF NOT EXISTS / unschedule.",
      "# Format: <file>:<line>:<jobname>",
      "",
      ...hits.map(key).sort(),
    ];
    fs.writeFileSync(BASELINE, lines.join("\n") + "\n");
    console.log(`[OK] baseline written: ${hits.length} entries`);
    process.exit(0);
  }

  if (newViolations.length > 0) {
    console.error(`[FAIL] ${newViolations.length} new cron.schedule call(s) without idempotency guard:`);
    for (const v of newViolations) {
      console.error(`  - ${v.file}:${v.line} job='${v.jobname}'`);
    }
    console.error(
      "\nWrap each call in an IF NOT EXISTS / unschedule block. " +
        "See L12-11 finding or supabase/migrations/20260421840000_l03_15_expire_stale_deposits.sql for the pattern.",
    );
    process.exit(1);
  }

  console.log(
    `[OK] ${hits.length} cron.schedule calls; ${hits.length - baseline.size} new since baseline; 0 unguarded.`,
  );
}

main();
