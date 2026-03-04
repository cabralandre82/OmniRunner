import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { rateLimit } from "@/lib/rate-limit";
import { checkoutSchema } from "@/lib/schemas";

export async function POST(request: Request) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = rateLimit(`checkout:${user.id}`, { maxRequests: 5, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group selected" }, { status: 400 });
  }

  const body = await request.json();
  const parsed = checkoutSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0].message },
      { status: 400 },
    );
  }
  const { product_id: productId, gateway } = parsed.data;

  const { data: { session } } = await supabase.auth.getSession();
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;

  const fnName =
    gateway === "stripe"
      ? "create-checkout-session"
      : "create-checkout-mercadopago";

  const res = await fetch(`${supabaseUrl}/functions/v1/${fnName}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${session?.access_token}`,
    },
    body: JSON.stringify({ product_id: productId, group_id: groupId }),
  });

  let data;
  try {
    data = await res.json();
  } catch {
    const text = await res.text().catch(() => "");
    return NextResponse.json(
      { error: `Gateway error (${res.status}): ${text || "empty response"}` },
      { status: 502 },
    );
  }

  if (!res.ok || !data.ok) {
    return NextResponse.json(
      { error: data.error?.message ?? data.message ?? `Checkout failed (${res.status})` },
      { status: res.status },
    );
  }

  return NextResponse.json({
    checkout_url: data.checkout_url,
    purchase_id: data.purchase_id,
  });
}
