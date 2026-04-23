import { describe, expect, it } from "vitest";
import {
  CHALLENGE_LEDGER_REASONS,
  type ChallengeLedgerEvent,
  type ChallengeLedgerReason,
  isChallengeLedgerReason,
  PERSONAS_HIDING_COINS,
  shouldHideCoinAmount,
} from "./types";
import {
  assertChallengeLedgerReason,
  listSupportedReasons,
  personaShowsCoins,
  renderChallengeNarrative,
} from "./translate";

const T0 = Date.UTC(2026, 0, 1);

function makeEvent(overrides: Partial<ChallengeLedgerEvent> = {}): ChallengeLedgerEvent {
  return {
    id: "ledger-1",
    reason: "challenge_entry_fee",
    deltaCoins: -50,
    challengeId: "ch-1",
    challengeTitle: "10K da orla",
    occurredAt: T0,
    ...overrides,
  };
}

describe("omnicoin-narrative / types", () => {
  it("exposes the 8 challenge reasons emitted in production", () => {
    expect(CHALLENGE_LEDGER_REASONS.slice().sort()).toEqual([
      "challenge_entry_fee",
      "challenge_entry_refund",
      "challenge_group_completed",
      "challenge_one_vs_one_completed",
      "challenge_one_vs_one_won",
      "challenge_pool_won",
      "challenge_team_won",
      "challenge_withdrawal_refund",
    ]);
  });

  it("does NOT include non-challenge legacy reasons", () => {
    const forbidden = [
      "session_completed", "streak_weekly", "streak_monthly",
      "pr_distance", "pr_pace", "badge_reward", "mission_reward",
      "cosmetic_purchase", "admin_adjustment", "welcome_bonus",
      "referral_reward",
    ];
    for (const r of forbidden) {
      expect(isChallengeLedgerReason(r)).toBe(false);
    }
  });

  it("amateur is the only persona hiding coins today", () => {
    expect(PERSONAS_HIDING_COINS.has("amateur")).toBe(true);
    expect(PERSONAS_HIDING_COINS.has("pro")).toBe(false);
    expect(PERSONAS_HIDING_COINS.has("coach")).toBe(false);
    expect(PERSONAS_HIDING_COINS.has("admin_master")).toBe(false);
    expect(shouldHideCoinAmount("amateur")).toBe(true);
    expect(shouldHideCoinAmount("pro")).toBe(false);
    expect(personaShowsCoins("amateur")).toBe(false);
    expect(personaShowsCoins("admin_master")).toBe(true);
  });
});

describe("omnicoin-narrative / translate (amateur)", () => {
  const locales = ["pt-BR", "en-US"] as const;

  for (const reason of CHALLENGE_LEDGER_REASONS) {
    for (const locale of locales) {
      it(`${reason}/${locale}: amateur never sees the coin number`, () => {
        const out = renderChallengeNarrative({
          event: makeEvent({ reason, deltaCoins: 7373 }),
          persona: "amateur",
          locale,
        });
        expect(out.showCoinAmount).toBe(false);
        expect(out.headline).not.toMatch(/7373/);
        expect(out.body).not.toMatch(/7373/);
        expect(out.headline).not.toMatch(/OmniCoin/i);
        expect(out.body).not.toMatch(/OmniCoin/i);
      });
    }
  }

  it("includes the challenge title when present", () => {
    const out = renderChallengeNarrative({
      event: makeEvent({ reason: "challenge_entry_fee", challengeTitle: "Corrida da Lagoa" }),
      persona: "amateur",
      locale: "pt-BR",
    });
    expect(out.body).toContain("Corrida da Lagoa");
  });

  it("falls back gracefully when challenge title is empty", () => {
    const out = renderChallengeNarrative({
      event: makeEvent({ reason: "challenge_one_vs_one_won", challengeTitle: "   " }),
      persona: "amateur",
      locale: "en-US",
    });
    expect(out.body).not.toContain('""');
    expect(out.body.endsWith(".")).toBe(true);
  });
});

describe("omnicoin-narrative / translate (pro / coach / admin)", () => {
  it("pro sees raw OmniCoin amount in body", () => {
    const out = renderChallengeNarrative({
      event: makeEvent({ reason: "challenge_one_vs_one_won", deltaCoins: 250 }),
      persona: "pro",
      locale: "pt-BR",
    });
    expect(out.showCoinAmount).toBe(true);
    expect(out.body).toContain("250");
    expect(out.body).toMatch(/OmniCoins/i);
  });

  it("coach sees debit label for entry fee", () => {
    const out = renderChallengeNarrative({
      event: makeEvent({ reason: "challenge_entry_fee", deltaCoins: -50 }),
      persona: "coach",
      locale: "en-US",
    });
    expect(out.sign).toBe("debit");
    expect(out.body).toContain("-50");
  });

  it("admin_master sees refund with +sign", () => {
    const out = renderChallengeNarrative({
      event: makeEvent({ reason: "challenge_entry_refund", deltaCoins: 50 }),
      persona: "admin_master",
      locale: "pt-BR",
    });
    expect(out.sign).toBe("credit");
    expect(out.body).toContain("+50");
  });
});

describe("omnicoin-narrative / sign assignment", () => {
  const credits: ChallengeLedgerReason[] = [
    "challenge_entry_refund",
    "challenge_withdrawal_refund",
    "challenge_one_vs_one_won",
    "challenge_group_completed",
    "challenge_team_won",
    "challenge_pool_won",
  ];
  const debits: ChallengeLedgerReason[] = ["challenge_entry_fee"];
  const neutrals: ChallengeLedgerReason[] = ["challenge_one_vs_one_completed"];

  for (const r of credits) {
    it(`${r} is tagged as credit`, () => {
      const out = renderChallengeNarrative({
        event: makeEvent({ reason: r, deltaCoins: 10 }),
        persona: "pro",
        locale: "pt-BR",
      });
      expect(out.sign).toBe("credit");
    });
  }
  for (const r of debits) {
    it(`${r} is tagged as debit`, () => {
      const out = renderChallengeNarrative({
        event: makeEvent({ reason: r, deltaCoins: -10 }),
        persona: "pro",
        locale: "pt-BR",
      });
      expect(out.sign).toBe("debit");
    });
  }
  for (const r of neutrals) {
    it(`${r} is tagged as neutral`, () => {
      const out = renderChallengeNarrative({
        event: makeEvent({ reason: r, deltaCoins: 0 }),
        persona: "pro",
        locale: "pt-BR",
      });
      expect(out.sign).toBe("neutral");
    });
  }
});

describe("omnicoin-narrative / runtime guards", () => {
  it("listSupportedReasons matches the canonical list", () => {
    expect(listSupportedReasons().slice().sort()).toEqual(
      CHALLENGE_LEDGER_REASONS.slice().sort(),
    );
  });

  it("assertChallengeLedgerReason throws on legacy reasons", () => {
    expect(() => assertChallengeLedgerReason("session_completed")).toThrow();
    expect(() => assertChallengeLedgerReason("badge_reward")).toThrow();
    expect(() => assertChallengeLedgerReason("streak_weekly")).toThrow();
  });

  it("assertChallengeLedgerReason accepts every supported reason", () => {
    for (const r of CHALLENGE_LEDGER_REASONS) {
      expect(() => assertChallengeLedgerReason(r)).not.toThrow();
    }
  });
});
