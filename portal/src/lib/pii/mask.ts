/**
 * Canonical PII masking helpers (L04-12).
 *
 * Used by platform-admin tables (`/platform/users`,
 * `/platform/withdrawals`, ...) to render CPF / email / phone
 * with only the last few characters visible. The full value is
 * revealed via the `<MaskedDoc>` component on operator click,
 * which audit-logs the reveal.
 *
 * These helpers are pure (string in, string out) and live
 * outside `/components/` so they can be reused in:
 *   - Server-side rendering (RSC tables)
 *   - CSV export (we mask before writing the file)
 *   - Audit log redaction (when rotating logs to long-term storage)
 *
 * Tests: see `mask.test.ts`.
 */

const ASCII_DIGIT = /\d/g;

/**
 * Brazilian CPF (11 digits). Accepts dotted, dashed or raw input.
 * Output: `123.***.***-45` — first 3 + last 2 digits visible.
 */
export function maskCpf(cpf: string | null | undefined): string {
  if (!cpf) return "";
  const digits = cpf.replace(/\D/g, "");
  if (digits.length !== 11) return "***.***.***-**";
  return `${digits.slice(0, 3)}.***.***-${digits.slice(9, 11)}`;
}

/**
 * Brazilian CNPJ (14 digits). Accepts dotted, dashed or raw input.
 * Output looks like `12.AAA.AAA/AAAA-34` where AAA / AAAA are masked.
 */
export function maskCnpj(cnpj: string | null | undefined): string {
  if (!cnpj) return "";
  const digits = cnpj.replace(/\D/g, "");
  if (digits.length !== 14) return "**.***.***/****-**";
  return `${digits.slice(0, 2)}.***.***/****-${digits.slice(12, 14)}`;
}

/**
 * Email. Output: `a***@example.com` (first char + tail of domain).
 * Multi-character TLD-only domains are still safe to expose.
 */
export function maskEmail(email: string | null | undefined): string {
  if (!email) return "";
  const at = email.indexOf("@");
  if (at < 1) return "***";
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  const localMasked = local.length <= 1 ? "*" : `${local[0]}***`;
  return `${localMasked}@${domain}`;
}

/**
 * Brazilian phone number. Accepts +55, parens, dashes, spaces.
 * Output: `(11) ****-**89` — area code + last 2 digits visible.
 */
export function maskPhone(phone: string | null | undefined): string {
  if (!phone) return "";
  const digits = phone.replace(/\D/g, "");
  // Strip leading country code (55) if present.
  const local = digits.length > 11 ? digits.slice(-11) : digits;
  if (local.length < 10) return "***-****";
  const ddd = local.slice(0, 2);
  const last2 = local.slice(-2);
  return `(${ddd}) ****-**${last2}`;
}

/**
 * Generic name masker. Output: `Alice **** ****` — first name only,
 * remaining tokens hidden. Useful for "user list" tables where the
 * operator only needs to recognise their own assignments.
 */
export function maskName(name: string | null | undefined): string {
  if (!name) return "";
  const tokens = name.trim().split(/\s+/);
  if (tokens.length === 1) return tokens[0];
  return `${tokens[0]} ${tokens.slice(1).map(() => "****").join(" ")}`;
}

/**
 * IBAN-like account number. Mask all but last 4 digits.
 */
export function maskAccount(value: string | null | undefined): string {
  if (!value) return "";
  if (value.length <= 4) return "****";
  return "*".repeat(Math.max(4, value.length - 4)) + value.slice(-4);
}

// Helper used by tests + audit log scrubber to detect "this looks
// like a CPF" when scanning free-form text.
export function looksLikeCpf(s: string): boolean {
  const digits = s.match(ASCII_DIGIT);
  return !!digits && digits.length === 11;
}
