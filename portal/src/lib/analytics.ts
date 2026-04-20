import { createClient } from "@/lib/supabase/server";
import {
  PRODUCT_EVENT_MAX_STRING_LEN,
  PRODUCT_EVENT_NAMES,
  PRODUCT_EVENT_PROPERTY_KEYS,
  validateProductEvent,
  type ProductEventName,
} from "./product-event-schema";

// Re-export schema constants so existing imports of `./analytics` keep
// working — there are tests, callers, and docs that reference them at
// this path. The actual definitions live in product-event-schema.ts so
// they stay dependency-free and importable from non-Next contexts (the
// integration test in tools/, future workers, etc.).
export {
  PRODUCT_EVENT_MAX_STRING_LEN,
  PRODUCT_EVENT_NAMES,
  PRODUCT_EVENT_PROPERTY_KEYS,
  validateProductEvent,
  type ProductEventName,
};

/**
 * Fire-and-forget billing analytics event.
 *
 * Writes to `public.product_events`. Never throws — analytics must not
 * block the user flow. Validation drift between this client and the
 * Postgres trigger surfaces as a warning in stderr (so a CI lint /
 * grep can catch it) without failing the request.
 *
 * Defence model (L08-01 + L08-02):
 *   • Postgres trigger is canonical (rejects PE001..PE005).
 *   • This function pre-validates so typos are visible in dev/server
 *     logs immediately instead of being swallowed by the silent
 *     try/catch around the insert.
 *   • For one-shot events (`first_*`, `onboarding_completed`) the
 *     unique partial index `idx_product_events_user_event_once` is the
 *     concurrency guarantee — see the Dart `trackOnce` for the upsert
 *     path. The portal currently only emits multi-shot `billing_*`
 *     events so it stays on the plain `insert` path.
 */
export async function trackBillingEvent(
  eventName: string,
  properties: Record<string, unknown> = {},
): Promise<void> {
  try {
    const reason = validateProductEvent(eventName, properties);
    if (reason !== null) {
      // Don't throw — analytics is fire-and-forget — but make the drop
      // visible. CI / Sentry can grep for this string.
      // eslint-disable-next-line no-console
      console.warn(
        `[analytics] dropping invalid product event "${eventName}": ${reason}`,
      );
      return;
    }

    const supabase = createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    await supabase.from("product_events").insert({
      user_id: user.id,
      event_name: eventName,
      properties,
    });
  } catch {
    // Analytics must never block the user flow
  }
}
