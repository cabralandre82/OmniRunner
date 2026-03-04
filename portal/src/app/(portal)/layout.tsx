import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/sidebar";
import { Header } from "@/components/header";

interface Branding {
  logo_url: string | null;
  primary_color: string;
  sidebar_bg: string;
  sidebar_text: string;
  accent_color: string;
}

export default async function PortalLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  const role = cookieStore.get("portal_role")?.value ?? "assistant";

  if (!groupId) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("platform_role")
      .eq("id", user.id)
      .single();

    if (profile?.platform_role === "admin") {
      redirect("/platform/assessorias");
    }

    redirect("/select-group");
  }

  const { data: memberships } = await supabase
    .from("coaching_members")
    .select("group_id")
    .eq("user_id", user.id)
    .in("role", ["admin_master", "coach", "assistant"]);

  const multiGroup = (memberships?.length ?? 0) > 1;

  const [groupRes, profileRes, brandingRes] = await Promise.all([
    supabase
      .from("coaching_groups")
      .select("name")
      .eq("id", groupId)
      .single(),
    supabase
      .from("profiles")
      .select("platform_role")
      .eq("id", user.id)
      .single(),
    supabase
      .from("portal_branding")
      .select("logo_url, primary_color, sidebar_bg, sidebar_text, accent_color")
      .eq("group_id", groupId)
      .maybeSingle(),
  ]);

  const groupName = groupRes.data?.name ?? "Assessoria";
  const isPlatformAdmin = profileRes.data?.platform_role === "admin";

  const { data: custodyAccount } = await supabase
    .from("custody_accounts")
    .select("is_blocked")
    .eq("group_id", groupId)
    .maybeSingle();

  const isBlocked = custodyAccount?.is_blocked ?? false;
  const environment = process.env.NEXT_PUBLIC_ENV ?? "production";

  const branding: Branding = {
    logo_url: brandingRes.data?.logo_url ?? null,
    primary_color: brandingRes.data?.primary_color ?? "#3b82f6",
    sidebar_bg: brandingRes.data?.sidebar_bg ?? "#111827",
    sidebar_text: brandingRes.data?.sidebar_text ?? "#f1f5f9",
    accent_color: brandingRes.data?.accent_color ?? "#3b82f6",
  };

  const cssVars = {
    "--brand-primary": branding.primary_color,
    "--brand-sidebar-bg": branding.sidebar_bg,
    "--brand-sidebar-text": branding.sidebar_text,
    "--brand-accent": branding.accent_color,
  } as React.CSSProperties;

  return (
    <div className="flex h-screen overflow-hidden bg-bg-primary" style={cssVars}>
      <Sidebar
        role={role}
        isPlatformAdmin={isPlatformAdmin}
        logoUrl={branding.logo_url}
        groupName={groupName}
      />
      <div className="flex flex-1 flex-col overflow-hidden">
        <Header
          groupName={groupName}
          userEmail={user.email ?? ""}
          multiGroup={multiGroup}
          role={role}
          environment={environment}
          isBlocked={isBlocked}
        />
        <main className="flex-1 overflow-y-auto bg-bg-primary p-4 sm:p-6">{children}</main>
      </div>
    </div>
  );
}
