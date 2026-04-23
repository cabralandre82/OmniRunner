/// Supported share surfaces for a challenge invite.
///
/// Distinguishing these at the domain level lets the use-case
/// compose copy that fits each channel's norms:
///
///   * [whatsapp] — WhatsApp deep link (`https://wa.me/?text=...`).
///     Messages are emoji-heavy, short, friendly; body must be
///     URL-encoded because the entire share runs through a query
///     parameter.
///   * [native] — Platform share sheet (iOS/Android). Messages can
///     be slightly longer, no emoji required; uses `share_plus`
///     under the hood.
///   * [copyLink] — Clipboard. Plain URL, no decorating copy.
///
/// Finding reference: L22-08 (viral loop via WhatsApp deep link +
/// Android App Links + iOS Universal Links).
enum ChallengeShareChannel {
  whatsapp,
  native,
  copyLink,
}
