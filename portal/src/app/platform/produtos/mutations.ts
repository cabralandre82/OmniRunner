"use server";

import { revalidatePath } from "next/cache";
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

  if (!user) return { error: "Não autenticado" };

  const { data: profile } = await supabase
    .from("profiles")
    .select("platform_role")
    .eq("id", user.id)
    .single();

  if (profile?.platform_role !== "admin") return { error: "Sem permissão" };

  return { user };
}

function revalidate() {
  revalidatePath("/platform/produtos", "page");
}

export async function toggleProduct(productId: string, isActive: boolean) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) return { ok: false, error: auth.error };

  const rl = await rateLimit(`platform-product:${auth.user.id}`, { maxRequests: 20, windowMs: 60_000 });
  if (!rl.allowed) return { ok: false, error: "Muitas requisições. Aguarde." };

  const parsed = platformProductToggleSchema.safeParse({
    action: "toggle_active",
    product_id: productId,
    is_active: isActive,
  });
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Dados inválidos" };

  const admin = createAdminClient();
  const { error } = await admin
    .from("billing_products")
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq("id", productId);

  if (error) return { ok: false, error: error.message };

  await auditLog({
    actorId: auth.user.id,
    action: "platform.toggle_product",
    targetType: "product",
    targetId: productId,
    metadata: { is_active: isActive },
  });

  revalidate();
  return { ok: true };
}

export async function deleteProduct(productId: string) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) return { ok: false, error: auth.error };

  const rl = await rateLimit(`platform-product:${auth.user.id}`, { maxRequests: 20, windowMs: 60_000 });
  if (!rl.allowed) return { ok: false, error: "Muitas requisições. Aguarde." };

  const parsed = platformProductDeleteSchema.safeParse({
    action: "delete",
    product_id: productId,
  });
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Dados inválidos" };

  const admin = createAdminClient();
  const { error } = await admin
    .from("billing_products")
    .delete()
    .eq("id", productId);

  if (error) {
    if (error.message.includes("foreign key") || error.code === "23503") {
      return { ok: false, error: "Este produto tem compras vinculadas e não pode ser removido. Suspenda-o." };
    }
    return { ok: false, error: error.message };
  }

  await auditLog({
    actorId: auth.user.id,
    action: "platform.delete_product",
    targetType: "product",
    targetId: productId,
  });

  revalidate();
  return { ok: true };
}

export async function updateProduct(data: {
  product_id: string;
  name?: string;
  description?: string;
  credits_amount?: number;
  price_cents?: number;
  sort_order?: number;
}) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) return { ok: false, error: auth.error };

  const rl = await rateLimit(`platform-product:${auth.user.id}`, { maxRequests: 20, windowMs: 60_000 });
  if (!rl.allowed) return { ok: false, error: "Muitas requisições. Aguarde." };

  const parsed = platformProductUpdateSchema.safeParse({ action: "update", ...data });
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Dados inválidos" };

  const updatePayload: Record<string, unknown> = { updated_at: new Date().toISOString() };
  if (data.name !== undefined) updatePayload.name = data.name;
  if (data.description !== undefined) updatePayload.description = data.description;
  if (data.credits_amount !== undefined) updatePayload.credits_amount = data.credits_amount;
  if (data.price_cents !== undefined) updatePayload.price_cents = data.price_cents;
  if (data.sort_order !== undefined) updatePayload.sort_order = data.sort_order;

  const admin = createAdminClient();
  const { error } = await admin
    .from("billing_products")
    .update(updatePayload)
    .eq("id", data.product_id);

  if (error) return { ok: false, error: error.message };

  await auditLog({
    actorId: auth.user.id,
    action: "platform.update_product",
    targetType: "product",
    targetId: data.product_id,
    metadata: updatePayload,
  });

  revalidate();
  return { ok: true };
}

export async function createProduct(data: {
  name: string;
  description: string;
  credits_amount: number;
  price_cents: number;
  sort_order: number;
  product_type: string;
}) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) return { ok: false, error: auth.error };

  const rl = await rateLimit(`platform-product:${auth.user.id}`, { maxRequests: 20, windowMs: 60_000 });
  if (!rl.allowed) return { ok: false, error: "Muitas requisições. Aguarde." };

  const parsed = platformProductCreateSchema.safeParse({ action: "create", ...data });
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Dados inválidos" };

  const admin = createAdminClient();
  const { error } = await admin.from("billing_products").insert({
    name: data.name,
    description: data.description,
    credits_amount: data.credits_amount,
    price_cents: data.price_cents,
    sort_order: data.sort_order,
    product_type: (data.product_type as "coins" | "badges") ?? "coins",
  });

  if (error) return { ok: false, error: error.message };

  await auditLog({
    actorId: auth.user.id,
    action: "platform.create_product",
    targetType: "product",
    metadata: { name: data.name, credits_amount: data.credits_amount, price_cents: data.price_cents },
  });

  revalidate();
  return { ok: true };
}
