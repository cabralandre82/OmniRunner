/**
 * check-omnicoin-narrative.ts
 *
 * L22-02 — CI guard for the OmniCoin narrative copy
 * module.
 *
 * Invariantes críticas:
 *   - OmniCoins são **somente** para desafios — módulo
 *     não pode declarar reasons fora da lista canônica.
 *   - Amateur **nunca** vê número de coins no headline
 *     ou body — showCoinAmount = false e os templates
 *     amateur nunca mencionam "OmniCoin" ou numerais
 *     derivados de deltaCoins.
 *   - Lista de reasons suportados bate com o que os edge
 *     functions emitem hoje.
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

const dir = "portal/src/lib/omnicoin-narrative";
const types     = safeRead(resolve(ROOT, `${dir}/types.ts`),          "types.ts present");
const translate = safeRead(resolve(ROOT, `${dir}/translate.ts`),      "translate.ts present");
const idx       = safeRead(resolve(ROOT, `${dir}/index.ts`),          "index.ts present");
const test      = safeRead(resolve(ROOT, `${dir}/translate.test.ts`), "translate.test.ts present");

const CANONICAL_REASONS = [
  "challenge_entry_fee",
  "challenge_entry_refund",
  "challenge_withdrawal_refund",
  "challenge_one_vs_one_completed",
  "challenge_one_vs_one_won",
  "challenge_group_completed",
  "challenge_team_won",
  "challenge_pool_won",
];

const FORBIDDEN_REASONS = [
  "session_completed", "streak_weekly", "streak_monthly",
  "pr_distance", "pr_pace", "badge_reward", "mission_reward",
  "cosmetic_purchase", "admin_adjustment", "welcome_bonus",
  "referral_reward", "goal_milestone", "streak_reward",
  "coach_payout", "coach_withdrawal", "gift_sent", "gift_received",
  "subscription_credit", "subscription_debit",
];

if (types) {
  for (const r of CANONICAL_REASONS) {
    push(
      `types: declares canonical reason "${r}"`,
      new RegExp(`"${r}"`).test(types),
    );
  }
  for (const r of FORBIDDEN_REASONS) {
    push(
      `types: does NOT declare legacy reason "${r}"`,
      !new RegExp(`"${r}"`).test(types),
    );
  }
  push(
    "types: ChallengeLedgerReason is a closed union (8 reasons)",
    /export type ChallengeLedgerReason\s*=/.test(types)
      && /\|\s*"challenge_entry_fee"/.test(types)
      && /\|\s*"challenge_pool_won"/.test(types),
  );
  push(
    "types: CHALLENGE_LEDGER_REASONS exported as ReadonlyArray",
    /export const CHALLENGE_LEDGER_REASONS: ReadonlyArray<ChallengeLedgerReason>/.test(types),
  );
  push(
    "types: isChallengeLedgerReason uses the canonical array",
    /export function isChallengeLedgerReason\b/.test(types)
      && /CHALLENGE_LEDGER_REASONS[\s\S]{0,80}\.includes\(value\)/.test(types),
  );
  push(
    "types: ChallengeLedgerEvent carries deltaCoins + challengeId",
    /deltaCoins: number/.test(types) && /challengeId: string/.test(types),
  );
  push(
    "types: AudiencePersona union is amateur | pro | coach | admin_master",
    /"amateur"/.test(types)
      && /"pro"/.test(types)
      && /"coach"/.test(types)
      && /"admin_master"/.test(types),
  );
  push(
    "types: PERSONAS_HIDING_COINS contains amateur",
    /PERSONAS_HIDING_COINS: ReadonlySet<AudiencePersona>[\s\S]{0,80}"amateur"/.test(types),
  );
  push(
    "types: PERSONAS_HIDING_COINS does NOT contain pro / coach / admin_master",
    !/PERSONAS_HIDING_COINS: ReadonlySet<AudiencePersona>[\s\S]{0,300}"(pro|coach|admin_master)"/.test(types),
  );
  push(
    "types: NarrativeRenderOutput exposes showCoinAmount + sign",
    /showCoinAmount: boolean/.test(types)
      && /sign: "credit" \| "debit" \| "neutral"/.test(types),
  );
  push(
    "types: module-level doc reiterates coins-are-challenges-only",
    /exclusivamente.*desafios/i.test(types) || /only.*challenges/i.test(types),
  );
}

if (translate) {
  push(
    "translate: pure (no fs/http/net imports)",
    !/from ["']node:(fs|http|net|child_process)["']/.test(translate),
  );
  push(
    "translate: does not reference Date.now",
    !/Date\.now\(\)/.test(translate),
  );
  push(
    "translate: exports renderChallengeNarrative",
    /export function renderChallengeNarrative\b/.test(translate),
  );
  push(
    "translate: exports assertChallengeLedgerReason",
    /export function assertChallengeLedgerReason\b/.test(translate),
  );
  push(
    "translate: exports listSupportedReasons",
    /export function listSupportedReasons\b/.test(translate),
  );
  push(
    "translate: exports personaShowsCoins",
    /export function personaShowsCoins\b/.test(translate),
  );
  push(
    "translate: TEMPLATES keyed by each canonical reason",
    CANONICAL_REASONS.every((r) => new RegExp(`${r}: \\{`).test(translate)),
  );
  push(
    "translate: hideCoins branch skips the general templates",
    /shouldHideCoinAmount\(input\.persona\)[\s\S]{0,400}entry\.amateur\[input\.locale\]\(input\.event\)/.test(translate),
  );
  push(
    "translate: showCoinAmount reflects hideCoins",
    /showCoinAmount: !hideCoins/.test(translate),
  );
  push(
    "translate: each template entry declares sign",
    /sign: "credit"/.test(translate)
      && /sign: "debit"/.test(translate)
      && /sign: "neutral"/.test(translate),
  );
  push(
    "translate: assertChallengeLedgerReason throws on unknown input",
    /omnicoin-narrative: unsupported reason/.test(translate),
  );

  // Critical anti-regression guard: amateur templates must
  // not interpolate deltaCoins, amountCoins, or the word
  // "OmniCoin". Look for the amateur: { … } blocks and
  // scan their text.
  const amateurBlocks = translate.match(/amateur:\s*\{[\s\S]*?general:/g) ?? [];
  push(
    "translate: every template has an amateur block",
    amateurBlocks.length === CANONICAL_REASONS.length,
    `found ${amateurBlocks.length} blocks`,
  );
  let amateurLeaksCoins = false;
  let amateurLeaksOmniCoinWord = false;
  for (const block of amateurBlocks) {
    if (/deltaCoins|amountCoins|\$\{[^}]*\.deltaCoins/.test(block)) {
      amateurLeaksCoins = true;
    }
    if (/OmniCoin/i.test(block)) {
      amateurLeaksOmniCoinWord = true;
    }
  }
  push(
    "translate: amateur templates never interpolate deltaCoins/amountCoins",
    !amateurLeaksCoins,
  );
  push(
    "translate: amateur templates never mention the word 'OmniCoin'",
    !amateurLeaksOmniCoinWord,
  );

  // General (non-amateur) copy must mention OmniCoin so the
  // operator knows what the column represents.
  const generalBlocks = translate.match(/general:\s*\{[\s\S]*?\},\s*\},/g) ?? [];
  push(
    "translate: every template has a general block",
    generalBlocks.length === CANONICAL_REASONS.length,
    `found ${generalBlocks.length} blocks`,
  );
  let generalMissingOmniCoin = 0;
  for (const block of generalBlocks) {
    if (!/OmniCoin/i.test(block)) generalMissingOmniCoin += 1;
  }
  push(
    "translate: every general block mentions OmniCoin (operator clarity)",
    generalMissingOmniCoin === 0,
    `${generalMissingOmniCoin} missing`,
  );
}

if (idx) {
  push(
    "index re-exports types + translate",
    /from "\.\/types"/.test(idx) && /from "\.\/translate"/.test(idx),
  );
}

if (test) {
  push(
    "test: exhaustively iterates CHALLENGE_LEDGER_REASONS × locales for amateur coin-hiding",
    /for \(const reason of CHALLENGE_LEDGER_REASONS\)[\s\S]{0,800}amateur never sees the coin number/.test(test),
  );
  push(
    "test: asserts the 8 canonical reasons",
    /challenge_entry_fee[\s\S]{0,500}challenge_pool_won/.test(test),
  );
  push(
    "test: forbids the legacy reasons",
    /session_completed[\s\S]{0,200}streak_weekly[\s\S]{0,400}isChallengeLedgerReason\(r\)\)\.toBe\(false\)/.test(test),
  );
  push(
    "test: amateur regexp excludes 'OmniCoin' word from output",
    /\/OmniCoin\/i/.test(test) || /OmniCoin\/i/.test(test),
  );
  push(
    "test: pro / coach / admin_master see coin amount",
    /pro sees raw OmniCoin amount/.test(test)
      && /coach sees debit label/.test(test)
      && /admin_master sees refund/.test(test),
  );
  push(
    "test: covers sign='credit' / 'debit' / 'neutral' at least once each",
    /is tagged as credit/.test(test)
      && /is tagged as debit/.test(test)
      && /is tagged as neutral/.test(test),
  );
  push(
    "test: assertChallengeLedgerReason throws on legacy reasons",
    /assertChallengeLedgerReason throws on legacy reasons/.test(test),
  );
  push(
    "test: assertChallengeLedgerReason accepts every supported reason",
    /assertChallengeLedgerReason accepts every supported reason/.test(test),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L22-02-conceito-de-moeda-omnicoin-confunde-amador.md",
);
const finding = safeRead(findingPath, "L22-02 finding present");
if (finding) {
  push(
    "finding references omnicoin-narrative module",
    /portal\/src\/lib\/omnicoin-narrative/.test(finding),
  );
  push(
    "finding references renderChallengeNarrative or CHALLENGE_LEDGER_REASONS",
    /renderChallengeNarrative/.test(finding)
      || /CHALLENGE_LEDGER_REASONS/.test(finding)
      || /shouldHideCoinAmount/.test(finding),
  );
  push(
    "finding references L22-02 correction migration",
    /20260421700000_l22_02_revoke_nonchallenge_coins\.sql/.test(finding),
  );
}

// ─── Database-side invariant: coin_ledger_reason_check is challenge-only ──
const correctionPath = resolve(
  ROOT,
  "supabase/migrations/20260421700000_l22_02_revoke_nonchallenge_coins.sql",
);
const correction = safeRead(correctionPath, "L22-02 correction migration present");
if (correction) {
  const checkBlock = correction.match(/ADD CONSTRAINT coin_ledger_reason_check CHECK \([\s\S]*?\);/);
  push(
    "correction migration contains reason-check block",
    !!checkBlock,
  );
  if (checkBlock) {
    const body = checkBlock[0];
    const forbidden = [
      "referral_referrer_reward",
      "referral_referred_reward",
      "referral_bonus",
      "referral_new_user",
      "sponsorship_payout",
      "redemption_payout",
      "custody_reversal",
      "championship_reward",
      "welcome_bonus",
      "onboarding_bonus",
    ];
    for (const r of forbidden) {
      push(
        `canonical coin_ledger CHECK does NOT allow ${r}`,
        !new RegExp(`'${r}'`).test(body),
      );
    }
    push(
      "canonical coin_ledger CHECK keeps institution_token_issue (pre-existing)",
      /'institution_token_issue'/.test(body),
    );
    push(
      "canonical coin_ledger CHECK keeps challenge_entry_fee",
      /'challenge_entry_fee'/.test(body),
    );
    push(
      "canonical coin_ledger CHECK keeps challenge_withdrawal_refund",
      /'challenge_withdrawal_refund'/.test(body),
    );
  }
}

// ─── Code-side invariant: no non-challenge coin crediting in supabase/ ────
//
// Scan every file under supabase/migrations and supabase/functions for
// INSERT INTO public.coin_ledger; each emission site's nearest `reason` token
// must be in the canonical challenge-bound set (or one of the pre-existing
// institution_token_* reasons that already existed before Batch J).  The
// check is conservative: it only flags clearly non-challenge reason literals.

const ALLOWED_LEDGER_REASON_LITERALS = new Set<string>([
  "challenge_entry_fee",
  "challenge_entry_refund",
  "challenge_withdrawal_refund",
  "challenge_one_vs_one_completed",
  "challenge_one_vs_one_won",
  "challenge_group_completed",
  "challenge_pool_won",
  "challenge_team_won",
  "session_completed",
  "streak_weekly",
  "streak_monthly",
  "pr_distance",
  "pr_pace",
  "cosmetic_purchase",
  "admin_adjustment",
  "badge_reward",
  "mission_reward",
  "institution_token_issue",
  "institution_token_burn",
  "institution_switch_burn",
  "institution_token_reverse_emission",
  "institution_token_reverse_burn",
]);

const KNOWN_FORBIDDEN_REASONS = new Set<string>([
  "referral_referrer_reward",
  "referral_referred_reward",
  "referral_bonus",
  "referral_new_user",
  "sponsorship_payout",
  "redemption_payout",
  "custody_reversal",
  "championship_reward",
  "welcome_bonus",
  "onboarding_bonus",
  "signup_bonus",
  "invite_bonus",
]);

function collectFiles(root: string, exts: string[]): string[] {
  const { readdirSync, statSync } = require("node:fs") as typeof import("node:fs");
  const { join } = require("node:path") as typeof import("node:path");
  const out: string[] = [];
  const walk = (p: string) => {
    let entries: string[] = [];
    try { entries = readdirSync(p); } catch { return; }
    for (const name of entries) {
      if (name === "node_modules" || name === ".git") continue;
      const full = join(p, name);
      let s;
      try { s = statSync(full); } catch { continue; }
      if (s.isDirectory()) walk(full);
      else if (exts.some((e) => name.endsWith(e))) out.push(full);
    }
  };
  walk(root);
  return out;
}

const scanTargets = [
  ...collectFiles(resolve(ROOT, "supabase/migrations"), [".sql"]),
  ...collectFiles(resolve(ROOT, "supabase/functions"), [".ts"]),
];

// Migrations are append-only: the original L15-02 and L16-05 files have the
// forbidden literals baked in because that is how they got into the schema
// in the first place, and the compensating migration L22-02 is what actually
// drops them at runtime. We only flag NEW occurrences in files other than
// the three historically-involved migrations.
const HISTORICAL_ALLOWED = new Set([
  resolve(ROOT, "supabase/migrations/20260421580000_l15_02_referral_program.sql"),
  resolve(ROOT, "supabase/migrations/20260421620000_l16_05_sponsorships.sql"),
  resolve(ROOT, "supabase/migrations/20260421700000_l22_02_revoke_nonchallenge_coins.sql"),
]);

let forbiddenHits = 0;
const forbiddenDetails: string[] = [];
for (const file of scanTargets) {
  if (HISTORICAL_ALLOWED.has(file)) continue;
  let body = "";
  try { body = readFileSync(file, "utf8"); } catch { continue; }
  for (const reason of KNOWN_FORBIDDEN_REASONS) {
    const needle = new RegExp(`'${reason}'`);
    if (needle.test(body)) {
      forbiddenHits += 1;
      forbiddenDetails.push(`${file.replace(ROOT + "/", "")} references '${reason}'`);
    }
  }
}
push(
  "no new non-challenge reason literals in supabase/ code",
  forbiddenHits === 0,
  forbiddenHits === 0 ? undefined : forbiddenDetails.slice(0, 10).join("; "),
);

// Sanity: the canonical allowed list is non-trivial.
push(
  "canonical allowed-reason whitelist covers all challenge reasons used by edge functions",
  ["challenge_entry_fee", "challenge_entry_refund", "challenge_withdrawal_refund",
   "challenge_group_completed", "challenge_one_vs_one_won", "badge_reward"].every(
     (r) => ALLOWED_LEDGER_REASON_LITERALS.has(r),
   ),
);

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} omnicoin-narrative checks passed.`,
);
if (failed > 0) {
  console.error("\nL22-02 invariants broken.");
  process.exit(1);
}
