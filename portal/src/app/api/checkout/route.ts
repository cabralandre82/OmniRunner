import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export async function POST(request: Request) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group selected" }, { status: 400 });
  }

  const body = await request.json();
  const productId = body.product_id;
  const gateway = body.gateway ?? "mercadopago";
  if (!productId) {
    return NextResponse.json(
      { error: "product_id is required" },
      { status: 400 },
    );
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;

  const fnName =
    gateway === "stripe"
      ? "create-checkout-session"
      : "create-checkout-mercadopago";

  const res = await fetch(`${supabaseUrl}/functions/v1/${fnName}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${session.access_token}`,
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
