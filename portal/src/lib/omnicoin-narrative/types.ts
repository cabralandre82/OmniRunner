/**
 * L22-02 — OmniCoin narrative copy (pure domain).
 *
 * OmniCoins são **exclusivamente** a economia dos desafios:
 * entrada de desafio, reembolso, saque antes do settle e
 * prêmio no settle. Nenhum outro evento (sessão concluída,
 * streak, PR, badge, missão, convite, assinatura de
 * assessoria) gera OmniCoins — esses reasons legados do
 * schema inicial não são emitidos por nenhum caminho de
 * código atual e não são modelados aqui.
 *
 * Os reasons suportados espelham o que os edge functions
 * `settle-challenge`, `challenge-join` e `challenge-withdraw`
 * gravam hoje em public.coin_ledger:
 *
 *   - challenge_entry_fee
 *   - challenge_entry_refund
 *   - challenge_withdrawal_refund
 *   - challenge_one_vs_one_completed
 *   - challenge_one_vs_one_won
 *   - challenge_group_completed
 *   - challenge_team_won
 *   - challenge_pool_won
 *
 * Persona:
 *   - amateur: só vê narrativa, **nunca** vê o número de
 *     OmniCoins. Se o evento é uma entrada ou um prêmio,
 *     a cópia traduz para linguagem de evento esportivo
 *     ("Sua inscrição foi confirmada", "Você venceu o
 *     desafio 1v1").
 *   - pro / coach / admin_master: veem o número de coins
 *     e o BRL equivalente porque operam o fluxo.
 *
 * O módulo é puro: sem IO, sem Date.now, sem localização
 * externa — o mobile (Flutter) e o portal web consomem a
 * mesma árvore de decisão via bindings finos.
 */

export type AudiencePersona = "amateur" | "pro" | "coach" | "admin_master";

export type LocaleCode = "pt-BR" | "en-US";

/**
 * Conjunto fechado de reasons do coin_ledger que efetivamente
 * rodam em produção. Mantido deliberadamente pequeno para
 * que qualquer reason novo obrigue a passar pelo revisor
 * desta cópia (prevenindo o retorno de "coins por streak"
 * às escuras).
 */
export type ChallengeLedgerReason =
  | "challenge_entry_fee"
  | "challenge_entry_refund"
  | "challenge_withdrawal_refund"
  | "challenge_one_vs_one_completed"
  | "challenge_one_vs_one_won"
  | "challenge_group_completed"
  | "challenge_team_won"
  | "challenge_pool_won";

export const CHALLENGE_LEDGER_REASONS: ReadonlyArray<ChallengeLedgerReason> = [
  "challenge_entry_fee",
  "challenge_entry_refund",
  "challenge_withdrawal_refund",
  "challenge_one_vs_one_completed",
  "challenge_one_vs_one_won",
  "challenge_group_completed",
  "challenge_team_won",
  "challenge_pool_won",
];

export function isChallengeLedgerReason(value: string): value is ChallengeLedgerReason {
  return (CHALLENGE_LEDGER_REASONS as ReadonlyArray<string>).includes(value);
}

export interface ChallengeLedgerEvent {
  id: string;
  reason: ChallengeLedgerReason;
  deltaCoins: number;
  challengeId: string;
  challengeTitle?: string;
  occurredAt: number;
}

export type NarrativeIcon =
  | "trophy"
  | "refund"
  | "ticket"
  | "flag"
  | "handshake"
  | "generic";

export interface NarrativeRenderInput {
  event: ChallengeLedgerEvent;
  persona: AudiencePersona;
  locale: LocaleCode;
}

export interface NarrativeRenderOutput {
  reason: ChallengeLedgerReason;
  headline: string;
  body: string;
  icon: NarrativeIcon;
  showCoinAmount: boolean;
  amountCoins: number;
  sign: "credit" | "debit" | "neutral";
}

export const PERSONAS_HIDING_COINS: ReadonlySet<AudiencePersona> = new Set([
  "amateur",
]);

export function shouldHideCoinAmount(persona: AudiencePersona): boolean {
  return PERSONAS_HIDING_COINS.has(persona);
}
