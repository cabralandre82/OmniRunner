"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { portalCookieOptions } from "@/lib/route-policy";

export async function setPortalGroup(groupId: string, role: string) {
  const opts = portalCookieOptions();
  cookies().set("portal_group_id", groupId, opts);
  cookies().set("portal_role", role, opts);
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
  // L01-06: rotate the CSRF token on sign-out so the next session
  // doesn't inherit the previous user's value.
  cookies().delete("portal_csrf");
  redirect("/login");
}
