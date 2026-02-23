import { createClient } from "@/lib/supabase/server";

/**
 * Fire-and-forget billing analytics event.
 * Writes to product_events table. Never throws.
 */
export async function trackBillingEvent(
  eventName: string,
  properties: Record<string, unknown> = {},
): Promise<void> {
  try {
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
