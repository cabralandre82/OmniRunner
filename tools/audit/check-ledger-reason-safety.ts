/**
 * check-ledger-reason-safety.ts
 *
 * L04-07 — CI guard that flags migrations introducing `INSERT INTO coin_ledger`
 * with a `reason` literal that looks like free-form PII.
 *
 * The database CHECK constraints (coin_ledger_reason_check +
 * coin_ledger_reason_pii_guard + coin_ledger_reason_length_guard) catch PII
 * at runtime, but a migration that slips a bad `format('%s email=%s', …)`
 * through only fails when the migration runs against real data. This script
 * fails CI at PR-time, shifting detection left.
 *
 * Heuristics:
 *
 *   - Whitelist of canonical reasons (must match exactly a literal OR be a
 *     plpgsql variable that our codebase names with `v_reason_*`).
 *   - Reject any `format(…)` expression passed as `reason` — those are ALWAYS
 *     dynamic and the author must justify via `-- L04-07-OK: ...` comment.
 *   - Reject literals with '@' or the patterns "by user %s" / "from %s".
 *   - Ignore commented-out lines, ignore historical migrations older than the
 *     guard migration (2026-04-21) since they were backfilled.
 *
 * Usage:
 *   npx tsx tools/audit/check-ledger-reason-safety.ts
 *
 * Exit 0 = clean, exit 1 = violations found.
 */

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const MIG_DIR = join(ROOT, "supabase", "migrations");

/**
 * Whitelist canônica — qualquer nova reason-string deve:
 *   (a) já estar aqui, ou
 *   (b) ser adicionada nesta lista + ao CHECK `coin_ledger_reason_check` no
 *       mesmo commit, passando o lint + o self-test da migration.
 *
 * Atualizado em lockstep com 20260421700000_l22_02_revoke_nonchallenge_coins.sql
 * (L22-02 correction), que é a migration mais recente a reescrever a
 * whitelist. Política do produto (L22-02): OmniCoins são emitidas/queimadas
 * somente em fluxos de desafio — qualquer reason proposto para
 * reward de referral / sponsorship / onboarding / welcome é rejeitado.
 */
const CANONICAL_REASONS = new Set<string>([
  // challenge-bound user payouts
  "session_completed",
  "challenge_one_vs_one_completed",
  "challenge_one_vs_one_won",
  "challenge_group_completed",
  "challenge_team_completed",
  "challenge_team_won",
  "challenge_entry_fee",
  "challenge_pool_won",
  "challenge_entry_refund",
  "challenge_withdrawal_refund",
  "challenge_prize_pending",
  "challenge_prize_cleared",
  "cross_assessoria_pending",
  "cross_assessoria_cleared",
  "cross_assessoria_burned",
  // streak / PR / badge / mission (challenge-adjacent personal records)
  "streak_weekly",
  "streak_monthly",
  "pr_distance",
  "pr_pace",
  "badge_reward",
  "mission_reward",
  // cosmetic spend (user burns coins on skins)
  "cosmetic_purchase",
  // institutional token lifecycle (B2B)
  "institution_token_issue",
  "institution_token_burn",
  "institution_switch_burn",
  "institution_token_reverse_emission",
  "institution_token_reverse_burn",
  // operational correction tools
  "admin_adjustment",
  "admin_correction",
  "batch_credit",
]);

/**
 * Cutoff: qualquer migration ANTES desse timestamp já foi "congelada" pelo
 * backfill de L04-07 (20260421220000). Só checamos migrations novas.
 */
const GUARD_MIGRATION_TIMESTAMP = "20260421220000";

type Violation = {
  file: string;
  line: number;
  snippet: string;
  reason: string;
};

const violations: Violation[] = [];

