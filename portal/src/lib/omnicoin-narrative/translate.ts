/**
 * L22-02 — Narrative translator para eventos do coin_ledger
 * de desafios.
 *
 * Regra invariante: se persona ∈ PERSONAS_HIDING_COINS
 * (hoje: "amateur"), a saída **nunca** contém o valor
 * numérico de coins no headline ou body. O `showCoinAmount`
 * retorna `false` e a UI é obrigada a não renderizar o
 * `amountCoins` — que continua disponível no objeto caso o
 * coach precise auditar depois.
 *
 * Qualquer reason que não seja challenge_* é rejeitado pela
 * assinatura (checagem estática via union TS) e, para
 * robustez em runtime, também pelo default do switch.
 */

import {
  type ChallengeLedgerEvent,
  type ChallengeLedgerReason,
  type LocaleCode,
  type NarrativeRenderInput,
  type NarrativeRenderOutput,
  type NarrativeIcon,
  type AudiencePersona,
  shouldHideCoinAmount,
} from "./types";

interface AmateurCopy {
  headline: string;
  body: string;
  icon: NarrativeIcon;
}

interface GeneralCopyInput {
  event: ChallengeLedgerEvent;
  locale: LocaleCode;
}

interface TemplateEntry {
  sign: "credit" | "debit" | "neutral";
  amateur: Record<LocaleCode, (event: ChallengeLedgerEvent) => AmateurCopy>;
  general: Record<LocaleCode, (input: GeneralCopyInput) => AmateurCopy>;
}

function describeChallenge(event: ChallengeLedgerEvent): string {
  return event.challengeTitle && event.challengeTitle.trim().length > 0
    ? `"${event.challengeTitle.trim()}"`
    : "";
}

function joinWithChallenge(base: string, event: ChallengeLedgerEvent): string {
  const label = describeChallenge(event);
  return label ? `${base} ${label}.` : `${base}.`;
}

