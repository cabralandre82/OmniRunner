"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const COOKIE_OPTS = {
  path: "/",
  httpOnly: true,
  sameSite: "lax" as const,
  maxAge: 60 * 60 * 8,
};

export async function setPortalGroup(groupId: string, role: string) {
  cookies().set("portal_group_id", groupId, COOKIE_OPTS);
  cookies().set("portal_role", role, COOKIE_OPTS);
  redirect("/dashboard");
}

export async function clearPortalGroup() {
  cookies().delete("portal_group_id");
  cookies().delete("portal_role");
  redirect("/select-group");
}

export async function signOut() {
  const supabase = createClient();
  await supabase.auth.signOut();
  cookies().delete("portal_group_id");
  cookies().delete("portal_role");
  redirect("/login");
}
