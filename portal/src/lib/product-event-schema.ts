/**
 * Canonical schema constants for `public.product_events`.
 *
 * This module is deliberately dependency-free (no Next.js, no Supabase
 * import) so it can be imported from:
 *
 *   • the server-side `analytics.ts` helper (Server Component path)
 *   • the integration test
 *     `tools/test_l08_01_02_product_events_hardening.ts`
 *   • any future client-side component or worker
 *
 * MUST stay in sync with:
 *   • the Postgres trigger `fn_validate_product_event()` in
 *     `supabase/migrations/20260421100000_l08_product_events_hardening.sql`
 *   • `ProductEvents.allowedNames` / `allowedPropertyKeys` in
 *     `omni_runner/lib/core/analytics/product_event_tracker.dart`
 *
 * Drift between the three is caught by
 * `tools/test_l08_01_02_product_events_hardening.ts` ("cross-language
 * whitelist parity" section).
 */

export const PRODUCT_EVENT_NAMES = [
  "billing_checkout_returned",
  "billing_credits_viewed",
  "billing_purchases_viewed",
  "billing_settings_viewed",
  "first_challenge_created",
  "first_championship_launched",
  "flow_abandoned",
  "onboarding_completed",
] as const;

export type ProductEventName = (typeof PRODUCT_EVENT_NAMES)[number];

/**
 * Whitelist of allowed `product_events.properties` keys.
 *
 * NEVER add free-text fields like `email`, `name`, `cpf`, `lat`,
 * `lng`, `polyline`, `comment`. Those would re-introduce the L08-02
 * LGPD risk. See `docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md`.
 */
export const PRODUCT_EVENT_PROPERTY_KEYS = new Set<string>([
  "balance",
  "challenge_id",
  "championship_id",
  "count",
  "duration_ms",
  "flow",
  "goal",
  "group_id",
  "method",
  "metric",
  "outcome",
  "products_count",
  "reason",
  "role",
  "step",
  "template_id",
  "total_count",
  "type",
]);

/** Mirror of Postgres trigger constant `v_max_string_len`. */
export const PRODUCT_EVENT_MAX_STRING_LEN = 200;

/**
 * Validate an event before sending. Returns `null` when valid, or a
 * human-readable reason string when invalid. Defensive mirror of the
 * Postgres trigger so dev typos / accidental PII keys are caught at
 * write time, not after a round trip.
 */
export function validateProductEvent(
  eventName: string,
  properties: Record<string, unknown>,
): string | null {
  if (!(PRODUCT_EVENT_NAMES as readonly string[]).includes(eventName)) {
    return `unknown event_name "${eventName}" (allowed: ${PRODUCT_EVENT_NAMES.join(", ")})`;
  }

  for (const [key, value] of Object.entries(properties)) {
    if (!PRODUCT_EVENT_PROPERTY_KEYS.has(key)) {
      return `unknown property key "${key}" (PII risk — see PRODUCT_EVENTS_RUNBOOK)`;
    }

    if (value === null || value === undefined) continue;

    const t = typeof value;
    if (t !== "string" && t !== "number" && t !== "boolean") {
      // Objects, arrays, functions, symbols, bigints all rejected.
      // Postgres trigger raises PE003 for the same shapes; failing
      // early avoids round-tripping a doomed insert.
      return `property "${key}" has unsupported value type "${t}" — only string/number/boolean/null allowed`;
    }

    if (
      t === "string" &&
      (value as string).length > PRODUCT_EVENT_MAX_STRING_LEN
    ) {
      return `property "${key}" string value exceeds ${PRODUCT_EVENT_MAX_STRING_LEN} chars (got ${(value as string).length})`;
    }
  }

  return null;
}