const TEMPLATES: Record<ChallengeLedgerReason, TemplateEntry> = {
  challenge_entry_fee: {
    sign: "debit",
    amateur: {
      "pt-BR": (e) => ({
        headline: "Inscrição confirmada",
        body: joinWithChallenge("Você está dentro do desafio", e),
        icon: "ticket",
      }),
      "en-US": (e) => ({
        headline: "Entry confirmed",
        body: joinWithChallenge("You're in the challenge", e),
        icon: "ticket",
      }),
    },
    general: {
      "pt-BR": ({ event }) => ({
        headline: "Taxa de entrada do desafio",
        body: `${event.deltaCoins} OmniCoins debitados pela inscrição.`,
        icon: "ticket",
      }),
      "en-US": ({ event }) => ({
        headline: "Challenge entry fee",
        body: `${event.deltaCoins} OmniCoins debited for the entry.`,
        icon: "ticket",
      }),
    },
  },
  challenge_entry_refund: {
    sign: "credit",
    amateur: {
      "pt-BR": (e) => ({
        headline: "Inscrição devolvida",
        body: joinWithChallenge("Sua inscrição foi estornada no desafio", e),
        icon: "refund",
      }),
      "en-US": (e) => ({
        headline: "Entry refunded",
        body: joinWithChallenge("Your entry was refunded for", e),
        icon: "refund",
      }),
    },
    general: {
      "pt-BR": ({ event }) => ({
        headline: "Estorno de inscrição",
        body: `+${event.deltaCoins} OmniCoins (reembolso).`,
        icon: "refund",
      }),
      "en-US": ({ event }) => ({
        headline: "Entry refund",
        body: `+${event.deltaCoins} OmniCoins (refund).`,
        icon: "refund",
      }),
    },
  },
  challenge_withdrawal_refund: {
    sign: "credit",
    amateur: {
      "pt-BR": (e) => ({
        headline: "Saída do desafio confirmada",
        body: joinWithChallenge("Sua inscrição foi devolvida ao sair do desafio", e),
        icon: "refund",
      }),
      "en-US": (e) => ({
        headline: "Withdrawal confirmed",
        body: joinWithChallenge("Your entry was returned when you withdrew from", e),
        icon: "refund",
      }),
    },
    general: {
      "pt-BR": ({ event }) => ({
        headline: "Estorno por saída do desafio",
        body: `+${event.deltaCoins} OmniCoins (desistência antes do settle).`,
        icon: "refund",
      }),
      "en-US": ({ event }) => ({
        headline: "Withdrawal refund",
        body: `+${event.deltaCoins} OmniCoins (withdrew before settle).`,
        icon: "refund",
      }),
    },
  },
  challenge_one_vs_one_completed: {
    sign: "neutral",
    amateur: {
      "pt-BR": (e) => ({
        headline: "Desafio 1v1 concluído",
        body: joinWithChallenge("Você participou até o fim do desafio", e),
        icon: "flag",
      }),
      "en-US": (e) => ({
        headline: "1v1 challenge completed",
        body: joinWithChallenge("You went the distance in", e),
        icon: "flag",
      }),
    },
    general: {
      "pt-BR": ({ event }) => ({
        headline: "1v1 concluído",
        body: event.deltaCoins !== 0
          ? `${event.deltaCoins >= 0 ? "+" : ""}${event.deltaCoins} OmniCoins (participação concluída).`
          : "Participação concluída.",
        icon: "flag",
      }),
      "en-US": ({ event }) => ({
        headline: "1v1 completed",
        body: event.deltaCoins !== 0
          ? `${event.deltaCoins >= 0 ? "+" : ""}${event.deltaCoins} OmniCoins (completion credited).`
          : "Completion credited.",
        icon: "flag",
      }),
    },
  },
  challenge_one_vs_one_won: {
    sign: "credit",
    amateur: {
      "pt-BR": (e) => ({
        headline: "Vitória no 1v1!",
        body: joinWithChallenge("Você venceu o desafio", e),
        icon: "trophy",
      }),
      "en-US": (e) => ({
        headline: "1v1 victory!",
        body: joinWithChallenge("You won", e),
        icon: "trophy",
      }),
    },
    general: {
      "pt-BR": ({ event }) => ({
        headline: "Prêmio 1v1",
        body: `+${event.deltaCoins} OmniCoins pela vitória no 1v1.`,
        icon: "trophy",
      }),
      "en-US": ({ event }) => ({
        headline: "1v1 prize",
        body: `+${event.deltaCoins} OmniCoins for the 1v1 win.`,
        icon: "trophy",
      }),
    },
  },
  challenge_group_completed: {
    sign: "credit",
    amateur: {
      "pt-BR": (e) => ({
        headline: "Desafio em grupo concluído",
        body: joinWithChallenge("Seu grupo fechou o desafio", e),
        icon: "handshake",
      }),
      "en-US": (e) => ({
        headline: "Group challenge completed",
        body: joinWithChallenge("Your group closed out", e),
        icon: "handshake",
      }),
    },
    general: {
      "pt-BR": ({ event }) => ({
        headline: "Conclusão em grupo",
        body: `${event.deltaCoins >= 0 ? "+" : ""}${event.deltaCoins} OmniCoins do fechamento do grupo.`,
        icon: "handshake",
      }),
      "en-US": ({ event }) => ({
        headline: "Group completion",
        body: `${event.deltaCoins >= 0 ? "+" : ""}${event.deltaCoins} OmniCoins from group settle.`,
        icon: "handshake",
      }),
    },
  },
  challenge_team_won: {
    sign: "credit",
    amateur: {
      "pt-BR": (e) => ({
        headline: "Time vencedor!",
        body: joinWithChallenge("Seu time ganhou o desafio", e),
        icon: "trophy",
      }),
      "en-US": (e) => ({
        headline: "Team victory!",
        body: joinWithChallenge("Your team won", e),
        icon: "trophy",
      }),
    },
    general: {
      "pt-BR": ({ event }) => ({
        headline: "Prêmio do time",
        body: `+${event.deltaCoins} OmniCoins da vitória do time.`,
        icon: "trophy",
      }),
      "en-US": ({ event }) => ({
        headline: "Team prize",
        body: `+${event.deltaCoins} OmniCoins from the team win.`,
        icon: "trophy",
      }),
    },
  },
  challenge_pool_won: {
    sign: "credit",
    amateur: {
      "pt-BR": (e) => ({
        headline: "Prêmio do desafio",
        body: joinWithChallenge("Você levou o prêmio do desafio", e),
        icon: "trophy",
      }),
      "en-US": (e) => ({
        headline: "Challenge prize",
        body: joinWithChallenge("You took the prize for", e),
        icon: "trophy",
      }),
    },
    general: {
      "pt-BR": ({ event }) => ({
        headline: "Pool do desafio",
        body: `+${event.deltaCoins} OmniCoins do pool.`,
        icon: "trophy",
      }),
      "en-US": ({ event }) => ({
        headline: "Challenge pool",
        body: `+${event.deltaCoins} OmniCoins from the pool.`,
        icon: "trophy",
      }),
    },
  },
};

export function renderChallengeNarrative(
  input: NarrativeRenderInput,
): NarrativeRenderOutput {
  const entry = TEMPLATES[input.event.reason];
  const hideCoins = shouldHideCoinAmount(input.persona);
  const copy = hideCoins
    ? entry.amateur[input.locale](input.event)
    : entry.general[input.locale]({ event: input.event, locale: input.locale });
  return {
    reason: input.event.reason,
    headline: copy.headline,
    body: copy.body,
    icon: copy.icon,
    showCoinAmount: !hideCoins,
    amountCoins: input.event.deltaCoins,
    sign: entry.sign,
  };
}

/**
 * Defensive runtime guard — se um edge function novo emitir
 * um reason fora do conjunto conhecido, o caller deve
 * rejeitar antes de chamar renderChallengeNarrative. Assim
 * não vazamos texto vazio / default no mobile.
 */
export function assertChallengeLedgerReason(value: string): asserts value is ChallengeLedgerReason {
  if (!(value in TEMPLATES)) {
    throw new Error(`omnicoin-narrative: unsupported reason "${value}"`);
  }
}

export function listSupportedReasons(): ReadonlyArray<ChallengeLedgerReason> {
  return Object.keys(TEMPLATES) as ReadonlyArray<ChallengeLedgerReason>;
}

export function personaShowsCoins(persona: AudiencePersona): boolean {
  return !shouldHideCoinAmount(persona);
}
