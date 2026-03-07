import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import {
  platformProductCreateSchema,
  platformProductToggleSchema,
  platformProductUpdateSchema,
  platformProductDeleteSchema,
} from "@/lib/schemas";

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

  const rl = await rateLimit(`platform-product:${auth.user.id}`, { maxRequests: 20, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const body = await req.json();
  const admin = createAdminClient();

  if (body.action === "create") {
    const parsed = platformProductCreateSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: parsed.error.issues[0]?.message ?? "Invalid input" },
        { status: 400 },
      );
    }
    const { name, description, credits_amount, price_cents, sort_order, product_type } = parsed.data;

    const { error } = await admin.from("billing_products").insert({
      name,
      description,
      credits_amount,
      price_cents,
      sort_order,
      product_type: product_type ?? "coins",
    });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.create_product", targetType: "product", metadata: { name, credits_amount, price_cents } });
    return NextResponse.json({ status: "created" });
  }

  if (body.action === "toggle_active") {
    const parsed = platformProductToggleSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: parsed.error.issues[0]?.message ?? "Invalid input" },
        { status: 400 },
      );
    }
    const { product_id, is_active } = parsed.data;

    const { error } = await admin
      .from("billing_products")
      .update({ is_active, updated_at: new Date().toISOString() })
      .eq("id", product_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.toggle_product", targetType: "product", targetId: product_id, metadata: { is_active } });
    return NextResponse.json({ status: "updated" });
  }

  if (body.action === "update") {
    const parsed = platformProductUpdateSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: parsed.error.issues[0]?.message ?? "Invalid input" },
        { status: 400 },
      );
    }
    const { product_id, name, description, credits_amount, price_cents, sort_order } = parsed.data;

    const updatePayload: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };
    if (name !== undefined) updatePayload.name = name;
    if (description !== undefined) updatePayload.description = description;
    if (credits_amount !== undefined) updatePayload.credits_amount = credits_amount;
    if (price_cents !== undefined) updatePayload.price_cents = price_cents;
    if (sort_order !== undefined) updatePayload.sort_order = sort_order;

    const { error } = await admin
      .from("billing_products")
      .update(updatePayload)
      .eq("id", product_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.update_product", targetType: "product", targetId: product_id, metadata: updatePayload });
    return NextResponse.json({ status: "updated" });
  }

  if (body.action === "delete") {
    const parsed = platformProductDeleteSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: parsed.error.issues[0]?.message ?? "Invalid input" },
        { status: 400 },
      );
    }
    const { product_id } = parsed.data;

    const { error } = await admin
      .from("billing_products")
      .delete()
      .eq("id", product_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.delete_product", targetType: "product", targetId: product_id });
    return NextResponse.json({ status: "deleted" });
  }

  return NextResponse.json({ error: "Invalid action" }, { status: 400 });
}
