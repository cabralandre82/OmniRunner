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
  if (!productId) {
    return NextResponse.json(
      { error: "product_id is required" },
      { status: 400 },
    );
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const res = await fetch(
    `${supabaseUrl}/functions/v1/create-checkout-session`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ product_id: productId, group_id: groupId }),
    },
  );

  const data = await res.json();

  if (!res.ok || !data.ok) {
    return NextResponse.json(
      { error: data.error?.message ?? "Checkout failed" },
      { status: res.status },
    );
  }

  return NextResponse.json({
    checkout_url: data.checkout_url,
    purchase_id: data.purchase_id,
  });
}
