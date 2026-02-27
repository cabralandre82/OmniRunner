import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Not authenticated", status: 401 };
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("platform_role")
    .eq("id", user.id)
    .single();

  if (profile?.platform_role !== "admin") {
    return { error: "Not a platform admin", status: 403 };
  }

  return { user };
}

export async function POST(req: NextRequest) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json(
      { error: auth.error },
      { status: auth.status },
    );
  }

  const body = await req.json();
  const admin = createAdminClient();

  if (body.action === "create") {
    const { name, description, credits_amount, price_cents, sort_order } = body;

    if (!name || !credits_amount || !price_cents) {
      return NextResponse.json(
        { error: "Missing required fields" },
        { status: 400 },
      );
    }

    const { error } = await admin.from("billing_products").insert({
      name,
      description: description || "",
      credits_amount,
      price_cents,
      sort_order: sort_order ?? 0,
    });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ status: "created" });
  }

  if (body.action === "toggle_active") {
    const { product_id, is_active } = body;

    if (!product_id) {
      return NextResponse.json(
        { error: "Missing product_id" },
        { status: 400 },
      );
    }

    const { error } = await admin
      .from("billing_products")
      .update({ is_active, updated_at: new Date().toISOString() })
      .eq("id", product_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ status: "updated" });
  }

  if (body.action === "update") {
    const { product_id, ...fields } = body;
    delete fields.action;

    if (!product_id) {
      return NextResponse.json(
        { error: "Missing product_id" },
        { status: 400 },
      );
    }

    const { error } = await admin
      .from("billing_products")
      .update({ ...fields, updated_at: new Date().toISOString() })
      .eq("id", product_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ status: "updated" });
  }

  return NextResponse.json({ error: "Invalid action" }, { status: 400 });
}