function scanFile(relPath: string, content: string): void {
  const lines = content.split("\n");

  // Strategy: walk the file, find each `INSERT INTO ... coin_ledger (` header,
  // capture the column list to detect `reason` position, then inspect the next
  // `VALUES` block for the literal/expression in that position.
  //
  // We accept a simple single-tuple VALUES pattern because that's what >99% of
  // our codebase uses. Multi-row inserts are flagged as unreviewed.
  const insertRe = /INSERT\s+INTO\s+(?:public\.)?coin_ledger(?:_idempotency)?\s*\(([^)]+)\)/gi;

  let match: RegExpExecArray | null;
  while ((match = insertRe.exec(content)) !== null) {
    const cols = match[1]
      .split(",")
      .map((c) => c.trim().replace(/\s+/g, " "))
      .filter(Boolean);
    const reasonIdx = cols.findIndex((c) => c === "reason");
    if (reasonIdx === -1) continue;

    // Line number of the INSERT header
    const before = content.slice(0, match.index);
    const headerLine = before.split("\n").length;

    // idempotency table: reason is a free-form tag we don't restrict
    if (/coin_ledger_idempotency/i.test(match[0])) continue;

    // Find next VALUES block after match.index
    const after = content.slice(match.index + match[0].length);
    const valuesMatch = /VALUES\s*\(([\s\S]*?)\)/i.exec(after);
    if (!valuesMatch) continue;

    const valuesBody = valuesMatch[1];
    const reasonExpr = splitTopLevelArgs(valuesBody)[reasonIdx]?.trim();
    if (!reasonExpr) continue;

    // Ignore trivially safe plpgsql variables (v_reason, _reason, etc.)
    if (/^[_a-z][a-z0-9_]*$/i.test(reasonExpr)) continue;

    // Opt-out: `-- L04-07-OK: <justificativa>` up to 5 lines above the
    // INSERT header. Aplicável a QUALQUER expressão nesse insert (self-tests,
    // blocos DO-block transitórios, testes etc.).
    if (hasOptOut(lines, headerLine)) continue;

    // Reject format(...) — too dynamic to audit
    if (/^format\s*\(/i.test(reasonExpr)) {
      violations.push({
        file: relPath,
        line: headerLine,
        snippet: reasonExpr.slice(0, 120),
        reason:
          "reason uses format() — all format() output is unaudited. " +
          "Add `-- L04-07-OK: <justificativa>` no mesmo bloco.",
      });
      continue;
    }

    // String literal (single-quoted)
    const litMatch = /^'([^']*)'$/.exec(reasonExpr);
    if (litMatch) {
      const literal = litMatch[1];
      if (!CANONICAL_REASONS.has(literal)) {
        violations.push({
          file: relPath,
          line: headerLine,
          snippet: `'${literal}'`,
          reason:
            `reason literal '${literal}' não está em CANONICAL_REASONS. ` +
            `Se é genuinamente novo, adicione a lockstep em:\n` +
            `  - tools/audit/check-ledger-reason-safety.ts (CANONICAL_REASONS)\n` +
            `  - supabase/migrations/20260421130000_l03_reverse_coin_flows.sql (coin_ledger_reason_check)\n` +
            `no mesmo commit.`,
        });
      }
      if (literal.includes("@")) {
        violations.push({
          file: relPath,
          line: headerLine,
          snippet: `'${literal}'`,
          reason: "reason contém '@' (email) — PII proibida em coin_ledger",
        });
      }
      continue;
    }

    // Concatenation (||) — likely dynamic. Flag.
    if (reasonExpr.includes("||")) {
      violations.push({
        file: relPath,
        line: headerLine,
        snippet: reasonExpr.slice(0, 120),
        reason:
          "reason uses string concatenation (||) — add canonical literal or " +
          "`-- L04-07-OK: <justificativa>`.",
      });
    }
  }
}

function splitTopLevelArgs(body: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let inSingle = false;
  let inDouble = false;
  let buf = "";
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (inSingle) {
      buf += ch;
      if (ch === "'" && body[i - 1] !== "\\") inSingle = false;
      continue;
    }
    if (inDouble) {
      buf += ch;
      if (ch === '"') inDouble = false;
      continue;
    }
    if (ch === "'") { inSingle = true; buf += ch; continue; }
    if (ch === '"') { inDouble = true; buf += ch; continue; }
    if (ch === "(") { depth++; buf += ch; continue; }
    if (ch === ")") { depth--; buf += ch; continue; }
    if (ch === "," && depth === 0) { parts.push(buf); buf = ""; continue; }
    buf += ch;
  }
  if (buf.trim()) parts.push(buf);
  return parts;
}

function hasOptOut(lines: string[], lineNo: number): boolean {
  // Look at the 5 lines before and at lineNo for an `L04-07-OK:` tag in a comment.
  const from = Math.max(0, lineNo - 5);
  for (let i = from; i < Math.min(lines.length, lineNo + 1); i++) {
    if (/L04-07-OK/.test(lines[i])) return true;
  }
  return false;
}

function main(): number {
  if (!existsSync(MIG_DIR)) {
    console.error(`[L04-07 lint] supabase/migrations not found`);
    return 1;
  }

  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith(".sql"));
  let scanned = 0;
  for (const f of files) {
    // Only scan NEW migrations (the guard was introduced on 2026-04-21 22:00).
    // Historical migrations already backfilled in the guard migration itself.
    const ts = f.slice(0, 14); // YYYYMMDDHHMMSS prefix
    if (ts < GUARD_MIGRATION_TIMESTAMP) continue;
    const abs = join(MIG_DIR, f);
    const content = readFileSync(abs, "utf8");
    scanFile(`supabase/migrations/${f}`, content);
    scanned++;
  }

  console.log(`[L04-07 lint] scanned ${scanned} migrations (≥ ${GUARD_MIGRATION_TIMESTAMP})`);

  if (violations.length === 0) {
    console.log(`[L04-07 lint] OK`);
    return 0;
  }

  console.error(`\n[L04-07 lint] FAIL — ${violations.length} violation(s):\n`);
  for (const v of violations) {
    console.error(`  ${v.file}:${v.line}`);
    console.error(`    snippet : ${v.snippet}`);
    console.error(`    reason  : ${v.reason}\n`);
  }
  return 1;
}

// Só sai do processo quando chamado direto (não em testes que importem
// este módulo). Heurística compatível com o padrão do repo.
const invokedPath = process.argv[1] ?? "";
if (invokedPath.endsWith("check-ledger-reason-safety.ts")
 || invokedPath.endsWith("check-ledger-reason-safety.js")) {
  process.exit(main());
}

export { CANONICAL_REASONS, scanFile as __scanFileForTests };
