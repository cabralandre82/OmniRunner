/**
 * L15-01 — UTM attribution capture.
 *
 * Client-side: `captureUtmFromUrl()` reads `utm_*` query params on
 * every landing and writes a JSON cookie (`utm_attribution`) with
 * a 90-day TTL. First-touch wins: if the cookie already exists we
 * do NOT overwrite it, so a returning visitor who arrives via a
 * direct URL keeps the original attribution.
 *
 * Server-side: `parseAttributionCookie(request)` extracts and
 * validates that cookie, and the `/api/attribution/capture` route
 * handles the signup-time fan-in to
 * `public.marketing_attribution_events`.
 *
 * Why cookie and not localStorage: cookie is sent on every request
 * so the server-side signup flow can attach it to the event write
 * without depending on any client JS to fire at the right moment.
 *
 * LGPD / cookie-consent: capture only runs when the marketing-
 * consent flag is set (see consentAllowsMarketing()). Callers that
 * bypass consent must explicitly pass `{force: true}`.
 */

export interface AttributionSnapshot {
  source?: string;
  medium?: string;
  campaign?: string;
  term?: string;
  content?: string;
  landing?: string;
  referrer?: string;
  first_seen_at: number;
}

const COOKIE_NAME = "utm_attribution";
const COOKIE_TTL_DAYS = 90;
const UTM_KEYS = ["source", "medium", "campaign", "term", "content"] as const;

// Guard: max 200 chars per UTM field to block ad-network payload abuse.
const MAX_LEN = 200;

function clamp(value: string | null | undefined): string | undefined {
  if (!value) return undefined;
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  return trimmed.slice(0, MAX_LEN);
}

export function consentAllowsMarketing(): boolean {
  if (typeof document === "undefined") return false;
  const m = document.cookie.match(/(?:^|;\s*)consent_marketing=([^;]+)/);
  return m?.[1] === "1";
}

export function readAttributionCookie(
  cookieHeader: string | null | undefined,
): AttributionSnapshot | null {
  if (!cookieHeader) return null;
  const match = cookieHeader.match(
    new RegExp(`(?:^|;\\s*)${COOKIE_NAME}=([^;]+)`),
  );
  if (!match?.[1]) return null;
  try {
    const decoded = Buffer.from(
      decodeURIComponent(match[1]),
      "base64",
    ).toString("utf8");
    const parsed = JSON.parse(decoded) as unknown;
    if (!parsed || typeof parsed !== "object") return null;
    return parsed as AttributionSnapshot;
  } catch {
    return null;
  }
}

export function captureUtmFromUrl(opts?: { force?: boolean }): void {
  if (typeof window === "undefined" || typeof document === "undefined") return;
  if (!opts?.force && !consentAllowsMarketing()) return;

  if (document.cookie.includes(`${COOKIE_NAME}=`)) return;

  const params = new URLSearchParams(window.location.search);

  const snap: Partial<AttributionSnapshot> = {};
  let hasAny = false;
  for (const key of UTM_KEYS) {
    const v = clamp(params.get(`utm_${key}`));
    if (v) {
      (snap as Record<string, string>)[key] = v;
      hasAny = true;
    }
  }

  if (!hasAny) return;

  snap.landing = clamp(window.location.pathname);
  try {
    if (document.referrer) {
      const u = new URL(document.referrer);
      snap.referrer = clamp(u.hostname);
    }
  } catch {
    // Malformed referrer — skip.
  }

  snap.first_seen_at = Date.now();

  const encoded = btoa(unescape(encodeURIComponent(JSON.stringify(snap))));

  const maxAge = COOKIE_TTL_DAYS * 86400;
  const secure =
    typeof window !== "undefined" && window.location.protocol === "https:"
      ? "; Secure"
      : "";
  document.cookie =
    `${COOKIE_NAME}=${encoded}; Path=/; Max-Age=${maxAge}; SameSite=Lax${secure}`;
}
